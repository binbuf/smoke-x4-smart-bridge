/*
 * ble_tx_core.c - fixed-size live notification ring (T28).
 *
 * Plain C11, no ESP-IDF and no heap. Frames are already encoded 20-byte
 * payloads, so the producer cost is one encoder call and one copy.
 */
#include "ble_tx.h"

#include <stddef.h>
#include <string.h>

#include "ble_live.h"

static uint32_t payload_seq(const uint8_t *payload) {
    return (uint32_t)payload[10] | ((uint32_t)payload[11] << 8) |
           ((uint32_t)payload[12] << 16) | ((uint32_t)payload[13] << 24);
}

void ble_tx_core_init(ble_tx_core_t *tx) {
    if (tx == NULL) {
        return;
    }
    memset(tx, 0, sizeof(*tx));
}

void ble_tx_core_clear(ble_tx_core_t *tx) {
    if (tx == NULL) {
        return;
    }
    tx->head = 0;
    tx->tail = 0;
    tx->count = 0;
    tx->have_last = false;
    tx->last_seq = 0;
    tx->last_flags = 0;
}

bool ble_tx_core_queue_live(ble_tx_core_t *tx,
                            const bridge_state_live_t *snapshot) {
    ble_tx_frame_t frame;

    if (tx == NULL || snapshot == NULL) {
        return false;
    }
    memset(&frame, 0, sizeof(frame));
    frame.len =
        (uint8_t)ble_live_encode(snapshot, frame.payload, sizeof(frame.payload));
    if (frame.len != SX4_LIVE_SIZE) {
        return false;
    }

    const uint8_t flags = frame.payload[1];
    const uint32_t seq = payload_seq(frame.payload);
    if (tx->have_last && seq == tx->last_seq && flags == tx->last_flags) {
        return false; /* no stored sample and no flag transition */
    }

    if (tx->count >= BLE_TX_QUEUE_DEPTH) {
        tx->dropped++;
        return false;
    }

    tx->frames[tx->tail] = frame;
    tx->tail = (uint8_t)((tx->tail + 1u) % BLE_TX_QUEUE_DEPTH);
    tx->count++;
    tx->queued++;
    tx->have_last = true;
    tx->last_seq = seq;
    tx->last_flags = flags;
    return true;
}

bool ble_tx_core_take(ble_tx_core_t *tx, ble_tx_frame_t *out) {
    if (tx == NULL || out == NULL || tx->count == 0u) {
        return false;
    }
    *out = tx->frames[tx->head];
    tx->head = (uint8_t)((tx->head + 1u) % BLE_TX_QUEUE_DEPTH);
    tx->count--;
    tx->sent++;
    return true;
}
