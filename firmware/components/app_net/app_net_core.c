/* app_net_core — mode selection and STA supervision (F8.1–F8.3). */
#include "app_net_core.h"

#include <stdio.h>
#include <string.h>

#include "app_config_store.h"

static const app_net_ops_t *s_ops;
static void *s_ctx;

static app_net_state_t s_state;
static uint8_t s_mode; /* the EFFECTIVE mode this boot (forced or stored) */
static bool s_forced_ap;

static uint64_t s_sta_deadline_ms;   /* budget for the current attempt */
static int s_retry_attempt;          /* failed attempts so far */
static uint64_t s_next_retry_ms;     /* when the next attempt fires */
static bool s_retry_in_flight;       /* a background attempt is running */

static int s_ap_clients;
static uint64_t s_last_activity_ms;
static bool s_sta_pending_switch;    /* STA is up behind the AP, waiting
                                        for the quiet guard */
static uint8_t s_pending_ip[4];

static void publish(app_net_evt_t evt, const uint8_t ip[4]) {
    if (s_ops->publish) {
        s_ops->publish(s_ctx, evt, ip);
    }
}

uint32_t app_net_retry_delay_min(int attempt) {
    static const uint32_t ladder[APP_NET_RETRY_LADDER_LEN] = {1, 2, 5, 10};
    if (attempt < 0) {
        attempt = 0;
    }
    if (attempt >= APP_NET_RETRY_LADDER_LEN) {
        attempt = APP_NET_RETRY_LADDER_LEN - 1;
    }
    return ladder[attempt];
}

void app_net_ap_ssid(const uint8_t mac[6], char out[APP_NET_SSID_MAX]) {
    snprintf(out, APP_NET_SSID_MAX, "SmokeBridge-%02X%02X", mac[4], mac[5]);
}

static void start_sta_attempt(uint64_t now_ms) {
    s_sta_deadline_ms = now_ms + APP_NET_STA_BUDGET_MS;
    (void)s_ops->sta_connect(s_ctx);
}

static void engage_fallback(uint64_t now_ms) {
    /* The device is never unreachable: STA failed, bring the AP up and
     * retry behind it on the ladder (§5.4). */
    s_state = APP_NET_STATE_FALLBACK_AP;
    s_retry_in_flight = false;
    s_next_retry_ms =
        now_ms + (uint64_t)app_net_retry_delay_min(s_retry_attempt) * 60000u;
    s_retry_attempt++;
    (void)s_ops->start_ap(s_ctx);
    publish(APP_NET_EVT_FALLBACK, NULL);
}

int app_net_core_init(const app_net_ops_t *ops, void *ctx, uint8_t mode,
                      bool forced_ap, uint64_t now_ms) {
    if (!ops || !ops->start_ap || !ops->stop_ap || !ops->sta_connect ||
        !ops->sta_disconnect) {
        return -1;
    }
    s_ops = ops;
    s_ctx = ctx;
    s_forced_ap = forced_ap;
    s_mode = forced_ap ? APP_CONFIG_NET_MODE_AP : mode;
    s_retry_attempt = 0;
    s_retry_in_flight = false;
    s_ap_clients = 0;
    s_last_activity_ms = now_ms;
    s_sta_pending_switch = false;

    if (s_mode == APP_CONFIG_NET_MODE_STA) {
        s_state = APP_NET_STATE_STA_CONNECTING;
        start_sta_attempt(now_ms);
    } else {
        s_state = APP_NET_STATE_AP_STARTING;
        (void)s_ops->start_ap(s_ctx);
    }
    return 0;
}

app_net_state_t app_net_core_state(void) { return s_state; }

void app_net_core_on_ap_started(uint64_t now_ms) {
    (void)now_ms;
    if (s_state == APP_NET_STATE_AP_STARTING) {
        s_state = APP_NET_STATE_AP_UP;
    }
    /* In FALLBACK_AP the state already says it all. */
    publish(APP_NET_EVT_AP_UP, NULL);
}

