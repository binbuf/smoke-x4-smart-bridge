/*
 * sx_radio.c - SX1262 wrapper and the radio_rx task.
 *
 * The vendored ra01s driver is used for configuration and for IRQ/status
 * queries, but not for LoRaReceive(): that helper mallocs per packet. The read
 * below uses the same public driver primitives with a fixed static buffer, so
 * the RX path performs no heap allocation.
 *
 * The task polls with vTaskDelay(1); DIO1 is not used (post-MVP optimization).
 * Incoming payloads are untrusted bytes. Every frame is offered to the pairing
 * FSM (T16) and then published with length, bytes, RSSI and SNR through the
 * raw seam; the sample/parser task owns record building.
 */
#include "sx_radio.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "bridge_config.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "ra01s.h"
#include "sx_protocol.h"
#include "sx_radio_pair.h"

static const char *TAG = "sx4.radio";

static uint64_t pair_now_ms(void) {
    return (uint64_t)(esp_timer_get_time() / 1000);
}

/* LoRaReceive()/ReadBuffer() in ra01s mallocs; these primitives do not. */
#define SX4_RX_SCRATCH_BYTES (SX4_RADIO_MAX_PAYLOAD + 3u)

static uint8_t s_scratch[SX4_RX_SCRATCH_BYTES];
static uint32_t s_frequency_hz = SX4_RADIO_DEFAULT_FREQUENCY_HZ;
static bool s_configured;
static bool s_started;
static volatile bool s_sleeping;

/* The pairing FSM is single-owner: radio_rx and the T48 unpair action share it
 * through this mutex. */
static SemaphoreHandle_t s_pair_lock;

static void pair_lock(void) {
    if (s_pair_lock != NULL) {
        (void)xSemaphoreTake(s_pair_lock, portMAX_DELAY);
    }
}

static void pair_unlock(void) {
    if (s_pair_lock != NULL) {
        (void)xSemaphoreGive(s_pair_lock);
    }
}

/*
 * Pairing persistence adapter. bridge_config is the only NVS owner; paired_at
 * is left unknown (0) because this task has no wall clock (T20 owns UTC).
 */
static bool pair_load(void *ctx, sx4_pair_record_t *out) {
    (void)ctx;
    bridge_config_pairing_t stored;
    if (bridge_config_get_pairing(&stored) != BRIDGE_CONFIG_OK ||
        !stored.paired) {
        return false;
    }
    memset(out, 0, sizeof *out);
    memcpy(out->device_id, stored.device_id, sizeof out->device_id - 1u);
    out->frequency_hz = stored.frequency_hz;
    out->num_probes = stored.num_probes;
    return true;
}

static bool pair_save(void *ctx, const sx4_pair_record_t *record) {
    (void)ctx;
    bridge_config_pairing_t stored;
    memset(&stored, 0, sizeof stored);
    memcpy(stored.device_id, record->device_id,
           strnlen(record->device_id, BRIDGE_CONFIG_DEVICE_ID_MAX));
    stored.frequency_hz = record->frequency_hz;
    stored.num_probes = record->num_probes;
    stored.paired_at = 0;
    return bridge_config_set_pairing(&stored) == BRIDGE_CONFIG_OK;
}

static bool pair_clear(void *ctx) {
    (void)ctx;
    return bridge_config_clear_pairing() == BRIDGE_CONFIG_OK;
}

static bool pair_tune(void *ctx, uint32_t frequency_hz) {
    (void)ctx;
    return sx_radio_set_frequency(frequency_hz) == ESP_OK;
}

/*
 * The product's only LoRa transmission. It is reachable only through the
 * pairing FSM's send_ack callback, and the FSM calls that callback only from
 * the sync-beacon branch.
 */
static bool pair_send_ack(void *ctx, const char *ack, size_t length) {
    (void)ctx;
    if (!s_configured || ack == NULL || length == 0 ||
        length > (size_t)INT16_MAX) {
        return false;
    }
    bool sent = LoRaSend((uint8_t *)ack, (int16_t)length,
                         SX126x_TXMODE_SYNC);
    if (sent) {
        ESP_LOGI(TAG, "pair ACK sent on %lu Hz",
                 (unsigned long)s_frequency_hz);
    } else {
        ESP_LOGW(TAG, "pair ACK failed on %lu Hz",
                 (unsigned long)s_frequency_hz);
    }
    return sent;
}

static const sx4_radio_pair_io_t s_pair_io = {
    .ctx = NULL,
    .load = pair_load,
    .save = pair_save,
    .clear = pair_clear,
    .tune = pair_tune,
    .send_ack = pair_send_ack,
};

