/* Host tests for app_net (F8.1–F8.6): every §5.2 selection path, the §5.4
 * budget → fallback-AP → retry ladder, the switch-back guard, deferred
 * reconfiguration, channel pick, the DNS shim codec, and the live TXT
 * builder. */
#include <string.h>

#include "app_config_store.h"
#include "app_net_core.h"
#include "app_net_txt.h"
#include "dns_shim.h"
#include "test_util.h"

/* In-memory config backend (the F8.4 apply persists through it). */
typedef struct {
    char ns[16];
    char key[16];
    size_t len;
    uint8_t val[80];
} cfg_entry_t;

static struct {
    cfg_entry_t entries[64];
    int count;
} g_cfg;

static cfg_entry_t *cfg_find(const char *ns, const char *key) {
    for (int i = 0; i < g_cfg.count; i++) {
        if (strcmp(g_cfg.entries[i].ns, ns) == 0 &&
            strcmp(g_cfg.entries[i].key, key) == 0) {
            return &g_cfg.entries[i];
        }
    }
    return NULL;
}

static int cfg_get(void *ctx, const char *ns, const char *key, void *out,
                   size_t *len) {
    (void)ctx;
    const cfg_entry_t *e = cfg_find(ns, key);
    if (!e) {
        return APP_CONFIG_ERR_NOT_FOUND;
    }
    if (!out) {
        *len = e->len;
        return APP_CONFIG_OK;
    }
    if (*len < e->len) {
        return APP_CONFIG_ERR;
    }
    memcpy(out, e->val, e->len);
    *len = e->len;
    return APP_CONFIG_OK;
}

static int cfg_set(void *ctx, const char *ns, const char *key,
                   const void *val, size_t len) {
    (void)ctx;
    cfg_entry_t *e = cfg_find(ns, key);
    if (!e) {
        e = &g_cfg.entries[g_cfg.count++];
        snprintf(e->ns, sizeof e->ns, "%s", ns);
        snprintf(e->key, sizeof e->key, "%s", key);
    }
    memcpy(e->val, val, len);
    e->len = len;
    return APP_CONFIG_OK;
}

static int cfg_erase(void *ctx) {
    (void)ctx;
    g_cfg.count = 0;
    return APP_CONFIG_OK;
}

static const app_config_backend_t g_cfg_backend = {
    .get = cfg_get, .set = cfg_set, .erase_all = cfg_erase, .ctx = NULL};

static uint32_t cfg_rng(void) { return 5u; }

static int g_start_ap, g_stop_ap, g_sta_connect, g_sta_disconnect;
static int g_evt_counts[8];

static int op_start_ap(void *c) {
    (void)c;
    g_start_ap++;
    return 0;
}
static int op_stop_ap(void *c) {
    (void)c;
    g_stop_ap++;
    return 0;
}
static int op_sta_connect(void *c) {
    (void)c;
    g_sta_connect++;
    return 0;
}
static int op_sta_disconnect(void *c) {
    (void)c;
    g_sta_disconnect++;
    return 0;
}
static void op_publish(void *c, app_net_evt_t evt, const uint8_t ip[4]) {
    (void)c;
    (void)ip;
    g_evt_counts[evt]++;
}

static const app_net_ops_t g_ops = {
    .start_ap = op_start_ap,
    .stop_ap = op_stop_ap,
    .sta_connect = op_sta_connect,
    .sta_disconnect = op_sta_disconnect,
    .publish = op_publish,
};

static void reset_doubles(void) {
    g_start_ap = g_stop_ap = g_sta_connect = g_sta_disconnect = 0;
    memset(g_evt_counts, 0, sizeof g_evt_counts);
}

static const uint8_t IP[4] = {192, 168, 1, 50};

/* Board-found: esp_wifi raises WIFI_EVENT_AP_START the instant the softAP
 * comes up, which beat app_net_core_init in the boot race and drove a
 * null-`s_ops` deref panic (LoadProhibited at publish+12, twice, before the
 * third boot won). Every on_* handler must be a safe no-op before init.
 *
 * MUST run first in main(): `s_ops` is only genuinely null before any test
 * has called app_net_core_init, and nothing resets it afterward. */
