/* app_alarm.c — the ESP-IDF glue for the alarm engine (F13.6).
 *
 * Deliberately thin. Everything that decides anything lives in
 * app_alarm_svc.c / rules.c / alarm_engine.c and is host-tested; this file
 * owns the event subscriptions, the 10 s tick, the four device facts, and
 * the app_alarm task row that has been declared in main/tasks.h since
 * F1.4 (M5 populates it — it does not add one).
 *
 * Handlers MUTATE A FLAG AND NOTIFY. Rule evaluation never runs on the
 * event loop: 03 §3.2's duration guard is the rule, and ws_push and
 * ble_push have each paid for forgetting it once.
 */
#include "app_alarm.h"

#include <string.h>

#include "esp_core_dump.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "app_alarm_svc.h"
#include "bridge_event.h"
#include "smoke_x_ctrl.h"

static const char *TAG = "app_alarm";

/* Mirrors the app_alarm row of main/tasks.h — components cannot depend on
 * `main`, so the table stays the single source of truth and this is a copy
 * of one row. test_tasks_table.c pins the values. */
#define ALARM_TASK_NAME "app_alarm"
#define ALARM_TASK_STACK 3072
#define ALARM_TASK_PRIO 4
#define ALARM_TASK_CORE 0

/* 09 §9.2: "on every sample plus a 10 s tick". */
#define ALARM_TICK_MS 10000

static TaskHandle_t s_task;
static volatile bool s_sample_pending;
static volatile bool s_session_ended;
static volatile bool s_session_started;
static bool s_coredump_present;
static uint8_t s_soc = BRIDGE_SOC_UNKNOWN;
static uint8_t s_storage_free_pct;
static bool s_storage_known;

/* ── the four device facts ──────────────────────────────────────────── */

static bool op_coredump(void *ctx) {
    (void)ctx;
    return s_coredump_present;
}

static bool op_storage(void *ctx, uint8_t *pct) {
    (void)ctx;
    if (!s_storage_known) {
        return false;
    }
    *pct = s_storage_free_pct;
    return true;
}

static uint8_t op_soc(void *ctx) {
    (void)ctx;
    return s_soc;
}

static void op_publish(void *ctx, const app_alarm_evt_t *e) {
    (void)ctx;
    /* One BRIDGE_EVT_ALARM per transition. app_api fans it out to the
     * WebSocket, app_ble to live_state, app_ui to the overlay and the
     * LED — none of which app_alarm knows exist. */
    bridge_evt_alarm_t evt = {
        .alarm_id = e->id,
        .rule = e->rule,
        .probe = e->probe,
        .value_f10 = e->value_f10,
    };
    if (e->kind == APP_ALARM_EVT_RAISED) {
        evt.action = BRIDGE_ALARM_RAISED;
    } else if (e->kind == APP_ALARM_EVT_ACKED) {
        evt.action = BRIDGE_ALARM_ACKED;
    } else {
        evt.action = BRIDGE_ALARM_CLEARED;
    }
    (void)bridge_event_post(BRIDGE_EVT_ALARM, &evt, sizeof evt);
    ESP_LOGI(TAG, "%s %s probe %u (id %u)",
             e->kind == APP_ALARM_EVT_RAISED
                 ? "RAISED"
                 : (e->kind == APP_ALARM_EVT_ACKED ? "acked" : "cleared"),
             bridge_alarm_rule_str(e->rule), (unsigned)e->probe,
             (unsigned)e->id);
}

static const app_alarm_ops_t k_ops = {
    .coredump_present = op_coredump,
    .storage_free_pct = op_storage,
    .soc_pct = op_soc,
    .publish = op_publish,
};

/* ── event handlers: flag and notify, nothing else ──────────────────── */

static void on_sample(void *arg, esp_event_base_t base, int32_t id,
                      void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    s_sample_pending = true;
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

static void on_session(void *arg, esp_event_base_t base, int32_t id,
                       void *data) {
    (void)arg;
    (void)base;
    (void)id;
    const bridge_evt_session_t *e = data;
    if (e == NULL) {
        return;
    }
    if (e->action == BRIDGE_SESSION_ENDED) {
        s_session_ended = true;
    } else if (e->action == BRIDGE_SESSION_STARTED) {
        s_session_started = true;
    }
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

static void on_storage(void *arg, esp_event_base_t base, int32_t id,
                       void *data) {
    (void)arg;
    (void)base;
    (void)id;
    const bridge_evt_storage_t *e = data;
    if (e == NULL) {
        return;
    }
    s_storage_free_pct = e->free_pct;
    s_storage_known = true;
}

static void on_power(void *arg, esp_event_base_t base, int32_t id,
                     void *data) {
    (void)arg;
    (void)base;
    (void)id;
    const bridge_evt_power_t *e = data;
    if (e == NULL) {
        return;
    }
    s_soc = e->soc_pct;
}

/* ── the task row ───────────────────────────────────────────────────── */

static void alarm_task(void *arg) {
    (void)arg;
    for (;;) {
        /* Wake on a sample, or every 10 s. The tick is not a fallback:
         * base_lost fires on the ABSENCE of a packet. */
        (void)ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(ALARM_TICK_MS));
        const uint64_t now_ms = (uint64_t)esp_timer_get_time() / 1000ull;
        const uint32_t now_s = (uint32_t)(now_ms / 1000ull);

        if (s_session_started) {
            s_session_started = false;
            app_alarm_svc_session_started();
        }
        if (s_session_ended) {
            s_session_ended = false;
            app_alarm_svc_session_ended();
        }

        if (s_sample_pending) {
            s_sample_pending = false;
            app_alarm_svc_on_sample(now_s);
            continue;
        }

        const uint64_t last = smoke_x_ctrl_last_valid_ms();
        const uint32_t since_s =
            (uint32_t)((now_ms > last ? now_ms - last : 0ull) / 1000ull);
        app_alarm_svc_tick(now_s, since_s);
    }
}

int app_alarm_init(void) {
    /* system_fault (09 §9.2): a coredump found at boot means the bridge
     * restarted unexpectedly, and the user is owed that even if
     * everything looks fine now. */
    size_t addr = 0;
    size_t size = 0;
    s_coredump_present =
        esp_core_dump_image_get(&addr, &size) == ESP_OK && size > 0;

    if (app_alarm_svc_init(&k_ops) != 0) {
        return -1;
    }

    if (bridge_event_handler_register(BRIDGE_EVT_SAMPLE, on_sample, NULL,
                                      "app_alarm.sample") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_SESSION, on_session, NULL,
                                      "app_alarm.session") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_STORAGE, on_storage, NULL,
                                      "app_alarm.storage") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_POWER, on_power, NULL,
                                      "app_alarm.power") != ESP_OK) {
        return -1;
    }

    if (xTaskCreatePinnedToCore(alarm_task, ALARM_TASK_NAME, ALARM_TASK_STACK,
                                NULL, ALARM_TASK_PRIO, &s_task,
                                ALARM_TASK_CORE) != pdPASS) {
        return -1;
    }
    ESP_LOGI(TAG, "alarm engine up: 9 rules, 10 s tick%s",
             s_coredump_present ? ", coredump found (system_fault)" : "");
    return 0;
}

int app_alarm_ack(uint8_t id) { return app_alarm_svc_ack(id); }

int app_alarm_ack_all(void) { return app_alarm_svc_ack_all(); }

bool app_alarm_unacked(void) { return app_alarm_svc_unacked(); }

int app_alarm_list(const app_alarm_slot_t **out, int cap) {
    return app_alarm_svc_list(out, cap);
}
