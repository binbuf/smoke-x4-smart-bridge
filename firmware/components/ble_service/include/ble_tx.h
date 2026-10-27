/*
 * ble_tx.h - bounded live-notification hand-off owned by the ble_tx task
 * (design 03 section 3.3, design 05 section 5.4, T28).
 *
 * The sample path and the bridge_state flag setters only encode 20 bytes and
 * append them to a fixed ring. ble_tx is the single NimBLE notification writer:
 * it drains the ring from its own task, never from the radio/sample tasks, and
 * performs no allocation while producing the payload.
 *
 * The core (ble_tx_core.c) is plain C11 and host-tested. The ESP-IDF adapter
 * (ble_tx.c) serialises it with a critical section, installs the bridge_state
 * change hook and owns the NimBLE send.
 */
#ifndef SX4_BLE_TX_H
#define SX4_BLE_TX_H

#include <stdbool.h>
#include <stdint.h>

#include "bridge_state.h"
#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Fixed depth of the live queue. A full queue drops the newest frame. */
#define BLE_TX_QUEUE_DEPTH 8u

typedef struct {
    uint8_t payload[SX4_LIVE_SIZE];
    uint8_t len;
} ble_tx_frame_t;

typedef struct {
    ble_tx_frame_t frames[BLE_TX_QUEUE_DEPTH];
    uint8_t head;
    uint8_t tail;
    uint8_t count;
    uint32_t queued;
    uint32_t dropped;
    uint32_t sent;
    bool have_last;
    uint32_t last_seq;
    uint8_t last_flags;
} ble_tx_core_t;

void ble_tx_core_init(ble_tx_core_t *tx);

/* Drop queued frames and forget the last-sent seq/flags; counters survive. */
void ble_tx_core_clear(ble_tx_core_t *tx);

/*
 * Encode one snapshot. It is queued as a new notification when its seq or its
 * wire flags differ from the last *queued* frame; an identical snapshot is a
 * no-op. Returns true when a frame was appended. A full queue drops the newest
 * frame (sync recovers it) and returns false.
 */
bool ble_tx_core_queue_live(ble_tx_core_t *tx,
                            const bridge_state_live_t *snapshot);

/* Pop the oldest frame. Returns false when empty. */
bool ble_tx_core_take(ble_tx_core_t *tx, ble_tx_frame_t *out);

#ifdef ESP_PLATFORM
#include "esp_err.h"

/* Create the ble_tx task and install the bridge_state change hook. */
esp_err_t ble_tx_start(void);

/* The GATT value handle of `live`; set after service registration. */
void ble_tx_set_live_handle(uint16_t attr_handle);

/* GAP events. A subscription change also primes the queue with the snapshot. */
void ble_tx_on_connect(uint16_t conn_handle);
void ble_tx_on_disconnect(void);
void ble_tx_on_live_subscribe(bool subscribed);

/* bridge_state change hook: non-blocking producer, safe from any task. */
void ble_tx_live_changed(void *ctx);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_TX_H */
