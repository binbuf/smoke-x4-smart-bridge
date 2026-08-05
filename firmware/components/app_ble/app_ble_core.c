/* app_ble_core.c — the registry, the security predicate, the payload
 * builders, and the MTU chunker (F10.1, F10.3, F10.9).
 *
 * The write dispatch lives in app_ble_ctrl.c and the advertising builders
 * in app_ble_adv.c; app_ble_internal.h is what they share.
 */
#include "app_ble_internal.h"

#include <string.h>

#include "app_alarm_svc.h"
#include "app_power_svc.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"

const app_ble_ops_t *g_ble_ops;
static uint16_t s_mtu = APP_BLE_MTU_DEFAULT;
static uint8_t s_bonds;
static bool s_passkey_active;
static uint32_t s_passkey;

/* ── Registry (ble-gatt §1 and §3, one table, no second copy) ─────── */

static const app_ble_char_def_t k_chars[APP_BLE_CH_COUNT] = {
    [APP_BLE_CH_DEVICE_INFO] = {0x0001, APP_BLE_PROP_READ, APP_BLE_SEC_OPEN,
                                BRIDGE_DEVICE_INFO_SIZE, "device_info"},
    [APP_BLE_CH_NET_STATUS] = {0x0002, APP_BLE_PROP_READ | APP_BLE_PROP_NOTIFY,
                               APP_BLE_SEC_ENCRYPTED,
                               BRIDGE_NET_STATUS_MAX_SIZE, "net_status"},
    [APP_BLE_CH_WIFI_SCAN_CTRL] = {0x0003, APP_BLE_PROP_WRITE,
                                   APP_BLE_SEC_ENCRYPTED,
                                   BRIDGE_WIFI_SCAN_CTRL_SIZE,
                                   "wifi_scan_ctrl"},
    [APP_BLE_CH_WIFI_SCAN_RESULT] = {0x0004, APP_BLE_PROP_NOTIFY,
                                     APP_BLE_SEC_ENCRYPTED,
                                     BRIDGE_WIFI_SCAN_RESULT_MAX_SIZE,
                                     "wifi_scan_result"},
    /* The two that can change network config or wipe the device. */
    [APP_BLE_CH_WIFI_CONFIG] = {0x0005, APP_BLE_PROP_WRITE,
                                APP_BLE_SEC_AUTHENTICATED,
                                BRIDGE_WIFI_CONFIG_MAX_SIZE, "wifi_config"},
    [APP_BLE_CH_DEVICE_CONTROL] = {0x0006, APP_BLE_PROP_WRITE,
                                   APP_BLE_SEC_AUTHENTICATED,
                                   BRIDGE_DEVICE_CONTROL_MAX_SIZE,
                                   "device_control"},
    [APP_BLE_CH_LIVE_STATE] = {0x0007, APP_BLE_PROP_READ | APP_BLE_PROP_NOTIFY,
                               APP_BLE_SEC_ENCRYPTED, BRIDGE_LIVE_STATE_SIZE,
                               "live_state"},
    [APP_BLE_CH_HISTORY_PREVIEW] = {0x0008, APP_BLE_PROP_READ,
                                    APP_BLE_SEC_ENCRYPTED,
                                    BRIDGE_HISTORY_PREVIEW_MAX_SIZE,
                                    "history_preview"},
    [APP_BLE_CH_RESULT] = {0x0009, APP_BLE_PROP_NOTIFY, APP_BLE_SEC_ENCRYPTED,
                           BRIDGE_RESULT_MAX_SIZE, "result"},
    /* v1.1 — full history over BLE. `encrypted`, not `authenticated`: these
     * two read stored cooks and change nothing, so they sit with live_state
     * rather than with the pair that can reconfigure or wipe the device
     * (§3). A bond is still required — a cook is not public. */
    [APP_BLE_CH_HISTORY_CTRL] = {0x000A, APP_BLE_PROP_WRITE,
                                 APP_BLE_SEC_ENCRYPTED,
                                 BRIDGE_HISTORY_CTRL_SIZE, "history_ctrl"},
    [APP_BLE_CH_HISTORY_DATA] = {0x000B, APP_BLE_PROP_NOTIFY,
                                 APP_BLE_SEC_ENCRYPTED,
                                 BRIDGE_HISTORY_DATA_MAX_SIZE, "history_data"},
};

const app_ble_char_def_t *app_ble_char_def(app_ble_char_t ch) {
    if (ch < 0 || ch >= APP_BLE_CH_COUNT) {
        return NULL;
    }
    return &k_chars[ch];
}

