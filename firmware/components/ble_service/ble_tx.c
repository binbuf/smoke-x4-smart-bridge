/*
 * ble_tx.c - ESP-IDF adapter for the live notification ring (T28).
 *
 * One ble_tx task (design 03 section 3.3) drains the fixed ring and is the only
 * caller of ble_gatts_notify_custom() for `live`. Producers are bridge_state
 * change hooks and the GAP subscribe event; both only append 20 bytes under a
 * short critical section, so the sample path never waits on the BLE host.
 */
#include "ble_tx.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "os/os_mbuf.h"

/* Mirrors the ble_tx row in firmware/main/tasks.h. */
#define BLE_TX_TASK_STACK_BYTES 3072u
#define BLE_TX_TASK_PRIORITY 4u
#define BLE_TX_TASK_CORE 0
/* Time-driven flag transitions (smoke_live expiry) are noticed within 1 s. */
#define BLE_TX_POLL_MS 1000u

static const char *TAG = "sx4.ble.tx";

static ble_tx_core_t s_tx;
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
static SemaphoreHandle_t s_wake;
static bool s_started;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_live_handle;
static volatile bool s_subscribed;

static void wake_writer(void) {
    if (s_wake != NULL) {
        (void)xSemaphoreGive(s_wake);
    }
}

static void ble_tx_send(const ble_tx_frame_t *frame) {
    if (!s_subscribed || s_conn_handle == BLE_HS_CONN_HANDLE_NONE ||
        s_live_handle == 0u) {
        return;
    }
    struct os_mbuf *om =
        ble_hs_mbuf_from_flat(frame->payload, frame->len);
    if (om == NULL) {
        ESP_LOGW(TAG, "no mbuf for live notification");
        return;
    }
    int rc = ble_gatts_notify_custom(s_conn_handle, s_live_handle, om);
    if (rc != 0) {
        ESP_LOGD(TAG, "live notify failed (%d)", rc);
    }
}

static void ble_tx_task(void *argument) {
    (void)argument;
    for (;;) {
        (void)xSemaphoreTake(s_wake, pdMS_TO_TICKS(BLE_TX_POLL_MS));
        for (;;) {
            ble_tx_frame_t frame;
            bool have;
            taskENTER_CRITICAL(&s_mux);
            have = ble_tx_core_take(&s_tx, &frame);
            taskEXIT_CRITICAL(&s_mux);
            if (!have) {
                break;
            }
            ble_tx_send(&frame);
        }
        /*
         * smoke_live expires from the clock, not from a setter. A low-rate
         * snapshot check catches that transition; the core's seq/flags dedupe
         * keeps it from sending unchanged frames.
         */
        ble_tx_live_changed(NULL);
    }
}

void ble_tx_live_changed(void *ctx) {
    (void)ctx;
    if (!s_started || !s_subscribed) {
        return;
    }

    bridge_state_live_t snapshot;
    if (bridge_state_snapshot(&snapshot) != BRIDGE_STATE_OK) {
        return;
    }

    bool queued;
    taskENTER_CRITICAL(&s_mux);
    queued = ble_tx_core_queue_live(&s_tx, &snapshot);
    taskEXIT_CRITICAL(&s_mux);
    if (queued) {
        wake_writer();
    }
}

void ble_tx_set_live_handle(uint16_t attr_handle) {
    s_live_handle = attr_handle;
}

void ble_tx_on_connect(uint16_t conn_handle) {
    s_conn_handle = conn_handle;
}

void ble_tx_on_disconnect(void) {
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_subscribed = false;
    taskENTER_CRITICAL(&s_mux);
    ble_tx_core_clear(&s_tx);
    taskEXIT_CRITICAL(&s_mux);
}

void ble_tx_on_live_subscribe(bool subscribed) {
    s_subscribed = subscribed;

    bool queued = false;
    if (subscribed) {
        bridge_state_live_t snapshot;
        if (bridge_state_snapshot(&snapshot) == BRIDGE_STATE_OK) {
            taskENTER_CRITICAL(&s_mux);
            ble_tx_core_clear(&s_tx);
            queued = ble_tx_core_queue_live(&s_tx, &snapshot);
            taskEXIT_CRITICAL(&s_mux);
        }
    } else {
        taskENTER_CRITICAL(&s_mux);
        ble_tx_core_clear(&s_tx);
        taskEXIT_CRITICAL(&s_mux);
    }
    if (queued) {
        wake_writer();
    }
}

esp_err_t ble_tx_start(void) {
    if (s_started) {
        return ESP_OK;
    }

    ble_tx_core_init(&s_tx);
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_live_handle = 0;
    s_subscribed = false;

    s_wake = xSemaphoreCreateBinary();
    if (s_wake == NULL) {
        return ESP_ERR_NO_MEM;
    }
    BaseType_t created = xTaskCreatePinnedToCore(
        ble_tx_task, "ble_tx", BLE_TX_TASK_STACK_BYTES, NULL, BLE_TX_TASK_PRIORITY,
        NULL, BLE_TX_TASK_CORE);
    if (created != pdPASS) {
        vSemaphoreDelete(s_wake);
        s_wake = NULL;
        return ESP_ERR_NO_MEM;
    }

    bridge_state_set_change_hook(ble_tx_live_changed, NULL);
    s_started = true;
    return ESP_OK;
}
