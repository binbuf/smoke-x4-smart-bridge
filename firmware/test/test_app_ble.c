/* test_app_ble.c — the Bridge Control Service on the host (F10.1–F10.3,
 * F10.6–F10.9).
 *
 * The whole GATT contract, proven without NimBLE and without a phone:
 * every builder byte-matches the P3.2 fixtures for seeded state, both
 * advertising PDUs byte-match the §2 tables, the chunker is table-tested
 * at MTU 23 and 247, the security layer refuses before the handler runs,
 * and every device_control op reaches its component double and comes back
 * as an exact `result` frame.
 *
 * The bench is still the only test that counts (R7) — but everything the
 * bench could tell us about the CONTRACT is already known here, so the
 * sitting is spent on OEM behaviour instead of on byte layouts.
 */
#include "app_alarm_svc.h"
#include "app_power_svc.h"
#include "app_ble_internal.h"
#include "app_config_store.h"
#include "app_ui_core.h"
#include "app_time_core.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"
#include "test_cook_doubles.h"
#include "test_util.h"

#include <stdint.h>

/* ── the seam ─────────────────────────────────────────────────────── */

#define NOTIFY_MAX 64

typedef struct {
    app_ble_char_t ch;
    uint8_t buf[256];
    size_t len;
} notif_t;

static notif_t g_notifs[NOTIFY_MAX];
static int g_notif_count;
static app_ble_net_snapshot_t g_net;
static app_net_pending_cfg_t g_applied;
static int g_apply_calls;
static int g_scan_starts;
static int g_scan_cancels;
static int g_scan_start_rc;
static int g_identify_calls;
static int g_reboot_calls;
static int g_factory_calls;
static uint64_t g_uptime_ms;
/* Set to fire a cancel from inside notify(), to prove a scan stream can
 * be interrupted mid-flight rather than only before it starts. */
static int g_cancel_after_notif;

static void fake_sysinfo(app_ble_sysinfo_t *out) {
    memset(out, 0, sizeof *out);
    memcpy(out->id, "A4F2", 4);
    out->model = "heltec-v3";
    out->fw = "1.0.0";
    out->probes = 4;
    /* wifi_ap | wifi_sta | history_preview — battery (b5) stays clear
     * until F12, which is what makes soc_pct SOC_UNKNOWN (§5.1.1). */
    out->caps = (1u << 0) | (1u << 1) | (1u << 3);
    const uint8_t mac[6] = {0x24, 0x6F, 0x28, 0x11, 0xA4, 0xF2};
    memcpy(out->mac, mac, 6);
}

static void fake_net_status(app_ble_net_snapshot_t *out) { *out = g_net; }

static int fake_apply(const app_net_pending_cfg_t *cfg) {
    g_applied = *cfg;
    g_apply_calls++;
    return 0;
}

static void cancel_scan_now(void);

static int fake_notify(app_ble_char_t ch, const uint8_t *buf, size_t len) {
    if (g_notif_count < NOTIFY_MAX) {
        g_notifs[g_notif_count].ch = ch;
        g_notifs[g_notif_count].len = len;
        memcpy(g_notifs[g_notif_count].buf, buf,
               len < sizeof g_notifs[0].buf ? len : sizeof g_notifs[0].buf);
        g_notif_count++;
    }
    if (g_cancel_after_notif > 0 && g_notif_count == g_cancel_after_notif) {
        cancel_scan_now();
    }
    return 0;
}

static int fake_scan_start(void) {
    g_scan_starts++;
    return g_scan_start_rc;
}

static int fake_scan_cancel(void) {
    g_scan_cancels++;
    return 0;
}

static int fake_identify(void) {
    g_identify_calls++;
    return APP_BLE_OK;
}

static void fake_reboot(void) { g_reboot_calls++; }

static int fake_factory_reset(void) {
    g_factory_calls++;
    return APP_BLE_OK;
}

static uint64_t fake_uptime(void) { return g_uptime_ms; }

static const app_ble_ops_t k_ops = {
    .sysinfo = fake_sysinfo,
    .net_status = fake_net_status,
    .net_request_config = fake_apply,
    .scan_start = fake_scan_start,
    .scan_cancel = fake_scan_cancel,
    .notify = fake_notify,
    .identify = fake_identify,
    .reboot = fake_reboot,
    .factory_reset = fake_factory_reset,
    .uptime_ms = fake_uptime,
};

static const app_ble_link_t k_open = {.encrypted = false,
                                      .authenticated = false};
static const app_ble_link_t k_encrypted = {.encrypted = true,
                                           .authenticated = false};
static const app_ble_link_t k_authed = {.encrypted = true,
                                        .authenticated = true};

/* The radio double: pair/unpair drive the real smoke_x_ctrl, exactly as
 * the REST group does, so "reaches its component" is a real claim. */
static int rop_set_freq(void *c, uint32_t hz) {
    (void)c;
    (void)hz;
    return 0;
}
static int rop_tx(void *c, const char *p) {
    (void)c;
    (void)p;
    return 0;
}
static void rop_scan(void *c) { (void)c; }
static void rop_pub(void *c, smoke_x_evt_t e, const void *p) {
    (void)c;
    (void)e;
    (void)p;
}
static const smoke_x_ops_t k_radio_ops = {.set_frequency = rop_set_freq,
                                          .transmit = rop_tx,
                                          .start_scan = rop_scan,
                                          .publish = rop_pub};

/* On the device, session start/stop are enqueued onto the cook_store task
 * (the BLE host task must never touch flash-owning state directly). These
 * hooks stand in for that queue, so "reaches F5.4's lifecycle" is a real
 * claim rather than a call into a default that always refuses. */
static int hook_start(void) {
    if (cook_session_is_open()) {
        return COOK_STORE_ERR_STATE;
    }
    const cook_session_params_t params = {
        .num_probes = 4,
        .started_uptime_s = 0,
        .name = "Brisket",
        .device_id = "|abCDe",
    };
    return cook_session_open(&params);
}

static int hook_stop(void) {
    return cook_session_is_open() ? cook_session_close(0)
                                  : COOK_STORE_ERR_STATE;
}

static void reset_all(void) {
    g_notif_count = 0;
    g_apply_calls = 0;
    g_scan_starts = 0;
    g_scan_cancels = 0;
    g_scan_start_rc = APP_BLE_OK;
    g_identify_calls = 0;
    g_reboot_calls = 0;
    g_factory_calls = 0;
    g_cancel_after_notif = 0;
    g_uptime_ms = 1000;
    memset(&g_applied, 0, sizeof g_applied);
    memset(&g_net, 0, sizeof g_net);

    memfs_reset();
    cfg_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);
    cook_store_set_request_hooks(hook_start, hook_stop);
    CHECK_EQ_INT(smoke_x_ctrl_init(&k_radio_ops, NULL, false, 0), 0);
    cook_ring_reset();
    CHECK_EQ_INT(app_time_core_init(0, NULL, NULL), 0);
    CHECK_EQ_INT(app_alarm_svc_init(NULL), 0);
    CHECK_EQ_INT(app_power_svc_init(), 0);
    CHECK_EQ_INT(app_ble_core_init(&k_ops), APP_BLE_OK);
    app_ble_set_mtu(APP_BLE_MTU_PREFERRED);
}

static void cancel_scan_now(void) {
    const uint8_t cancel[2] = {1, BRIDGE_SCAN_CMD_CANCEL};
    (void)app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, cancel,
                             sizeof cancel);
}

static const notif_t *last_of(app_ble_char_t ch) {
    for (int i = g_notif_count - 1; i >= 0; i--) {
        if (g_notifs[i].ch == ch) {
            return &g_notifs[i];
        }
    }
    return NULL;
}