/* 7f9aXXXX-4c5b-4b0f-9a3d-1c2e3f405162, reversed for the air. */
void app_ble_uuid128(uint16_t uuid16, uint8_t out[16]) {
    static const uint8_t base_be[16] = {0x7F, 0x9A, 0x00, 0x00, 0x4C, 0x5B,
                                        0x4B, 0x0F, 0x9A, 0x3D, 0x1C, 0x2E,
                                        0x3F, 0x40, 0x51, 0x62};
    uint8_t be[16];
    memcpy(be, base_be, sizeof be);
    be[2] = (uint8_t)(uuid16 >> 8);
    be[3] = (uint8_t)(uuid16 & 0xFFu);
    for (int i = 0; i < 16; i++) {
        out[i] = be[15 - i];
    }
}

bool app_ble_access_allowed(app_ble_char_t ch, const app_ble_link_t *link) {
    const app_ble_char_def_t *def = app_ble_char_def(ch);
    if (def == NULL || link == NULL) {
        return false;
    }
    switch (def->sec) {
    case APP_BLE_SEC_OPEN:
        return true;
    case APP_BLE_SEC_ENCRYPTED:
        return link->encrypted;
    case APP_BLE_SEC_AUTHENTICATED:
        /* Authentication without encryption is not a state the stack can
         * produce, but requiring both makes that impossible to assume. */
        return link->encrypted && link->authenticated;
    default:
        return false;
    }
}

int app_ble_core_init(const app_ble_ops_t *ops) {
    if (ops == NULL) {
        return APP_BLE_ERR_INVALID;
    }
    g_ble_ops = ops;
    s_mtu = APP_BLE_MTU_DEFAULT;
    s_bonds = 0;
    s_passkey_active = false;
    s_passkey = 0;
    app_ble_ctrl_reset();
    app_ble_adv_reset();
    app_ble_history_reset();
    return APP_BLE_OK;
}

/* ── MTU and chunking (F10.3) ─────────────────────────────────────── */

void app_ble_set_mtu(uint16_t mtu) {
    /* Never trust a peer below the spec floor; never exceed what we asked
     * for. Both directions have been seen from real stacks. */
    if (mtu < APP_BLE_MTU_DEFAULT) {
        mtu = APP_BLE_MTU_DEFAULT;
    }
    if (mtu > APP_BLE_MTU_PREFERRED) {
        mtu = APP_BLE_MTU_PREFERRED;
    }
    s_mtu = mtu;
}

uint16_t app_ble_mtu(void) { return s_mtu; }

size_t app_ble_notify_chunk(void) {
    return (size_t)s_mtu - APP_BLE_ATT_NOTIFY_OVERHEAD;
}

int app_ble_notify_chunked(app_ble_char_t ch, const uint8_t *buf, size_t len) {
    if (g_ble_ops == NULL || g_ble_ops->notify == NULL) {
        return APP_BLE_ERR_FAILED;
    }
    const size_t chunk = app_ble_notify_chunk();
    /* ATT cannot fragment a notification, so we do it: consecutive
     * notifications split at MTU-3, concatenated by the client until the
     * length implied by the fixed prefix is satisfied. Every variable
     * payload's fixed prefix is ≤ 10 B, so it always arrives whole in the
     * first chunk — even at the 20-byte default (ble-gatt §4). */
    if (len == 0) {
        return APP_BLE_OK;
    }
    size_t off = 0;
    while (off < len) {
        size_t n = len - off;
        if (n > chunk) {
            n = chunk;
        }
        const int err = g_ble_ops->notify(ch, buf + off, n);
        if (err != 0) {
            return err;
        }
        off += n;
    }
    return APP_BLE_OK;
}

/* ── Builders (F10.1) ─────────────────────────────────────────────── */

