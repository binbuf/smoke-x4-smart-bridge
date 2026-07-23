/* app_lora — device glue over the vendored ra01s driver (F2).
 *
 * The RX loop polls with vTaskDelay(1) while holding the radio semaphore —
 * fine at one packet per 30 s; DIO1 interrupts are a deliberate v1.1 item
 * (§12.7). Do not migrate them here.
 */
#include "app_lora.h"

#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "ra01s.h"

static const char *TAG = "app_lora";

#define PAYLOAD_MAX 255

/* Mirrors the lora_rx row of main/tasks.h (the budget-audited table). */
#define RX_TASK_NAME "lora_rx"
#define RX_TASK_STACK 4096
#define RX_TASK_PRIO 6
#define RX_TASK_CORE 1

static SemaphoreHandle_t s_radio_sem;
static TaskHandle_t s_rx_task;
static app_lora_rx_cb_t s_rx_cb;
static volatile bool s_scanning;
static volatile uint32_t s_freq_hz;
static uint64_t s_scan_started_ms;

static uint64_t now_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

static void retune_locked(uint32_t hz) {
    SetRfFrequency(hz);
    SetRx(0xFFFFFF);
    s_freq_hz = hz;
}

int app_lora_set_frequency(uint32_t hz) {
    s_scanning = false;
    if (xSemaphoreTake(s_radio_sem, portMAX_DELAY) != pdTRUE) {
        return -1;
    }
    retune_locked(hz);
    xSemaphoreGive(s_radio_sem);
    ESP_LOGI(TAG, "tuned to %u Hz", (unsigned)hz);
    return 0;
}

void app_lora_set_scanning(bool on) {
    if (on && !s_scanning) {
        s_scan_started_ms = now_ms();
    }
    s_scanning = on;
}

int app_lora_start_tx(const char *payload) {
    if (!payload) {
        return -1;
    }
    /* F2.3: the guard, not the caller, is the authority. */
    if (!app_lora_guard_tx_allowed(s_freq_hz)) {
        ESP_LOGE(TAG, "TX refused: sync window closed or out of band");
        return -1;
    }
    const size_t len = strlen(payload);
    int rc = -1;
    if (xSemaphoreTake(s_radio_sem, portMAX_DELAY) == pdTRUE) {
        if (LoRaSend((uint8_t *)payload, (uint8_t)len, SX126x_TXMODE_SYNC)) {
            ESP_LOGI(TAG, "%u bytes transmitted (%s)", (unsigned)len,
                     payload);
            rc = 0;
        } else {
            ESP_LOGE(TAG, "TX failed");
        }
        SetRx(0xFFFFFF);
        xSemaphoreGive(s_radio_sem);
    }
    return rc;
}

static void rx_task(void *arg) {
    (void)arg;
    uint8_t buf[PAYLOAD_MAX + 1];
    ESP_LOGI(TAG, "LoRa RX running");
    while (true) {
        if (s_scanning) {
            const uint32_t want =
                app_lora_scan_freq_at(now_ms(), s_scan_started_ms);
            if (want != s_freq_hz &&
                xSemaphoreTake(s_radio_sem, portMAX_DELAY) == pdTRUE) {
                retune_locked(want);
                xSemaphoreGive(s_radio_sem);
            }
        }
        int len = 0;
        int8_t rssi = 0, snr = 0;
        if (xSemaphoreTake(s_radio_sem, pdMS_TO_TICKS(10)) == pdTRUE) {
            len = (int)LoRaReceive(buf, PAYLOAD_MAX);
            if (len > 0) {
                buf[len] = 0;
                GetPacketStatus(&rssi, &snr);
            }
            xSemaphoreGive(s_radio_sem);
        }
        if (len > 0 && s_rx_cb) {
            s_rx_cb((const char *)buf, rssi, snr);
        }
        vTaskDelay(1);
    }
}

int app_lora_init(void) {
    const app_lora_params_t *p = app_lora_params();
    app_lora_guard_reset();
    LoRaInit();
    if (LoRaBegin(APP_LORA_SCAN_FREQ_X4, p->tx_power_dbm, p->tcxo_volts,
                  p->use_ldo) != 0) {
        ESP_LOGE(TAG, "SX1262 init failed");
        return -1;
    }
    /* Bandwidth is an INDEX (4 = 125 kHz) on this driver (01 §1.5). */
    LoRaConfig(p->spreading_factor, p->bandwidth_index, p->coding_rate,
               p->preamble_len, 0, p->crc_on, false);
    s_freq_hz = APP_LORA_SCAN_FREQ_X4;
    s_radio_sem = xSemaphoreCreateBinary();
    if (!s_radio_sem) {
        return -1;
    }
    xSemaphoreGive(s_radio_sem);
    ESP_LOGI(TAG, "SX1262 initialised (SF%u BW-idx %u CR%u sync 0x%02X)",
             p->spreading_factor, p->bandwidth_index, p->coding_rate,
             p->sync_word);
    return 0;
}

int app_lora_start(app_lora_rx_cb_t cb) {
    if (s_rx_task) {
        return -1;
    }
    s_rx_cb = cb;
    if (xTaskCreatePinnedToCore(rx_task, RX_TASK_NAME, RX_TASK_STACK, NULL,
                                RX_TASK_PRIO, &s_rx_task,
                                RX_TASK_CORE) != pdPASS) {
        return -1;
    }
    return 0;
}