static void log_payload(const uint8_t *payload, uint8_t length) {
    char text[SX4_RADIO_MAX_PAYLOAD + 1];
    char hex[SX4_RADIO_MAX_PAYLOAD * 3u + 1u];
    size_t pos = 0;
    for (uint8_t i = 0; i < length; i++) {
        uint8_t byte = payload[i];
        text[i] = (byte >= 0x20 && byte <= 0x7e) ? (char)byte : '.';
        int written = snprintf(&hex[pos], sizeof(hex) - pos, "%02X ", byte);
        if (written <= 0) {
            break;
        }
        pos += (size_t)written;
    }
    text[length] = '\0';
    hex[pos] = '\0';
    ESP_LOGI(TAG, "payload=\"%s\" hex=%s", text, hex);
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
        if (s_sleeping) {
            /* sx_radio_sleep() owns the bus now; never poll a sleeping part. */
            vTaskDelay(portMAX_DELAY);
        }
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
                    /* Pairing consumes sync/state frames; the seam below still
                     * carries the raw bytes to the sample pipeline (T21). */
                    pair_lock();
                    (void)sx4_radio_pair_on_packet(payload, length,
                                                   pair_now_ms());
                    pair_unlock();
                    if (sx4_radio_rx_publish(payload, length, rssi, snr)) {
                        ESP_LOGI(TAG,
                                 "rx len=%u rssi=%d snr=%d freq=%lu", length,
                                 rssi, snr,
                                 (unsigned long)sx_radio_frequency());
                        log_payload(payload, length);
                    } else {
                        ESP_LOGW(TAG,
                                 "rx seam full; packet dropped (dropped=%lu)",
                                 (unsigned long)sx4_radio_rx_dropped_count());
                    }
                }
            } else if (irq & SX126X_IRQ_CRC_ERR) {
                sx_protocol_note_crc_failure();
                ESP_LOGW(TAG, "rx CRC error");
            } else {
                sx_protocol_note_crc_failure();
                ESP_LOGW(TAG, "rx header error");
            }
            rearm_receive();
        }
        pair_lock();
        sx4_radio_pair_tick(pair_now_ms());
        pair_unlock();
        vTaskDelay(SX4_RADIO_POLL_DELAY_TICKS);
    }
}

esp_err_t sx_radio_init(void) {
    sx4_radio_rx_reset();
    if (s_pair_lock == NULL) {
        s_pair_lock = xSemaphoreCreateMutex();
        if (s_pair_lock == NULL) {
            return ESP_ERR_NO_MEM;
        }
    }

    /* Load pairing before the SX1262 is configured: the FSM's tune callback
     * sets s_frequency_hz (and is a no-op on the hardware until configured). */
    if (!sx4_radio_pair_init(&s_pair_io, pair_now_ms())) {
        ESP_LOGE(TAG, "pairing state init failed");
        return ESP_FAIL;
    }

    LoRaInit();
    int16_t status = LoRaBegin(s_frequency_hz, 22, sx4_radio_params.tcxo_voltage,
                               sx4_radio_params.use_regulator_ldo);
    if (status != ERR_NONE) {
        ESP_LOGE(TAG, "LoRaBegin failed: %d", status);
        return ESP_FAIL;
    }

    SetSyncWord(sx4_radio_params.sync_word);

    /* Read back what the radio actually latched. A mismatch here is a deaf
     * receiver even though LoRaBegin() and SetRx() both look healthy. */
    uint8_t sync_read[2] = {0, 0};
    ReadRegister(SX126X_REG_LORA_SYNC_WORD_MSB, sync_read, 2);
    uint16_t sync_actual = (uint16_t)((sync_read[0] << 8) | sync_read[1]);
    if (sync_actual != (uint16_t)sx4_radio_params.sync_word) {
        ESP_LOGE(TAG, "sync word mismatch: wrote 0x%04x read 0x%04x",
                 (unsigned)sx4_radio_params.sync_word, (unsigned)sync_actual);
        return ESP_FAIL;
    }

    LoRaConfig(sx4_radio_params.spreading_factor,
               sx4_radio_params.bandwidth_index, sx4_radio_params.coding_rate,
               sx4_radio_params.preamble_symbols, 0, sx4_radio_params.crc_on,
               false);

    s_configured = true;
    ESP_LOGI(TAG, "configured: SF%u BW%u CR0x%02x preamble=%u sync=0x%04x "
                  "crc=%d tcxo=%.1fV ldo=%d freq=%lu",
             sx4_radio_params.spreading_factor,
             sx4_radio_params.bandwidth_index, sx4_radio_params.coding_rate,
             sx4_radio_params.preamble_symbols,
             (unsigned)sx4_radio_params.sync_word,
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

esp_err_t sx_radio_unpair(void) {
    if (s_pair_lock == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    pair_lock();
    const bool cleared = sx4_radio_pair_unpair(pair_now_ms());
    pair_unlock();
    if (!cleared) {
        ESP_LOGW(TAG, "unpair_smoke_x: pairing clear failed");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "unpair_smoke_x: pairing cleared, scanning 915/920");
    return ESP_OK;
}

esp_err_t sx_radio_sleep(void) {
    if (!s_configured) {
        return ESP_OK;
    }

    /* Let an in-flight RX poll finish, then park the task before touching the
     * SPI bus from the power-off path. The task checks the flag every poll. */
    s_sleeping = true;
    vTaskDelay(pdMS_TO_TICKS(50));

    SetStandby(SX126X_STANDBY_RC);
    uint8_t sleep_config = SX126X_SLEEP_START_COLD;
    WriteCommand(SX126X_CMD_SET_SLEEP, &sleep_config, 1);
    s_configured = false;
    ESP_LOGI(TAG, "SX1262 asleep (cold start)");
    return ESP_OK;
}
