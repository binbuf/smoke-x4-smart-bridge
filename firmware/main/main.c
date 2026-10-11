/* main.c — app_main: boot sequence, wiring, nothing else (design 03 §3.1).
 *
 * BLE-ONLY SLIM BUILD. The network/HTTP/OTA/MQTT/alarm subsystems of the full
 * bridge are gone; what remains is the part that is the product: receive the
 * Smoke X4 over LoRa, record it to flash, draw it on the OLED, and serve it
 * over Bluetooth. The two properties kept from the full boot are structural:
 * LoRa-before-BLE ordering lives in boot_seq's step table, and the
 * double-reset token is armed/consumed against RTC SRAM below — now used to
 * enter the on-device recovery (factory reset) flow rather than Wi-Fi AP mode.
 */
#include <inttypes.h>
#include <string.h>

#include "esp_attr.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "nvs_flash.h"

#include "app_ble.h"
#include "app_config.h"
#include "app_power.h"
#include "app_time.h"
#include "app_ui.h"
#include "boot_seq.h"
#include "cook_store.h"
#include "double_reset.h"
#include "smoke_x.h"
#include "tasks.h"

static const char *TAG = "smoke_bridge";

/* Survives a reset (not a power cycle) — the double-reset recovery token. */
static RTC_NOINIT_ATTR bridge_drt_token_t s_drt_token;

typedef struct {
    bool recovery; /* double reset: open the factory-reset flow this boot */
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
        ESP_LOGW(TAG, "double reset detected — opening recovery this boot");
        boot->recovery = true;
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

/* F12: early, because the OLED status strip and the saver profile read what
 * it publishes. Not fatal — a bridge that cannot measure its pack says
 * SOC_UNKNOWN and cooks. */
static int step_power(void *ctx) {
    (void)ctx;
    return app_power_init();
}

/* The display comes up BEFORE BLE, because the pairing passkey is shown on
 * it. Neither is fatal: a bridge with a dead panel or no BLE still cooks. */
static int step_ui(void *ctx) {
    (void)ctx;
    return app_ui_init();
}

static int step_ble(void *ctx) {
    (void)ctx;
    return app_ble_init();
}

static void disarm_timer_cb(void *arg) {
    (void)arg;
    bridge_double_reset_disarm(&s_drt_token);
    ESP_LOGD(TAG, "double-reset token disarmed");
}

/* The confirmed recovery: wipe every store, then reboot. Registered with
 * app_ui so the UI never depends on the components that own the stores. */
static void recovery_commit(void) {
    ESP_LOGW(TAG, "factory reset: wiping bonds, config and recorded cooks");
    (void)app_ble_forget_bonds();
    (void)cook_store_wipe_all();
    (void)app_config_store_factory_reset();
    esp_restart(); /* does not return */
}

void app_main(void) {
    /* Soft power (07 §7.4): if this boot is a wake from a PRG-hold deep
     * sleep, confirm a sustained hold here — before any subsystem starts —
     * or go straight back to sleep. Returns immediately on a normal boot. */
    app_power_wake_gate();

    ESP_LOGI(TAG, "Smoke X4 Smart Bridge — BLE-only slim build");
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
                [BRIDGE_BOOT_POWER - 1] = step_power,
                [BRIDGE_BOOT_UI - 1] = step_ui,
                [BRIDGE_BOOT_COOK_STORE - 1] = step_cook_store,
                [BRIDGE_BOOT_SMOKE_X_INIT - 1] = step_smoke_x_init,
                [BRIDGE_BOOT_SMOKE_X_START - 1] = step_smoke_x_start,
                [BRIDGE_BOOT_TIME - 1] = step_time,
                [BRIDGE_BOOT_BLE - 1] = step_ble,
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

    /* The UI owns the button and the panel, so it owns the reset flow; main
     * supplies what the commit does. Register before any recovery can open. */
    app_ui_set_recovery_hook(recovery_commit);

    /* If this boot came from a double reset, open the flow now. */
    if (boot.recovery) {
        app_ui_request_recovery();
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