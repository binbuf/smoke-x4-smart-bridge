/* bench.c — the V1.3/V1.4 bench instrument (design 01 §1.2–§1.4, §1.8).
 *
 * One sitting, one flash, a DMM, and this log output close:
 *   V1.3  GPIO37 gates the VBAT divider; ratio ×4.9 vs ×2.0 vs the DMM
 *   V1.4  PRG button debounce · GPIO35 LED active-HIGH + PWM dim ·
 *         GPIO36 Vext gate · OLED I²C @ 400 kHz stable under Wi-Fi AP
 *
 * Every measurement line is prefixed "BENCH" so it can be grepped straight
 * into docs/hardware-verified.md. The BLE half of the I²C stability check
 * cannot run yet (no BLE stack until M3) and is carried forward per V1.4.
 */
#include "bench.h"

#include "sdkconfig.h"

#if CONFIG_SMOKEBRIDGE_BENCH_MODE

#include <inttypes.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/ledc.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

static const char *TAG = "bench";

/* Heltec WiFi LoRa 32 V3 pins (design 01 §1.2). */
#define PIN_BTN 0        /* PRG, active LOW, boot strapping pin      */
#define PIN_LED 35       /* white LED, active HIGH, PWM-capable      */
#define PIN_VEXT 36      /* OLED rail gate, active LOW (P-MOSFET)    */
#define PIN_ADC_CTRL 37  /* drive LOW to enable the battery divider  */
#define PIN_OLED_SDA 17
#define PIN_OLED_SCL 18
#define PIN_OLED_RST 21
#define VBAT_ADC_CHANNEL ADC_CHANNEL_0 /* GPIO1 = ADC1_CH0 */
#define OLED_ADDR 0x3C

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali; /* NULL when calibration unavailable */
static i2c_master_bus_handle_t s_i2c_bus;
static i2c_master_dev_handle_t s_oled;
static uint32_t s_i2c_ok;
static uint32_t s_i2c_err;

/* ── battery ADC (V1.3) ───────────────────────────────────────────── */

static void adc_init(void)
{
    const adc_oneshot_unit_init_cfg_t ucfg = {
        .unit_id = ADC_UNIT_1,
    };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&ucfg, &s_adc));
    const adc_oneshot_chan_cfg_t ccfg = {
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, VBAT_ADC_CHANNEL, &ccfg));

    const adc_cali_curve_fitting_config_t cali_cfg = {
        .unit_id = ADC_UNIT_1,
        .chan = VBAT_ADC_CHANNEL,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    if (adc_cali_create_scheme_curve_fitting(&cali_cfg, &s_cali) != ESP_OK) {
        s_cali = NULL;
        ESP_LOGW(TAG, "ADC calibration unavailable — reporting raw counts");
    }
}

/* Oversampled, calibrated millivolts at the ADC pin. */
static int adc_read_mv(void)
{
    int64_t sum = 0;
    const int samples = 64;
    for (int i = 0; i < samples; i++) {
        int raw = 0;
        if (adc_oneshot_read(s_adc, VBAT_ADC_CHANNEL, &raw) != ESP_OK) {
            return -1;
        }
        sum += raw;
    }
    const int raw_avg = (int)(sum / samples);
    if (s_cali != NULL) {
        int mv = 0;
        if (adc_cali_raw_to_voltage(s_cali, raw_avg, &mv) == ESP_OK) {
            return mv;
        }
    }
    /* Uncalibrated fallback: 12-bit full scale ≈ 3100 mV at 12 dB. */
    return raw_avg * 3100 / 4095;
}

static void vbat_measure(void)
{
    /* Divider enabled: GPIO37 LOW, settle, read (01 §1.3). */
    gpio_set_level(PIN_ADC_CTRL, 0);
    esp_rom_delay_us(200);
    const int mv_on = adc_read_mv();
    /* Divider disabled: the pin should no longer track the pack. */
    gpio_set_level(PIN_ADC_CTRL, 1);
    esp_rom_delay_us(200);
    const int mv_off = adc_read_mv();

    ESP_LOGI(TAG,
             "BENCH V1.3 vbat: adc_divider_ON=%dmV adc_divider_OFF=%dmV | "
             "pack_if_x4.9=%dmV pack_if_x2.0=%dmV  <- compare DMM here",
             mv_on, mv_off, mv_on * 49 / 10, mv_on * 2);
}

/* ── OLED / I²C (V1.4) ────────────────────────────────────────────── */

static esp_err_t oled_cmds(const uint8_t *cmds, size_t n)
{
    uint8_t buf[40];
    if (n + 1 > sizeof buf) {
        return ESP_ERR_INVALID_ARG;
    }
    buf[0] = 0x00; /* control byte: commands */
    memcpy(buf + 1, cmds, n);
    return i2c_master_transmit(s_oled, buf, n + 1, 100);
}