static int count_of(app_ble_char_t ch) {
    int n = 0;
    for (int i = 0; i < g_notif_count; i++) {
        if (g_notifs[i].ch == ch) {
            n++;
        }
    }
    return n;
}

/* Decodes the last `result` frame. Returns false if there wasn't one. */
static bool last_result(bridge_result_t *out) {
    const notif_t *n = last_of(APP_BLE_CH_RESULT);
    if (n == NULL) {
        return false;
    }
    memset(out, 0, sizeof *out);
    return bridge_result_unpack(n->buf, n->len, out) > 0;
}

/* ── fixtures (P3.2's shared vectors) ─────────────────────────────── */

static size_t load_fixture(const char *name, uint8_t *out, size_t cap) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s.hex", FIXTURES_DIR, name);
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return 0;
    }
    size_t n = 0;
    char line[512];
    while (fgets(line, sizeof line, f) != NULL) {
        if (line[0] == '#') {
            continue;
        }
        for (char *p = line; *p != '\0';) {
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
                p++;
            }
            if (*p == '\0') {
                break;
            }
            unsigned v;
            if (sscanf(p, "%2x", &v) != 1 || n >= cap) {
                fclose(f);
                return 0;
            }
            out[n++] = (uint8_t)v;
            while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\r' &&
                   *p != '\n') {
                p++;
            }
        }
    }
    fclose(f);
    return n;
}

/* ── F10.1: the registry and the security table ───────────────────── */

static void test_registry_matches_the_contract(void) {
    /* ble-gatt §1, transcribed once so a drift here is a red test. */
    struct {
        app_ble_char_t ch;
        uint16_t uuid;
        uint8_t props;
        uint8_t sec;
    } want[] = {
        {APP_BLE_CH_DEVICE_INFO, 0x0001, APP_BLE_PROP_READ, APP_BLE_SEC_OPEN},
        {APP_BLE_CH_NET_STATUS, 0x0002,
         APP_BLE_PROP_READ | APP_BLE_PROP_NOTIFY, APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_WIFI_SCAN_CTRL, 0x0003, APP_BLE_PROP_WRITE,
         APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_WIFI_SCAN_RESULT, 0x0004, APP_BLE_PROP_NOTIFY,
         APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_WIFI_CONFIG, 0x0005, APP_BLE_PROP_WRITE,
         APP_BLE_SEC_AUTHENTICATED},
        {APP_BLE_CH_DEVICE_CONTROL, 0x0006, APP_BLE_PROP_WRITE,
         APP_BLE_SEC_AUTHENTICATED},
        {APP_BLE_CH_LIVE_STATE, 0x0007,
         APP_BLE_PROP_READ | APP_BLE_PROP_NOTIFY, APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_HISTORY_PREVIEW, 0x0008, APP_BLE_PROP_READ,
         APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_RESULT, 0x0009, APP_BLE_PROP_NOTIFY,
         APP_BLE_SEC_ENCRYPTED},
    };
    CHECK_EQ_INT(sizeof want / sizeof want[0], APP_BLE_CH_COUNT);
    for (size_t i = 0; i < sizeof want / sizeof want[0]; i++) {
        const app_ble_char_def_t *d = app_ble_char_def(want[i].ch);
        CHECK(d != NULL);
        if (d == NULL) {
            continue;
        }
        CHECK_EQ_INT(d->uuid16, want[i].uuid);
        CHECK_EQ_INT(d->props, want[i].props);
        CHECK_EQ_INT(d->sec, want[i].sec);
    }
    CHECK(app_ble_char_def(APP_BLE_CH_COUNT) == NULL);
    CHECK(app_ble_char_def((app_ble_char_t)-1) == NULL);
}

static void test_uuid_is_little_endian_on_air(void) {
    uint8_t u[16];
    app_ble_uuid128(0x0000, u);
    /* 7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162 reversed. */
    static const uint8_t want[16] = {0x62, 0x51, 0x40, 0x3F, 0x2E, 0x1C,
                                     0x3D, 0x9A, 0x0F, 0x4B, 0x5B, 0x4C,
                                     0x00, 0x00, 0x9A, 0x7F};
    CHECK(memcmp(u, want, 16) == 0);

    /* The XXXX slot is bytes 2..3 big-endian, so bytes 13..12 on air. */
    app_ble_uuid128(0x0007, u);
    CHECK_EQ_INT(u[13], 0x00);
    CHECK_EQ_INT(u[12], 0x07);
    /* Only those two bytes move; the rest of the base is untouched. */
    CHECK(memcmp(u, want, 12) == 0);
    CHECK(memcmp(u + 14, want + 14, 2) == 0);
}

static void test_security_table(void) {
    /* device_info is readable with no pairing at all, so the app can
     * identify a bridge before bonding (§3). */
    CHECK(app_ble_access_allowed(APP_BLE_CH_DEVICE_INFO, &k_open));
    CHECK(app_ble_access_allowed(APP_BLE_CH_DEVICE_INFO, &k_encrypted));

    CHECK(!app_ble_access_allowed(APP_BLE_CH_NET_STATUS, &k_open));
    CHECK(app_ble_access_allowed(APP_BLE_CH_NET_STATUS, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_LIVE_STATE, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_HISTORY_PREVIEW, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_RESULT, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_WIFI_SCAN_RESULT, &k_encrypted));

    /* The two that can change network config or wipe the device need an
     * MITM-protected key — an encrypted-but-unauthenticated link is not
     * enough, and that is the whole reason the OLED shows a passkey. */
    CHECK(!app_ble_access_allowed(APP_BLE_CH_WIFI_CONFIG, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_WIFI_CONFIG, &k_authed));
    CHECK(!app_ble_access_allowed(APP_BLE_CH_DEVICE_CONTROL, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_DEVICE_CONTROL, &k_authed));

    CHECK(!app_ble_access_allowed(APP_BLE_CH_WIFI_CONFIG, NULL));
}

/* ── F10.1: builders against the P3.2 fixtures ────────────────────── */

static void test_device_info_matches_fixture(void) {
    reset_all();
    uint8_t out[BRIDGE_DEVICE_INFO_SIZE];
    CHECK_EQ_INT(app_ble_build_device_info(out, sizeof out),
                 BRIDGE_DEVICE_INFO_SIZE);
    uint8_t want[64];
    const size_t n = load_fixture("ble-device-info", want, sizeof want);
    CHECK_EQ_INT(n, BRIDGE_DEVICE_INFO_SIZE);
    CHECK(memcmp(out, want, BRIDGE_DEVICE_INFO_SIZE) == 0);

    /* Too small a buffer refuses rather than overruns. */
    CHECK_EQ_INT(app_ble_build_device_info(out, 8), -1);
}

static void test_net_status_matches_fixture(void) {
    reset_all();
    g_net.mode = BRIDGE_NET_MODE_STA;
    g_net.state = BRIDGE_NET_STATE_UP;
    g_net.rssi = -54;
    g_net.ip[0] = 192;
    g_net.ip[1] = 168;
    g_net.ip[2] = 1;
    g_net.ip[3] = 42;
    snprintf(g_net.ssid, sizeof g_net.ssid, "Backyard");
    snprintf(g_net.host, sizeof g_net.host, "smokebridge");

    uint8_t out[BRIDGE_NET_STATUS_MAX_SIZE];
    const int len = app_ble_build_net_status(out, sizeof out);
    uint8_t want[64];
    const size_t n = load_fixture("ble-net-status-sta-up", want, sizeof want);
    CHECK_EQ_INT(len, (int)n);
    CHECK(memcmp(out, want, n) == 0);
}

