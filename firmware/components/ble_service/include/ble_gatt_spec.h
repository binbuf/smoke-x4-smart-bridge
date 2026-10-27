/*
 * ble_gatt_spec.h - the static GATT contract used by both the NimBLE server and
 * the host tests (design 05 section 5.1).
 *
 * The table is plain data so it can be checked without ESP-IDF: eight slots,
 * exactly the properties and security levels in the contract, a CCCD on every
 * Notify characteristic and no Wi-Fi/OTA/DFU slot.
 */
#ifndef SX4_BLE_GATT_SPEC_H
#define SX4_BLE_GATT_SPEC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t slot;      /* 0x0001 .. 0x0008 */
    const char *name;   /* info, live, ... */
    const char *uuid;   /* full 128-bit characteristic UUID */
    uint8_t props;      /* SX4_BLE_PROP_* bit mask */
    uint8_t security;   /* SX4_BLE_SEC_* */
} ble_gatt_spec_t;

extern const ble_gatt_spec_t ble_gatt_specs[];
extern const size_t ble_gatt_spec_count;

/* NULL when `slot` is not one of the eight registered slots. */
const ble_gatt_spec_t *ble_gatt_spec_by_slot(uint16_t slot);

/*
 * A Notify characteristic must also expose a CCCD. The CCCD write inherits the
 * characteristic's security level, so this is true exactly for the Notify
 * slots and never for a read/write-only slot.
 */
bool ble_gatt_spec_needs_cccd(const ble_gatt_spec_t *spec);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_GATT_SPEC_H */
