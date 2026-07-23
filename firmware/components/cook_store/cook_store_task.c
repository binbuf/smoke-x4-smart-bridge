/* cook_store_task — the receive→persist spine (F5 wiring, design 03 §3.2
 * rule 2): the BRIDGE_EVT_SAMPLE handler only copies the payload onto a
 * queue; every flash touch happens on the cook_store task, so a LittleFS
 * garbage-collection pause can never stall the decoder.
 *
 * All decisions live in host-tested modules (cook_lifecycle, cook_store
 * core); this file routes.
 */
#include <string.h>

#include "app_config_store.h"
#include "app_time_core.h"
#include "bridge_event.h"
#include "cook_store.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "record_gen.h"

static const char *TAG = "cook_task";

/* Mirrors the cook_store row of main/tasks.h (the budget-audited table). */
#define TASK_NAME "cook_store"
#define TASK_STACK 4096
#define TASK_PRIO 4
#define TASK_CORE 0

#define QUEUE_DEPTH 8

typedef enum {
    MSG_SAMPLE = 0,
    MSG_TIME,
    MSG_EXPLICIT_START,
    MSG_EXPLICIT_STOP,
} msg_kind_t;

typedef struct {
    msg_kind_t kind;
    bridge_evt_sample_t sample; /* MSG_SAMPLE */
} cook_msg_t;

static QueueHandle_t s_queue;
static cook_lifecycle_t s_lc;

static void enqueue(const cook_msg_t *msg) {
    if (s_queue && xQueueSend(s_queue, msg, 0) != pdTRUE) {
        ESP_LOGW(TAG, "queue full, message dropped");
    }
}

static void on_sample_evt(void *arg, esp_event_base_t base, int32_t id,
                          void *data) {
    (void)arg;
    (void)base;
    (void)id;
    cook_msg_t msg = {.kind = MSG_SAMPLE};
    memcpy(&msg.sample, data, sizeof msg.sample);
    enqueue(&msg);
}

static void on_time_evt(void *arg, esp_event_base_t base, int32_t id,
                        void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    const cook_msg_t msg = {.kind = MSG_TIME};
    enqueue(&msg);
}

static uint64_t uptime_ms_of(const bridge_evt_sample_t *s) {
    return (uint64_t)s->t_rel_s * 1000u; /* smoke_x publishes uptime secs */
}

static void open_session(const bridge_evt_sample_t *s) {
    uint64_t started_unix = 0;
    (void)app_time_core_now(uptime_ms_of(s), &started_unix);
    if (app_time_core_source() == APP_TIME_NONE ||
        app_time_core_source() == APP_TIME_STALE) {
        started_unix = 0; /* stale is approximate: back-patch when real */
    }
    app_config_pairing_t p;
    const char *dev = app_config_store_get_pairing(&p) == APP_CONFIG_OK
                          ? p.device_id
                          : "";
    const cook_session_params_t params = {
        .num_probes = s->num_probes,
        .started_unix_ms = started_unix,
        .started_uptime_s = s->t_rel_s,
        .name = NULL,
        .device_id = dev,
    };
    if (cook_session_open(&params) == COOK_STORE_OK) {
        cook_lifecycle_note_started(&s_lc, s->t_rel_s);
        cook_ring_reset();
        bridge_evt_session_t evt = {.action = BRIDGE_SESSION_STARTED,
                                    .session_id = cook_session_active_id()};
        (void)bridge_event_post(BRIDGE_EVT_SESSION, &evt, sizeof evt);
    }
}

static void close_session(void) {
    const uint32_t id = cook_session_active_id();
    /* Best-effort: the close stamps whatever clock quality exists. */
    const uint64_t now_up = (uint64_t)esp_timer_get_time() / 1000u;
    uint64_t ended_unix = 0;
    (void)app_time_core_now(now_up, &ended_unix);
    if (cook_session_close(ended_unix) == COOK_STORE_OK) {
        cook_lifecycle_note_ended(&s_lc);
        bridge_evt_session_t evt = {.action = BRIDGE_SESSION_ENDED,
                                    .session_id = id};
        (void)bridge_event_post(BRIDGE_EVT_SESSION, &evt, sizeof evt);
    }
}

