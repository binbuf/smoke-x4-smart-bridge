/*
 * sx_radio.c - SX1262 wrapper and the radio_rx task.
 *
 * The vendored ra01s driver is used for configuration and for IRQ/status
 * queries, but not for LoRaReceive(): that helper mallocs per packet. The read
 * below uses the same public driver primitives with a fixed static buffer, so
 * the RX path performs no heap allocation.
 *
 * The task polls with vTaskDelay(1); DIO1 is not used (post-MVP optimization).
 * Incoming payloads are untrusted bytes: this layer publishes length, bytes,
 * RSSI and SNR and does not parse the CSV.
 */
#include "sx_radio.h"

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "ra01s.h"

static const char *TAG = "sx4.radio";

/* LoRaReceive()/ReadBuffer() in ra01s mallocs; these primitives do not. */
#define SX4_RX_SCRATCH_BYTES (SX4_RADIO_MAX_PAYLOAD + 3u)

static uint8_t s_scratch[SX4_RX_SCRATCH_BYTES];
static uint32_t s_frequency_hz = SX4_RADIO_DEFAULT_FREQUENCY_HZ;
static bool s_configured;
static bool s_started;

static void log_payload(const uint8_t *payload, uint8_t length) {
    char text[SX4_RADIO_MAX_PAYLOAD + 1];
    for (uint8_t i = 0; i < length; i++) {
        uint8_t byte = payload[i];
        text[i] = (byte >= 0x20 && byte <= 0x7e) ? (char)byte : '.';
    }
    text[length] = '\0';
    ESP_LOGI(TAG, "payload=\"%s\"", text);
}

/* Copy the radio FIFO without allocating. Returns the payload length, or 0. */
static uint8_t read_payload(uint8_t *out, uint8_t capacity) {
    uint8_t length = 0;
    uint8_t offset = 0;
    GetRxBufferStatus(&length, &offset);
    if (length == 0 || length > capacity) {
        return 0;
    }

    WaitForIdleBegin(BUSY_WAIT, "rx-buffer-start");
    s_scratch[0] = SX126X_CMD_READ_BUFFER;
    s_scratch[1] = offset;
    s_scratch[2] = SX126X_CMD_NOP;
    memset(&s_scratch[3], SX126X_CMD_NOP, length);
    spi_read_byte(s_scratch, s_scratch, (size_t)length + 3u);
    memcpy(out, &s_scratch[3], length);
    WaitForIdle(BUSY_WAIT, "rx-buffer-end", false);
    return length;
}

static void rearm_receive(void) { SetRx(SX126X_RX_TIMEOUT_INF); }

static void radio_task(void *argument) {
    (void)argument;
    ESP_LOGI(TAG, "radio_rx started on core %d", xPortGetCoreID());

    for (;;) {
        uint16_t irq = GetIrqStatus();
        if (irq & (SX126X_IRQ_RX_DONE | SX126X_IRQ_CRC_ERR |
                   SX126X_IRQ_HEADER_ERR)) {
            ClearIrqStatus(SX126X_IRQ_ALL);
            if (irq & SX126X_IRQ_RX_DONE) {
                uint8_t payload[SX4_RADIO_MAX_PAYLOAD];
                uint8_t length =
                    read_payload(payload, SX4_RADIO_MAX_PAYLOAD);
                if (length > 0) {
                    int8_t rssi = 0;
                    int8_t snr = 0;
                    GetPacketStatus(&rssi, &snr);
                    if (sx4_radio_rx_publish(payload, length, rssi, snr)) {
                        ESP_LOGI(TAG, "rx len=%u rssi=%d snr=%d", length,
                                 rssi, snr);
                        log_payload(payload, length);
                    } else {
                        ESP_LOGW(TAG,
                                 "rx seam full; packet dropped (dropped=%lu)",
                                 (unsigned long)sx4_radio_rx_dropped_count());
                    }
                }
            } else if (irq & SX126X_IRQ_CRC_ERR) {
                ESP_LOGW(TAG, "rx CRC error");
            } else {
                ESP_LOGW(TAG, "rx header error");
            }
            rearm_receive();
        }
        vTaskDelay(SX4_RADIO_POLL_DELAY_TICKS);
    }
}

esp_err_t sx_radio_init(void) {
    sx4_radio_rx_reset();

    LoRaInit();
    int16_t status = LoRaBegin(s_frequency_hz, 22, sx4_radio_params.tcxo_voltage,
                               sx4_radio_params.use_regulator_ldo);
    if (status != ERR_NONE) {
        ESP_LOGE(TAG, "LoRaBegin failed: %d", status);
        return ESP_FAIL;
    }

    SetSyncWord(sx4_radio_params.sync_word);
    LoRaConfig(sx4_radio_params.spreading_factor,
               sx4_radio_params.bandwidth_index, sx4_radio_params.coding_rate,
               sx4_radio_params.preamble_symbols, 0, sx4_radio_params.crc_on,
               false);

    s_configured = true;
    ESP_LOGI(TAG, "configured: SF%u BW%u CR0x%02x preamble=%u sync=0x%02x "
                  "crc=%d tcxo=%.1fV ldo=%d freq=%lu",
             sx4_radio_params.spreading_factor,
             sx4_radio_params.bandwidth_index, sx4_radio_params.coding_rate,
             sx4_radio_params.preamble_symbols, sx4_radio_params.sync_word,
             sx4_radio_params.crc_on ? 1 : 0,
             (double)sx4_radio_params.tcxo_voltage,
             sx4_radio_params.use_regulator_ldo ? 1 : 0,
             (unsigned long)s_frequency_hz);
    return ESP_OK;
}

esp_err_t sx_radio_start(void) {
    if (!s_configured) {
        return ESP_ERR_INVALID_STATE;
    }
    if (s_started) {
        return ESP_OK;
    }
    BaseType_t created = xTaskCreatePinnedToCore(
        radio_task, "radio_rx", SX4_RADIO_TASK_STACK_BYTES, NULL,
        SX4_RADIO_TASK_PRIORITY, NULL, SX4_RADIO_TASK_CORE);
    if (created != pdPASS) {
        ESP_LOGE(TAG, "radio_rx task creation failed");
        return ESP_ERR_NO_MEM;
    }
    s_started = true;
    return ESP_OK;
}

esp_err_t sx_radio_set_frequency(uint32_t frequency_hz) {
    if (!sx4_radio_frequency_valid(frequency_hz)) {
        return ESP_ERR_INVALID_ARG;
    }
    s_frequency_hz = frequency_hz;
    if (!s_configured) {
        return ESP_OK;
    }

    SetStandby(SX126X_STANDBY_RC);
    SetRfFrequency(frequency_hz);
    rearm_receive();
    ESP_LOGI(TAG, "tuned to %lu Hz", (unsigned long)frequency_hz);
    return ESP_OK;
}

uint32_t sx_radio_frequency(void) { return s_frequency_hz; }
