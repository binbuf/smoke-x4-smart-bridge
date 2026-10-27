#include "board.h"

#include <stdbool.h>

#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "sx4.board";

esp_err_t board_power_init(void) {
    /* Vext is active LOW. Configure it first so the rail is live before the
     * I2C bus is created (T09 bench rule). */
    gpio_config_t vext = {
        .pin_bit_mask = 1ULL << BOARD_PIN_VEXT,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&vext);
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
