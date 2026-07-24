/* app_power.c — the ESP-IDF glue for battery measurement (F12.4;
 * design 01 §1.2, §1.3, hardware-verified V1.3).
 *
 * Thin by construction: ADC1 channel 0 on GPIO1 through adc_oneshot with
 * the calibration scheme, the GPIO37 divider gate, and the app_power task
 * row that has been declared in main/tasks.h since F1.4 (M5 populates it,
 * it does not add one). Every decision — the curve, the filter, the
 * charging inference, the plateau solver, the saver hysteresis — is in
 * app_power_core.h and runs on the host.
 *
 * THE ONE FACT THAT LIVES ONLY HERE: V1.3 found the divider gate INVERTED
 * from 01 §1.3's own pseudocode. GPIO37 **HIGH** connects the divider;
 * LOW disconnects it and reads 0 mV. op_gate() is the single place in the
 * firmware that knows, the same way app_ui's op_vext_power is the single
 * place that knows Vext is active LOW.
 *
 * ADC2 is unusable while Wi-Fi is active (01 §1.2). Nothing here touches
 * it.
 */
#include "app_power.h"

#include <string.h>

#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "app_power_svc.h"
#include "bridge_event.h"

static const char *TAG = "app_power";

/* Mirrors the app_power row of main/tasks.h — components cannot depend on
 * `main`, so the table stays the single source of truth and this is a copy
 * of one row. test_tasks_table.c pins the values. */
#define POWER_TASK_NAME "app_power"
#define POWER_TASK_STACK 2560
#define POWER_TASK_PRIO 2
#define POWER_TASK_CORE 0

/* 01 §1.2 pin map. */
#define PIN_VBAT_ADC ADC_CHANNEL_0 /* GPIO1 */
#define PIN_ADC_CTRL GPIO_NUM_37

/* 01 §1.6: "battery ADC every 30 s, SoC filter". */
#define POWER_PERIOD_MS 30000
/* 01 §1.3: "oversample ADC1_CH0 ... ~64 samples". */
#define POWER_OVERSAMPLE 64

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;
static bool s_have_cali;

/* ── the ADC seam (host-tested in test_app_power.c) ─────────────────── */

static int op_gate(void *ctx, bool enable) {
    (void)ctx;
    /* V1.3: HIGH = divider connected. Inverted from 01 §1.3's pseudocode,
     * which drives it LOW; the board wins. */
    return gpio_set_level(PIN_ADC_CTRL, enable ? 1 : 0) == ESP_OK ? 0 : -1;
}

static int op_read_mv(void *ctx, uint16_t *mv) {
    (void)ctx;
    if (s_adc == NULL) {
        return -1;
    }
    int32_t sum = 0;
    int taken = 0;
    for (int i = 0; i < POWER_OVERSAMPLE; i++) {
        int raw = 0;
        if (adc_oneshot_read(s_adc, PIN_VBAT_ADC, &raw) != ESP_OK) {
            continue;
        }
        sum += raw;
        taken++;
    }
    if (taken == 0) {
        return -1;
    }
    const int avg = (int)(sum / taken);
    int out_mv = 0;
    if (s_have_cali) {
        if (adc_cali_raw_to_voltage(s_cali, avg, &out_mv) != ESP_OK) {
            return -1;
        }
    } else {
        /* No calibration scheme (an unfused part): the 12-bit full scale
         * at 12 dB is ~3.1 V. Approximate rather than refuse — a rough
         * percentage still beats none, and the plateau solver corrects
         * the divider half of the error. */
        out_mv = (avg * 3100) / 4095;
    }
    *mv = (uint16_t)(out_mv < 0 ? 0 : out_mv);
    return 0;
}

static void op_delay_us(void *ctx, uint32_t us) {
    (void)ctx;
    esp_rom_delay_us(us);
}

static const app_power_adc_ops_t k_adc_ops = {
    .gate = op_gate,
    .read_mv = op_read_mv,
    .delay_us = op_delay_us,
};

/* ── the task row ───────────────────────────────────────────────────── */

static void publish(void) {
    const bridge_evt_power_t e = {
        .mv = app_power_svc_mv(),
        .soc_pct = app_power_svc_soc(),
        .charging = app_power_svc_charging(),
        .saver = app_power_svc_saver(),
    };
    (void)bridge_event_post(BRIDGE_EVT_POWER, &e, sizeof e);
}

static void power_task(void *arg) {
    (void)arg;
    for (;;) {
        uint16_t adc_mv = 0;
        const uint32_t now_s =
            (uint32_t)((uint64_t)esp_timer_get_time() / 1000000ull);
        if (app_power_read_once(&k_adc_ops, &adc_mv) != 0) {
            adc_mv = 0; /* SOC_UNKNOWN, never a fabricated 0 % */
        }
        /* Published on change only: a steady pack costs nothing on the
         * event loop, and 03 §3.2 cares about that. */
        if (app_power_svc_sample(adc_mv, now_s)) {
            publish();
        }
        vTaskDelay(pdMS_TO_TICKS(POWER_PERIOD_MS));
    }
}

int app_power_init(void) {
    const gpio_config_t out = {
        .pin_bit_mask = 1ULL << PIN_ADC_CTRL,
        .mode = GPIO_MODE_OUTPUT,
    };
    if (gpio_config(&out) != ESP_OK) {
        return -1;
    }
    /* Leave the divider DISCONNECTED between reads — it is a permanent
     * quiescent draw otherwise, on a device whose whole §1.6 budget is
     * about tens of milliamps. */
    (void)op_gate(NULL, false);

    const adc_oneshot_unit_init_cfg_t unit = {.unit_id = ADC_UNIT_1};
    if (adc_oneshot_new_unit(&unit, &s_adc) != ESP_OK) {
        return -1;
    }
    const adc_oneshot_chan_cfg_t chan = {
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    if (adc_oneshot_config_channel(s_adc, PIN_VBAT_ADC, &chan) != ESP_OK) {
        return -1;
    }
#if CONFIG_IDF_TARGET_ESP32S3
    const adc_cali_curve_fitting_config_t cali = {
        .unit_id = ADC_UNIT_1,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    s_have_cali =
        adc_cali_create_scheme_curve_fitting(&cali, &s_cali) == ESP_OK;
#endif

    if (app_power_svc_init() != 0) {
        return -1;
    }

    if (xTaskCreatePinnedToCore(power_task, POWER_TASK_NAME, POWER_TASK_STACK,
                                NULL, POWER_TASK_PRIO, NULL,
                                POWER_TASK_CORE) != pdPASS) {
        return -1;
    }
    ESP_LOGI(TAG, "battery up: GPIO37 HIGH gates the divider (V1.3), %s",
             s_have_cali ? "eFuse-calibrated ADC" : "uncalibrated ADC");
    return 0;
}