static esp_err_t oled_init_display(void)
{
    static const uint8_t init_seq[] = {
        0xAE,       /* display off              */
        0xD5, 0x80, /* clock divide             */
        0xA8, 0x3F, /* multiplex 64             */
        0xD3, 0x00, /* display offset           */
        0x40,       /* start line 0             */
        0x8D, 0x14, /* charge pump on           */
        0x20, 0x00, /* horizontal addressing    */
        0xA1,       /* segment remap            */
        0xC8,       /* COM scan direction       */
        0xDA, 0x12, /* COM pins                 */
        0x81, 0xCF, /* contrast                 */
        0xD9, 0xF1, /* precharge                */
        0xDB, 0x40, /* VCOM detect              */
        0xA4,       /* resume from RAM          */
        0xA6,       /* normal (not inverted)    */
        0xAF,       /* display on               */
    };
    return oled_cmds(init_seq, sizeof init_seq);
}

/* Checkerboard with a moving inverted column so life is visible. */
static esp_err_t oled_draw_frame(uint32_t frame)
{
    static uint8_t buf[1 + 1024];
    static const uint8_t window[] = {
        0x21, 0x00, 0x7F, /* columns 0..127 */
        0x22, 0x00, 0x07, /* pages 0..7     */
    };
    esp_err_t err = oled_cmds(window, sizeof window);
    if (err != ESP_OK) {
        return err;
    }
    buf[0] = 0x40; /* control byte: data */
    const int live_col = (int)(frame % 128u);
    for (int i = 0; i < 1024; i++) {
        const int col = i % 128;
        const int page = i / 128;
        uint8_t v = ((col / 8 + page) % 2 != 0) ? 0xFF : 0x00;
        if (col == live_col) {
            v = (uint8_t)~v;
        }
        buf[1 + i] = v;
    }
    return i2c_master_transmit(s_oled, buf, sizeof buf, 200);
}

static void oled_and_vext_init(void)
{
    const i2c_master_bus_config_t bus_cfg = {
        .i2c_port = -1,
        .sda_io_num = PIN_OLED_SDA,
        .scl_io_num = PIN_OLED_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags = { .enable_internal_pullup = true },
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_cfg, &s_i2c_bus));

    /* The Vext gate test: with the rail OFF (GPIO36 HIGH) the OLED must
     * not ACK; with the rail ON (LOW) it must. */
    gpio_set_level(PIN_VEXT, 1);
    vTaskDelay(pdMS_TO_TICKS(100));
    const esp_err_t off_probe = i2c_master_probe(s_i2c_bus, OLED_ADDR, 100);

    /* The board's I²C pull-ups hang off the SWITCHED rail: the dead-rail
     * probe ran on floating lines and can leave the controller flagged
     * bus-busy. Recreate the bus once the rail is up, or the rail-on
     * probe fails for a reason that has nothing to do with the gate. */
    ESP_ERROR_CHECK(i2c_del_master_bus(s_i2c_bus));

    gpio_set_level(PIN_VEXT, 0);
    vTaskDelay(pdMS_TO_TICKS(100));
    /* Reset pulse after the rail is up. */
    gpio_set_level(PIN_OLED_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(10));
    gpio_set_level(PIN_OLED_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(50));
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_cfg, &s_i2c_bus));
    const esp_err_t on_probe = i2c_master_probe(s_i2c_bus, OLED_ADDR, 100);
    if (on_probe != ESP_OK) {
        /* Probe quirks must not condemn the gate: scan for anything that
         * ACKs before believing the rail is dead. */
        for (uint8_t a = 0x08; a <= 0x77; a++) {
            if (i2c_master_probe(s_i2c_bus, a, 20) == ESP_OK) {
                ESP_LOGI(TAG, "BENCH V1.4 i2c-scan: ACK at 0x%02X", a);
            }
        }
    }

    /* The authoritative rail-on check is the panel INIT, not the probe —
     * the reference proved this exact panel on these pins by simply
     * initialising it. */
    const i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = OLED_ADDR,
        .scl_speed_hz = 400000, /* the V1.4 rate under test */
    };
    ESP_ERROR_CHECK(i2c_master_bus_add_device(s_i2c_bus, &dev_cfg, &s_oled));
    const esp_err_t init_res = oled_init_display();

    ESP_LOGI(TAG,
             "BENCH V1.4 vext-gate: rail_off_probe=%s%s rail_on_probe=%s "
             "rail_on_init=%s%s",
             off_probe == ESP_OK ? "ACK" : "NO_ACK",
             off_probe == ESP_OK ? "(UNEXPECTED!)" : "(expected)",
             on_probe == ESP_OK ? "ACK" : "NO_ACK",
             init_res == ESP_OK ? "OK" : "FAIL",
             init_res == ESP_OK ? "(good)" : "(check Vext/GPIO36)");

    if (init_res == ESP_OK) {
        ESP_LOGI(TAG, "BENCH V1.4 oled: init OK @400kHz — expect a "
                      "checkerboard with a moving stripe");
    }
}