static void test_events_before_init_are_safe(void) {
    reset_doubles();
    /* No app_net_core_init here — s_ops is still NULL. Unfixed, each of
     * these dereferences it and the process dies before the asserts. */
    app_net_core_on_ap_started(987);
    app_net_core_on_sta_connected(IP, 987);
    app_net_core_on_sta_disconnected(987);
    app_net_core_on_ap_client_count(1);
    /* Reaching here at all is the crash test; and nothing was published. */
    for (int i = 0; i < (int)(sizeof g_evt_counts / sizeof g_evt_counts[0]);
         i++) {
        CHECK_EQ_INT(g_evt_counts[i], 0);
    }
    CHECK_EQ_INT(g_start_ap, 0);
    CHECK_EQ_INT(g_sta_disconnect, 0);
}

static void test_mode_selection_paths(void) {
    /* Stored AP → AP. */
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_AP, false, 0), 0);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_AP_STARTING);
    CHECK_EQ_INT(g_start_ap, 1);
    app_net_core_on_ap_started(100);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_AP_UP);

    /* Stored STA → STA connect attempt. */
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_STA, false, 0),
        0);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_CONNECTING);
    CHECK_EQ_INT(g_sta_connect, 1);
    CHECK_EQ_INT(g_start_ap, 0);

    /* Forced AP (recovery window / double reset) overrides stored STA —
     * for this boot only; the stored mode is the caller's to keep. */
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_STA, true, 0),
        0);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_AP_STARTING);
    CHECK_EQ_INT(g_sta_connect, 0);

    /* A later explicit mode change supersedes the boot force. */
    CHECK_EQ_INT(app_net_core_set_mode(APP_CONFIG_NET_MODE_STA, 5000), 0);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_CONNECTING);
    CHECK_EQ_INT(g_sta_connect, 1);
}

static void test_sta_success_and_loss(void) {
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_STA, false, 0),
        0);
    app_net_core_on_sta_connected(IP, 4000);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_UP);
    CHECK_EQ_INT(g_evt_counts[APP_NET_EVT_STA_UP], 1);

    /* Router reboots mid-cook: fallback engages, device stays reachable. */
    app_net_core_on_sta_disconnected(10000);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_FALLBACK_AP);
    CHECK_EQ_INT(g_start_ap, 1);
    CHECK_EQ_INT(g_evt_counts[APP_NET_EVT_STA_LOST], 1);
    CHECK_EQ_INT(g_evt_counts[APP_NET_EVT_FALLBACK], 1);
}

static void test_budget_timeout_and_retry_ladder(void) {
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_STA, false, 0),
        0);

    /* 30 s budget expires → AP fallback. */
    app_net_core_tick(APP_NET_STA_BUDGET_MS - 1);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_CONNECTING);
    app_net_core_tick(APP_NET_STA_BUDGET_MS);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_FALLBACK_AP);
    CHECK_EQ_INT(g_start_ap, 1);
    app_net_core_on_ap_started(APP_NET_STA_BUDGET_MS + 100);

    /* The ladder: 1, 2, 5, 10, 10... minutes between attempts. */
    CHECK_EQ_INT((int)app_net_retry_delay_min(0), 1);
    CHECK_EQ_INT((int)app_net_retry_delay_min(1), 2);
    CHECK_EQ_INT((int)app_net_retry_delay_min(2), 5);
    CHECK_EQ_INT((int)app_net_retry_delay_min(3), 10);
    CHECK_EQ_INT((int)app_net_retry_delay_min(9), 10);

    /* First retry fires ~1 min after the fallback, not before. */
    uint64_t t = APP_NET_STA_BUDGET_MS;
    const int connects_before = g_sta_connect;
    app_net_core_tick(t + 59000);
    CHECK_EQ_INT(g_sta_connect, connects_before);
    app_net_core_tick(t + 61000);
    CHECK_EQ_INT(g_sta_connect, connects_before + 1);

    /* That retry fails → next one waits ~2 min. */
    app_net_core_on_sta_disconnected(t + 62000);
    app_net_core_tick(t + 62000 + 119000);
    CHECK_EQ_INT(g_sta_connect, connects_before + 1);
    app_net_core_tick(t + 62000 + 121000);
    CHECK_EQ_INT(g_sta_connect, connects_before + 2);
}

