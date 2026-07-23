/* app_ble_core — the Bridge Control Service as a pure core (F10.1–F10.3,
 * F10.6–F10.9; protocol/ble-gatt.md, design 05 §5.6).
 *
 * Same shape as F8 and F9: the characteristic registry, the security
 * table, every payload builder, the write dispatcher, and the notification
 * chunker are plain C11 over injected ops. The NimBLE glue is thin enough
 * to be uninteresting, which is the point — everything that can be wrong
 * about this contract is wrong on the host, in CI, before a phone is
 * involved.
 *
 * TWO RULES THIS FILE LIVES UNDER, both inherited rather than invented:
 *
 *  1. Every payload serializes through record_gen.h. Nothing is
 *     hand-rolled. The codecs, their fixtures, and the Dart mirrors have
 *     existed since M0; F10's job is to stand a GATT server in front of
 *     them.
 *  2. TEMP_DETACHED is the detached sentinel end to end, never 0 — the
 *     same invariant F9.3 grep-proofed for JSON. A detached probe that
 *     surfaces as 0 °F is a lie on a graph and a lie on a screen.
 */
#ifndef APP_BLE_CORE_H
#define APP_BLE_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_net_core.h"
#include "record_gen.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Return codes (map 1:1 onto result_status) ────────────────────── */

#define APP_BLE_OK 0
#define APP_BLE_ERR_INVALID (-1)
#define APP_BLE_ERR_BUSY (-2)
#define APP_BLE_ERR_FAILED (-3)

/* ── The nine characteristics (ble-gatt §1) ───────────────────────── */

typedef enum {
    APP_BLE_CH_DEVICE_INFO = 0, /* 0001 */
    APP_BLE_CH_NET_STATUS,      /* 0002 */
    APP_BLE_CH_WIFI_SCAN_CTRL,  /* 0003 */
    APP_BLE_CH_WIFI_SCAN_RESULT,/* 0004 */
    APP_BLE_CH_WIFI_CONFIG,     /* 0005 */
    APP_BLE_CH_DEVICE_CONTROL,  /* 0006 */
    APP_BLE_CH_LIVE_STATE,      /* 0007 */
    APP_BLE_CH_HISTORY_PREVIEW, /* 0008 */
    APP_BLE_CH_RESULT,          /* 0009 */
    APP_BLE_CH_COUNT,
} app_ble_char_t;

#define APP_BLE_PROP_READ (1u << 0)
#define APP_BLE_PROP_WRITE (1u << 1)
#define APP_BLE_PROP_NOTIFY (1u << 2)

/* ble-gatt §3. `authenticated` implies `encrypted`. */
typedef enum {
    APP_BLE_SEC_OPEN = 0,
    APP_BLE_SEC_ENCRYPTED,
    APP_BLE_SEC_AUTHENTICATED,
} app_ble_sec_t;

typedef struct {
    uint16_t uuid16; /* the XXXX slot of the base UUID */
    uint8_t props;
    uint8_t sec; /* app_ble_sec_t */
    uint16_t max_len;
    const char *name;
} app_ble_char_def_t;

const app_ble_char_def_t *app_ble_char_def(app_ble_char_t ch);

/* Base UUID 7f9aXXXX-4c5b-4b0f-9a3d-1c2e3f405162, written little-endian
 * as it goes on air (which is how NimBLE wants it too). */
void app_ble_uuid128(uint16_t uuid16, uint8_t out[16]);
#define APP_BLE_SERVICE_UUID16 0x0000

/* The connection's security state, as the stack reports it. */
typedef struct {
    bool encrypted;
    bool authenticated; /* MITM-protected LTK (passkey pairing) */
} app_ble_link_t;

/* ble-gatt §3, enforced HERE rather than in each handler: a write that
 * fails this never reaches the code that would act on it. */
bool app_ble_access_allowed(app_ble_char_t ch, const app_ble_link_t *link);

/* ── Injected facts and actions ───────────────────────────────────── */

typedef struct {
    char id[8]; /* "A4F2" — the same suffix as the AP SSID and BLE name */
    const char *model;
    const char *fw;
    uint8_t probes; /* 2 or 4 */
    uint8_t caps;   /* device_info caps bits (ble-gatt §5.1) */
    uint8_t mac[6];
} app_ble_sysinfo_t;

