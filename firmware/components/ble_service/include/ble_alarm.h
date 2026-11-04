/*
 * ble_alarm.h - pure `alarm` encoder (protocol minor 1).
 *
 * One bridge_state snapshot becomes the fixed 20-byte alarm payload: per-probe
 * active/armed/acknowledged bits plus canonical high/low setpoints. The encoder
 * is plain C11 so the GATT read, the notification producer and the host vector
 * test all use the same mapping.
 */
#ifndef SX4_BLE_ALARM_H
#define SX4_BLE_ALARM_H

#include <stddef.h>
#include <stdint.h>

#include "bridge_state.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Returns SX4_ALARM_SIZE on success, 0 on a bad argument or short buffer. */
size_t ble_alarm_encode(const bridge_state_live_t *snapshot, uint8_t *out,
                        size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_ALARM_H */
