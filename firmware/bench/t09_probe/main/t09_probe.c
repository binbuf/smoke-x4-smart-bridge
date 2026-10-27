/*
 * T09 bench probe — NOT product code.
 *
 * Purpose, one bench sitting:
 *   - prove the board really is an ESP32-S3 / 8 MB / SSD1306 / SX1262 Heltec V3
 *   - prove Vext (GPIO36 LOW) gates the OLED rail and the panel ACKs on I2C
 *   - prove GPIO37 HIGH enables the battery divider and report a pack voltage
 *   - show GPIO0 (PRG) as a clean debounced button after boot
 *   - advertise over bare NimBLE for a few seconds, then enter deep sleep
 *   - on each GPIO0 wake, print a monotonic WAKE line from RTC RAM, so an
 *     external driver can count application boots vs ROM-download boots.
 *
 * The image is intentionally an IDF example-shaped throwaway: one app slot,
 * no product service, no Wi-Fi, no storage. It is flashed only for T09.
 */

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_task_wdt.h"
#include "esp_timer.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"

#define PIN_PRG        0
#define PIN_VEXT       36
#define PIN_ADC_CTRL   37
#define PIN_ADC        1
#define PIN_SDA        17
#define PIN_SCL        18
#define PIN_OLED_RST   21
#define PIN_LORA_NSS   8
#define PIN_LORA_SCK   9
#define PIN_LORA_MOSI  10
#define PIN_LORA_MISO  11
#define PIN_LORA_RST   12
#define PIN_LORA_BUSY  13

#define PROBE_NAME "SX4-T09-PROBE"
#define OLED_ADDR  0x3C

static const char *TAG = "t09probe";

/* Survives deep sleep on the ESP32-S3 RTC domain. */
RTC_DATA_ATTR static uint32_t s_boot_count;
RTC_DATA_ATTR static uint32_t s_wake_count;
RTC_DATA_ATTR static uint32_t s_probe_done;
#define PROBE_MAGIC 0x54303902u

static i2c_master_bus_handle_t s_i2c_bus;

/* ── OLED / Vext ─────────────────────────────────────────────────────── */

static esp_err_t oled_cmd(i2c_master_dev_handle_t dev, uint8_t cmd)
{
    uint8_t buf[2] = { 0x00, cmd };
    return i2c_master_transmit(dev, buf, sizeof buf, 100);
}

static esp_err_t oled_init_and_check(void)
{
    /* RST must be released before the bus is probed. Vext is active LOW on
     * this board. Power the rail BEFORE the bus. */
    gpio_set_direction(PIN_OLED_RST, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_OLED_RST, 1);
    gpio_set_direction(PIN_VEXT, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_VEXT, 0);
    vTaskDelay(pdMS_TO_TICKS(100));

    i2c_master_bus_config_t bus_cfg = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_0,
        .scl_io_num = PIN_SCL,
        .sda_io_num = PIN_SDA,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    esp_err_t err = i2c_new_master_bus(&bus_cfg, &s_i2c_bus);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "VEXT_CHECK i2c bus: %s", esp_err_to_name(err));
        return err;
    }

    err = i2c_master_probe(s_i2c_bus, OLED_ADDR, 200);
    ESP_LOGI(TAG, "VEXT_CHECK gpio36=0, i2c probe 0x%02x: %s", OLED_ADDR,
             esp_err_to_name(err));
    if (err != ESP_OK) {
        /* Address scan, so a missing ACK is evidence rather than a guess. */
        char found[64] = { 0 };
        for (uint8_t a = 0x08; a < 0x78; a++) {
            if (i2c_master_probe(s_i2c_bus, a, 20) == ESP_OK) {
                size_t n = strlen(found);
                snprintf(found + n, sizeof found - n, " 0x%02x", a);
            }
        }
        ESP_LOGW(TAG, "VEXT_CHECK i2c scan found:%s",
                 found[0] ? found : " (none)");
        return err;
    }

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = OLED_ADDR,
        .scl_speed_hz = 400000,
    };
    i2c_master_dev_handle_t oled;
    err = i2c_master_bus_add_device(s_i2c_bus, &dev_cfg, &oled);
    if (err != ESP_OK) {
        return err;
    }

    gpio_set_direction(PIN_OLED_RST, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_OLED_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    gpio_set_level(PIN_OLED_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(20));

    static const uint8_t init[] = {
        0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40,
        0x8D, 0x14, 0x20, 0x00, 0xA1, 0xC8, 0xDA, 0x12,
        0x81, 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6,
        0x2E, 0xAF,
    };
    uint8_t buf[1 + sizeof init];
    buf[0] = 0x00;
    memcpy(buf + 1, init, sizeof init);
    err = i2c_master_transmit(oled, buf, sizeof buf, 200);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "VEXT_CHECK SSD1306 init: %s", esp_err_to_name(err));
        return err;
    }

    /* Fill the panel with a visible 8-pixel stripe pattern so a human can see
     * that the rail and panel really came up, then leave it on. */
    oled_cmd(oled, 0x21); /* column addressing */
    oled_cmd(oled, 0x00);
    oled_cmd(oled, 0x7F);
    oled_cmd(oled, 0x22);        /* page addressing */
    oled_cmd(oled, 0x00);
    oled_cmd(oled, 0x07);
    uint8_t row[129];
    row[0] = 0x40;
    for (int page = 0; page < 8; page++) {
        memset(row + 1, (page & 1) ? 0xAA : 0x55, 128);
        i2c_master_transmit(oled, row, sizeof row, 200);
    }
    ESP_LOGI(TAG, "VEXT_CHECK SSD1306 init + 1 KiB pattern write: OK");
    return ESP_OK;
}

