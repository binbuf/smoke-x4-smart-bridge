/*
 * sample_pipe_esp.c - firmware wiring for the sample pipeline (T21).
 *
 * Two core-0 tasks (design 03 section 3.3):
 *   sample_pipe (prio 5)  drain the radio seam, parse, build, enqueue
 *   log_writer  (prio 4)  append to the ring, publish the live snapshot
 *
 * The queue between them is static and bounded. The sample task's enqueue is
 * non-blocking: a full queue is a counted drop, never a wait on flash.
 */
#include "sample_pipe.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "bridge_config.h"
#include "bridge_state.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "sample_log.h"
#include "sx_radio_rx.h"
#include "ui.h"

/* Mirrors the sample_pipe/log_writer rows in firmware/main/tasks.h. */
#define SAMPLE_PIPE_TASK_STACK_BYTES 4096u
#define SAMPLE_PIPE_TASK_PRIORITY 5u
#define SAMPLE_PIPE_TASK_CORE 0
#define SAMPLE_LOG_WRITER_STACK_BYTES 4096u
#define SAMPLE_LOG_WRITER_PRIORITY 4u
#define SAMPLE_LOG_WRITER_CORE 0
#define SAMPLE_PIPE_POLL_MS 5u

static const char *TAG = "sx4.sample";

static sample_pipe_t s_pipe;
static bool s_started;
static QueueHandle_t s_log_queue;
static StaticQueue_t s_log_queue_struct;
static sample_pipe_pending_t
    s_log_queue_storage[SAMPLE_PIPE_LOG_QUEUE_DEPTH];

static uint64_t now_ms(void *ctx) {
    (void)ctx;
    return (uint64_t)(esp_timer_get_time() / 1000);
}

static bool load_pairing(void *ctx, sample_pipe_pairing_t *out) {
    (void)ctx;
    bridge_config_pairing_t stored;
    if (out == NULL ||
        bridge_config_get_pairing(&stored) != BRIDGE_CONFIG_OK ||
        !stored.paired) {
        return false;
    }
    memset(out, 0, sizeof(*out));
    out->paired = true;
    memcpy(out->device_id, stored.device_id, sizeof(out->device_id) - 1u);
    out->num_probes = stored.num_probes;
    return true;
}

static bool save_probe_count(void *ctx, const char *device_id,
                             uint8_t num_probes) {
    (void)ctx;
    bridge_config_pairing_t stored;
    if (device_id == NULL ||
        bridge_config_get_pairing(&stored) != BRIDGE_CONFIG_OK ||
        !stored.paired || strcmp(stored.device_id, device_id) != 0) {
        return false;
    }
    if (stored.num_probes == num_probes) {
        return true;
    }
    stored.num_probes = num_probes;
    return bridge_config_set_pairing(&stored) == BRIDGE_CONFIG_OK;
}

static bool enqueue_log(void *ctx, const sample_pipe_pending_t *pending) {
    (void)ctx;
    if (s_log_queue == NULL) {
        return false;
    }
    return xQueueSend(s_log_queue, pending, 0) == pdTRUE;
}

static bool stamp_record(void *ctx, sx4_sample_rec_t *rec) {
    (void)ctx;
    return bridge_state_stamp_record(rec) == BRIDGE_STATE_OK;
}

static void publish_snapshot(void *ctx, const bridge_state_sample_t *sample) {
    (void)ctx;
    (void)bridge_state_update(sample);
    bridge_state_set_smoke_paired(true);
}

static void mark_dirty(void *ctx) {
    (void)ctx;
    ui_mark_dirty();
}

static const sample_pipe_io_t s_io = {
    .ctx = NULL,
    .load_pairing = load_pairing,
    .save_probe_count = save_probe_count,
    .enqueue_log = enqueue_log,
    .stamp_record = stamp_record,
    .publish_snapshot = publish_snapshot,
    .mark_dirty = mark_dirty,
    .now_ms = now_ms,
};

static void sample_pipe_task(void *argument) {
    (void)argument;
    sx4_radio_packet_t packet;
    for (;;) {
        bool did_work = false;
        while (sx4_radio_rx_take(&packet)) {
            did_work = true;
            (void)sample_pipe_process(&s_pipe, packet.payload, packet.length,
                                      packet.rssi, packet.snr);
        }
        if (!did_work) {
            vTaskDelay(pdMS_TO_TICKS(SAMPLE_PIPE_POLL_MS));
        }
    }
}

static void log_writer_task(void *argument) {
    (void)argument;
    for (;;) {
        sample_pipe_pending_t pending;
        if (xQueueReceive(s_log_queue, &pending, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        sx4_sample_rec_t rec = pending.rec;
        esp_err_t err = sample_log_append(&rec);
        const bool stored = err == ESP_OK;
        if (stored) {
            /* Bench evidence: show the canonical record, after sequence
             * assignment, including the detached sentinel and Celsius
             * provenance. */
            ESP_LOGI(TAG,
                     "stored seq=%lu t=%d,%d,%d,%d flags=0x%02x",
                     (unsigned long)sx4_sample_rec_seq_get(&rec),
                     rec.temp[0], rec.temp[1], rec.temp[2], rec.temp[3],
                     rec.flags);
        } else {
            ESP_LOGW(TAG, "not stored: %s", esp_err_to_name(err));
        }
        bridge_state_set_storage_ok(sample_log_storage_ok());
        sample_pipe_complete(&s_pipe, &pending, stored,
                             stored ? sx4_sample_rec_seq_get(&rec) : 0u);
        /* Clock persistence is owned by the housekeeping task (T24). */
    }
}

esp_err_t sample_pipe_start(void) {
    if (s_started) {
        return ESP_OK;
    }

    s_log_queue = xQueueCreateStatic(
        SAMPLE_PIPE_LOG_QUEUE_DEPTH, sizeof(sample_pipe_pending_t),
        (uint8_t *)s_log_queue_storage, &s_log_queue_struct);
    if (s_log_queue == NULL) {
        return ESP_ERR_NO_MEM;
    }
    if (!sample_pipe_init(&s_pipe, &s_io)) {
        return ESP_ERR_INVALID_ARG;
    }

    bridge_state_set_storage_ok(sample_log_storage_ok());

    BaseType_t created = xTaskCreatePinnedToCore(
        sample_pipe_task, "sample_pipe", SAMPLE_PIPE_TASK_STACK_BYTES, NULL,
        SAMPLE_PIPE_TASK_PRIORITY, NULL, SAMPLE_PIPE_TASK_CORE);
    if (created != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    created = xTaskCreatePinnedToCore(
        log_writer_task, "log_writer", SAMPLE_LOG_WRITER_STACK_BYTES, NULL,
        SAMPLE_LOG_WRITER_PRIORITY, NULL, SAMPLE_LOG_WRITER_CORE);
    if (created != pdPASS) {
        return ESP_ERR_NO_MEM;
    }

    s_started = true;
    return ESP_OK;
}
