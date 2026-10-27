#include "board.h"

#include <stdbool.h>

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "sx4.board";

static esp_err_t configure_vext_output(void) {
    gpio_config_t vext = {
        .pin_bit_mask = 1ULL << BOARD_PIN_VEXT,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    return gpio_config(&vext);
}

esp_err_t board_power_init(void) {
    /* Vext is active LOW. Configure it first so the rail is live before the
     * I2C bus is created (T09 bench rule). */
    esp_err_t err = configure_vext_output();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Vext config failed: %s", esp_err_to_name(err));
        return err;
    }
    gpio_set_level(BOARD_PIN_VEXT, 0);

    gpio_config_t rst = {
        .pin_bit_mask = 1ULL << BOARD_PIN_OLED_RST,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    err = gpio_config(&rst);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "OLED reset config failed: %s", esp_err_to_name(err));
        return err;
    }
    gpio_set_level(BOARD_PIN_OLED_RST, 1);

    /* Vext settle before the I2C bus/panel is touched (T09: 100 ms). */
    vTaskDelay(pdMS_TO_TICKS(100));
    ESP_LOGI(TAG, "Vext on (GPIO%d low), OLED reset released", BOARD_PIN_VEXT);
    return ESP_OK;
}

esp_err_t board_oled_reset_pulse(void) {
    gpio_set_level(BOARD_PIN_OLED_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    gpio_set_level(BOARD_PIN_OLED_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(20));
    return ESP_OK;
}

esp_err_t board_prg_init(void) {
    gpio_config_t prg = {
        .pin_bit_mask = 1ULL << BOARD_PIN_PRG,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&prg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "PRG config failed: %s", esp_err_to_name(err));
    }
    return err;
}

bool board_prg_pressed(void) { return gpio_get_level(BOARD_PIN_PRG) == 0; }

esp_err_t board_power_off_vext(void) {
    esp_err_t err = configure_vext_output();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Vext off config failed: %s", esp_err_to_name(err));
        return err;
    }
    gpio_set_level(BOARD_PIN_VEXT, 1);
    ESP_LOGI(TAG, "Vext off (GPIO%d high)", BOARD_PIN_VEXT);
    return ESP_OK;
}

esp_err_t board_enter_deep_sleep(void) {
    esp_err_t err = board_power_off_vext();
    if (err != ESP_OK) {
        return err;
    }

    /* GPIO0 is an RTC pin; EXT1 ANY_LOW is the path proved 20/20 by T09
     * (ADR 0020). The wake is a reset, so the boot path confirms the hold. */
    err = esp_sleep_enable_ext1_wakeup_io(1ULL << BOARD_PIN_PRG,
                                          ESP_EXT1_WAKEUP_ANY_LOW);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "GPIO%d EXT1 wake arm failed: %s", BOARD_PIN_PRG,
                 esp_err_to_name(err));
        return err;
    }
    ESP_LOGI(TAG, "deep sleep: Vext off, GPIO%d ANY_LOW wake armed",
             BOARD_PIN_PRG);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_deep_sleep_start();
    return ESP_ERR_INVALID_STATE; /* unreachable */
}