static void seed_ring(int16_t pit, int count) {
    for (int i = 0; i < count; i++) {
        cook_ring_sample_t s = {0};
        s.t = (uint32_t)(i * 30);
        s.temp[0] = (int16_t)(pit + i);
        s.temp[1] = 1632;
        s.temp[2] = BRIDGE_TEMP_DETACHED;
        s.temp[3] = BRIDGE_TEMP_INVALID;
        s.rssi = -71;
        cook_ring_push(&s);
    }
}

static void test_live_state_sentinels_survive(void) {
    reset_all();
    seed_ring(2431, 1);
    uint8_t out[BRIDGE_LIVE_STATE_SIZE];
    CHECK_EQ_INT(app_ble_build_live_state(out, sizeof out),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_t s;
    bridge_live_state_decode(out, &s);
    CHECK_EQ_INT(s.ver, 1);
    CHECK_EQ_INT(s.temp[0], 2431);
    /* NEVER 0 — the invariant F9.3 grep-proofed for JSON, on the wire. */
    CHECK_EQ_INT(s.temp[2], BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT(s.temp[3], BRIDGE_TEMP_INVALID);
    CHECK_EQ_INT(s.rssi_lora, -71);
    /* No app_power until M5's F12, decided once in P3.2. */
    CHECK_EQ_INT(s.soc_pct, BRIDGE_SOC_UNKNOWN);

    /* With no packets at all, every probe reads detached, not 0. */
    reset_all();
    CHECK_EQ_INT(app_ble_build_live_state(out, sizeof out),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_decode(out, &s);
    for (int i = 0; i < 4; i++) {
        CHECK_EQ_INT(s.temp[i], BRIDGE_TEMP_DETACHED);
    }
}

static void test_history_preview(void) {
    reset_all();
    /* A full 2 h ring: 240 samples at ~30 s → 120 one-minute buckets. */
    seed_ring(2000, 240);
    uint8_t out[BRIDGE_HISTORY_PREVIEW_MAX_SIZE];
    int len = app_ble_build_history_preview(out, sizeof out);
    bridge_history_preview_t h;
    CHECK(bridge_history_preview_unpack(out, (size_t)len, &h) == len);
    CHECK_EQ_INT(h.count, 120);
    CHECK_EQ_INT(h.bucket_min, 1);
    CHECK_EQ_INT(h.probe_index, 0);
    CHECK_EQ_INT(len, 4 + 2 * 120);
    CHECK(len <= (int)BRIDGE_HISTORY_PREVIEW_MAX_SIZE);
    /* Oldest first, newest last (ble-gatt §5.8). */
    CHECK(h.values[0] < h.values[119]);

    /* A ring shorter than 2 h yields count < 120 rather than padding. */
    reset_all();
    seed_ring(2000, 21);
    len = app_ble_build_history_preview(out, sizeof out);
    CHECK(bridge_history_preview_unpack(out, (size_t)len, &h) == len);
    CHECK_EQ_INT(h.count, 11);
    CHECK(h.count < 120);

    /* An empty ring is count 0, not a crash and not 120 zeroes. */
    reset_all();
    len = app_ble_build_history_preview(out, sizeof out);
    CHECK(bridge_history_preview_unpack(out, (size_t)len, &h) == len);
    CHECK_EQ_INT(h.count, 0);
    CHECK_EQ_INT(len, 4);
}

/* ── F10.2: advertising ───────────────────────────────────────────── */

static void test_advertising_pdus(void) {
    reset_all();
    uint8_t adv[APP_BLE_ADV_MAX];
    const int adv_len = app_ble_build_adv(adv, sizeof adv);
    /* §2.1: 21 of 31 bytes. */
    CHECK_EQ_INT(adv_len, 21);
    CHECK_EQ_INT(adv[0], 2);
    CHECK_EQ_INT(adv[1], 0x01); /* Flags */
    CHECK_EQ_INT(adv[2], 0x06); /* LE General Discoverable, no BR/EDR */
    CHECK_EQ_INT(adv[3], 17);
    CHECK_EQ_INT(adv[4], 0x07); /* Complete 128-bit UUID list */
    uint8_t uuid[16];
    app_ble_uuid128(APP_BLE_SERVICE_UUID16, uuid);
    CHECK(memcmp(adv + 5, uuid, 16) == 0);
    CHECK(adv_len <= APP_BLE_ADV_MAX);

    uint8_t rsp[APP_BLE_ADV_MAX];
    const int rsp_len = app_ble_build_scan_rsp(rsp, sizeof rsp);
    /* §2.2: 29 of 31 bytes. */
    CHECK_EQ_INT(rsp_len, 29);
    CHECK_EQ_INT(rsp[0], 17);
    CHECK_EQ_INT(rsp[1], 0x09); /* Complete Local Name */
    CHECK(memcmp(rsp + 2, "SmokeBridge-A4F2", 16) == 0);
    CHECK_EQ_INT(rsp[18], 10);
    CHECK_EQ_INT(rsp[19], 0xFF); /* Manufacturer Specific Data */
    CHECK_EQ_INT(bridge_get_u16(rsp + 20), APP_BLE_COMPANY_ID);
    CHECK(rsp_len <= APP_BLE_ADV_MAX);

    /* The BLE name is the AP SSID: one helper, so they cannot disagree. */
    const uint8_t mac[6] = {0x24, 0x6F, 0x28, 0x11, 0xA4, 0xF2};
    char ble_name[APP_BLE_NAME_MAX];
    char ap_ssid[APP_NET_SSID_MAX];
    app_ble_local_name(mac, ble_name);
    app_net_ap_ssid(mac, ap_ssid);
    CHECK(strcmp(ble_name, ap_ssid) == 0);
}

static void test_status_blob_matrix(void) {
    /* Unpaired, no session: the state a fresh bridge advertises. */
    reset_all();
    uint8_t blob[APP_BLE_STATUS_BLOB_LEN];
    CHECK_EQ_INT(app_ble_build_status_blob(blob), APP_BLE_STATUS_BLOB_LEN);
    CHECK_EQ_INT(blob[0], 1);
    CHECK_EQ_INT(blob[1] & BRIDGE_LIVE_STATE_FLAGS_PAIRED, 0);
    /* A detached pit advertises the sentinel, so the scan list can render
     * "—" rather than a confident, wrong "0 °F". */
    CHECK_EQ_INT((int16_t)bridge_get_u16(blob + 2), BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT(blob[4], BRIDGE_SOC_UNKNOWN);
    CHECK_EQ_INT(bridge_get_u16(blob + 5), 0);

    /* Mid-session: "pit 243 °F · 4 h 12 m" is what the scan list draws. */
    reset_all();
    cook_ring_sample_t s = {0};
    s.t = 15120; /* 4 h 12 m */
    s.temp[0] = 2431;
    s.rssi = -71;
    cook_ring_push(&s);
    CHECK_EQ_INT(app_ble_build_status_blob(blob), APP_BLE_STATUS_BLOB_LEN);
    CHECK_EQ_INT((int16_t)bridge_get_u16(blob + 2), 2431);
    /* session_minutes is 0 while no session is open, whatever the ring
     * says — the blob must not claim a cook that is not running. */
    CHECK_EQ_INT(bridge_get_u16(blob + 5), 0);

    /* The blob and live_state agree on flags and pit temp, always. */
    uint8_t live[BRIDGE_LIVE_STATE_SIZE];
    app_ble_build_live_state(live, sizeof live);
    bridge_live_state_t ls;
    bridge_live_state_decode(live, &ls);
    CHECK_EQ_INT(blob[1], ls.flags);
    CHECK_EQ_INT((int16_t)bridge_get_u16(blob + 2), ls.temp[0]);
    CHECK_EQ_INT(blob[4], ls.soc_pct);
}

static void test_adv_interval_policy(void) {
    reset_all();
    /* Idle by default. */
    CHECK_EQ_INT(app_ble_adv_interval_ms(0), APP_BLE_ADV_IDLE_MS);
    /* Fast for 60 s after boot or a button press, then idle again. */
    app_ble_adv_note_fast(10000);
    CHECK_EQ_INT(app_ble_adv_interval_ms(10000), APP_BLE_ADV_FAST_MS);
    CHECK_EQ_INT(app_ble_adv_interval_ms(69999), APP_BLE_ADV_FAST_MS);
    CHECK_EQ_INT(app_ble_adv_interval_ms(70000), APP_BLE_ADV_IDLE_MS);
    CHECK_EQ_INT(app_ble_adv_interval_ms(999999), APP_BLE_ADV_IDLE_MS);
    /* A second press re-arms the window from that moment. */
    app_ble_adv_note_fast(100000);
    CHECK_EQ_INT(app_ble_adv_interval_ms(150000), APP_BLE_ADV_FAST_MS);
}

/* ── F10.3: MTU and the chunker ───────────────────────────────────── */

static void test_mtu_negotiation_bounds(void) {
    reset_all();
    app_ble_set_mtu(247);
    CHECK_EQ_INT(app_ble_mtu(), 247);
    CHECK_EQ_INT(app_ble_notify_chunk(), 244);
    /* A peer below the spec floor is clamped up, not believed. */
    app_ble_set_mtu(0);
    CHECK_EQ_INT(app_ble_mtu(), APP_BLE_MTU_DEFAULT);
    CHECK_EQ_INT(app_ble_notify_chunk(), 20);
    /* A peer above what we asked for is clamped down. */
    app_ble_set_mtu(517);
    CHECK_EQ_INT(app_ble_mtu(), APP_BLE_MTU_PREFERRED);
}

static void test_chunker_at_both_mtus(void) {
    /* history_preview's 244 B is exactly one PDU at 247 — the reason 247
     * is the number we ask for (§4). */
    reset_all();
    seed_ring(2000, 240);
    app_ble_set_mtu(247);
    uint8_t buf[BRIDGE_HISTORY_PREVIEW_MAX_SIZE];
    const int len = app_ble_build_history_preview(buf, sizeof buf);
    CHECK_EQ_INT(len, 244);
    g_notif_count = 0;
    app_ble_notify_chunked(APP_BLE_CH_HISTORY_PREVIEW, buf, (size_t)len);
    CHECK_EQ_INT(g_notif_count, 1);
    CHECK_EQ_INT(g_notifs[0].len, 244);

    /* At the 23-byte default the same payload splits at 20 and the client
     * concatenates: 244 = 12 x 20 + 4. */
    app_ble_set_mtu(23);
    g_notif_count = 0;
    app_ble_notify_chunked(APP_BLE_CH_HISTORY_PREVIEW, buf, (size_t)len);
    CHECK_EQ_INT(g_notif_count, 13);
    size_t total = 0;
    uint8_t joined[BRIDGE_HISTORY_PREVIEW_MAX_SIZE];
    for (int i = 0; i < g_notif_count; i++) {
        CHECK(g_notifs[i].len <= 20);
        memcpy(joined + total, g_notifs[i].buf, g_notifs[i].len);
        total += g_notifs[i].len;
    }
    CHECK_EQ_INT(total, 244);
    CHECK(memcmp(joined, buf, 244) == 0);

    /* THE fixed-prefix rule: every variable payload's prefix is ≤ 10 B,
     * so the length the client needs always arrives whole in chunk 1 —
     * even at 20 bytes. history_preview's prefix is 4. */
    CHECK(g_notifs[0].len >= 4);
    bridge_history_preview_t h;
    /* The first chunk alone is enough to learn `count`. */
    CHECK_EQ_INT(g_notifs[0].buf[2], 120);
    CHECK(bridge_history_preview_unpack(joined, total, &h) == (int)total);
    CHECK_EQ_INT(h.count, 120);

    /* live_state is untouched at the default MTU — the 16 B design
     * surviving contact with the OEM most likely to break negotiation. */
    g_notif_count = 0;
    app_ble_notify_live_state();
    CHECK_EQ_INT(g_notif_count, 1);
    CHECK_EQ_INT(g_notifs[0].len, BRIDGE_LIVE_STATE_SIZE);
    CHECK(BRIDGE_LIVE_STATE_SIZE <= 20);

    /* A zero-length notification is a no-op, not an empty PDU. */
    g_notif_count = 0;
    app_ble_notify_chunked(APP_BLE_CH_RESULT, buf, 0);
    CHECK_EQ_INT(g_notif_count, 0);
}

static void test_result_frames_chunk_too(void) {
    /* A 64-byte detail is 68 B on the wire: four notifications at MTU 23,
     * one at 247. `result` is variable, so it chunks like the rest. */
    reset_all();
    app_ble_set_mtu(23);
    char detail[65];
    memset(detail, 'x', 64);
    detail[64] = '\0';
    g_notif_count = 0;
    app_ble_answer(BRIDGE_CONTROL_OP_PAIR, BRIDGE_RESULT_STATUS_FAILED,
                   detail);
    CHECK_EQ_INT(count_of(APP_BLE_CH_RESULT), 4);
    /* The 4-byte fixed prefix arrives whole in the first chunk. */
    CHECK(g_notifs[0].len >= 4);
    CHECK_EQ_INT(g_notifs[0].buf[3], 64);

    app_ble_set_mtu(247);
    g_notif_count = 0;
    app_ble_answer(BRIDGE_CONTROL_OP_PAIR, BRIDGE_RESULT_STATUS_FAILED,
                   detail);
    CHECK_EQ_INT(count_of(APP_BLE_CH_RESULT), 1);
    CHECK_EQ_INT(g_notifs[0].len, 68);
}

/* ── F10.6: wifi_config ───────────────────────────────────────────── */

static size_t pack_wifi_config(uint8_t *out, uint8_t mode, const char *ssid,
                               const char *psk) {
    bridge_wifi_config_t c;
    memset(&c, 0, sizeof c);
    c.ver = 1;
    c.mode = mode;
    c.auth = 3;
    if (ssid != NULL) {
        c.ssid_len = (uint8_t)strlen(ssid);
        memcpy(c.ssid, ssid, c.ssid_len);
    }
    if (psk != NULL) {
        c.psk_len = (uint8_t)strlen(psk);
        memcpy(c.psk, psk, c.psk_len);
    }
    return (size_t)bridge_wifi_config_pack(&c, out, BRIDGE_WIFI_CONFIG_MAX_SIZE);
}

static void test_wifi_config_accept_then_apply(void) {
    reset_all();
    uint8_t buf[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    const size_t len =
        pack_wifi_config(buf, BRIDGE_NET_MODE_STA, "Backyard", "hunter2boo");
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, buf,
                                    len),
                 APP_BLE_OK);

    /* THE ordering that makes a wrong password recoverable from a lawn
     * chair: the result frame is pushed BEFORE the apply is requested. */
    CHECK_EQ_INT(g_apply_calls, 1);
    CHECK(g_notif_count >= 1);
    CHECK_EQ_INT(g_notifs[0].ch, APP_BLE_CH_RESULT);

    bridge_result_t r;
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(r.op_echo, 0); /* wifi_config answers with op_echo 0 */
    CHECK_EQ_INT(r.len, 0);     /* no PSK on an STA change */

    /* The wire enum (sta=2) becomes the stored enum (sta=1). */
    CHECK_EQ_INT(g_applied.mode, APP_CONFIG_NET_MODE_STA);
    CHECK(strcmp(g_applied.sta_ssid, "Backyard") == 0);
    CHECK(strcmp(g_applied.sta_psk, "hunter2boo") == 0);

    /* A superseding config wins: F8.4 owns the window, we just hand it
     * the newer one, and the newer one is what the core last passed on. */
    const size_t len2 =
        pack_wifi_config(buf, BRIDGE_NET_MODE_STA, "Garage", "second-pw");
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, buf,
                                    len2),
                 APP_BLE_OK);
    CHECK_EQ_INT(g_apply_calls, 2);
    CHECK(strcmp(g_applied.sta_ssid, "Garage") == 0);
}

static void test_wifi_config_ap_carries_the_psk(void) {
    reset_all();
    /* app_config generates the AP PSK on first init (F7.3). */
    char psk[APP_CONFIG_PSK_LEN + 1] = "";
    CHECK_EQ_INT(app_config_store_get_str(APP_CONFIG_NET_AP_PSK, psk,
                                          sizeof psk),
                 APP_CONFIG_OK);
    CHECK(psk[0] != '\0');

    uint8_t buf[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    const size_t len = pack_wifi_config(buf, BRIDGE_NET_MODE_AP, NULL, NULL);
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, buf,
                                    len),
                 APP_BLE_OK);
    bridge_result_t r;
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_OK);
    /* The phone needs it to join (§5.9, 05 §5.7). */
    CHECK_EQ_INT(r.len, (int)strlen(psk));
    CHECK(memcmp(r.detail, psk, r.len) == 0);
    CHECK_EQ_INT(g_applied.mode, APP_CONFIG_NET_MODE_AP);
}