/* ── LED (V1.4) ───────────────────────────────────────────────────── */

static void led_init(void)
{
    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_13_BIT,
        .timer_num = LEDC_TIMER_0,
        .freq_hz = 5000,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));
    const ledc_channel_config_t channel = {
        .gpio_num = PIN_LED,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_0,
        .intr_type = LEDC_INTR_DISABLE,
        .timer_sel = LEDC_TIMER_0,
        .duty = 0,
        .hpoint = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel));
    ESP_ERROR_CHECK(ledc_fade_func_install(0));
}

static void led_breathe(bool up)
{
    const uint32_t target = up ? 8191 : 0;
    ledc_set_fade_with_time(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, target, 1900);
    ledc_fade_start(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, LEDC_FADE_NO_WAIT);
    ESP_LOGI(TAG,
             "BENCH V1.4 led: fading to %s (active-HIGH: LED should %s)",
             up ? "100%" : "0%", up ? "brighten" : "dim");
}

/* ── button (V1.4) ────────────────────────────────────────────────── */

static void button_task(void *arg)
{
    (void)arg;
    int stable = 1; /* pull-up idle HIGH */
    int candidate = 1;
    int candidate_ticks = 0;
    uint32_t presses = 0;
    int64_t pressed_at_us = 0;

    for (;;) {
        const int level = gpio_get_level(PIN_BTN);
        if (level == candidate) {
            if (candidate_ticks < 100) {
                candidate_ticks++;
            }
        } else {
            candidate = level;
            candidate_ticks = 0;
        }
        /* 30 ms of agreement = debounced (survives the boot strap). */
        if (candidate_ticks == 3 && candidate != stable) {
            stable = candidate;
            if (stable == 0) {
                presses++;
                pressed_at_us = esp_timer_get_time();
                ESP_LOGI(TAG, "BENCH V1.4 button: PRG press #%" PRIu32,
                         presses);
            } else {
                ESP_LOGI(TAG,
                         "BENCH V1.4 button: PRG released (held %d ms)",
                         (int)((esp_timer_get_time() - pressed_at_us) / 1000));
            }
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* ── Wi-Fi soft-AP (the "while Wi-Fi is active" half of V1.4) ─────── */

static void wifi_ap_init(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    wifi_config_t ap = { 0 };
    memcpy(ap.ap.ssid, "SmokeBridge-BENCH", 17);
    ap.ap.ssid_len = 17;
    ap.ap.channel = 6;
    ap.ap.max_connection = 2;
    ap.ap.authmode = WIFI_AUTH_OPEN;
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_LOGI(TAG, "BENCH wifi: soft-AP 'SmokeBridge-BENCH' up (open, ch 6)");
}

/* ── the bench loop ───────────────────────────────────────────────── */

void bench_run(void)
{
    ESP_LOGI(TAG, "════ Smoke Bridge BENCH mode (V1.3/V1.4) ════");
    ESP_LOGI(TAG, "grep for 'BENCH' and transcribe into "
                  "docs/hardware-verified.md");

    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    }

    const gpio_config_t out_cfg = {
        .pin_bit_mask = (1ULL << PIN_VEXT) | (1ULL << PIN_ADC_CTRL) |
                        (1ULL << PIN_OLED_RST),
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_ERROR_CHECK(gpio_config(&out_cfg));
    const gpio_config_t btn_cfg = {
        .pin_bit_mask = 1ULL << PIN_BTN,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&btn_cfg));

    wifi_ap_init();
    adc_init();
    led_init();
    oled_and_vext_init();
    xTaskCreate(button_task, "bench_btn", 3072, NULL, 5, NULL);

    uint32_t frame = 0;
    bool led_up = true;
    for (;;) {
        vbat_measure();

        if (s_oled != NULL) {
            /* A burst of frames = the I²C-under-Wi-Fi stability counter. */
            for (int i = 0; i < 10; i++) {
                if (oled_draw_frame(frame++) == ESP_OK) {
                    s_i2c_ok++;
                } else {
                    s_i2c_err++;
                }
            }
            ESP_LOGI(TAG,
                     "BENCH V1.4 i2c@400kHz(wifi-ap-on): ok=%" PRIu32
                     " err=%" PRIu32,
                     s_i2c_ok, s_i2c_err);
        }

        led_breathe(led_up);
        led_up = !led_up;

        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}

#else /* !CONFIG_SMOKEBRIDGE_BENCH_MODE */

void bench_run(void)
{
    /* Bench mode not compiled in. */
}

#endif