static void test_switch_back_guard(void) {
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_STA, false, 0),
        0);
    app_net_core_tick(APP_NET_STA_BUDGET_MS); /* → fallback */
    app_net_core_on_ap_started(APP_NET_STA_BUDGET_MS + 100);

    /* A phone joins our AP and starts polling. */
    app_net_core_on_ap_client_count(1);
    uint64_t t = APP_NET_STA_BUDGET_MS + 61000;
    app_net_core_tick(t); /* retry fires */
    app_net_core_note_client_activity(t + 500);

    /* STA recovers — but a client is on the AP: DO NOT switch. */
    app_net_core_on_sta_connected(IP, t + 1000);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_FALLBACK_AP);
    CHECK_EQ_INT(g_stop_ap, 0);

    /* Client leaves but was active 30 s ago: still guarded. */
    app_net_core_on_ap_client_count(0);
    app_net_core_tick(t + 31000);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_FALLBACK_AP);

    /* 60 s of quiet: NOW the switch happens. */
    app_net_core_tick(t + 500 + 61000);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_UP);
    CHECK_EQ_INT(g_stop_ap, 1);
    CHECK_EQ_INT(g_evt_counts[APP_NET_EVT_STA_UP], 1);
}

static void test_ap_ssid_from_mac(void) {
    const uint8_t mac[6] = {0xAC, 0xA7, 0x04, 0x38, 0xA4, 0xF2};
    char ssid[APP_NET_SSID_MAX];
    app_net_ap_ssid(mac, ssid);
    CHECK(strcmp(ssid, "SmokeBridge-A4F2") == 0);
}

static void test_channel_pick(void) {
    /* Least congested of 1/6/11; ties to the lower channel. */
    uint8_t counts[13] = {0};
    CHECK_EQ_INT(app_net_pick_channel(counts), 1); /* all clear: tie → 1 */
    counts[0] = 5; /* ch 1 busy */
    CHECK_EQ_INT(app_net_pick_channel(counts), 6);
    counts[5] = 3; /* ch 6 some */
    counts[10] = 2;
    CHECK_EQ_INT(app_net_pick_channel(counts), 11);
    counts[3] = 9; /* ch 4 irrelevant: only 1/6/11 are candidates */
    CHECK_EQ_INT(app_net_pick_channel(counts), 11);
}

/* BOARD-FOUND (M3 bench): re-provisioning a bridge that is ALREADY in
 * STA mode used to be a silent no-op — set_mode returned early because
 * the mode had not changed. Nothing re-associated, and because no state
 * changed, no event was published, so the phone's wizard waited out its
 * whole handoff budget for a transition that could never arrive. The
 * nastier half: pointing an STA bridge at a DIFFERENT network persisted
 * the new credentials and then kept using the old association. */
static void test_reprovision_while_already_sta(void) {
    cfg_erase(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_STA, false, 0), 0);
    const uint8_t ip[4] = {10, 50, 50, 38};
    app_net_core_on_sta_connected(ip, 100);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_UP);
    const int connects_before = g_sta_connect;

    /* Same mode, DIFFERENT network: this is a command, not a preference. */
    app_net_pending_cfg_t cfg = {.mode = APP_CONFIG_NET_MODE_STA,
                                 .sta_auth = 1};
    snprintf(cfg.sta_ssid, sizeof cfg.sta_ssid, "Garage");
    snprintf(cfg.sta_psk, sizeof cfg.sta_psk, "second-pw");
    CHECK_EQ_INT(app_net_core_apply_later(&cfg, 1000), 0);
    app_net_core_tick(1000 + APP_NET_APPLY_DELAY_MS + 1);

    /* It must actually TEAR DOWN the old association first — connecting
     * an already-connected station is a no-op on the chip, which is how
     * this produced total silence on the board — and then re-associate. */
    CHECK_EQ_INT(g_sta_disconnect, 1);
    CHECK(g_sta_connect > connects_before);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_CONNECTING);
    /* ...with the new credentials persisted... */
    char ssid[33] = {0};
    CHECK_EQ_INT(app_config_store_get_str(APP_CONFIG_NET_STA_SSID, ssid,
                                          sizeof ssid),
                 APP_CONFIG_OK);
    CHECK(strcmp(ssid, "Garage") == 0);
    /* The disconnect WE caused must not be mistaken for a failure: no
     * fallback AP, still connecting. */
    app_net_core_on_sta_disconnected(1600);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_CONNECTING);
    CHECK_EQ_INT(g_evt_counts[APP_NET_EVT_FALLBACK], 0);

    /* ...and the resulting transition must be observable, because that is
     * what the app waits on. */
    app_net_core_on_sta_connected(ip, 2000);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_UP);
    CHECK(g_evt_counts[APP_NET_EVT_STA_UP] >= 2);

    /* The flag is one-shot: a REAL disconnect after it is still a real
     * failure, and still falls back. */
    app_net_core_on_sta_disconnected(2500);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_FALLBACK_AP);

    /* A plain preference — "be in the mode you are already in" — still
     * does nothing, because yanking a working network for nothing is the
     * behaviour the early return exists to protect. */
    const int connects_after = g_sta_connect;
    CHECK_EQ_INT(app_net_core_set_mode(APP_CONFIG_NET_MODE_STA, 3000), 0);
    CHECK_EQ_INT(g_sta_connect, connects_after);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_FALLBACK_AP);
}

