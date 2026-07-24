/* app_ota.c — F14.4: the thin IDF half. esp_ota_* behind the injected
 * seam ota_core.c drives, plus the health-gate timer boot step 16 arms.
 *
 * NO NEW TASK ROW (main/tasks.h): the image write runs on the httpd task,
 * which already carries the board-found 8192 B stack, and the gate runs on
 * an esp_timer callback.
 */
#include "app_ota.h"

#include <string.h>

#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"

static const char *TAG = "app_ota";

/* ── the upload session and its flash ops ──────────────────────────── */

static app_ota_session_t s_session;
static esp_ota_handle_t s_handle;
static const esp_partition_t *s_target;

static int op_begin(void *ctx, size_t total_hint) {
    (void)ctx;
    s_target = esp_ota_get_next_update_partition(NULL);
    if (!s_target) {
        ESP_LOGE(TAG, "no free OTA slot");
        return -1;
    }
    const esp_err_t err =
        esp_ota_begin(s_target, total_hint ? total_hint : OTA_SIZE_UNKNOWN,
                      &s_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_begin(%s): %s", s_target->label,
                 esp_err_to_name(err));
        s_target = NULL;
        return -1;
    }
    ESP_LOGW(TAG, "OTA started into %s (%u B declared)", s_target->label,
             (unsigned)total_hint);
    return 0;
}

static int op_write(void *ctx, const void *data, size_t n) {
    (void)ctx;
    return esp_ota_write(s_handle, data, n) == ESP_OK ? 0 : -1;
}

static int op_end(void *ctx) {
    (void)ctx;
    /* Where the SHA-256 and the image-validity check actually happen. A
     * failure here leaves the boot partition alone, which is what keeps a
     * corrupt image from ever being booted. */
    const esp_err_t err = esp_ota_end(s_handle);
    s_handle = 0;
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_end: %s", esp_err_to_name(err));
        return -1;
    }
    return 0;
}

static int op_set_boot(void *ctx) {
    (void)ctx;
    if (!s_target) {
        return -1;
    }
    const esp_err_t err = esp_ota_set_boot_partition(s_target);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_set_boot_partition: %s", esp_err_to_name(err));
        return -1;
    }
    return 0;
}

static void reboot_cb(void *arg) {
    (void)arg;
    ESP_LOGW(TAG, "rebooting into the new image");
    esp_restart();
}

static void op_reboot_later(void *ctx, uint32_t delay_ms) {
    (void)ctx;
    /* Deferred so the 200 reaches the client before the socket dies. */
    static esp_timer_handle_t timer;
    if (!timer) {
        const esp_timer_create_args_t args = {.callback = reboot_cb,
                                              .name = "ota_reboot"};
        if (esp_timer_create(&args, &timer) != ESP_OK) {
            esp_restart();
            return;
        }
    }
    (void)esp_timer_start_once(timer, (uint64_t)delay_ms * 1000ull);
}

static const char *op_slot_name(void *ctx) {
    (void)ctx;
    return s_target ? s_target->label : "";
}

static const app_ota_ops_t k_flash_ops = {
    .begin = op_begin,
    .write = op_write,
    .end = op_end,
    .set_boot = op_set_boot,
    .reboot_later = op_reboot_later,
    .slot_name = op_slot_name,
    .ctx = NULL,
};

const app_ota_ops_t *app_ota_flash_ops(void) { return &k_flash_ops; }

app_ota_session_t *app_ota_the_session(void) { return &s_session; }

/* ── the health gate (03 §3.7) ─────────────────────────────────────── */

static app_ota_gate_hooks_t s_hooks;
static app_ota_gate_verdict_t s_verdict = APP_OTA_GATE_NOT_APPLICABLE;
static uint32_t s_failed_mask;
static bool s_pending_verify;
static esp_timer_handle_t s_gate_timer;

static bool reset_was_crash(void) {
    switch (esp_reset_reason()) {
    case ESP_RST_PANIC:
    case ESP_RST_TASK_WDT:
    case ESP_RST_INT_WDT:
        return true;
    default:
        /* BROWNOUT, POWERON and SW are the world's fault, not the
         * image's: a pack that sagged during a Wi-Fi TX burst says
         * nothing about whether this firmware is sound. */
        return false;
    }
}