/* ── Battery divider ─────────────────────────────────────────────────── */

static void battery_check(void)
{
    adc_oneshot_unit_handle_t adc;
    adc_oneshot_unit_init_cfg_t unit_cfg = { .unit_id = ADC_UNIT_1 };
    if (adc_oneshot_new_unit(&unit_cfg, &adc) != ESP_OK) {
        ESP_LOGE(TAG, "BATT_CHECK adc unit init failed");
        return;
    }
    adc_oneshot_chan_cfg_t chan_cfg = {
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    if (adc_oneshot_config_channel(adc, ADC_CHANNEL_0, &chan_cfg) != ESP_OK) {
        ESP_LOGE(TAG, "BATT_CHECK adc channel init failed");
        goto out;
    }

    gpio_set_direction(PIN_ADC_CTRL, GPIO_MODE_OUTPUT);

    /* Divider OFF first: this is the gate proof. */
    gpio_set_level(PIN_ADC_CTRL, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    int off_raw = 0;
    int off_mv = 0;
    adc_oneshot_read(adc, ADC_CHANNEL_0, &off_raw);

    /* Divider ON: GPIO37 HIGH on this board revision. */
    gpio_set_level(PIN_ADC_CTRL, 1);
    vTaskDelay(pdMS_TO_TICKS(20));
    int on_raw = 0;
    int64_t sum = 0;
    for (int i = 0; i < 32; i++) {
        int raw = 0;
        if (adc_oneshot_read(adc, ADC_CHANNEL_0, &raw) == ESP_OK) {
            sum += raw;
        }
        vTaskDelay(pdMS_TO_TICKS(2));
    }
    on_raw = (int)(sum / 32);
    gpio_set_level(PIN_ADC_CTRL, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    int off_after = 0;
    adc_oneshot_read(adc, ADC_CHANNEL_0, &off_after);

    adc_cali_handle_t cali = NULL;
    adc_cali_curve_fitting_config_t cali_cfg = {
        .unit_id = ADC_UNIT_1,
        .chan = ADC_CHANNEL_0,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    bool have_cali = adc_cali_create_scheme_curve_fitting(&cali_cfg, &cali) == ESP_OK;
    int mv = 0;
    if (have_cali) {
        adc_cali_raw_to_voltage(cali, on_raw, &mv);
    }

    ESP_LOGI(TAG,
             "BATT_CHECK gpio37=0 raw=%d mv=%d | gpio37=1 raw=%d mv=%d "
             "pack~%dmV (x4.9) | gpio37=0 again raw=%d",
             off_raw, off_mv, on_raw, mv, (int)(mv * 4.9f), off_after);
out:
    adc_oneshot_del_unit(adc);
}

/* ── SX1262 presence ─────────────────────────────────────────────────── */

static void lora_check(void)
{
    gpio_set_direction(PIN_LORA_NSS, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_LORA_NSS, 1);
    gpio_set_direction(PIN_LORA_RST, GPIO_MODE_OUTPUT);
    gpio_set_direction(PIN_LORA_BUSY, GPIO_MODE_INPUT);

    spi_bus_config_t bus_cfg = {
        .mosi_io_num = PIN_LORA_MOSI,
        .miso_io_num = PIN_LORA_MISO,
        .sclk_io_num = PIN_LORA_SCK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 64,
    };
    if (spi_bus_initialize(SPI2_HOST, &bus_cfg, SPI_DMA_CH_AUTO) != ESP_OK) {
        ESP_LOGE(TAG, "LORA_CHECK spi bus init failed");
        return;
    }
    spi_device_interface_config_t dev_cfg = {
        .clock_speed_hz = 8 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = -1, /* manual CS below */
        .queue_size = 1,
    };
    spi_device_handle_t spi;
    if (spi_bus_add_device(SPI2_HOST, &dev_cfg, &spi) != ESP_OK) {
        ESP_LOGE(TAG, "LORA_CHECK spi device add failed");
        return;
    }

    gpio_set_level(PIN_LORA_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(2));
    gpio_set_level(PIN_LORA_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(10));
    int waited = 0;
    while (gpio_get_level(PIN_LORA_BUSY) && waited < 200) {
        vTaskDelay(pdMS_TO_TICKS(1));
        waited++;
    }

    /* GetStatus (0xC0) — a live SX126x answers with a status byte whose
     * chip-mode field is 0b010 (STDBY_RC) or 0b011 (STDBY_XOSC) after reset. */
    uint8_t tx[2] = { 0xC0, 0x00 };
    uint8_t rx[2] = { 0 };
    spi_transaction_t t = { .length = 16, .tx_buffer = tx, .rx_buffer = rx };
    gpio_set_level(PIN_LORA_NSS, 0);
    spi_device_polling_transmit(spi, &t);
    gpio_set_level(PIN_LORA_NSS, 1);

    /* ReadRegister(0x0320, 16) — SX126x firmware version string area. */
    uint8_t tx2[4 + 16];
    uint8_t rx2[4 + 16];
    memset(tx2, 0, sizeof tx2);
    memset(rx2, 0, sizeof rx2);
    tx2[0] = 0x1D; /* ReadRegister */
    tx2[1] = 0x03;
    tx2[2] = 0x20;
    tx2[3] = 0x00;
    spi_transaction_t t2 = { .length = (4 + 16) * 8, .tx_buffer = tx2, .rx_buffer = rx2 };
    gpio_set_level(PIN_LORA_NSS, 0);
    spi_device_polling_transmit(spi, &t2);
    gpio_set_level(PIN_LORA_NSS, 1);

    char ver[17];
    memcpy(ver, rx2 + 4, 16);
    ver[16] = '\0';
    for (int i = 0; i < 16; i++) {
        if (ver[i] != '\0' && (ver[i] < 0x20 || ver[i] > 0x7e)) {
            ver[i] = '.';
        }
    }
    ESP_LOGI(TAG, "LORA_CHECK busy_low_after=%dms status=0x%02x mode=%u "
             "reg0320=\"%s\"",
             waited, rx[1], (unsigned)((rx[1] >> 4) & 0x07), ver);
}

/* ── PRG debounce ────────────────────────────────────────────────────── */

static void prg_check(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << PIN_PRG,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&cfg);

    ESP_LOGI(TAG, "PRG_CHECK idle level=%d; observing 8 s (30 ms debounce)",
             gpio_get_level(PIN_PRG));
    int stable = gpio_get_level(PIN_PRG);
    int last_raw = stable;
    int64_t changed_at = esp_timer_get_time();
    int64_t end = esp_timer_get_time() + 8 * 1000 * 1000;
    int events = 0;
    while (esp_timer_get_time() < end) {
        int raw = gpio_get_level(PIN_PRG);
        if (raw != last_raw) {
            last_raw = raw;
            changed_at = esp_timer_get_time();
        }
        if (raw != stable && esp_timer_get_time() - changed_at >= 30000) {
            stable = raw;
            events++;
            ESP_LOGI(TAG, "PRG_CHECK %s at %lldms", stable ? "UP" : "DOWN",
                     (long long)(esp_timer_get_time() / 1000));
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    ESP_LOGI(TAG, "PRG_CHECK done events=%d final=%d", events,
             gpio_get_level(PIN_PRG));
}

/* ── Bare BLE advertising ────────────────────────────────────────────── */

static uint8_t s_own_addr_type;

static int ble_gap_event(struct ble_gap_event *event, void *arg)
{
    (void)event;
    (void)arg;
    return 0;
}

static void ble_advertise(void)
{
    struct ble_hs_adv_fields fields = { 0 };
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    const char *name = PROBE_NAME;
    fields.name = (uint8_t *)name;
    fields.name_len = strlen(name);
    fields.name_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE_CHECK set fields rc=%d", rc);
        return;
    }
    struct ble_gap_adv_params params = { 0 };
    params.conn_mode = BLE_GAP_CONN_MODE_NON;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &params,
                           ble_gap_event, NULL);
    ESP_LOGI(TAG, "BLE_CHECK adv_start rc=%d (0=OK), active=%d name=%s",
             rc, ble_gap_adv_active(), PROBE_NAME);
}

static void ble_on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (rc == 0) {
        rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    }
    ESP_LOGI(TAG, "BLE_CHECK host synced rc=%d addr_type=%u", rc,
             s_own_addr_type);
    if (rc == 0) {
        ble_advertise();
    }
}

static void ble_on_reset(int reason)
{
    ESP_LOGW(TAG, "BLE_CHECK host reset reason=%d", reason);
}

static void ble_host_task(void *param)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static bool ble_start(void)
{
    if (nimble_port_init() != ESP_OK) {
        ESP_LOGE(TAG, "BLE_CHECK nimble_port_init failed");
        return false;
    }
    ble_hs_cfg.reset_cb = ble_on_reset;
    ble_hs_cfg.sync_cb = ble_on_sync;
    ble_svc_gap_device_name_set(PROBE_NAME);
    nimble_port_freertos_init(ble_host_task);
    return true;
}

/* ── Sleep / wake ────────────────────────────────────────────────────── */

static void enter_deep_sleep(void)
{
    /* Rail off; the wake source is the PRG net (GPIO0), active low.
     * EXT1 is the deep-sleep-capable path on the ESP32-S3; GPIO0 is an RTC
     * pin, so this is the same physical signal the PRG button pulls down. */
    gpio_set_level(PIN_VEXT, 1);

    esp_err_t err = esp_sleep_enable_ext1_wakeup_io(1ULL << PIN_PRG,
                                                    ESP_EXT1_WAKEUP_ANY_LOW);
    ESP_LOGI(TAG, "SLEEP gpio0-low wake enable: %s (boot=%u wake=%u)",
             esp_err_to_name(err), (unsigned)s_boot_count,
             (unsigned)s_wake_count);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "SLEEP entering deep sleep now");
    } else {
        ESP_LOGE(TAG, "SLEEP wake source failed; staying awake for 30 s");
        vTaskDelay(pdMS_TO_TICKS(30000));
    }
    fflush(stdout);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_deep_sleep_start();
}