void app_net_core_on_sta_connected(const uint8_t ip[4], uint64_t now_ms) {
    if (s_state == APP_NET_STATE_STA_CONNECTING) {
        s_state = APP_NET_STATE_STA_UP;
        s_retry_attempt = 0;
        publish(APP_NET_EVT_STA_UP, ip);
        return;
    }
    if (s_state == APP_NET_STATE_FALLBACK_AP) {
        /* STA recovered behind the AP. Switch back ONLY when nobody is
         * using the AP — yanking the network from a connected phone
         * would be worse than staying put (§5.4). */
        s_retry_in_flight = false;
        s_retry_attempt = 0;
        memcpy(s_pending_ip, ip, 4);
        s_sta_pending_switch = true;
        app_net_core_tick(now_ms); /* may switch immediately */
    }
}

void app_net_core_on_sta_disconnected(uint64_t now_ms) {
    switch (s_state) {
        case APP_NET_STATE_STA_CONNECTING:
            engage_fallback(now_ms);
            break;
        case APP_NET_STATE_STA_UP:
            /* Router rebooted mid-cook: same ladder, same guarantee. */
            publish(APP_NET_EVT_STA_LOST, NULL);
            engage_fallback(now_ms);
            break;
        case APP_NET_STATE_FALLBACK_AP:
            /* A background retry failed; schedule the next one. */
            s_retry_in_flight = false;
            s_sta_pending_switch = false;
            s_next_retry_ms =
                now_ms +
                (uint64_t)app_net_retry_delay_min(s_retry_attempt) * 60000u;
            s_retry_attempt++;
            break;
        default:
            break;
    }
}

void app_net_core_on_ap_client_count(int count) {
    s_ap_clients = count >= 0 ? count : 0;
}

void app_net_core_note_client_activity(uint64_t now_ms) {
    s_last_activity_ms = now_ms;
}

int app_net_core_set_mode(uint8_t mode, uint64_t now_ms) {
    if (mode == s_mode && !s_forced_ap) {
        return 0;
    }
    s_forced_ap = false; /* an explicit choice supersedes the boot force */
    s_mode = mode;
    s_retry_attempt = 0;
    s_sta_pending_switch = false;
    if (mode == APP_CONFIG_NET_MODE_STA) {
        (void)s_ops->stop_ap(s_ctx);
        s_state = APP_NET_STATE_STA_CONNECTING;
        start_sta_attempt(now_ms);
    } else {
        (void)s_ops->sta_disconnect(s_ctx);
        s_state = APP_NET_STATE_AP_STARTING;
        (void)s_ops->start_ap(s_ctx);
    }
    return 0;
}

void app_net_core_tick(uint64_t now_ms) {
    switch (s_state) {
        case APP_NET_STATE_STA_CONNECTING:
            if (now_ms >= s_sta_deadline_ms) {
                (void)s_ops->sta_disconnect(s_ctx);
                engage_fallback(now_ms);
            }
            break;
        case APP_NET_STATE_FALLBACK_AP:
            if (s_sta_pending_switch) {
                /* The §5.4 guard: no station on our AP, and no client
                 * activity for 60 s. */
                if (s_ap_clients == 0 &&
                    now_ms - s_last_activity_ms >= APP_NET_CLIENT_QUIET_MS) {
                    (void)s_ops->stop_ap(s_ctx);
                    s_state = APP_NET_STATE_STA_UP;
                    s_sta_pending_switch = false;
                    publish(APP_NET_EVT_STA_UP, s_pending_ip);
                }
                break;
            }
            if (!s_retry_in_flight && now_ms >= s_next_retry_ms &&
                s_mode == APP_CONFIG_NET_MODE_STA) {
                s_retry_in_flight = true;
                (void)s_ops->sta_connect(s_ctx);
            }
            break;
        default:
            break;
    }
}