typedef struct {
    uint8_t mode;  /* bridge_net_mode_t (wire values) */
    uint8_t state; /* bridge_net_state_t */
    int8_t rssi;
    uint8_t ip[4];
    char ssid[33];
    char host[23];
} app_ble_net_snapshot_t;

typedef struct {
    char ssid[33];
    int8_t rssi;
    uint8_t auth;    /* ble-gatt §5.4.1 */
    uint8_t channel; /* 1..14 */
} app_ble_scan_ap_t;

typedef struct {
    void (*sysinfo)(app_ble_sysinfo_t *out);
    void (*net_status)(app_ble_net_snapshot_t *out);
    /* F8.4's deferred apply — the ~500 ms window that lets the BLE
     * acknowledgement flush before the radio it rode on reconfigures. */
    int (*net_request_config)(const app_net_pending_cfg_t *cfg);
    /* Scanning from AP mode is not free on this chip; the cost is the
     * glue's problem, and the empirical size of it is a named bench
     * observation (F10.7). Returns APP_BLE_ERR_BUSY if already scanning. */
    int (*scan_start)(void);
    int (*scan_cancel)(void);
    /* Push `len` bytes on `ch`. The chunker has already split at the
     * negotiated boundary, so the glue never fragments anything. */
    int (*notify)(app_ble_char_t ch, const uint8_t *buf, size_t len);
    /* op 10: wake the display and flash what exists. The LED driver is
     * M5's, so in M3 this is honestly partial, not fake. */
    int (*identify)(void);
    void (*reboot)(void);
    /* op 8: wipe NVS **including all bonds**, sessions, and config. */
    int (*factory_reset)(void);
    uint64_t (*uptime_ms)(void);
} app_ble_ops_t;

/* Binds the seam and resets all internal state (safe to call repeatedly,
 * which is what lets one host process drive many scenarios). */
int app_ble_core_init(const app_ble_ops_t *ops);

/* ── Payload builders (F10.1) ─────────────────────────────────────────
 * Each returns the wire length or -1 if `cap` is too small. */

int app_ble_build_device_info(uint8_t *out, size_t cap);
int app_ble_build_net_status(uint8_t *out, size_t cap);
int app_ble_build_live_state(uint8_t *out, size_t cap);
/* The pit probe's last 2 h at 1-minute buckets, straight from cook_ring —
 * no flash read, ≤ 120 values (ble-gatt §5.8). A ring shorter than 2 h
 * yields count < 120 rather than padding. */
int app_ble_build_history_preview(uint8_t *out, size_t cap);

/* ── MTU and the notification chunker (F10.3, ble-gatt §4) ────────── */

#define APP_BLE_MTU_DEFAULT 23
#define APP_BLE_MTU_PREFERRED 247
/* ATT overhead on a notification: opcode + handle. */
#define APP_BLE_ATT_NOTIFY_OVERHEAD 3

/* THE load-bearing guarantee of the whole design, as a build error rather
 * than a yard failure: live_state fits an unnegotiated link, so a phone
 * whose MTU exchange fails still gets telemetry (R7). Adding a field to
 * live_state breaks the build here, deliberately. */
_Static_assert(BRIDGE_LIVE_STATE_SIZE <=
                   APP_BLE_MTU_DEFAULT - APP_BLE_ATT_NOTIFY_OVERHEAD,
               "live_state must survive the default 23-byte ATT MTU — see "
               "ble-gatt §4; do not raise this bound, shrink the payload");

void app_ble_set_mtu(uint16_t mtu);
uint16_t app_ble_mtu(void);
/* Usable notification payload: MTU - 3, floored at the 20-byte default. */
size_t app_ble_notify_chunk(void);

/* Splits `len` bytes at the negotiated boundary and pushes each piece
 * through ops->notify. Reads use Read Blob and long writes use
 * Prepare/Execute — those are stack behaviour, verified rather than
 * reimplemented. Returns 0, or the first ops->notify error. */
int app_ble_notify_chunked(app_ble_char_t ch, const uint8_t *buf, size_t len);

