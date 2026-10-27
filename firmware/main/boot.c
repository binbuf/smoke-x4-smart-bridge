/*
 * boot.c - ordered, failure-tolerant boot sequence (design 03 section 3.4).
 *
 * Only NVS is fatal. The remaining steps log a warning and continue, because a
 * BLE, radio or storage failure must not stop the parts that still work.
 */
#include "boot.h"

#include <stdbool.h>

#include "ble_service.h"
#include "board.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
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
    run_step("sx_radio_start", sx_radio_start);
    run_step("ble_service_start", ble_service_start);

    /* TODO(T20/T24): insert housekeeping_start() before the UI's first page,
     * per design 03 section 3.4 step 10. The task row already exists in
     * tasks.h so its stack is inside the asserted budget. */
    run_step("ui_start", ui_start);

    ESP_LOGI(TAG, "boot: sequence complete");
}
