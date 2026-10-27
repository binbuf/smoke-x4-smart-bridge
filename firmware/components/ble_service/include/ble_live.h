/*
 * ble_live.h - pure `live` encoder (design 05 section 5.4, T28).
 *
 * One bridge_state snapshot becomes the fixed 20-byte wire payload. The encoder
 * knows only the MVP mapping rules:
 *   - a detached probe always uses SX4_TEMP_DETACHED, never the sample value;
 *   - seq is 0xFFFFFFFF until the log has stored a sample;
 *   - an unknown Billows target is 0 and billows_output is always 0;
 *   - battery_pct 255 means unknown.
 * The generated codec (protocol/gen/records.c) owns the offsets and byte order.
 */
#ifndef SX4_BLE_LIVE_H
#define SX4_BLE_LIVE_H

#include <stddef.h>
#include <stdint.h>

#include "bridge_state.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Returns SX4_LIVE_SIZE on success, 0 on a bad argument or short buffer. */
size_t ble_live_encode(const bridge_state_live_t *snapshot, uint8_t *out,
                       size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_LIVE_H */
