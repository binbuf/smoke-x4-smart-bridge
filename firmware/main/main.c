/* main.c — app_main: boot sequence, wiring, nothing else (design 03 §3.1).
 *
 * M0 skeleton: every subsystem behind the boot sequence is a stub that logs
 * and succeeds. The two properties that must be real from the start already
 * are: LoRa-before-network ordering lives in boot_seq's step table, and the
 * double-reset token is armed/consumed against RTC SRAM below.
 */
#include <inttypes.h>

#include "esp_attr.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"

#include "app_config.h"
#include "app_time.h"
#include "bench.h"
#include "boot_seq.h"
#include "cook_store.h"
#include "double_reset.h"
#include "smoke_x.h"
#include "tasks.h"

static const char *TAG = "smoke_bridge";

/* Survives a reset (not a power cycle) — the double-reset recovery token. */
static RTC_NOINIT_ATTR bridge_drt_token_t s_drt_token;

typedef struct {
    bool force_ap; /* double reset or PRG recovery window */
} boot_ctx_t;

static uint64_t rtc_now_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

static int step_nvs(void *ctx) {
    (void)ctx;
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS needs erase (%s), erasing", esp_err_to_name(err));
        if (nvs_flash_erase() != ESP_OK) {
            return -1;
        }
        err = nvs_flash_init();
    }
    return err == ESP_OK ? 0 : -1;
}

static int step_boot_reason(void *ctx) {
    boot_ctx_t *boot = ctx;
    const uint64_t now = rtc_now_ms();
    if (bridge_double_reset_check(&s_drt_token, now)) {
        ESP_LOGW(TAG, "double reset detected — forcing AP mode this boot");
        boot->force_ap = true;
    } else {
        bridge_double_reset_arm(&s_drt_token, now);
    }
    return 0;
}

static int step_event_loop(void *ctx) {
    (void)ctx;
    return esp_event_loop_create_default() == ESP_OK ? 0 : -1;
}

static int step_config(void *ctx) {
    (void)ctx;
    const int rc = app_config_init();
    if (rc != APP_CONFIG_OK) {
        ESP_LOGE(TAG, "app_config_init failed (%d)", rc);
        return -1;
    }
    ESP_LOGI(TAG, "config store at version %u", app_config_store_version());
    return 0;
}

static int step_stub(void *ctx) {
    (void)ctx;
    return 0;
}

static int step_cook_store(void *ctx) {
    (void)ctx;
    if (cook_store_init() != 0) {
        return -1;
    }
    return cook_store_task_start();
}

static int step_smoke_x_init(void *ctx) {
    (void)ctx;
    return smoke_x_init();
}

static int step_smoke_x_start(void *ctx) {
    (void)ctx;
    return smoke_x_start();
}

static int step_time(void *ctx) {
    (void)ctx;
    return app_time_init();
}

static int step_recovery_window(void *ctx) {
    (void)ctx;
    /* 3 s PRG hold on the splash — stubbed until F11 (app_ui). */
    ESP_LOGI(TAG, "PRG recovery window: stub until F11");
    return 0;
}

static int step_ota_health_gate(void *ctx) {
    (void)ctx;
    /* esp_ota_mark_app_valid_cancel_rollback() behind the 03 §3.7 health
     * gate — stubbed until F14. */
    ESP_LOGI(TAG, "OTA health gate: stub until F14");
    return 0;
}

static void disarm_timer_cb(void *arg) {
    (void)arg;
    bridge_double_reset_disarm(&s_drt_token);
    ESP_LOGD(TAG, "double-reset token disarmed");
}

void app_main(void) {
#if CONFIG_SMOKEBRIDGE_BENCH_MODE
    /* The V1.3/V1.4 bench instrument replaces the app entirely. */
    bench_run();
    return;
#endif
    ESP_LOGI(TAG, "Smoke X4 Smart Bridge — M0 skeleton");
    ESP_LOGI(TAG, "task stack budget: %d B declared across %u tasks",
             (int)BRIDGE_TASK_STACK_TOTAL, (unsigned)BRIDGE_TASK_COUNT);

    boot_ctx_t boot = {0};
    const bridge_boot_ops_t ops = {
        .steps =
            {
                [BRIDGE_BOOT_NVS - 1] = step_nvs,
                [BRIDGE_BOOT_BOOT_REASON - 1] = step_boot_reason,
                [BRIDGE_BOOT_CONFIG - 1] = step_config,
                [BRIDGE_BOOT_EVENT_LOOP - 1] = step_event_loop,
                [BRIDGE_BOOT_POWER - 1] = step_stub, /* F12 */
                [BRIDGE_BOOT_UI - 1] = step_stub,    /* F11 */
                [BRIDGE_BOOT_RECOVERY_WINDOW - 1] = step_recovery_window,
                [BRIDGE_BOOT_COOK_STORE - 1] = step_cook_store,
                [BRIDGE_BOOT_SMOKE_X_INIT - 1] = step_smoke_x_init,
                [BRIDGE_BOOT_SMOKE_X_START - 1] = step_smoke_x_start,
                [BRIDGE_BOOT_TIME - 1] = step_time,
                [BRIDGE_BOOT_NET - 1] = step_stub,           /* F8 */
                [BRIDGE_BOOT_API - 1] = step_stub,           /* F9 */
                [BRIDGE_BOOT_BLE - 1] = step_stub,           /* F10 */
                [BRIDGE_BOOT_ALARM - 1] = step_stub,         /* F13 */
                [BRIDGE_BOOT_OTA_HEALTH_GATE - 1] = step_ota_health_gate,
            },
    };

    bridge_boot_result_t result;
    if (!bridge_boot_run(&ops, &boot, &result)) {
        ESP_LOGE(TAG, "fatal boot failure at step %d (%s)", result.fatal_step,
                 bridge_boot_step_name(result.fatal_step));
        return;
    }
    for (int step = 1; step <= BRIDGE_BOOT_STEP_COUNT; step++) {
        if (result.failed_mask & (1u << (step - 1))) {
            ESP_LOGW(TAG, "step %d (%s) failed — continuing without it", step,
                     bridge_boot_step_name(step));
        }
    }
    if (boot.force_ap) {
        ESP_LOGW(TAG, "network override: AP mode for this boot only");
    }

    /* Clear the double-reset token once the boot has been stable ~10 s. */
    const esp_timer_create_args_t targs = {
        .callback = disarm_timer_cb,
        .name = "drt_disarm",
    };
    esp_timer_handle_t timer;
    if (esp_timer_create(&targs, &timer) == ESP_OK) {
        esp_timer_start_once(timer, (uint64_t)BRIDGE_DRT_WINDOW_MS * 1000u);
    }

    ESP_LOGI(TAG, "boot complete: %d/%d steps", result.steps_completed,
             BRIDGE_BOOT_STEP_COUNT);
}