int app_ble_build_device_info(uint8_t *out, size_t cap) {
    if (g_ble_ops == NULL || cap < BRIDGE_DEVICE_INFO_SIZE) {
        return -1;
    }
    app_ble_sysinfo_t sys;
    memset(&sys, 0, sizeof sys);
    g_ble_ops->sysinfo(&sys);

    bridge_device_info_t d;
    memset(&d, 0, sizeof d);
    d.ver = 1;
    d.api = 1;
    d.probes = sys.probes;
    d.caps = sys.caps;
    /* F12.5 — caps b5 `battery` is DERIVED, never a literal: it says
     * whether a real soc_pct can ever arrive (ble-gatt §5.1.1), which is
     * exactly what lets the app tell "no battery data" from "a flat
     * battery". Deriving it here rather than in the glue keeps it from
     * drifting away from the value it describes. */
    if (app_power_svc_available()) {
        d.caps |= (1u << 5);
    } else {
        d.caps &= (uint8_t)~(1u << 5);
    }
    memcpy(d.id, sys.id, sizeof d.id < sizeof sys.id ? sizeof d.id : 4);
    if (sys.model != NULL) {
        strncpy(d.model, sys.model, sizeof d.model);
    }
    if (sys.fw != NULL) {
        strncpy(d.fw, sys.fw, sizeof d.fw);
    }
    bridge_device_info_encode(&d, out);
    return (int)BRIDGE_DEVICE_INFO_SIZE;
}

int app_ble_build_net_status(uint8_t *out, size_t cap) {
    if (g_ble_ops == NULL) {
        return -1;
    }
    app_ble_net_snapshot_t n;
    memset(&n, 0, sizeof n);
    g_ble_ops->net_status(&n);

    bridge_net_status_t s;
    memset(&s, 0, sizeof s);
    s.ver = 1;
    s.mode = n.mode;
    s.state = n.state;
    s.wifi_rssi = n.rssi;
    memcpy(s.ip, n.ip, 4);
    size_t ssid_len = strnlen(n.ssid, sizeof n.ssid - 1);
    if (ssid_len > sizeof s.ssid) {
        ssid_len = sizeof s.ssid;
    }
    s.ssid_len = (uint8_t)ssid_len;
    memcpy(s.ssid, n.ssid, ssid_len);
    size_t host_len = strnlen(n.host, sizeof n.host - 1);
    if (host_len > sizeof s.host) {
        host_len = sizeof s.host;
    }
    s.host_len = (uint8_t)host_len;
    memcpy(s.host, n.host, host_len);
    return bridge_net_status_pack(&s, out, cap);
}

/* The live snapshot both live_state and the advertising blob are built
 * from, so the two can never disagree about what the pit is doing. */
void app_ble_live_snapshot(app_ble_live_t *out) {
    memset(out, 0, sizeof *out);
    out->paired = smoke_x_ctrl_state() == SMOKE_X_CONFIRMED;
    out->session_active = cook_session_is_open();
    out->clock_valid = app_time_core_source() != APP_TIME_NONE;
    /* No battery truth until F12 (M5): the degenerate value is decided
     * once, in the contract (ble-gatt §5.1.1), and emitted from here. */
    /* F12.5 — a real reading when app_power has one, and the P3.2
     * sentinel when it does not. 255 rather than 0 because a device with
     * no battery sensor rendering as one about to die is worse than
     * rendering as "unknown" (ble-gatt §5.1.1). */
    out->soc_pct = app_power_svc_soc();

    for (int i = 0; i < 4; i++) {
        out->temp[i] = BRIDGE_TEMP_DETACHED;
    }
    const cook_ring_sample_t *newest = cook_ring_get(0);
    if (newest != NULL) {
        for (int i = 0; i < 4; i++) {
            out->temp[i] = newest->temp[i];
        }
        out->billows =
            (newest->flags & BRIDGE_SAMPLE_REC_FLAGS_BILLOWS) != 0;
        out->rssi_lora = newest->rssi;
        if (out->session_active) {
            out->session_t = newest->t;
        }
    }
    /* F13 (M5) owns alarm state, and here it is: true only while an alarm
     * is raised and NOT acknowledged. Acknowledging silences — it does not
     * resolve — so an acked alarm leaves this false while still appearing
     * in /status (09 §9.2). */
    out->alarm_active = app_alarm_svc_unacked();
}

int app_ble_build_live_state(uint8_t *out, size_t cap) {
    if (cap < BRIDGE_LIVE_STATE_SIZE) {
        return -1;
    }
    app_ble_live_t live;
    app_ble_live_snapshot(&live);

    bridge_live_state_t s;
    memset(&s, 0, sizeof s);
    s.ver = 1;
    if (live.paired) {
        s.flags |= BRIDGE_LIVE_STATE_FLAGS_PAIRED;
    }
    if (live.session_active) {
        s.flags |= BRIDGE_LIVE_STATE_FLAGS_SESSION_ACTIVE;
    }
    if (live.billows) {
        s.flags |= BRIDGE_LIVE_STATE_FLAGS_BILLOWS;
    }
    if (live.alarm_active) {
        s.flags |= BRIDGE_LIVE_STATE_FLAGS_ALARM_ACTIVE;
    }
    if (live.clock_valid) {
        s.flags |= BRIDGE_LIVE_STATE_FLAGS_CLOCK_VALID;
    }
    for (int i = 0; i < 4; i++) {
        s.temp[i] = live.temp[i]; /* sentinels survive to the wire */
    }
    s.soc_pct = live.soc_pct;
    s.rssi_lora = live.rssi_lora;
    s.session_t = live.session_t;
    bridge_live_state_encode(&s, out);
    return (int)BRIDGE_LIVE_STATE_SIZE;
}