static void test_no_path_emits_a_stored_sta_psk(void) {
    /* F9.7's discipline, on the GATT surface: store a distinctive STA
     * credential, then exercise every readable/notifiable characteristic
     * and every write answer, and assert those bytes appear nowhere.
     *
     * The static half is a grep over the component sources for the config
     * key itself — the only way to read the stored PSK back. */
    reset_all();
    static const char kSecret[] = "SuperSecretPassword123";
    CHECK_EQ_INT(app_config_store_set_str(APP_CONFIG_NET_STA_PSK, kSecret),
                 APP_CONFIG_OK);
    seed_ring(2431, 40);
    snprintf(g_net.ssid, sizeof g_net.ssid, "Backyard");
    snprintf(g_net.host, sizeof g_net.host, "smokebridge");
    g_net.mode = BRIDGE_NET_MODE_STA;
    g_net.state = BRIDGE_NET_STATE_UP;

    uint8_t out[512];
    for (int ch = 0; ch < APP_BLE_CH_COUNT; ch++) {
        const int len = app_ble_core_read((app_ble_char_t)ch, out, sizeof out);
        if (len <= 0) {
            continue;
        }
        for (int i = 0; i + (int)strlen(kSecret) <= len; i++) {
            CHECK(memcmp(out + i, kSecret, strlen(kSecret)) != 0);
        }
    }

    /* And through every notification the write paths produce. */
    g_notif_count = 0;
    uint8_t cfg[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    size_t len = pack_wifi_config(cfg, BRIDGE_NET_MODE_AP, NULL, NULL);
    app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, cfg, len);
    len = pack_wifi_config(cfg, BRIDGE_NET_MODE_STA, "Other", "another-pw");
    app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, cfg, len);
    app_ble_notify_net_status();
    app_ble_notify_live_state();
    for (int n = 0; n < g_notif_count; n++) {
        for (int i = 0;
             i + (int)strlen(kSecret) <= (int)g_notifs[n].len; i++) {
            CHECK(memcmp(g_notifs[n].buf + i, kSecret, strlen(kSecret)) != 0);
        }
    }
}