static void test_deferred_apply(void) {
    cfg_erase(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    reset_doubles();
    CHECK_EQ_INT(
        app_net_core_init(&g_ops, NULL, APP_CONFIG_NET_MODE_AP, false, 0), 0);
    app_net_core_on_ap_started(100);

    app_net_pending_cfg_t cfg = {.mode = APP_CONFIG_NET_MODE_STA,
                                 .sta_auth = 1};
    snprintf(cfg.sta_ssid, sizeof cfg.sta_ssid, "Backyard");
    snprintf(cfg.sta_psk, sizeof cfg.sta_psk, "hunter22");
    CHECK_EQ_INT(app_net_core_apply_later(&cfg, 1000), 0);
    CHECK(app_net_core_apply_pending());

    /* Not yet: the HTTP reply is still flushing. */
    app_net_core_tick(1000 + APP_NET_APPLY_DELAY_MS - 1);
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_AP_UP);
    uint8_t mode = 99;
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_NET_MODE, &mode),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(mode, APP_CONFIG_NET_MODE_AP); /* nothing persisted yet */

    /* A second config inside the window supersedes the first. */
    app_net_pending_cfg_t cfg2 = cfg;
    snprintf(cfg2.sta_ssid, sizeof cfg2.sta_ssid, "Garage");
    CHECK_EQ_INT(app_net_core_apply_later(&cfg2, 1200), 0);

    /* The first deadline passes without firing (superseded)... */
    app_net_core_tick(1000 + APP_NET_APPLY_DELAY_MS + 1);
    CHECK(app_net_core_apply_pending());
    /* ...the second fires: persisted AND executed. */
    app_net_core_tick(1200 + APP_NET_APPLY_DELAY_MS + 1);
    CHECK(!app_net_core_apply_pending());
    CHECK_EQ_INT(app_net_core_state(), APP_NET_STATE_STA_CONNECTING);
    char ssid[33] = {0};
    CHECK_EQ_INT(
        app_config_store_get_str(APP_CONFIG_NET_STA_SSID, ssid, sizeof ssid),
        APP_CONFIG_OK);
    CHECK(strcmp(ssid, "Garage") == 0);
}

/* A minimal query for "abc.io", type/class parameterised. */
static size_t make_query(uint8_t *buf, uint16_t qtype, uint16_t qclass) {
    static const uint8_t head[12] = {0x12, 0x34, 0x01, 0x00,
                                     0x00, 0x01, 0, 0, 0, 0, 0, 0};
    memcpy(buf, head, 12);
    size_t p = 12;
    buf[p++] = 3;
    memcpy(buf + p, "abc", 3);
    p += 3;
    buf[p++] = 2;
    memcpy(buf + p, "io", 2);
    p += 2;
    buf[p++] = 0;
    buf[p++] = (uint8_t)(qtype >> 8);
    buf[p++] = (uint8_t)qtype;
    buf[p++] = (uint8_t)(qclass >> 8);
    buf[p++] = (uint8_t)qclass;
    return p;
}

