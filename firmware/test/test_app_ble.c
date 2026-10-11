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
#include "app_power_svc.h"
#include "app_ble_internal.h"
#include "app_config_store.h"
#include "app_ui_cook.h"
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
static int g_identify_calls;
static int g_reboot_calls;
static int g_factory_calls;
static uint64_t g_uptime_ms;

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

static int fake_notify(app_ble_char_t ch, const uint8_t *buf, size_t len) {
    if (g_notif_count < NOTIFY_MAX) {
        g_notifs[g_notif_count].ch = ch;
        g_notifs[g_notif_count].len = len;
        memcpy(g_notifs[g_notif_count].buf, buf,
               len < sizeof g_notifs[0].buf ? len : sizeof g_notifs[0].buf);
        g_notif_count++;
    }
    return 0;
}

static int fake_identify(void) {
    g_identify_calls++;
    return APP_BLE_OK;
}

static void fake_reboot(void) { g_reboot_calls++; }
static int g_power_off_calls;
static void fake_power_off(void) { g_power_off_calls++; }

static int fake_factory_reset(void) {
    g_factory_calls++;
    return APP_BLE_OK;
}

static uint64_t fake_uptime(void) { return g_uptime_ms; }

static const app_ble_ops_t k_ops = {
    .sysinfo = fake_sysinfo,
    .notify = fake_notify,
    .identify = fake_identify,
    .reboot = fake_reboot,
    .factory_reset = fake_factory_reset,
    .power_off = fake_power_off,
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
    g_identify_calls = 0;
    g_reboot_calls = 0;
    g_factory_calls = 0;
    g_power_off_calls = 0;
    g_uptime_ms = 1000;

    memfs_reset();
    cfg_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);
    cook_store_set_request_hooks(hook_start, hook_stop);
    CHECK_EQ_INT(smoke_x_ctrl_init(&k_radio_ops, NULL, false, 0), 0);
    cook_ring_reset();
    CHECK_EQ_INT(app_time_core_init(0, NULL, NULL), 0);
    CHECK_EQ_INT(app_power_svc_init(), 0);
    CHECK_EQ_INT(app_ble_core_init(&k_ops), APP_BLE_OK);
    app_ble_set_mtu(APP_BLE_MTU_PREFERRED);
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
        {APP_BLE_CH_DEVICE_CONTROL, 0x0006, APP_BLE_PROP_WRITE,
         APP_BLE_SEC_AUTHENTICATED},
        {APP_BLE_CH_LIVE_STATE, 0x0007,
         APP_BLE_PROP_READ | APP_BLE_PROP_NOTIFY, APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_HISTORY_PREVIEW, 0x0008, APP_BLE_PROP_READ,
         APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_RESULT, 0x0009, APP_BLE_PROP_NOTIFY,
         APP_BLE_SEC_ENCRYPTED},
        /* v1.1 full history. `encrypted`, deliberately NOT authenticated:
         * these read stored cooks and change nothing, so they sit with
         * live_state rather than with the pair that can reconfigure or
         * wipe the device (§3). */
        {APP_BLE_CH_HISTORY_CTRL, 0x000A, APP_BLE_PROP_WRITE,
         APP_BLE_SEC_ENCRYPTED},
        {APP_BLE_CH_HISTORY_DATA, 0x000B, APP_BLE_PROP_NOTIFY,
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

    CHECK(app_ble_access_allowed(APP_BLE_CH_LIVE_STATE, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_HISTORY_PREVIEW, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_RESULT, &k_encrypted));

    /* The one that can wipe the device needs an MITM-protected key — an
     * encrypted-but-unauthenticated link is not enough, and that is the
     * whole reason the OLED shows a passkey. */
    CHECK(!app_ble_access_allowed(APP_BLE_CH_DEVICE_CONTROL, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_DEVICE_CONTROL, &k_authed));

    CHECK(!app_ble_access_allowed(APP_BLE_CH_DEVICE_CONTROL, NULL));
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

    /* The BLE name is MAC-derived: "SmokeBridge-XXXX". */
    const uint8_t mac[6] = {0x24, 0x6F, 0x28, 0x11, 0xA4, 0xF2};
    char ble_name[APP_BLE_NAME_MAX];
    app_ble_local_name(mac, ble_name);
    CHECK(strcmp(ble_name, "SmokeBridge-A4F2") == 0);
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

/* ── F10.5 / security: refusal happens before the handler ─────────── */

static void test_unauthenticated_write_is_refused(void) {
    reset_all();
    bridge_result_t r;
    const uint8_t reboot[2] = {1, BRIDGE_CONTROL_OP_REBOOT};

    /* Encrypted but NOT authenticated: refused at the security layer. */
    CHECK_EQ_INT(
        app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_encrypted, reboot, 2),
        APP_BLE_OK);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_UNAUTHORIZED);
    /* The handler never ran: no reboot was requested. */
    CHECK_EQ_INT(g_reboot_calls, 0);

    /* And an unencrypted link. */
    reset_all();
    app_ble_core_write(APP_BLE_CH_DEVICE_CONTROL, &k_open, reboot, 2);
    CHECK(last_result(&r));
    CHECK_EQ_INT(r.status, BRIDGE_RESULT_STATUS_UNAUTHORIZED);
    CHECK_EQ_INT(g_reboot_calls, 0);

    /* Writing a read-only characteristic is refused outright. */
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_LIVE_STATE, &k_authed, reboot, 2),
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
    CHECK_EQ_INT(g_reboot_calls + g_factory_calls, 0);
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

    /* op 13 power_off is the third of the same shape: nothing remote wakes
     * the bridge afterwards, so the answer must already be on the wire. */
    reset_all();
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_POWER_OFF, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(g_power_off_calls, 1);
    CHECK_EQ_INT(g_notifs[0].ch, APP_BLE_CH_RESULT);
}