static void test_net_status_notifies_once_per_transition(void) {
    reset_all();
    g_net.mode = BRIDGE_NET_MODE_STA;
    g_net.state = BRIDGE_NET_STATE_CONNECTING;
    g_notif_count = 0;
    CHECK_EQ_INT(app_ble_notify_net_status(), APP_BLE_OK);
    CHECK_EQ_INT(count_of(APP_BLE_CH_NET_STATUS), 1);

    /* connecting → up → failed: each transition is exactly one correctly
     * packed notification. A missed one strands the wizard (§5.7). */
    g_net.state = BRIDGE_NET_STATE_UP;
    g_net.ip[0] = 192;
    g_net.ip[3] = 42;
    app_ble_notify_net_status();
    g_net.state = BRIDGE_NET_STATE_FAILED;
    app_ble_notify_net_status();
    CHECK_EQ_INT(count_of(APP_BLE_CH_NET_STATUS), 3);

    const notif_t *last = last_of(APP_BLE_CH_NET_STATUS);
    CHECK(last != NULL);
    bridge_net_status_t s;
    CHECK(bridge_net_status_unpack(last->buf, last->len, &s) == (int)last->len);
    CHECK_EQ_INT(s.state, BRIDGE_NET_STATE_FAILED);
    CHECK_EQ_INT(s.mode, BRIDGE_NET_MODE_STA);
}

/* ── F10.5 / security: refusal happens before the handler ─────────── */

static void test_unauthenticated_write_is_refused(void) {
    reset_all();
    uint8_t buf[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    const size_t len =
        pack_wifi_config(buf, BRIDGE_NET_MODE_STA, "Backyard", "pw");

    /* Encrypted but NOT authenticated: refused at the security layer. */
    CHECK_EQ_INT(
        app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_encrypted, buf, len),
        APP_BLE_OK);
    bridge_result_t r;
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_UNAUTHORIZED);
    /* The handler never ran: no apply was requested. */
    CHECK_EQ_INT(g_apply_calls, 0);

    /* Same for device_control, and for an unencrypted link. */
    reset_all();
    const uint8_t reboot[2] = {1, BRIDGE_CONTROL_OP_REBOOT};
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_encrypted, reboot, 2);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_UNAUTHORIZED);
    CHECK_EQ_INT(g_reboot_calls, 0);

    reset_all();
    const uint8_t scan[2] = {1, BRIDGE_SCAN_CMD_START};
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_open, scan, 2);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_UNAUTHORIZED);
    CHECK_EQ_INT(g_scan_starts, 0);

    /* Writing a read-only characteristic is refused outright. */
    CHECK_EQ_INT(
        app_ble_core_write(APP_BLE_CH_LIVE_STATE, &k_authed, scan, 2),
        APP_BLE_ERR_INVALID);
}

static void test_malformed_writes_answer_invalid(void) {
    reset_all();
    bridge_result_t r;

    /* Short. */
    const uint8_t one[1] = {1};
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_authed, one, 1);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);

    /* Over-length: refused against the declared max, never memcpy'd. */
    uint8_t big[256];
    memset(big, 0xAB, sizeof big);
    big[0] = 1;
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_authed, big, sizeof big);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);

    /* A future version byte is NOT a rejection reason — the additive
     * growth rule at the top of ble-gatt.md. ver=9 with a known op works. */
    reset_all();
    const uint8_t future[3] = {9, BRIDGE_CONTROL_OP_SET_UNITS,
                               BRIDGE_UNITS_CELSIUS};
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_authed, future, 3);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_OK);
    uint8_t units = 99;
    app_config_store_get_u8(APP_CONFIG_DEV_UNITS, &units);
    CHECK_EQ_INT(units, BRIDGE_UNITS_CELSIUS);

    /* An unknown op answers invalid with no side effects. */
    reset_all();
    const uint8_t unknown[2] = {1, 200};
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_authed, unknown, 2);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(r.op_echo, 200);
    CHECK_EQ_INT(g_reboot_calls + g_factory_calls + g_apply_calls, 0);

    /* Malformed wifi_config: invalid, and nothing is applied. */
    reset_all();
    const uint8_t short_cfg[3] = {1, BRIDGE_NET_MODE_STA, 3};
    app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, short_cfg, 3);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(g_apply_calls, 0);

    /* A mode of `off` is not something a phone may ask for. */
    reset_all();
    uint8_t cfg[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    const size_t len = pack_wifi_config(cfg, BRIDGE_NET_MODE_OFF, NULL, NULL);
    app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, cfg, len);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(g_apply_calls, 0);

    /* STA without an SSID is refused rather than silently hosting. */
    reset_all();
    const size_t len2 = pack_wifi_config(cfg, BRIDGE_NET_MODE_STA, NULL, "pw");
    app_ble_core_write(APP_BLE_CH_WIFI_CONFIG, &k_authed, cfg, len2);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(g_apply_calls, 0);
}