static void test_dns_shim(void) {
    const uint8_t ip[4] = {192, 168, 4, 1};
    uint8_t q[64];
    uint8_t out[DNS_SHIM_MAX_RESPONSE];

    /* A query → one answer with our IP. */
    size_t qlen = make_query(q, 1, 1);
    int n = dns_shim_respond(q, qlen, ip, out, sizeof out);
    CHECK_EQ_INT(n, (int)qlen + 16);
    CHECK_EQ_INT(out[0], 0x12); /* ID echoed */
    CHECK_EQ_INT(out[1], 0x34);
    CHECK(out[2] & 0x80);            /* QR = response */
    CHECK_EQ_INT(out[3] & 0x0F, 0);  /* RCODE 0 */
    CHECK_EQ_INT(out[7], 1);         /* ANCOUNT 1 */
    CHECK(memcmp(out + 12, q + 12, qlen - 12) == 0); /* question echoed */
    CHECK_EQ_INT(out[qlen], 0xC0);   /* name pointer */
    CHECK_EQ_INT(out[qlen + 11], 4); /* RDLENGTH */
    CHECK(memcmp(out + qlen + 12, ip, 4) == 0);

    /* AAAA → empty NOERROR, never NXDOMAIN (some resolvers would fail
     * over to IPv6 and skip us). */
    qlen = make_query(q, 28, 1);
    n = dns_shim_respond(q, qlen, ip, out, sizeof out);
    CHECK_EQ_INT(n, (int)qlen);
    CHECK_EQ_INT(out[3] & 0x0F, 0);
    CHECK_EQ_INT(out[7], 0); /* no answers */

    /* Wrong class → empty NOERROR too. */
    qlen = make_query(q, 1, 3);
    n = dns_shim_respond(q, qlen, ip, out, sizeof out);
    CHECK_EQ_INT(n, (int)qlen);
    CHECK_EQ_INT(out[7], 0);

    /* Malformed: truncated header, a response, zero questions → drop. */
    CHECK_EQ_INT(dns_shim_respond(q, 5, ip, out, sizeof out), -1);
    qlen = make_query(q, 1, 1);
    q[2] |= 0x80;
    CHECK_EQ_INT(dns_shim_respond(q, qlen, ip, out, sizeof out), -1);
    qlen = make_query(q, 1, 1);
    q[5] = 0;
    CHECK_EQ_INT(dns_shim_respond(q, qlen, ip, out, sizeof out), -1);
    /* Truncated mid-name → drop, no read past the end. */
    qlen = make_query(q, 1, 1);
    CHECK_EQ_INT(dns_shim_respond(q, 14, ip, out, sizeof out), -1);
}

static void test_txt_builder(void) {
    app_net_txt_record_t recs[APP_NET_TXT_COUNT];
    app_net_txt_state_t st = {
        .model = "heltec-v3",
        .fw = "1.0.0",
        .probes = 4,
        .paired = true,
        .session_id = 27,
        .sta_mode = true,
    };
    snprintf(st.id, sizeof st.id, "A4F2");
    CHECK_EQ_INT(app_net_txt_build(&st, recs), APP_NET_TXT_COUNT);
    /* The §5.5 table, byte-for-byte. */
    const char *want[APP_NET_TXT_COUNT][2] = {
        {"id", "A4F2"},     {"model", "heltec-v3"}, {"fw", "1.0.0"},
        {"api", "v1"},      {"probes", "4"},        {"paired", "1"},
        {"session", "27"},  {"mode", "sta"},
    };
    for (int i = 0; i < APP_NET_TXT_COUNT; i++) {
        CHECK(strcmp(recs[i].key, want[i][0]) == 0);
        CHECK(strcmp(recs[i].value, want[i][1]) == 0);
    }

    /* Unpaired AP-mode matrix row. */
    st.paired = false;
    st.probes = 0;
    st.session_id = 0;
    st.sta_mode = false;
    app_net_txt_build(&st, recs);
    CHECK(strcmp(recs[5].value, "0") == 0);
    CHECK(strcmp(recs[6].value, "0") == 0);
    CHECK(strcmp(recs[7].value, "ap") == 0);
}

int main(void) {
    test_events_before_init_are_safe(); /* MUST be first: s_ops still NULL */
    test_mode_selection_paths();
    test_sta_success_and_loss();
    test_budget_timeout_and_retry_ladder();
    test_switch_back_guard();
    test_ap_ssid_from_mac();
    test_channel_pick();
    test_deferred_apply();
    test_reprovision_while_already_sta();
    test_dns_shim();
    test_txt_builder();
    return test_summary("test_app_net");
}