static void test_set_battery_saver_takes_the_tri_state(void) {
    /* op 12 mirrors POST /config/device's off/on/auto so the two transports
     * cannot disagree about what "auto" means. */
    const uint8_t on = BRIDGE_BATTERY_SAVER_ON;
    reset_all();
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_BATTERY_SAVER, &on, 1),
                 BRIDGE_RESULT_STATUS_OK);
    uint8_t v = 0xff;
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_DEV_BATTERY_SAVER, &v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(v, BRIDGE_BATTERY_SAVER_ON);

    const uint8_t automatic = BRIDGE_BATTERY_SAVER_AUTO;
    reset_all();
    CHECK_EQ_INT(
        status_after(BRIDGE_CONTROL_OP_SET_BATTERY_SAVER, &automatic, 1),
        BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_DEV_BATTERY_SAVER, &v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(v, BRIDGE_BATTERY_SAVER_AUTO);

    /* Out of range is refused, and the stored value is left alone — checked
     * against a value set in the SAME scope, since reset_all() wipes NVS. */
    reset_all();
    const uint8_t known = BRIDGE_BATTERY_SAVER_ON;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_BATTERY_SAVER, &known, 1),
                 BRIDGE_RESULT_STATUS_OK);
    const uint8_t bogus = 9;
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_BATTERY_SAVER, &bogus, 1),
                 BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_DEV_BATTERY_SAVER, &v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(v, BRIDGE_BATTERY_SAVER_ON);

    /* An empty body is malformed, not a silent default. */
    reset_all();
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_BATTERY_SAVER, NULL, 0),
                 BRIDGE_RESULT_STATUS_INVALID);
}

/* The cook clock over BLE. It has to work here and not only over HTTP: BLE
 * is the transport that survives a yard with no Wi-Fi, which is exactly when
 * the glass is the only thing anyone can read.
 *
 * Note what this test does NOT do — it never opens a session. The clock and
 * the recording are independent, and that separation is the whole change. */
