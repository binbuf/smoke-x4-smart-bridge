/*
 * ble_adv.h - pure advertising/scan-response builder and interval state
 * machine (design 05 section 5.2, T30).
 *
 * The NimBLE glue in ble_service.c only copies these bytes into
 * ble_gap_adv_set_data()/ble_gap_adv_rsp_set_data() and follows the action
 * returned by the state machine. Keeping the AD structures and the
 * boot/disconnect/connect/timeout transitions here makes the wire format and
 * the 250 ms -> 1,000 ms policy host-testable without ESP-IDF.
 */
#ifndef SX4_BLE_ADV_H
#define SX4_BLE_ADV_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Design 05 section 5.2. */
#define BLE_ADV_FAST_INTERVAL_MS 250u
#define BLE_ADV_SLOW_INTERVAL_MS 1000u
#define BLE_ADV_FAST_WINDOW_MS 60000u

/* Bluetooth SIG reserved test company ID for the bench build. */
#define BLE_ADV_COMPANY_ID 0xFFFFu

#define BLE_ADV_NAME_PREFIX "SmokeX4-"
#define BLE_ADV_NAME_LEN 12u  /* "SmokeX4-" + four hex digits */
#define BLE_ADV_NAME_MAX 13u /* includes the NUL */

/* 9 B status blob after the 2-byte company ID. */
#define BLE_ADV_STATUS_SIZE 9u

/* Flags (3) + complete 128-bit service UUID list (18) = 21 of 31 bytes. */
#define BLE_ADV_PDU_SIZE 21u
/* Complete local name (14) + manufacturer specific data (13) = 27 of 31. */
#define BLE_ADV_SCAN_RSP_SIZE 27u

/* The generated service UUID, little-endian, as it appears on the air. */
#define BLE_ADV_SERVICE_UUID_LE                                             \
    {0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b,   \
     0x4c, 0x00, 0x00, 0x9b, 0x7f}

typedef struct {
    uint8_t flags;          /* same bits as live.flags */
    int16_t pit_temp_f10;   /* P4, tenths degF; sentinels are allowed */
    uint8_t battery_pct;    /* 0..100, 255 = unknown */
    int16_t billows_target_f10; /* 0 = unknown */
    uint16_t age_s;         /* clamped to 0..255 on the wire */
} ble_adv_status_t;

/* Encode the 9-byte blob. Returns BLE_ADV_STATUS_SIZE or 0 on bad arguments. */
size_t ble_adv_status_encode(const ble_adv_status_t *status, uint8_t *out,
                             size_t cap);

/*
 * Format `SmokeX4-XXXX` from the six-byte BLE address (most-significant byte
 * last, the NimBLE/ESP convention). The last two bytes are uppercase hex.
 * Returns BLE_ADV_NAME_LEN or 0 on bad arguments.
 */
size_t ble_adv_format_name(char out[BLE_ADV_NAME_MAX], const uint8_t mac[6]);

/* Advertising PDU: Flags (LE general discoverable, BR/EDR unsupported) plus
 * the complete 128-bit service UUID. Returns BLE_ADV_PDU_SIZE or 0. */
size_t ble_adv_build_pdu(uint8_t *out, size_t cap);

/*
 * Scan response: complete local name then manufacturer-specific data
 * (company ID + status blob). `name` may be NULL, in which case it is omitted.
 * Returns the byte count (up to BLE_ADV_SCAN_RSP_SIZE) or 0.
 */
size_t ble_adv_build_scan_rsp(const char *name,
                              const ble_adv_status_t *status, uint8_t *out,
                              size_t cap);

/*
 * Convert a millisecond advertising interval to NimBLE's 0.625 ms units,
 * clamped to the 16-bit field. 250 ms -> 400, 1000 ms -> 1600.
 */
uint16_t ble_adv_interval_units(uint32_t interval_ms);

typedef enum {
    BLE_ADV_PHASE_OFF = 0,
    BLE_ADV_PHASE_FAST,
    BLE_ADV_PHASE_SLOW,
} ble_adv_phase_t;

typedef enum {
    BLE_ADV_EVENT_BOOT = 0,   /* boot/button/radio-enable */
    BLE_ADV_EVENT_DISCONNECT, /* link ended */
    BLE_ADV_EVENT_CONNECT_FAILED,
    BLE_ADV_EVENT_TIMEOUT, /* controller finished an advertising procedure */
    BLE_ADV_EVENT_CONNECTED,
    BLE_ADV_EVENT_STOP,
} ble_adv_event_t;

typedef struct {
    ble_adv_phase_t phase;
    uint32_t fast_until_ms;
} ble_adv_state_t;

typedef struct {
    bool advertise;      /* start (or restart) advertising now */
    uint32_t interval_ms; /* valid when advertise */
} ble_adv_action_t;

void ble_adv_state_init(ble_adv_state_t *state);

/*
 * Apply one lifecycle event. Boot/disconnect/failed-connect start a fresh
 * 250 ms fast window; a timeout restarts at the current interval without
 * extending that window; connect/stop turn advertising off.
 */
ble_adv_action_t ble_adv_state_event(ble_adv_state_t *state,
                                     ble_adv_event_t event, uint32_t now_ms);

/*
 * Deadline tick. Crossing the 60 s fast window returns advertise=true with the
 * 1,000 ms interval so the caller restarts the advertising procedure; every
 * other tick returns advertise=false.
 */
ble_adv_action_t ble_adv_state_tick(ble_adv_state_t *state, uint32_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_ADV_H */
