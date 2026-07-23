/* bridge_event_types.h — event IDs and payload structs for the BRIDGE_EVENT
 * bus (design 03 §3.2). Pure C, no ESP-IDF includes, so host tests and the
 * ESP-IDF-free components can use it.
 *
 * Payloads are small POD structs copied by esp_event — never pointers into a
 * caller's stack.
 */
#ifndef BRIDGE_EVENT_TYPES_H
#define BRIDGE_EVENT_TYPES_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BRIDGE_EVT_SAMPLE,  /* bridge_evt_sample_t  — a decoded state message   */
    BRIDGE_EVT_PAIRING, /* bridge_evt_pairing_t — paired / unpaired / synced */
    BRIDGE_EVT_BASE_LOST, /* uint32_t seconds_since_last_packet               */
    BRIDGE_EVT_BASE_FOUND, /* no payload */
    BRIDGE_EVT_NET,     /* bridge_evt_net_t     — mode / ip / rssi changed  */
    BRIDGE_EVT_SESSION, /* bridge_evt_session_t — started / ended / renamed */
    BRIDGE_EVT_ALARM,   /* bridge_evt_alarm_t   — raised / cleared / acked  */
    BRIDGE_EVT_BUTTON, /* bridge_evt_button_t  — tap / double / hold / …   */
    BRIDGE_EVT_STORAGE, /* bridge_evt_storage_t — usage, low-space, purged  */
    BRIDGE_EVT_POWER,   /* bridge_evt_power_t   — mV, SoC, charging, saver  */
    BRIDGE_EVT_TIME,    /* bridge_evt_time_t    — clock source acquired     */
    BRIDGE_EVT_OTA,     /* bridge_evt_ota_t     — progress / result         */
    BRIDGE_EVT_BLE,     /* bridge_evt_ble_t     — passkey / link / bonds    */
    BRIDGE_EVT_MAX,
} bridge_event_id_t;

typedef struct {
    uint32_t t_rel_s; /* seconds since session start */
    int16_t
        temp_f10[4]; /* canonical tenths °F; BRIDGE_TEMP_DETACHED sentinel */
    uint8_t flags;   /* sample_rec flags byte (see record_gen.h) */
    uint8_t num_probes; /* 2 or 4 */
    int8_t rssi;
    int8_t snr;
} bridge_evt_sample_t;

typedef enum {
    BRIDGE_PAIRING_UNPAIRED = 0,
    BRIDGE_PAIRING_SYNCED,
    BRIDGE_PAIRING_PAIRED,
} bridge_pairing_state_t;

typedef struct {
    uint8_t state;     /* bridge_pairing_state_t */
    char device_id[8]; /* NUL-padded */
    uint32_t frequency_hz;
    uint8_t num_probes;
} bridge_evt_pairing_t;

typedef struct {
    uint8_t mode;  /* bridge_net_mode_t (record_gen.h wire values) */
    uint8_t state; /* bridge_net_state_t */
    uint8_t ip[4];
    int8_t rssi;
} bridge_evt_net_t;

typedef enum {
    BRIDGE_SESSION_STARTED = 0,
    BRIDGE_SESSION_ENDED,
    BRIDGE_SESSION_RENAMED,
} bridge_session_action_t;

typedef struct {
    uint8_t action; /* bridge_session_action_t */
    uint32_t session_id;
} bridge_evt_session_t;

typedef enum {
    BRIDGE_ALARM_RAISED = 0,
    BRIDGE_ALARM_CLEARED,
    BRIDGE_ALARM_ACKED,
} bridge_alarm_action_t;

typedef struct {
    uint8_t action; /* bridge_alarm_action_t */
    uint8_t alarm_id;
    uint8_t rule;
    uint8_t probe; /* 0 = whole cook, 1..4 */
    int16_t value_f10;
} bridge_evt_alarm_t;

typedef enum {
    BRIDGE_GESTURE_TAP = 0,
    BRIDGE_GESTURE_DOUBLE_TAP,
    BRIDGE_GESTURE_HOLD_2S,
    BRIDGE_GESTURE_HOLD_10S,
} bridge_gesture_t;

typedef struct {
    uint8_t gesture; /* bridge_gesture_t */
} bridge_evt_button_t;

typedef enum {
    BRIDGE_STORAGE_USAGE = 0,
    BRIDGE_STORAGE_LOW,
    BRIDGE_STORAGE_FULL,
    BRIDGE_STORAGE_PURGED,
} bridge_storage_kind_t;

typedef struct {
    uint8_t kind; /* bridge_storage_kind_t */
    uint32_t used_b;
    uint32_t total_b;
    uint8_t free_pct;
} bridge_evt_storage_t;

typedef struct {
    uint16_t mv;
    uint8_t soc_pct;
    bool charging;
    bool saver;
} bridge_evt_power_t;

typedef enum {
    BRIDGE_TIME_SOURCE_NONE = 0,
    BRIDGE_TIME_SOURCE_STALE, /* monotonic floor restored from NVS */
    BRIDGE_TIME_SOURCE_PHONE,
    BRIDGE_TIME_SOURCE_SNTP,
} bridge_time_source_t;

typedef struct {
    uint8_t source; /* bridge_time_source_t */
    uint64_t unix_ms;
} bridge_evt_time_t;

typedef enum {
    BRIDGE_OTA_WRITING = 0,
    BRIDGE_OTA_VERIFYING,
    BRIDGE_OTA_DONE,
    BRIDGE_OTA_FAILED,
} bridge_ota_phase_t;

typedef struct {
    uint8_t phase; /* bridge_ota_phase_t */
    uint8_t pct;
    int32_t err;
} bridge_evt_ota_t;

/* F10.5 publishes these; app_ui subscribes so the OLED can show the
 * passkey without app_ble ever knowing a display exists. Additive to the
 * enum above — the guard test's density check grows with it. */
typedef enum {
    BRIDGE_BLE_PASSKEY_SHOW = 0, /* passkey valid; display it */
    BRIDGE_BLE_PASSKEY_CLEAR,    /* bonded, failed, or timed out */
    BRIDGE_BLE_CONNECTED,
    BRIDGE_BLE_DISCONNECTED,
    BRIDGE_BLE_BONDED,
} bridge_ble_action_t;

typedef struct {
    uint8_t action;   /* bridge_ble_action_t */
    uint32_t passkey; /* 0..999999; meaningful only on PASSKEY_SHOW */
    uint8_t conns;    /* current central connections */
    uint8_t bonds;    /* stored bonds, 0..3 */
} bridge_evt_ble_t;

#ifdef __cplusplus
}
#endif

#endif /* BRIDGE_EVENT_TYPES_H */