static void test_cook_clock_ops(void) {
    reset_all();
    app_ui_cook_clear();
    uint32_t elapsed = 0;
    const uint32_t up_s = (uint32_t)(g_uptime_ms / 1000ull);

    CHECK(!app_ui_cook_get(up_s, &elapsed));

    bridge_ctrl_set_cook_clock_t c;
    c.elapsed_s = 300; /* "the cook is already five minutes in" */
    uint8_t body[BRIDGE_CTRL_SET_COOK_CLOCK_SIZE];
    bridge_ctrl_set_cook_clock_encode(&c, body);
    CHECK_EQ_INT(
        status_after(BRIDGE_CONTROL_OP_SET_COOK_CLOCK, body, sizeof body),
        BRIDGE_RESULT_STATUS_OK);
    CHECK(app_ui_cook_get(up_s, &elapsed));
    CHECK_EQ_INT((int)elapsed, 300);
    CHECK(!cook_session_is_open()); /* no recording was started */

    /* Re-sending adjusts rather than conflicting. */
    c.elapsed_s = 7200;
    bridge_ctrl_set_cook_clock_encode(&c, body);
    CHECK_EQ_INT(
        status_after(BRIDGE_CONTROL_OP_SET_COOK_CLOCK, body, sizeof body),
        BRIDGE_RESULT_STATUS_OK);
    CHECK(app_ui_cook_get(up_s, &elapsed));
    CHECK_EQ_INT((int)elapsed, 7200);

    /* Beyond 99:59 is refused, and the live clock survives the refusal. */
    c.elapsed_s = APP_UI_COOK_MAX_ELAPSED_S + 1;
    bridge_ctrl_set_cook_clock_encode(&c, body);
    CHECK_EQ_INT(
        status_after(BRIDGE_CONTROL_OP_SET_COOK_CLOCK, body, sizeof body),
        BRIDGE_RESULT_STATUS_INVALID);
    CHECK(app_ui_cook_get(up_s, &elapsed));
    CHECK_EQ_INT((int)elapsed, 7200);

    /* A short body is malformed, not a silent zero. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_SET_COOK_CLOCK, body, 2),
                 BRIDGE_RESULT_STATUS_INVALID);

    /* Clear carries no body and never fails — a retrying client sends it
     * twice, and the second must not read as an error. */
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_CLEAR_COOK_CLOCK, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
    CHECK(!app_ui_cook_get(up_s, &elapsed));
    CHECK_EQ_INT(status_after(BRIDGE_CONTROL_OP_CLEAR_COOK_CLOCK, NULL, 0),
                 BRIDGE_RESULT_STATUS_OK);
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
    CHECK(app_ble_access_allowed(APP_BLE_CH_DEVICE_CONTROL, &k_authed));

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

/* ── v1.1: full history over BLE (§5.10–§5.11) ────────────────────── */

/* The client half, in miniature: reassemble chunks into frames, check the
 * seq chain, and accumulate what arrives. A 12 h cook is ~104 frames —
 * far past NOTIFY_MAX — so this consumes as it goes rather than capturing.
 */
typedef struct {
    int frames;
    int samples;
    int sessions;
    int marks;
    bool saw_end;
    uint8_t end_status;
    int seq_gaps;
    uint16_t next_seq;
    uint32_t first_t;
    uint32_t last_t;
    bool all_crcs_ok;
    bool any_frame_over_mtu;
    char first_name[29];
    uint32_t first_sample_count;
    /* partial-frame reassembly across chunks */
    uint8_t buf[BRIDGE_HISTORY_DATA_MAX_SIZE];
    size_t used;
} hist_sink_t;

static hist_sink_t g_hist;

static void hist_sink_reset(void) {
    memset(&g_hist, 0, sizeof g_hist);
    g_hist.all_crcs_ok = true;
    g_hist.first_t = UINT32_MAX;
}

static void hist_consume_frame(const uint8_t *bytes, size_t len) {
    bridge_history_data_t f;
    if (bridge_history_data_unpack(bytes, len, &f) < 0) {
        g_hist.all_crcs_ok = false;
        return;
    }
    g_hist.frames++;
    /* A busy refusal deliberately rides seq UINT16_MAX so it cannot be
     * mistaken for a frame of the stream already in flight. */
    if (f.seq != UINT16_MAX) {
        if (f.seq != g_hist.next_seq) {
            g_hist.seq_gaps++;
        }
        g_hist.next_seq = (uint16_t)(f.seq + 1);
    }

    switch (f.kind) {
    case BRIDGE_HISTORY_KIND_SAMPLES:
        for (int i = 0; i < f.count; i++) {
            bridge_sample_rec_t rec;
            if (!bridge_sample_rec_decode(
                    f.payload + i * BRIDGE_SAMPLE_REC_SIZE, &rec)) {
                g_hist.all_crcs_ok = false;
            }
            if (rec.t < g_hist.first_t) {
                g_hist.first_t = rec.t;
            }
            g_hist.last_t = rec.t;
            g_hist.samples++;
        }
        break;
    case BRIDGE_HISTORY_KIND_SESSION:
        for (int i = 0; i < f.count; i++) {
            bridge_history_session_t s;
            bridge_history_session_decode(
                f.payload + i * BRIDGE_HISTORY_SESSION_SIZE, &s);
            if (g_hist.sessions == 0) {
                memcpy(g_hist.first_name, s.name, sizeof s.name);
                g_hist.first_name[sizeof s.name] = '\0';
                g_hist.first_sample_count = s.sample_count;
            }
            g_hist.sessions++;
        }
        break;
    case BRIDGE_HISTORY_KIND_MARKS:
        g_hist.marks += f.count;
        break;
    case BRIDGE_HISTORY_KIND_END:
        g_hist.saw_end = true;
        g_hist.end_status = f.len > 0 ? f.payload[0] : 0xFF;
        break;
    default:
        break;
    }
}

/* Installed in place of fake_notify for the history tests. */
static int hist_notify(app_ble_char_t ch, const uint8_t *buf, size_t len) {
    if (ch != APP_BLE_CH_HISTORY_DATA) {
        return 0; /* live_state and friends are not this test's business */
    }
    if (len > app_ble_notify_chunk()) {
        g_hist.any_frame_over_mtu = true;
    }
    if (g_hist.used + len > sizeof g_hist.buf) {
        g_hist.used = 0;
        g_hist.all_crcs_ok = false;
        return 0;
    }
    memcpy(g_hist.buf + g_hist.used, buf, len);
    g_hist.used += len;
    /* The 7-byte fixed prefix arrives whole in the first chunk (§4/§5.11),
     * so the total length is knowable from it — exactly what the app's
     * reassembler does. */
    if (g_hist.used < 7) {
        return 0;
    }
    const size_t want = 7u + g_hist.buf[6];
    if (g_hist.used < want) {
        return 0;
    }
    hist_consume_frame(g_hist.buf, want);
    g_hist.used = 0;
    return 0;
}

static app_ble_ops_t k_hist_ops;

static void use_history_ops(void) {
    k_hist_ops = k_ops;
    k_hist_ops.notify = hist_notify;
    /* history_defer stays NULL: with no ble_push row on the host the core
     * runs the stream inline, which is what a test wants. */
    CHECK_EQ_INT(app_ble_core_init(&k_hist_ops), APP_BLE_OK);
    app_ble_set_mtu(APP_BLE_MTU_PREFERRED);
}

static void write_history_ctrl(uint8_t req, uint32_t session_id,
                               uint32_t from_t, uint32_t to_t,
                               uint16_t stride) {
    bridge_history_ctrl_t c;
    memset(&c, 0, sizeof c);
    c.ver = 1;
    c.req = req;
    c.stride = stride;
    c.session_id = session_id;
    c.from_t = from_t;
    c.to_t = to_t;
    uint8_t buf[BRIDGE_HISTORY_CTRL_SIZE];
    bridge_history_ctrl_encode(&c, buf);
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_HISTORY_CTRL, &k_encrypted, buf,
                                    sizeof buf),
                 APP_BLE_OK);
}