/* ── F10.7: the scan flow ─────────────────────────────────────────── */

static void make_scan(app_ble_scan_ap_t *aps, int n) {
    for (int i = 0; i < n; i++) {
        memset(&aps[i], 0, sizeof aps[i]);
        snprintf(aps[i].ssid, sizeof aps[i].ssid, "AP-%02d", i);
        aps[i].rssi = (int8_t)(-40 - i);
        aps[i].auth = 3;
        aps[i].channel = (uint8_t)(1 + (i % 11));
    }
}

static void test_scan_streams_indexed_results(void) {
    reset_all();
    const uint8_t start[2] = {1, BRIDGE_SCAN_CMD_START};
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted,
                                    start, 2),
                 APP_BLE_OK);
    CHECK_EQ_INT(g_scan_starts, 1);
    CHECK(app_ble_scan_active());
    bridge_result_t r;
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_OK);

    app_ble_scan_ap_t aps[12];
    make_scan(aps, 12);
    g_notif_count = 0;
    app_ble_scan_deliver(aps, 12);
    CHECK_EQ_INT(count_of(APP_BLE_CH_WIFI_SCAN_RESULT), 12);
    for (int i = 0; i < 12; i++) {
        bridge_wifi_scan_result_t w;
        CHECK(bridge_wifi_scan_result_unpack(g_notifs[i].buf, g_notifs[i].len,
                                             &w) == (int)g_notifs[i].len);
        CHECK_EQ_INT(w.index, i);
        CHECK_EQ_INT(w.total, 12); /* completion is implicit in index/total */
        CHECK_EQ_INT(w.rssi, -40 - i);
        CHECK_EQ_INT(w.channel, 1 + (i % 11));
        char ssid[33];
        memcpy(ssid, w.ssid, w.ssid_len);
        ssid[w.ssid_len] = '\0';
        char want[16];
        snprintf(want, sizeof want, "AP-%02d", i);
        CHECK(strcmp(ssid, want) == 0);
    }
    /* Delivery ends the scan; a second delivery emits nothing. */
    CHECK(!app_ble_scan_active());
    g_notif_count = 0;
    app_ble_scan_deliver(aps, 12);
    CHECK_EQ_INT(g_notif_count, 0);
}

static void test_scan_busy_does_not_disturb_the_running_scan(void) {
    reset_all();
    const uint8_t start[2] = {1, BRIDGE_SCAN_CMD_START};
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, start, 2);
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, start, 2);

    bridge_result_t r;
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_BUSY);
    CHECK_EQ_INT(r.op_echo, 0);
    /* The running scan is untouched: no second start, no cancel. */
    CHECK_EQ_INT(g_scan_starts, 1);
    CHECK_EQ_INT(g_scan_cancels, 0);
    CHECK(app_ble_scan_active());

    /* And its results still arrive. */
    app_ble_scan_ap_t aps[3];
    make_scan(aps, 3);
    g_notif_count = 0;
    app_ble_scan_deliver(aps, 3);
    CHECK_EQ_INT(count_of(APP_BLE_CH_WIFI_SCAN_RESULT), 3);
}

static void test_scan_cancel_stops_the_stream(void) {
    /* Cancel before results: nothing is emitted at all. */
    reset_all();
    const uint8_t start[2] = {1, BRIDGE_SCAN_CMD_START};
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, start, 2);
    cancel_scan_now();
    CHECK_EQ_INT(g_scan_cancels, 1);
    CHECK(!app_ble_scan_active());
    app_ble_scan_ap_t aps[12];
    make_scan(aps, 12);
    g_notif_count = 0;
    app_ble_scan_deliver(aps, 12);
    CHECK_EQ_INT(count_of(APP_BLE_CH_WIFI_SCAN_RESULT), 0);

    /* Cancel MID-stream: the notifications already sent stand, the rest
     * are not. The fake fires the cancel from inside notify(). */
    reset_all();
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, start, 2);
    g_notif_count = 0;
    g_cancel_after_notif = 5;
    app_ble_scan_deliver(aps, 12);
    CHECK_EQ_INT(count_of(APP_BLE_CH_WIFI_SCAN_RESULT), 5);
    CHECK(!app_ble_scan_active());
}

static void test_scan_edge_cases(void) {
    /* An empty scan (total 0) completes rather than hanging the wizard. */
    reset_all();
    const uint8_t start[2] = {1, BRIDGE_SCAN_CMD_START};
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, start, 2);
    g_notif_count = 0;
    app_ble_scan_deliver(NULL, 0);
    CHECK_EQ_INT(count_of(APP_BLE_CH_WIFI_SCAN_RESULT), 0);
    CHECK(!app_ble_scan_active());

    /* A start that the radio refuses answers failed, and leaves no
     * phantom scan behind for the next start to trip over. */
    reset_all();
    g_scan_start_rc = APP_BLE_ERR_FAILED;
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, start, 2);
    bridge_result_t r;
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_FAILED);
    CHECK(!app_ble_scan_active());

    /* A nonsense cmd is invalid, not a silent start. */
    reset_all();
    const uint8_t bad[2] = {1, 42};
    app_ble_core_write(APP_BLE_CH_WIFI_SCAN_CTRL, &k_encrypted, bad, 2);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(g_scan_starts, 0);

    /* Cancelling when nothing is running is harmless and answers ok. */
    reset_all();
    cancel_scan_now();
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_OK);
}

/* ── F10.8: device_control ────────────────────────────────────────── */

static void write_op(uint8_t op, const uint8_t *body, size_t body_len) {
    uint8_t buf[BRIDGE_DEVICE_CONTROL_MAX_SIZE];
    buf[0] = 1;
    buf[1] = op;
    if (body_len > 0) {
        memcpy(buf + 2, body, body_len);
    }
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_authed, buf,
                       2 + body_len);
}

static uint8_t status_after(uint8_t op, const uint8_t *body, size_t n) {
    g_notif_count = 0;
    write_op(op, body, n);
    bridge_result_t r;
    if (!last_result(&r)) {
        return 0xFF;
    }
    CHECK_EQ_INT(r.op_echo, op); /* every answer echoes its op */
    return r.status;
}

