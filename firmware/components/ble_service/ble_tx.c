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
static uint16_t s_alarm_handle;
static volatile bool s_live_subscribed;
static volatile bool s_alarm_subscribed;

static void wake_writer(void) {
    if (s_wake != NULL) {
        (void)xSemaphoreGive(s_wake);
    }
}

static void ble_tx_send(const ble_tx_frame_t *frame) {
    const bool alarm = frame->type == BLE_TX_FRAME_ALARM;
    const uint16_t handle = alarm ? s_alarm_handle : s_live_handle;
    const bool subscribed = alarm ? s_alarm_subscribed : s_live_subscribed;

    if (!subscribed || s_conn_handle == BLE_HS_CONN_HANDLE_NONE ||
        handle == 0u) {
        return;
    }
    struct os_mbuf *om =
        ble_hs_mbuf_from_flat(frame->payload, frame->len);
    if (om == NULL) {
        ESP_LOGW(TAG, "no mbuf for %s notification", alarm ? "alarm" : "live");
        return;
    }
    int rc = ble_gatts_notify_custom(s_conn_handle, handle, om);
    if (rc != 0) {
        ESP_LOGD(TAG, "%s notify failed (%d)", alarm ? "alarm" : "live", rc);
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
    if (!s_started || (!s_live_subscribed && !s_alarm_subscribed)) {
        return;
    }

    bridge_state_live_t snapshot;
    if (bridge_state_snapshot(&snapshot) != BRIDGE_STATE_OK) {
        return;
    }

    bool queued = false;
    taskENTER_CRITICAL(&s_mux);
    /* Alarm first: a transition is the more important frame when the queue is
     * nearly full. Both encoders dedupe unchanged snapshots. */
    if (s_alarm_subscribed) {
        queued = ble_tx_core_queue_alarm(&s_tx, &snapshot) || queued;
    }
    if (s_live_subscribed) {
        queued = ble_tx_core_queue_live(&s_tx, &snapshot) || queued;
    }
    taskEXIT_CRITICAL(&s_mux);
    if (queued) {
        wake_writer();
    }
}

void ble_tx_set_live_handle(uint16_t attr_handle) {
    s_live_handle = attr_handle;
}

void ble_tx_set_alarm_handle(uint16_t attr_handle) {
    s_alarm_handle = attr_handle;
}

void ble_tx_on_connect(uint16_t conn_handle) {
    s_conn_handle = conn_handle;
}

void ble_tx_on_disconnect(void) {
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_live_subscribed = false;
    s_alarm_subscribed = false;
    taskENTER_CRITICAL(&s_mux);
    ble_tx_core_clear(&s_tx);
    taskEXIT_CRITICAL(&s_mux);
}

static void prime_queue(bool live, bool alarm) {
    bool queued = false;
    bridge_state_live_t snapshot;
    if (bridge_state_snapshot(&snapshot) == BRIDGE_STATE_OK) {
        taskENTER_CRITICAL(&s_mux);
        ble_tx_core_clear(&s_tx);
        if (alarm) {
            queued = ble_tx_core_queue_alarm(&s_tx, &snapshot) || queued;
        }
        if (live) {
            queued = ble_tx_core_queue_live(&s_tx, &snapshot) || queued;
        }
        taskEXIT_CRITICAL(&s_mux);
    }
    if (queued) {
        wake_writer();
    }
}

void ble_tx_on_live_subscribe(bool subscribed) {
    s_live_subscribed = subscribed;
    if (subscribed) {
        prime_queue(true, s_alarm_subscribed);
    } else if (!s_alarm_subscribed) {
        taskENTER_CRITICAL(&s_mux);
        ble_tx_core_clear(&s_tx);
        taskEXIT_CRITICAL(&s_mux);
    }
}

void ble_tx_on_alarm_subscribe(bool subscribed) {
    s_alarm_subscribed = subscribed;
    if (subscribed) {
        prime_queue(s_live_subscribed, true);
    } else if (!s_live_subscribed) {
        taskENTER_CRITICAL(&s_mux);
        ble_tx_core_clear(&s_tx);
        taskEXIT_CRITICAL(&s_mux);
    }
}

esp_err_t ble_tx_start(void) {
    if (s_started) {
        return ESP_OK;
    }

    ble_tx_core_init(&s_tx);
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_live_handle = 0;
    s_alarm_handle = 0;
    s_live_subscribed = false;
    s_alarm_subscribed = false;

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
