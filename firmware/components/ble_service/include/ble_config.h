/*
 * ble_config.h - pure `config` characteristic codec (design 05 section 5.9).
 *
 * The encoder and validator are plain C11 so the host tests can pin the exact
 * 80-byte wire vector and every refusal without NimBLE. The firmware callback
 * copies the mbuf, calls ble_config_parse(), then persists the accepted values
 * through bridge_config. No NVS access lives here.
 */
#ifndef SX4_BLE_CONFIG_H
#define SX4_BLE_CONFIG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The write status mirrors the control result names (design 05 section 5.6):
 * invalid = 1, unsupported = 2. A GATT write has no result notification, so
 * the status is carried as an ATT application error in the 0x80 range. */
#define BLE_CONFIG_ATT_APP_ERROR 0x80u
#define BLE_CONFIG_ATT_INVALID \
    (BLE_CONFIG_ATT_APP_ERROR | 1u) /* ATT 0x81: malformed / bad value */
#define BLE_CONFIG_ATT_UNSUPPORTED \
    (BLE_CONFIG_ATT_APP_ERROR | 2u) /* ATT 0x82: billows_mode != 0 */
#define BLE_CONFIG_ATT_STORAGE \
    (BLE_CONFIG_ATT_APP_ERROR | 7u) /* ATT 0x87: NVS write failed */

typedef enum {
    BLE_CONFIG_OK = 0,
    BLE_CONFIG_INVALID = 1,
    BLE_CONFIG_UNSUPPORTED = 2,
} ble_config_status_t;

typedef struct {
    uint8_t units;                /* 0 = Celsius, 1 = Fahrenheit (OLED) */
    uint16_t display_timeout_s;   /* 0 / 30 / 60 / 120 */
    char device_name[16];         /* UTF-8, NUL-terminated, 1..15 bytes */
} ble_config_view_t;

/*
 * Parse one complete 80-byte write.
 *
 * - wrong length, wrong ver, bad UTF-8, an unterminated/empty name, bad units
 *   or a bad timeout returns BLE_CONFIG_INVALID;
 * - a nonzero `billows_mode` returns BLE_CONFIG_UNSUPPORTED (the MVP has no
 *   control path and `caps.billows_control` is always 0);
 * - reserved probe name/role bytes and `billows_target_f10` are ignored.
 *
 * On any non-OK result `out` is untouched.
 */
ble_config_status_t ble_config_parse(const uint8_t *in, size_t len,
                                     ble_config_view_t *out);

/* Validate an in-memory view with the same rules as a wire write. */
ble_config_status_t ble_config_validate(const ble_config_view_t *view);

/*
 * Encode the fixed 80-byte payload. `ver` is 1, reserved fields and the
 * Billows target/mode are always 0. Returns SX4_CONFIG_SIZE, or 0 for a bad
 * argument, a too-small buffer or an invalid view.
 */
size_t ble_config_encode(const ble_config_view_t *view, uint8_t *out,
                         size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_CONFIG_H */