static void test_every_op_reaches_its_component(void) {
    reset_all();

    /* pair / unpair → smoke_x_ctrl. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_PAIR, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_UNPAIR, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);

    /* session_start / stop → F5.4's lifecycle, with the REST group's
     * refusal semantics: starting twice is busy, stopping nothing is
     * invalid. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SESSION_START, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK(cook_session_is_open());
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SESSION_START, NULL, 0),
                 BRIDGE_RESULT_STATUS_BUSY);

    /* mark → F5.9. */
    bridge_ctrl_mark_t m;
    memset(&m, 0, sizeof m);
    m.kind = BRIDGE_MARK_KIND_WRAPPED;
    m.len = 7;
    memcpy(m.text, "wrapped", 7);
    uint8_t mbody[BRIDGE_CTRL_MARK_MAX_SIZE];
    const int mlen = bridge_ctrl_mark_pack(&m, mbody, sizeof mbody);
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_MARK, mbody, (size_t)mlen),
                 BRIDGE_RESULT_STATUS_OK);

    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SESSION_STOP, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK(!cook_session_is_open());
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SESSION_STOP, NULL, 0),
                 BRIDGE_RESULT_STATUS_INVALID);
    /* A mark with no open session is refused, like the REST path. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_MARK, mbody, (size_t)mlen),
                 BRIDGE_RESULT_STATUS_INVALID);

    /* set_units → app_config. */
    uint8_t units = BRIDGE_UNITS_CELSIUS;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_UNITS, &units, 1),
                 BRIDGE_RESULT_STATUS_OK);
    uint8_t stored = 0xFF;
    app_config_store_get_u8(APP_CONFIG_DEV_UNITS, &stored);
    CHECK_EQ_INT(stored, BRIDGE_UNITS_CELSIUS);
    /* An out-of-range unit is invalid, not silently stored. */
    const uint8_t bad_units = 7;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_UNITS, &bad_units, 1),
                 BRIDGE_RESULT_STATUS_INVALID);
    app_config_store_get_u8(APP_CONFIG_DEV_UNITS, &stored);
    CHECK_EQ_INT(stored, BRIDGE_UNITS_CELSIUS);

    /* ack_alarm: F13.8 routes it to the engine. An id nothing matches
     * still answers ok — HTTP, BLE and the PRG button can all ack the
     * same alarm and none of them should fail for being second. */
    const uint8_t alarm_id = 3;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_ACK_ALARM, &alarm_id, 1),
                 BRIDGE_RESULT_STATUS_OK);

    /* identify: partial by design — the display wakes, the LED is M5's. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_IDENTIFY, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(g_identify_calls, 1);
}

static void test_reboot_and_reset_answer_before_they_act(void) {
    reset_all();
    /* Both destroy the link that carries the answer, so the answer must
     * already be on the wire when they run. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_REBOOT, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(g_reboot_calls, 1);
    CHECK_EQ_INT(g_notifs[0].ch, APP_BLE_CH_RESULT);

    reset_all();
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_FACTORY_RESET, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(g_factory_calls, 1);
    CHECK_EQ_INT(g_notifs[0].ch, APP_BLE_CH_RESULT);
}

static void test_set_time_backpatches_an_open_session(void) {
    reset_all();
    /* A session opened with no clock: started_unix_ms is 0 and
     * clock_valid is clear (the exact case F6.2 exists for). */
    app_time_core_init(0, NULL, NULL);
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_NONE);
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SESSION_START, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK(cook_session_is_open());
    CHECK(!cook_session_clock_valid());

    bridge_ctrl_set_time_t t;
    t.unix_ms = 1774051200000ull;
    t.tz_offset_min = -300;
    uint8_t body[BRIDGE_CTRL_SET_TIME_SIZE];
    bridge_ctrl_set_time_encode(&t, body);
    g_uptime_ms = 60000;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_TIME, body, sizeof body),
                 BRIDGE_RESULT_STATUS_OK);

    /* The clock is adopted as `phone`, and the timezone is persisted. */
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_PHONE);
    int32_t tz = 0;
    app_config_store_get_i32(APP_CONFIG_TIME_TZ_OFFSET_MIN, &tz);
    CHECK_EQ_INT(tz, -300);

    /* A zero epoch is refused rather than adopted as 1970. */
    memset(body, 0, sizeof body);
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_TIME, body, sizeof body),
                 BRIDGE_RESULT_STATUS_INVALID);
    /* Short body: invalid, clock untouched. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_TIME, body, 3),
                 BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_PHONE);
}

/* ── F10.5: bond accounting ───────────────────────────────────────── */

static void test_bond_cap(void) {
    reset_all();
    CHECK_EQ_INT(app_ble_bond_count(), 0);
    CHECK(app_ble_bond_slot_available());
    app_ble_set_bond_count(2);
    CHECK(app_ble_bond_slot_available());
    /* Three phones is the cap (§3); the fourth attempt is rejected until
     * a slot is freed. */
    app_ble_set_bond_count(APP_BLE_MAX_BONDS);
    CHECK(!app_ble_bond_slot_available());
    app_ble_set_bond_count(0); /* after forget-all / factory reset */
    CHECK(app_ble_bond_slot_available());
}

static void test_passkey_lifecycle(void) {
    reset_all();
    CHECK(!app_ble_passkey_active());
    app_ble_passkey_set(418302);
    CHECK(app_ble_passkey_active());
    CHECK_EQ_INT(app_ble_passkey(), 418302);
    /* Six digits, always — a stack that hands us more keeps the low six,
     * so the display and the phone agree. */
    app_ble_passkey_set(12418302);
    CHECK_EQ_INT(app_ble_passkey(), 418302);
    app_ble_passkey_clear();
    CHECK(!app_ble_passkey_active());
    CHECK_EQ_INT(app_ble_passkey(), 0);
}

/* The whole §3 bond cycle as the core sees it: an unbonded central can
 * read device_info and nothing else; encryption unlocks telemetry;
 * authentication unlocks the two dangerous writes; forgetting returns to
 * the start. The stack drives these transitions on the board — what is
 * asserted here is that the core's answer to each is the contract's. */
static void test_bond_cycle(void) {
    reset_all();
    bridge_result_t r;
    uint8_t out[BRIDGE_HISTORY_PREVIEW_MAX_SIZE];

    /* 1. Unbonded: the identity card is readable, so the app can tell one
     *    bridge from another before anyone types anything. */
    CHECK_EQ_INT(app_ble_bond_count(), 0);
    CHECK(app_ble_access_allowed(APP_BLE_CH_DEVICE_INFO, &k_open));
    CHECK(!app_ble_access_allowed(APP_BLE_CH_LIVE_STATE, &k_open));
    CHECK_EQ_INT(app_ble_build_device_info(out, sizeof out),
                 BRIDGE_DEVICE_INFO_SIZE);

    /* 2. Pairing: a passkey is generated and displayed. */
    app_ble_passkey_set(418302);
    CHECK(app_ble_passkey_active());

    /* 3. Bonded and encrypted+authenticated: everything opens, and the
     *    code comes off the glass. */
    app_ble_passkey_clear();
    app_ble_set_bond_count(1);
    CHECK(!app_ble_passkey_active());
    CHECK(app_ble_access_allowed(APP_BLE_CH_LIVE_STATE, &k_authed));
    CHECK(app_ble_access_allowed(APP_BLE_CH_WIFI_CONFIG, &k_authed));

    /* 4. Reconnect: encrypted from the stored LTK, no new passkey. */
    CHECK(!app_ble_passkey_active());
    CHECK(app_ble_access_allowed(APP_BLE_CH_LIVE_STATE, &k_encrypted));
    g_notif_count = 0;
    CHECK_EQ_INT(app_ble_notify_live_state(), APP_BLE_OK);
    CHECK_EQ_INT(count_of(APP_BLE_CH_LIVE_STATE), 1);

    /* 5. Three phones is the cap; the fourth is refused before a code is
     *    ever displayed, so nobody types a key that cannot be accepted. */
    app_ble_set_bond_count(APP_BLE_MAX_BONDS);
    CHECK(!app_ble_bond_slot_available());

    /* 6. Forget-all (factory reset, op 8): back to zero bonds, and the
     *    answer goes out BEFORE the reset that kills the link. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_FACTORY_RESET, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.op_echo, BRIDGE_CONTROL_OP_FACTORY_RESET);
    CHECK_EQ_INT(g_factory_calls, 1);
    app_ble_set_bond_count(0); /* what the glue does after ble_store_clear */
    CHECK(app_ble_bond_slot_available());
}

