/* Host tests for app_net_core (F8.1–F8.3): every §5.2 selection path,
 * the §5.4 30 s budget → fallback-AP → 1/2/5/10 min retry ladder, and
 * the switch-back guard that never yanks the network from a client. */
#include <string.h>

#include "app_config_store.h"
#include "app_net_core.h"
#include "test_util.h"

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

int main(void) {
    test_mode_selection_paths();
    test_sta_success_and_loss();
    test_budget_timeout_and_retry_ladder();
    test_switch_back_guard();
    test_ap_ssid_from_mac();
    return test_summary("test_app_net");
}
