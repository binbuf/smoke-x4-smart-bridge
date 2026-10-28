/*
 * boot.c - ordered, failure-tolerant boot sequence (design 03 section 3.4).
 *
 * Only NVS is fatal. The remaining steps log a warning and continue, because a
 * BLE, radio or storage failure must not stop the parts that still work.
 */
#include "boot.h"

#include <stdbool.h>

#include "ble_control.h"
#include "ble_control_actions.h"
#include "ble_service.h"
#include "ble_tx.h"
#include "board.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "housekeeping.h"
#include "nvs_flash.h"
#include "sample_log.h"
#include "sample_pipe.h"
#include "sx_protocol.h"
#include "sx_radio.h"
#include "ui.h"
#include "ui_button.h"

static const char *TAG = "sx4.boot";

static uint64_t boot_now_ms(void) {
    return (uint64_t)(esp_timer_get_time() / 1000);
}

/* A deep-sleep wake is the user holding PRG. Confirm the hold for ~1.5 s
 * before NVS, BLE or the UI start; an early release goes straight back to
 * sleep. Cold boots (USB, EN reset) skip this. */
static void confirm_wake_hold(void) {
    if ((esp_sleep_get_wakeup_causes() & (1u << ESP_SLEEP_WAKEUP_EXT1)) ==
        0u) {
        return;
    }
    (void)board_prg_init();
    ui_boot_hold_t hold;
    ui_boot_hold_init(&hold, board_prg_pressed(), boot_now_ms());
    ESP_LOGI(TAG, "deep-sleep wake: confirming PRG hold");

    for (;;) {
        ui_boot_hold_result_t result = ui_boot_hold_sample(
            &hold, board_prg_pressed(), boot_now_ms());
        if (result == UI_BOOT_HOLD_CONFIRMED) {
            ESP_LOGI(TAG, "hold-to-wake confirmed");
            return;
        }
        if (result == UI_BOOT_HOLD_RELEASED) {
            ESP_LOGW(TAG, "PRG released before 1.5 s; returning to sleep");
            for (;;) {
                if (board_enter_deep_sleep() == ESP_OK) {
                    return; /* unreachable */
                }
                vTaskDelay(pdMS_TO_TICKS(1000));
            }
        }
        vTaskDelay(pdMS_TO_TICKS(UI_BUTTON_SAMPLE_MS));
    }
}

static esp_err_t init_nvs(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "nvs needs erase (%s), reformatting", esp_err_to_name(err));
        esp_err_t erase_err = nvs_flash_erase();
        if (erase_err != ESP_OK) {
            return erase_err;
        }
        err = nvs_flash_init();
    }
    return err;
}

static void run_step(const char *name, esp_err_t (*step)(void)) {
    esp_err_t err = step();
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "%s: ok", name);
    } else {
        ESP_LOGW(TAG, "%s: failed (%s); continuing", name,
                 esp_err_to_name(err));
    }
}

/* T30 seam: the BLE service owns the passkey lifetime, the UI owns the OLED. */
static void show_passkey(const char *digits, void *ctx) {
    (void)ctx;
    ui_set_passkey(digits);
}

/* T47 seam: an accepted config write changes the OLED without a reboot. The
 * next UI snapshot reads units/name from bridge_config; the display timeout is
 * pushed straight into the sleep state machine. */
static void apply_config(uint8_t units, uint16_t display_timeout_s, void *ctx) {
    (void)units; /* read from bridge_config by the next snapshot */
    (void)ctx;
    ui_set_display_timeout(display_timeout_s);
    ui_mark_dirty();
}

/* ---- T48 destructive control actions ----------------------------------- */

static esp_timer_handle_t s_reboot_timer;

static void reboot_timer_cb(void *arg) {
    (void)arg;
    esp_restart();
}

static uint8_t config_failure(bridge_config_result_t rc) {
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return SX4_RESULT_STATUS_STORAGE;
    }
    if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
        return SX4_RESULT_STATUS_NOT_FOUND;
    }
    if (rc == BRIDGE_CONFIG_ERR_INVALID) {
        return SX4_RESULT_STATUS_INVALID;
    }
    return SX4_RESULT_STATUS_FAILED;
}

static uint8_t action_forget_phone(void *ctx) {
    (void)ctx;
    return ble_service_forget_current_peer();
}

