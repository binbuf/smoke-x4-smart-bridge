/*
 * board_battery_esp.c - GPIO37 divider gating and calibrated ADC sampling.
 *
 * One sample cycle, exactly as design 01 section 1.3 requires:
 *   GPIO37 HIGH -> 200 us settle -> 32 x ADC1_CH0 (GPIO1, 12 dB) -> GPIO37 LOW
 * The LOW write is on every exit path, including a failed read, so the divider
 * is never left enabled between housekeeping ticks.
 *
 * Only the housekeeping task calls board_battery_sample(); there is no lock
 * because the owner is single-threaded.
 */
#include "board_battery.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "board.h"
#include "driver/gpio.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_rom_sys.h"

#define BATTERY_ADC_UNIT ADC_UNIT_1
#define BATTERY_ADC_CHANNEL ADC_CHANNEL_0 /* GPIO1 */
#define BATTERY_ADC_ATTEN ADC_ATTEN_DB_12
/* Accept a sample when at least 3/4 of the oversampled reads succeeded. */
#define BATTERY_ADC_MIN_GOOD (BOARD_BATTERY_ADC_SAMPLES * 3u / 4u)

static const char *TAG = "sx4.batt";

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;
static bool s_ready;
static board_battery_stats_t s_stats = {
    .percent = BOARD_BATTERY_SOC_UNKNOWN,
};

esp_err_t board_battery_init(void) {
    if (s_ready) {
        return ESP_OK;
    }

    gpio_config_t ctrl = {
        .pin_bit_mask = 1ULL << BOARD_PIN_BATTERY_EN,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&ctrl);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "GPIO%d config failed: %s", BOARD_PIN_BATTERY_EN,
                 esp_err_to_name(err));
        return err;
    }
    /* Divider starts disconnected. */
    gpio_set_level(BOARD_PIN_BATTERY_EN, 0);

    adc_oneshot_unit_init_cfg_t unit_cfg = {
        .unit_id = BATTERY_ADC_UNIT,
    };
    err = adc_oneshot_new_unit(&unit_cfg, &s_adc);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ADC unit init failed: %s", esp_err_to_name(err));
        s_adc = NULL;
        return err;
    }

    adc_oneshot_chan_cfg_t chan_cfg = {
        .atten = BATTERY_ADC_ATTEN,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    err = adc_oneshot_config_channel(s_adc, BATTERY_ADC_CHANNEL, &chan_cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ADC channel config failed: %s", esp_err_to_name(err));
        adc_oneshot_del_unit(s_adc);
        s_adc = NULL;
        return err;
    }

    adc_cali_curve_fitting_config_t cali_cfg = {
        .unit_id = BATTERY_ADC_UNIT,
        .chan = BATTERY_ADC_CHANNEL,
        .atten = BATTERY_ADC_ATTEN,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    err = adc_cali_create_scheme_curve_fitting(&cali_cfg, &s_cali);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ADC calibration init failed: %s",
                 esp_err_to_name(err));
        adc_oneshot_del_unit(s_adc);
        s_adc = NULL;
        s_cali = NULL;
        return err;
    }

    board_battery_stats_reset(&s_stats);
    s_ready = true;
    ESP_LOGI(TAG, "battery ADC ready: GPIO%d/ADC1_CH0, x%.2f divider",
             BOARD_PIN_BATTERY_ADC, (double)BOARD_BATTERY_DIVIDER_X100 / 100.0);
    return ESP_OK;
}

board_battery_reading_t board_battery_sample(void) {
    board_battery_reading_t reading = {
        .percent = BOARD_BATTERY_SOC_UNKNOWN,
    };
    if (!s_ready) {
        board_battery_stats_apply(&s_stats, &reading);
        return reading;
    }

    /* Enable the divider and let the RC node settle before the first read. */
    gpio_set_level(BOARD_PIN_BATTERY_EN, 1);
    esp_rom_delay_us(BOARD_BATTERY_SETTLE_US);

    uint32_t sum_raw = 0u;
    uint32_t good = 0u;
    for (uint32_t i = 0u; i < BOARD_BATTERY_ADC_SAMPLES; i++) {
        int raw = 0;
        if (adc_oneshot_read(s_adc, BATTERY_ADC_CHANNEL, &raw) == ESP_OK &&
            raw >= 0) {
            sum_raw += (uint32_t)raw;
            good++;
        }
    }

    /* Disconnect the divider before the slower calibration conversion. */
    gpio_set_level(BOARD_PIN_BATTERY_EN, 0);

    bool adc_ok = good >= BATTERY_ADC_MIN_GOOD;
    int adc_mv = 0;
    if (adc_ok) {
        uint32_t raw_avg = (sum_raw + good / 2u) / good;
        if (raw_avg > INT32_MAX ||
            adc_cali_raw_to_voltage(s_cali, (int)raw_avg, &adc_mv) != ESP_OK ||
            adc_mv <= 0) {
            adc_ok = false;
        }
    }

    reading = board_battery_convert(
        adc_ok ? (uint16_t)adc_mv : 0u, adc_ok, BOARD_BATTERY_DIVIDER_X100);
    board_battery_stats_apply(&s_stats, &reading);

    if (reading.valid) {
        ESP_LOGD(TAG, "battery: adc %u mV -> pack %u mV, %u%%",
                 (unsigned)reading.adc_mv, (unsigned)reading.pack_mv,
                 (unsigned)reading.percent);
    } else if (s_stats.failures == 1u) {
        /* Log the first failure loudly; a dead divider would otherwise spam a
         * warning every battery period. The unknown value is still published. */
        ESP_LOGW(TAG, "battery sample failed (good=%u/%u)", (unsigned)good,
                 (unsigned)BOARD_BATTERY_ADC_SAMPLES);
    } else {
        ESP_LOGD(TAG, "battery sample still failing (failures=%u)",
                 (unsigned)s_stats.failures);
    }
    return reading;
}

board_battery_stats_t board_battery_stats_get(void) { return s_stats; }