/* ── Reads and writes (F10.1, F10.6–F10.9) ───────────────────────── */

/* Fills `out` with the characteristic's current value. Returns the length,
 * -1 for an unreadable characteristic or too small a buffer. Security is
 * the caller's (the glue asks the stack); app_ble_access_allowed() is the
 * shared predicate. */
int app_ble_core_read(app_ble_char_t ch, uint8_t *out, size_t cap);

/* Dispatches a write. ALWAYS answers on `result` — including for a
 * security refusal, a malformed frame, and an unknown op. Returns 0 when
 * an answer was produced. */
int app_ble_core_write(app_ble_char_t ch, const app_ble_link_t *link,
                       const uint8_t *data, size_t len);

/* ── Push paths (F10.6, F10.9) ────────────────────────────────────── */

/* One notification per BRIDGE_EVT_NET transition — the app watches
 * connecting → up/failed across the §5.7 handoff, and a missed transition
 * strands the wizard. */
int app_ble_notify_net_status(void);
/* Every decoded packet (~30 s), plus immediately on any alarm transition.
 * The alarm subscription is wired now so F13 (M5) changes nothing here. */
int app_ble_notify_live_state(void);

/* ── Wi-Fi scan flow (F10.7) ──────────────────────────────────────── */

bool app_ble_scan_active(void);
/* The glue calls this when esp_wifi hands back a completed scan. Emits one
 * correctly-indexed notification per AP, and stops early if a cancel
 * arrives mid-stream. A scan that was cancelled emits nothing. */
int app_ble_scan_deliver(const app_ble_scan_ap_t *aps, int n);

/* ── Advertising (F10.2, ble-gatt §2) ─────────────────────────────── */

#define APP_BLE_ADV_MAX 31
#define APP_BLE_NAME_MAX 20
#define APP_BLE_STATUS_BLOB_LEN 7
/* Bluetooth SIG reserved test ID until a real one is assigned. */
#define APP_BLE_COMPANY_ID 0xFFFF

/* "SmokeBridge-XXXX", built from F8.3's MAC-suffix helper so the BLE
 * name, the AP SSID, and the mDNS TXT `id` cannot disagree. */
void app_ble_local_name(const uint8_t mac[6], char out[APP_BLE_NAME_MAX]);

/* The 7-byte manufacturer status blob (§2.3), rebuilt on the same events
 * that feed live_state — a device list showing "pit 243 °F · 4 h 12 m"
 * from a stale blob is worse than showing none. */
int app_ble_build_status_blob(uint8_t out[APP_BLE_STATUS_BLOB_LEN]);

/* Flags + the 128-bit service UUID: 21 of the 31 legacy bytes. */
int app_ble_build_adv(uint8_t *out, size_t cap);
/* Complete local name + the manufacturer blob: 29 of 31. */
int app_ble_build_scan_rsp(uint8_t *out, size_t cap);

/* §2: 500 ms idle, 250 ms for 60 s after boot or a button press. */
#define APP_BLE_ADV_FAST_MS 250
#define APP_BLE_ADV_IDLE_MS 500
#define APP_BLE_ADV_FAST_WINDOW_MS (60u * 1000u)

void app_ble_adv_note_fast(uint64_t now_ms); /* boot or button */
uint16_t app_ble_adv_interval_ms(uint64_t now_ms);

/* ── Bonding and the passkey (F10.5, ble-gatt §3) ─────────────────── */

#define APP_BLE_MAX_BONDS 3

/* The stack reports bond-store activity through these; the core keeps the
 * cap and drives the passkey lifecycle. */
void app_ble_set_bond_count(uint8_t bonds);
uint8_t app_ble_bond_count(void);
/* False once three phones are bonded — the fourth pairing attempt is
 * rejected until a slot is freed (§3). */
bool app_ble_bond_slot_available(void);

/* Sets/clears the passkey. Publishing it to the bus (so app_ui shows the
 * overlay) is the glue's job; the core owns the value and its lifetime. */
void app_ble_passkey_set(uint32_t passkey);
void app_ble_passkey_clear(void);
bool app_ble_passkey_active(void);
uint32_t app_ble_passkey(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_BLE_CORE_H */