/* Pit probe, 1-minute buckets, newest last. The ring holds 240 samples at
 * ~30 s, i.e. 2 h — so two ring entries per bucket, and the bucket takes
 * the newer valid one. No flash is touched (ble-gatt §5.8). */
#define PREVIEW_BUCKET_MIN 1
#define PREVIEW_MAX_VALUES 120

int app_ble_build_history_preview(uint8_t *out, size_t cap) {
    bridge_history_preview_t h;
    memset(&h, 0, sizeof h);
    h.ver = 1;
    h.probe_index = 0;
    h.bucket_min = PREVIEW_BUCKET_MIN;

    const int available = cook_ring_count();
    int buckets = available / 2;
    if (buckets > PREVIEW_MAX_VALUES) {
        buckets = PREVIEW_MAX_VALUES;
    }
    /* An odd sample left over is still a minute worth showing. */
    if (buckets < PREVIEW_MAX_VALUES && (available % 2) != 0) {
        buckets++;
    }
    h.count = (uint8_t)buckets;
    for (int b = 0; b < buckets; b++) {
        /* Oldest first: bucket 0 is the furthest back we are reporting. */
        const int idx = (buckets - 1 - b) * 2;
        const cook_ring_sample_t *s = cook_ring_get(idx);
        if (s == NULL) {
            s = cook_ring_get(idx > 0 ? idx - 1 : 0);
        }
        h.values[b] = s != NULL ? s->temp[0] : BRIDGE_TEMP_DETACHED;
    }
    return bridge_history_preview_pack(&h, out, cap);
}

int app_ble_core_read(app_ble_char_t ch, uint8_t *out, size_t cap) {
    const app_ble_char_def_t *def = app_ble_char_def(ch);
    if (def == NULL || (def->props & APP_BLE_PROP_READ) == 0) {
        return -1;
    }
    switch (ch) {
    case APP_BLE_CH_DEVICE_INFO:
        return app_ble_build_device_info(out, cap);
    case APP_BLE_CH_NET_STATUS:
        return app_ble_build_net_status(out, cap);
    case APP_BLE_CH_LIVE_STATE:
        return app_ble_build_live_state(out, cap);
    case APP_BLE_CH_HISTORY_PREVIEW:
        return app_ble_build_history_preview(out, cap);
    default:
        return -1;
    }
}

/* ── Push paths (F10.6, F10.9) ────────────────────────────────────── */

int app_ble_notify_net_status(void) {
    uint8_t buf[BRIDGE_NET_STATUS_MAX_SIZE];
    const int len = app_ble_build_net_status(buf, sizeof buf);
    if (len < 0) {
        return APP_BLE_ERR_FAILED;
    }
    return app_ble_notify_chunked(APP_BLE_CH_NET_STATUS, buf, (size_t)len);
}

int app_ble_notify_live_state(void) {
    uint8_t buf[BRIDGE_LIVE_STATE_SIZE];
    const int len = app_ble_build_live_state(buf, sizeof buf);
    if (len < 0) {
        return APP_BLE_ERR_FAILED;
    }
    /* 16 B always fits one PDU; chunking it is a no-op that keeps one
     * path for every notification. */
    return app_ble_notify_chunked(APP_BLE_CH_LIVE_STATE, buf, (size_t)len);
}

/* ── Bonds and passkey (F10.5) ────────────────────────────────────── */

void app_ble_set_bond_count(uint8_t bonds) { s_bonds = bonds; }
uint8_t app_ble_bond_count(void) { return s_bonds; }
bool app_ble_bond_slot_available(void) { return s_bonds < APP_BLE_MAX_BONDS; }

void app_ble_passkey_set(uint32_t passkey) {
    s_passkey = passkey % 1000000u;
    s_passkey_active = true;
}

void app_ble_passkey_clear(void) {
    s_passkey_active = false;
    s_passkey = 0;
}

bool app_ble_passkey_active(void) { return s_passkey_active; }
uint32_t app_ble_passkey(void) { return s_passkey; }