/* F10.5's done-when, spelled out: the passkey the BLE layer generates is
 * the passkey on the glass. app_ble never learns a display exists — it
 * publishes a number — so this is the only place the two halves meet, and
 * it meets them against F11a's committed golden. */
static void test_passkey_reaches_the_renderer(void) {
    reset_all();
    app_ble_passkey_set(418302);

    /* Exactly what app_ui's BRIDGE_EVT_BLE handler does with the event.
     * M5 replaced F11a's `passkey_active` bool with the overlay enum, so
     * this mirrors the current handler rather than the M3 one. */
    app_ui_state_t st;
    memset(&st, 0, sizeof st);
    st.overlay = app_ble_passkey_active() ? APP_UI_OVERLAY_PASSKEY
                                          : APP_UI_OVERLAY_NONE;
    st.soc_pct = BRIDGE_SOC_UNKNOWN;
    snprintf(st.passkey, sizeof st.passkey, "%06u",
             (unsigned)app_ble_passkey());
    CHECK(strcmp(st.passkey, "418302") == 0);

    app_ui_fb_t fb;
    app_ui_render_overlay_passkey(&st, &fb);

    char path[512];
    snprintf(path, sizeof path, "%s/passkey-418302.fb", GOLDEN_DIR);
    FILE *f = fopen(path, "rb");
    CHECK(f != NULL);
    if (f != NULL) {
        uint8_t want[APP_UI_FB_BYTES];
        CHECK_EQ_INT(fread(want, 1, sizeof want, f), sizeof want);
        fclose(f);
        CHECK(memcmp(want, fb.px, sizeof want) == 0);
    }

    /* A leading-zero passkey must not lose its zero on the way to the
     * display — six digits, always. */
    app_ble_passkey_set(302);
    snprintf(st.passkey, sizeof st.passkey, "%06u",
             (unsigned)app_ble_passkey());
    CHECK(strcmp(st.passkey, "000302") == 0);

    /* And bonding ending takes it off the glass. */
    app_ble_passkey_clear();
    CHECK(!app_ble_passkey_active());
}

/* F13.8 — live_state.alarm_active was a hardcoded `false` from F10 until
 * M5, and op 11 parsed an id it then threw away. Both are wired now, and
 * this is the test that says so in the one place a phone can observe it. */
static void test_live_state_alarm_active_follows_the_engine(void) {
    reset_all();
    /* Probe 2 is a food probe about to pass its target. */
    CHECK_EQ_INT(app_config_store_set_u8(APP_CONFIG_PROBE2_ROLE,
                                         APP_CONFIG_ROLE_FOOD),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_set_i32(APP_CONFIG_PROBE2_TARGET, 2030),
                 APP_CONFIG_OK);

    uint8_t buf[BRIDGE_LIVE_STATE_SIZE];
    CHECK_EQ_INT(app_ble_build_live_state(buf, sizeof buf),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_t st;
    bridge_live_state_decode(buf, &st);
    CHECK_EQ_INT((st.flags & BRIDGE_LIVE_STATE_FLAGS_ALARM_ACTIVE) != 0, 0);

    cook_ring_sample_t rs = {.t = 30, .rssi = -70};
    rs.temp[0] = 2430;
    rs.temp[1] = 2041;
    rs.temp[2] = INT16_MIN;
    rs.temp[3] = INT16_MIN;
    cook_ring_push(&rs);
    app_alarm_svc_on_sample(30);

    CHECK_EQ_INT(app_ble_build_live_state(buf, sizeof buf),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_decode(buf, &st);
    CHECK_EQ_INT((st.flags & BRIDGE_LIVE_STATE_FLAGS_ALARM_ACTIVE) != 0, 1);

    /* The phone acks over op 11 — the real dispatch path, not the
     * service call — and the flag drops while the alarm REMAINS latched
     * in the list. Acknowledging silences; it does not resolve. */
    const app_alarm_slot_t *list[APP_ALARM_MAX_ACTIVE];
    CHECK_EQ_INT(app_alarm_svc_list(list, APP_ALARM_MAX_ACTIVE), 1);
    const uint8_t id = list[0]->id;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_ACK_ALARM, &id, 1),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(app_ble_build_live_state(buf, sizeof buf),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_decode(buf, &st);
    CHECK_EQ_INT((st.flags & BRIDGE_LIVE_STATE_FLAGS_ALARM_ACTIVE) != 0, 0);
    CHECK_EQ_INT(app_alarm_svc_list(list, APP_ALARM_MAX_ACTIVE), 1);
    CHECK_EQ_INT(list[0]->state, APP_ALARM_SLOT_ACKED);
}

/* F12.5 — soc_pct and the caps bit that makes it readable. P3.2 chose
 * SOC_UNKNOWN = 255 over 0 precisely because 0 is a plausible reading:
 * a device with no battery sensor would render as one about to die. */
static void test_soc_and_the_battery_capability_bit(void) {
    reset_all();
    uint8_t info[BRIDGE_DEVICE_INFO_SIZE];
    CHECK_EQ_INT(app_ble_build_device_info(info, sizeof info),
                 (int)BRIDGE_DEVICE_INFO_SIZE);
    bridge_device_info_t d;
    bridge_device_info_decode(info, &d);
    /* Before any reading: the bit says a real value can never arrive,
     * which is the whole distinction it exists to carry. */
    CHECK_EQ_INT((d.caps & (1u << 5)) != 0, 0);

    uint8_t live[BRIDGE_LIVE_STATE_SIZE];
    CHECK_EQ_INT(app_ble_build_live_state(live, sizeof live),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_t st;
    bridge_live_state_decode(live, &st);
    CHECK_EQ_INT(st.soc_pct, BRIDGE_SOC_UNKNOWN);

    /* V1.3's point, through the real service. */
    (void)app_power_svc_sample(788, 0);
    CHECK_EQ_INT(app_ble_build_device_info(info, sizeof info),
                 (int)BRIDGE_DEVICE_INFO_SIZE);
    bridge_device_info_decode(info, &d);
    CHECK_EQ_INT((d.caps & (1u << 5)) != 0, 1);
    CHECK_EQ_INT(app_ble_build_live_state(live, sizeof live),
                 BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_decode(live, &st);
    CHECK(st.soc_pct != BRIDGE_SOC_UNKNOWN);
    CHECK(st.soc_pct <= 100);
}

int main(void) {
    test_registry_matches_the_contract();
    test_uuid_is_little_endian_on_air();
    test_security_table();
    test_device_info_matches_fixture();
    test_net_status_matches_fixture();
    test_live_state_sentinels_survive();
    test_history_preview();
    test_advertising_pdus();
    test_status_blob_matrix();
    test_adv_interval_policy();
    test_mtu_negotiation_bounds();
    test_chunker_at_both_mtus();
    test_result_frames_chunk_too();
    test_wifi_config_accept_then_apply();
    test_wifi_config_ap_carries_the_psk();
    test_no_path_emits_a_stored_sta_psk();
    test_net_status_notifies_once_per_transition();
    test_unauthenticated_write_is_refused();
    test_malformed_writes_answer_invalid();
    test_scan_streams_indexed_results();
    test_scan_busy_does_not_disturb_the_running_scan();
    test_scan_cancel_stops_the_stream();
    test_scan_edge_cases();
    test_every_op_reaches_its_component();
    test_reboot_and_reset_answer_before_they_act();
    test_live_state_alarm_active_follows_the_engine();
    test_soc_and_the_battery_capability_bit();
    test_set_time_backpatches_an_open_session();
    test_bond_cap();
    test_passkey_lifecycle();
    test_bond_cycle();
    test_passkey_reaches_the_renderer();
    return test_summary("test_app_ble");
}
