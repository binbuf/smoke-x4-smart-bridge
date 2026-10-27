/*
 * ble_info.h - pure `info` characteristic encoder (design 05 section 5.3).
 *
 * The encoder is plain C11 so the host tests can pin the exact 32-byte wire
 * vector.  The firmware supplies the field values from bridge_config, the
 * NimBLE identity address and the bond store; this file never reads hardware.
 */
#ifndef SX4_BLE_INFO_H
#define SX4_BLE_INFO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* MVP model string (design 05 section 5.3 example). */
#define BLE_INFO_MODEL "heltec3"

/*
 * Firmware version string. Kept in step with UI_VERSION in ui_render.h; the
 * app shows the same string on its About page and the OLED splash.
 */
#define BLE_INFO_FW_VERSION "0.1.0"

/* Bond slots in the MVP (design 05 section 5.11). */
#define BLE_INFO_MAX_BONDS 4u

/* `caps` value with every MVP capability set. Bit 1 stays clear on the wire. */
#define BLE_INFO_CAPS_ALL 0xFFu

typedef struct {
    const char *device_id; /* 4 ASCII hex chars, e.g. "A4F2"; shorter is padded */
    const char *fw;        /* up to 12 UTF-8 bytes, NUL padded */
    const char *model;     /* up to 8 UTF-8 bytes, NUL padded */
    uint8_t probes;        /* 2 or 4 */
    uint8_t caps;          /* requested caps; billows_control is always cleared */
    uint8_t bonds_free;    /* 0..4, clamped */
} ble_info_view_t;

/*
 * Clear `caps.billows_control` (bit 1). The MVP is observation-only, so no
 * caller may publish a control capability (design 05 section 5.3).
 */
uint8_t ble_info_caps(uint8_t requested_caps);

/* Clamp a used-bond count to 0..4 and return the free slots. */
uint8_t ble_info_bonds_free(uint8_t used_bonds);

/*
 * Number of probes to publish: the paired Smoke X4's 2/4 value when known,
 * otherwise 4 (the bridge UI supports four probe channels).
 */
uint8_t ble_info_probes(bool paired, uint8_t configured_probes);

/*
 * Encode the fixed 32-byte `info` payload. Returns SX4_INFO_SIZE on success,
 * 0 for a bad argument or a too-small buffer. Fields not supplied are zero;
 * `ver` is always 1 and the reserved bytes are always 0.
 */
size_t ble_info_encode(const ble_info_view_t *view, uint8_t *out, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_INFO_H */