/* Records `hours` of a cook at the nominal 30 s cadence. */
static uint32_t seed_session(int hours) {
    CHECK_EQ_INT(cook_store_request_start(), COOK_STORE_OK);
    const uint32_t n = (uint32_t)hours * 120u;
    for (uint32_t i = 0; i < n; i++) {
        const int16_t temp[4] = {(int16_t)(2000 + (i % 400)), 1600,
                                 BRIDGE_TEMP_DETACHED, 900};
        CHECK_EQ_INT(cook_session_append(i * 30u, temp, 0, -70),
                     COOK_STORE_OK);
    }
    return cook_session_active_id();
}

/* THE POINT OF THE FEATURE: a bridge that recorded overnight with no phone
 * anywhere near it hands the whole cook to a phone over Bluetooth alone. */
static void test_twelve_hours_streams_over_ble(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(12);
    CHECK_EQ_INT(cook_session_sample_count(), 1440);

    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 0, UINT32_MAX, 1);

    /* Every record, in order, CRC-intact, with no gap in the frame chain. */
    CHECK_EQ_INT(g_hist.samples, 1440);
    CHECK_EQ_INT(g_hist.first_t, 0);
    CHECK_EQ_INT(g_hist.last_t, 1439u * 30u);
    CHECK(g_hist.all_crcs_ok);
    CHECK_EQ_INT(g_hist.seq_gaps, 0);
    CHECK(g_hist.saw_end);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
    CHECK(!g_hist.any_frame_over_mtu);
    /* 14 records per frame is the largest whole number that fits 237 B;
     * 1440/14 = 103 rounded up, plus the terminator. A frame count far off
     * this means items are straddling frames or frames are half empty. */
    CHECK_EQ_INT(g_hist.frames, 104);
}