void app_main(void)
{
    /* Bench probe: no product watchdog contract here, and the 10 s BLE wait
     * would trip it. Disable it so the log is about the hardware. */
    esp_task_wdt_deinit();

    s_boot_count++;
    uint32_t causes = esp_sleep_get_wakeup_causes();
    bool from_gpio = (causes & BIT(ESP_SLEEP_WAKEUP_EXT1)) != 0;
    if (from_gpio) {
        s_wake_count++;
    }

    ESP_LOGI(TAG, "BOOT count=%u wake_count=%u causes=0x%08x gpio0=%d",
             (unsigned)s_boot_count, (unsigned)s_wake_count, (unsigned)causes,
             gpio_get_level(PIN_PRG));

    if (from_gpio) {
        ESP_LOGI(TAG, "WAKE %u via PRG/GPIO0 EXT1 mask=0x%llx",
                 (unsigned)s_wake_count,
                 (unsigned long long)esp_sleep_get_ext1_wakeup_status());

        /* Let the external driver release the line, then confirm the release
         * and go back to sleep. This mirrors "short press wakes, then
         * returns to sleep" without implementing product behavior. */
        int held_ms = 0;
        while (gpio_get_level(PIN_PRG) == 0 && held_ms < 5000) {
            vTaskDelay(pdMS_TO_TICKS(10));
            held_ms += 10;
        }
        ESP_LOGI(TAG, "WAKE release after ~%dms (gpio0=%d)", held_ms,
                 gpio_get_level(PIN_PRG));
        enter_deep_sleep();
        return;
    }

    /* Cold boot. Run the full probe only on the first cold boot, so the
     * external driver's recovery resets do not spend 15 s apiece. */
    if (s_probe_done != PROBE_MAGIC) {
        s_probe_done = PROBE_MAGIC;
        battery_check();
        oled_init_and_check();
        lora_check();
        prg_check();
        if (ble_start()) {
            vTaskDelay(pdMS_TO_TICKS(10000));
            ESP_LOGI(TAG, "BLE_CHECK after 10 s: active=%d",
                     ble_gap_adv_active());
            ble_gap_adv_stop();
            nimble_port_stop();
            vTaskDelay(pdMS_TO_TICKS(200));
        }
        ESP_LOGI(TAG, "PROBE complete");
    } else {
        ESP_LOGI(TAG, "PROBE already done; recovery boot, sleeping again");
        vTaskDelay(pdMS_TO_TICKS(500));
    }

    enter_deep_sleep();
}