static void gate_eval_now(void) {
    const app_ota_gate_facts_t facts = {
        .pending_verify = s_pending_verify,
        .storage_mounted =
            s_hooks.storage_mounted ? s_hooks.storage_mounted() : false,
        .net_settled = s_hooks.net_settled ? s_hooks.net_settled() : false,
        .httpd_listening =
            s_hooks.httpd_listening ? s_hooks.httpd_listening() : false,
        .reset_was_crash = reset_was_crash(),
        .uptime_s = (uint32_t)(esp_timer_get_time() / 1000000ll),
    };
    uint32_t mask = 0;
    const app_ota_gate_verdict_t v = app_ota_gate_eval(&facts, &mask);
    if (v == APP_OTA_GATE_WAITING) {
        s_verdict = v;
        return;
    }
    if (s_verdict == v) {
        return; /* settled already; nothing to say twice */
    }
    s_verdict = v;
    s_failed_mask = mask;

    if (s_gate_timer) {
        (void)esp_timer_stop(s_gate_timer);
    }
    if (v == APP_OTA_GATE_PASS) {
        const esp_err_t err = esp_ota_mark_app_valid_cancel_rollback();
        ESP_LOGI(TAG, "health gate PASSED at %u s — image confirmed (%s)",
                 (unsigned)facts.uptime_s, esp_err_to_name(err));
        s_pending_verify = false;
    } else if (v == APP_OTA_GATE_FAIL) {
        char clauses[48];
        (void)app_ota_gate_clauses_str(mask, clauses, sizeof clauses);
        /* DELIBERATELY PASSIVE (see the M6 plan's decisions): three of the
         * four clauses can fail for reasons that are not the firmware's —
         * a dark router, a jammed channel, a pulled antenna — and forcing
         * a reboot would turn that into a rollback loop that costs the
         * cook. Not marking valid keeps the safety property: the next
         * reset rolls back on its own. */
        ESP_LOGE(TAG,
                 "health gate FAILED (%s) — NOT confirming; the next reset "
                 "rolls back",
                 clauses);
    }
}

static void gate_timer_cb(void *arg) {
    (void)arg;
    gate_eval_now();
}

int app_ota_init(const app_ota_gate_hooks_t *hooks) {
    if (hooks) {
        s_hooks = *hooks;
    }
    app_ota_session_reset(&s_session);

    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t state = ESP_OTA_IMG_UNDEFINED;
    if (running && esp_ota_get_state_partition(running, &state) == ESP_OK) {
        s_pending_verify = (state == ESP_OTA_IMG_PENDING_VERIFY);
    }

    const esp_app_desc_t *desc = esp_app_get_description();
    ESP_LOGI(TAG, "running %s v%s (%s)", running ? running->label : "?",
             desc ? desc->version : "?",
             s_pending_verify ? "PENDING VERIFY" : "confirmed");

    if (!s_pending_verify) {
        /* Nothing to confirm and nothing to roll back — a USB-flashed
         * image. Reporting `passed` here would be the /status.ble lesson
         * repeated. */
        s_verdict = APP_OTA_GATE_NOT_APPLICABLE;
        return 0;
    }

    s_verdict = APP_OTA_GATE_WAITING;
    const esp_timer_create_args_t args = {.callback = gate_timer_cb,
                                          .name = "ota_gate"};
    if (esp_timer_create(&args, &s_gate_timer) != ESP_OK) {
        return -1;
    }
    /* Evaluate once now so a crash reset fails immediately rather than
     * in ten seconds, then every 10 s until it settles. */
    gate_eval_now();
    if (s_verdict == APP_OTA_GATE_WAITING) {
        (void)esp_timer_start_periodic(s_gate_timer, 10ull * 1000ull * 1000ull);
    }
    return 0;
}

app_ota_gate_verdict_t app_ota_gate_state(uint32_t *failed_mask) {
    if (failed_mask) {
        *failed_mask = s_failed_mask;
    }
    return s_verdict;
}

const char *app_ota_running_slot(void) {
    const esp_partition_t *running = esp_ota_get_running_partition();
    return running ? running->label : "";
}

bool app_ota_pending_verify(void) { return s_pending_verify; }

bool app_ota_gate_failed(void) { return s_verdict == APP_OTA_GATE_FAIL; }