/* The default ATT MTU is the one Android is most likely to leave us with
 * (R7). The transfer must still complete — slower, never broken. */
static void test_history_survives_the_default_mtu(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(1);

    app_ble_set_mtu(APP_BLE_MTU_DEFAULT);
    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 0, UINT32_MAX, 1);

    CHECK_EQ_INT(g_hist.samples, 120);
    CHECK(g_hist.all_crcs_ok);
    CHECK_EQ_INT(g_hist.seq_gaps, 0);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
    /* Frames are unchanged; only the chunking below them differs. */
    CHECK(!g_hist.any_frame_over_mtu);
}

static void test_history_range_and_stride(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(2);

    /* A delta sync: everything after what the phone already holds. */
    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 3600, UINT32_MAX, 1);
    CHECK_EQ_INT(g_hist.samples, 120);
    CHECK_EQ_INT(g_hist.first_t, 3600);

    /* stride 0 means "every record", not "no records" (§5.10). */
    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 0, UINT32_MAX, 0);
    CHECK_EQ_INT(g_hist.samples, 240);

    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 0, UINT32_MAX, 4);
    CHECK_EQ_INT(g_hist.samples, 60);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
}

static void test_session_list_reports_a_live_cook_honestly(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(12);
    (void)id;

    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SESSIONS, 0, 0, UINT32_MAX, 1);

    CHECK_EQ_INT(g_hist.sessions, 1);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
    /* THE ONE THAT MATTERS FOR SYNC: the header's sample_count is only
     * authoritative once a session closes (04 §4.3). An open 12 h cook
     * whose entry said 0 would tell the phone there is nothing to fetch —
     * which is precisely the always-recording case this feature exists
     * for. */
    CHECK_EQ_INT(g_hist.first_sample_count, 1440);
    CHECK(strcmp(g_hist.first_name, "Brisket") == 0);
}

static void test_history_refusals_are_always_answered(void) {
    reset_all();
    use_history_ops();

    /* An unknown session: invalid, and still terminated. Silence is the
     * one answer a client waiting on a stream cannot recover from. */
    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, 999, 0, UINT32_MAX, 1);
    CHECK(g_hist.saw_end);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_INVALID);
    CHECK_EQ_INT(g_hist.samples, 0);

    /* An unknown req verb. */
    hist_sink_reset();
    write_history_ctrl(99, 1, 0, UINT32_MAX, 1);
    CHECK(g_hist.saw_end);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_INVALID);

    /* A short write. */
    hist_sink_reset();
    const uint8_t stub[4] = {1, BRIDGE_HISTORY_REQ_SAMPLES, 0, 0};
    CHECK_EQ_INT(app_ble_core_write(APP_BLE_CH_HISTORY_CTRL, &k_encrypted,
                                    stub, sizeof stub),
                 APP_BLE_OK);
    CHECK(g_hist.saw_end);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_INVALID);

    /* Cancel with nothing running is ok — a retrying client's second
     * cancel must not look like a failure. */
    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_CANCEL, 0, 0, 0, 0);
    CHECK(g_hist.saw_end);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);

    /* A session with no marks answers ok with no data frames — "no marks",
     * never a hang (§5.11, the §5.4 empty-scan rule). */
    const uint32_t id = seed_session(1);
    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_MARKS, id, 0, UINT32_MAX, 1);
    CHECK(g_hist.saw_end);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
    CHECK_EQ_INT(g_hist.marks, 0);
    CHECK_EQ_INT(g_hist.frames, 1);
}