static void handle_sample(const bridge_evt_sample_t *s, bool explicit_start,
                          bool explicit_stop) {
    bool any_attached = false;
    int16_t max_temp = INT16_MIN;
    for (int i = 0; i < s->num_probes && i < 4; i++) {
        const int16_t v = s->temp_f10[i];
        if (v != BRIDGE_TEMP_DETACHED && v != BRIDGE_TEMP_INVALID) {
            any_attached = true;
            if (v > max_temp) {
                max_temp = v;
            }
        }
    }

    const cook_lc_input_t in = {
        .now_s = s->t_rel_s,
        .paired = true,
        .sample = true,
        .any_attached = any_attached,
        .max_attached_temp_x10 = any_attached ? max_temp : 0,
        .explicit_start = explicit_start,
        .explicit_stop = explicit_stop,
        .unpaired = false,
    };
    switch (cook_lifecycle_step(&s_lc, &in)) {
        case COOK_LC_START:
            open_session(s);
            break;
        case COOK_LC_END_DETACHED:
        case COOK_LC_END_STOP:
        case COOK_LC_END_UNPAIRED:
            close_session();
            break;
        case COOK_LC_END_CAP:
            close_session();
            open_session(s); /* the 36 h continuation (04 §4.6) */
            break;
        case COOK_LC_NONE:
            break;
    }

    if (cook_session_is_open()) {
        const uint32_t t = s->t_rel_s - cook_session_started_uptime_s();
        const int rc = cook_session_append(t, s->temp_f10, s->flags, s->rssi);
        if (rc == COOK_STORE_OK) {
            const cook_ring_sample_t rs = {
                .t = t,
                .temp = {s->temp_f10[0], s->temp_f10[1], s->temp_f10[2],
                         s->temp_f10[3]},
                .flags = s->flags,
                .rssi = s->rssi,
            };
            cook_ring_push(&rs);
            if (s->flags & BRIDGE_SAMPLE_REC_FLAGS_NEW_ALARM) {
                (void)cook_session_flush(); /* §4.5 immediate trigger */
            }
        } else if (rc != COOK_STORE_ERR_FULL) {
            ESP_LOGE(TAG, "append failed (%d)", rc);
        }
    }
}

static void handle_time(void) {
    /* F6.2: a real clock landed; date a clockless open session. */
    if (!cook_session_is_open() || cook_session_clock_valid()) {
        return;
    }
    const uint64_t now_up = (uint64_t)esp_timer_get_time() / 1000u;
    uint64_t started = 0;
    if (app_time_core_unix_at(
            (uint64_t)cook_session_started_uptime_s() * 1000u, now_up,
            &started) &&
        started != 0) {
        (void)cook_session_set_clock(started);
    }
}

static void cook_task(void *arg) {
    (void)arg;
    cook_msg_t msg;
    bool pending_start = false, pending_stop = false;
    while (true) {
        if (xQueueReceive(s_queue, &msg, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        switch (msg.kind) {
            case MSG_SAMPLE:
                handle_sample(&msg.sample, pending_start, pending_stop);
                pending_start = pending_stop = false;
                break;
            case MSG_TIME:
                handle_time();
                break;
            case MSG_EXPLICIT_START:
                pending_start = true; /* honoured on the next sample */
                break;
            case MSG_EXPLICIT_STOP:
                if (cook_session_is_open()) {
                    close_session();
                }
                pending_stop = false;
                break;
        }
    }
}

int cook_store_task_start(void) {
    cook_lifecycle_reset(&s_lc);
    s_queue = xQueueCreate(QUEUE_DEPTH, sizeof(cook_msg_t));
    if (!s_queue) {
        return -1;
    }
    if (bridge_event_handler_register(BRIDGE_EVT_SAMPLE, on_sample_evt, NULL,
                                      "cook_store_sample") != ESP_OK) {
        return -1;
    }
    if (bridge_event_handler_register(BRIDGE_EVT_TIME, on_time_evt, NULL,
                                      "cook_store_time") != ESP_OK) {
        return -1;
    }
    if (xTaskCreatePinnedToCore(cook_task, TASK_NAME, TASK_STACK, NULL,
                                TASK_PRIO, NULL, TASK_CORE) != pdPASS) {
        return -1;
    }
    return 0;
}