/*
 * Wipe first, then schedule the reboot. A lost timer leaves a fully wiped
 * device rather than a half-wiped one. The result was notified ~250 ms ago.
 */
static uint8_t action_factory_reset(void *ctx) {
    (void)ctx;
    bridge_config_result_t rc = bridge_config_factory_reset();
    if (rc != BRIDGE_CONFIG_OK) {
        ESP_LOGE(TAG, "factory reset wipe failed (%d); not rebooting", (int)rc);
        return config_failure(rc);
    }

    if (s_reboot_timer == NULL) {
        const esp_timer_create_args_t args = {
            .callback = reboot_timer_cb,
            .name = "reset_reboot",
        };
        if (esp_timer_create(&args, &s_reboot_timer) != ESP_OK) {
            s_reboot_timer = NULL;
        }
    }
    if (s_reboot_timer != NULL &&
        esp_timer_start_once(s_reboot_timer, 50u * 1000u) == ESP_OK) {
        return SX4_RESULT_STATUS_OK;
    }

    /* No timer: reboot now. The wipe is already complete. */
    esp_restart();
    return SX4_RESULT_STATUS_OK;
}

static uint8_t action_power_off(void *ctx) {
    (void)ctx;
    (void)board_power_off_vext();
    (void)sx_radio_sleep();
    esp_err_t err = board_enter_deep_sleep();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "power_off: deep sleep failed (%s)",
                 esp_err_to_name(err));
        return SX4_RESULT_STATUS_FAILED;
    }
    return SX4_RESULT_STATUS_OK; /* unreachable */
}

static uint8_t action_clear_history(void *ctx) {
    (void)ctx;
    esp_err_t err = sample_log_clear();
    if (err == ESP_OK) {
        ui_mark_dirty();
        return SX4_RESULT_STATUS_OK;
    }
    if (err == ESP_ERR_INVALID_STATE) {
        return SX4_RESULT_STATUS_STORAGE;
    }
    return SX4_RESULT_STATUS_FAILED;
}

static uint8_t action_unpair_smoke_x(void *ctx) {
    (void)ctx;
    esp_err_t err = sx_radio_unpair();
    if (err == ESP_OK) {
        ui_mark_dirty();
        return SX4_RESULT_STATUS_OK;
    }
    return SX4_RESULT_STATUS_FAILED;
}

static const ble_control_action_ops_t s_control_actions = {
    .forget_phone = action_forget_phone,
    .factory_reset = action_factory_reset,
    .power_off = action_power_off,
    .clear_history = action_clear_history,
    .unpair_smoke_x = action_unpair_smoke_x,
};

static uint8_t run_control_action(ble_control_action_t action, void *ctx) {
    (void)ctx;
    return ble_control_actions_run(&s_control_actions, action);
}

void sx4_boot_run(void) {
    ESP_LOGI(TAG, "boot: starting");

    /* The wake confirmation owns the button until it either commits the boot
     * or returns to sleep; nothing else starts on an unconfirmed wake. */
    confirm_wake_hold();

    ESP_ERROR_CHECK(init_nvs());
    ESP_LOGI(TAG, "nvs: ok");

    run_step("bridge_config_init", bridge_config_init);
    run_step("bridge_state_init", bridge_state_init);
    run_step("board_prg_init", board_prg_init);
    run_step("board_power_init", board_power_init);
    run_step("ui_init", ui_init);
    run_step("sample_log_init", sample_log_init);
    run_step("sx_protocol_init", sx_protocol_init);
    run_step("sx_radio_init", sx_radio_init);
    run_step("sample_pipe_start", sample_pipe_start);
    run_step("ble_tx_start", ble_tx_start);
    run_step("sx_radio_start", sx_radio_start);
    ble_service_set_passkey_callback(show_passkey, NULL);
    ble_service_set_config_applied_callback(apply_config, NULL);
    /* T48: register the reply-first destructive handlers before the GATT
     * service can accept a control write. */
    ble_control_set_action_handler(run_control_action, NULL);
    run_step("ble_service_start", ble_service_start);

    /* Housekeeping owns battery sampling and the clock-persistence cadence;
     * it starts before the UI so the first page has a real battery value. */
    run_step("housekeeping_start", housekeeping_start);
    run_step("ui_start", ui_start);

    ESP_LOGI(TAG, "boot: sequence complete");
}
