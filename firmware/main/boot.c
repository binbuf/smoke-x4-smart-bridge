/*
 * boot.c - ordered, failure-tolerant boot sequence (design 03 section 3.4).
 *
 * Only NVS is fatal. The remaining steps log a warning and continue, because a
 * BLE, radio or storage failure must not stop the parts that still work.
 */
#include "boot.h"

#include <stdbool.h>

#include "ble_service.h"
#include "ble_tx.h"
#include "board.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_sleep.h"
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
    run_step("ble_service_start", ble_service_start);

    /* Housekeeping owns battery sampling and the clock-persistence cadence;
     * it starts before the UI so the first page has a real battery value. */
    run_step("housekeeping_start", housekeeping_start);
    run_step("ui_start", ui_start);

    ESP_LOGI(TAG, "boot: sequence complete");
}