static void test_history_marks_stream_verbatim(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(1);
    CHECK_EQ_INT(cook_session_mark(600, 2, 0, "lid open"), COOK_STORE_OK);
    CHECK_EQ_INT(cook_session_mark(1800, 1, 1, "wrapped"), COOK_STORE_OK);
    /* Outside the requested range below, so it must not be sent. */
    CHECK_EQ_INT(cook_session_mark(3400, 0, 0, "late"), COOK_STORE_OK);

    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_MARKS, id, 0, 2000, 1);
    CHECK_EQ_INT(g_hist.marks, 2);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
}

/* A phone pocketed mid-transfer must not wedge the characteristic — the
 * same latch bug the Wi-Fi scan had, caught before the board could teach
 * it again. */
static void test_disconnect_clears_a_latched_stream(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(1);

    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 0, UINT32_MAX, 1);
    CHECK(!app_ble_history_active());

    app_ble_ctrl_reset(); /* what BLE_GAP_EVENT_DISCONNECT calls */
    CHECK(!app_ble_history_active());

    hist_sink_reset();
    write_history_ctrl(BRIDGE_HISTORY_REQ_SAMPLES, id, 0, UINT32_MAX, 1);
    CHECK_EQ_INT(g_hist.samples, 120);
    CHECK_EQ_INT(g_hist.end_status, BRIDGE_RESULT_STATUS_OK);
}

/* history_ctrl needs a bond, but NOT the authenticated tier: it reads
 * stored cooks and changes nothing (§3). */
static void test_history_requires_encryption_only(void) {
    reset_all();
    use_history_ops();
    const uint32_t id = seed_session(1);

    CHECK(!app_ble_access_allowed(APP_BLE_CH_HISTORY_CTRL, &k_open));
    CHECK(app_ble_access_allowed(APP_BLE_CH_HISTORY_CTRL, &k_encrypted));
    CHECK(app_ble_access_allowed(APP_BLE_CH_HISTORY_DATA, &k_encrypted));

    /* An unencrypted write is refused before the handler runs, and the
     * refusal lands on `result` like every other security refusal. */
    hist_sink_reset();
    bridge_history_ctrl_t c;
    memset(&c, 0, sizeof c);
    c.ver = 1;
    c.req = BRIDGE_HISTORY_REQ_SAMPLES;
    c.session_id = id;
    c.to_t = UINT32_MAX;
    uint8_t buf[BRIDGE_HISTORY_CTRL_SIZE];
    bridge_history_ctrl_encode(&c, buf);
    (void)app_ble_core_write(APP_BLE_CH_HISTORY_CTRL, &k_open, buf,
                             sizeof buf);
    CHECK_EQ_INT(g_hist.samples, 0);
    CHECK_EQ_INT(g_hist.frames, 0);
}

int main(void) {
    test_registry_matches_the_contract();
    test_uuid_is_little_endian_on_air();
    test_security_table();
    test_device_info_matches_fixture();
    test_live_state_sentinels_survive();
    test_history_preview();
    test_advertising_pdus();
    test_status_blob_matrix();
    test_adv_interval_policy();
    test_mtu_negotiation_bounds();
    test_chunker_at_both_mtus();
    test_result_frames_chunk_too();
    test_unauthenticated_write_is_refused();
    test_malformed_writes_answer_invalid();
    test_every_op_reaches_its_component();
    test_reboot_and_reset_answer_before_they_act();
    test_set_battery_saver_takes_the_tri_state();
    test_soc_and_the_battery_capability_bit();
    test_cook_clock_ops();
    test_set_time_backpatches_an_open_session();
    test_bond_cap();
    test_passkey_lifecycle();
    test_bond_cycle();
    test_passkey_reaches_the_renderer();
    /* v1.1 — full history over BLE (§5.10–§5.11). */
    test_twelve_hours_streams_over_ble();
    test_history_survives_the_default_mtu();
    test_history_range_and_stride();
    test_session_list_reports_a_live_cook_honestly();
    test_history_refusals_are_always_answered();
    test_history_marks_stream_verbatim();
    test_disconnect_clears_a_latched_stream();
    test_history_requires_encryption_only();
    return test_summary("test_app_ble");
}
