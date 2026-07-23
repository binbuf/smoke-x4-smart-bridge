/* app_net_core — the Wi-Fi mode state machine and STA supervision
 * (F8.1–F8.3, design 05 §5.1–5.4).
 *
 * Pure C11 over injected ops: radio actions, event publication, and the
 * clock all arrive from outside, so every §5.2 selection path and the
 * whole §5.4 backoff/fallback ladder runs in the host suite. The
 * esp_wifi/esp_netif glue stays thin.
 *
 * The one invariant worth stating at the top: the device is NEVER
 * unreachable. STA failure always leaves an AP running, and the switch
 * back to STA never yanks the network out from under an active client.
 */
#ifndef APP_NET_CORE_H
#define APP_NET_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    APP_NET_STATE_OFF = 0,
    APP_NET_STATE_AP_STARTING,
    APP_NET_STATE_AP_UP,
    APP_NET_STATE_STA_CONNECTING,
    APP_NET_STATE_STA_UP,
    /* STA failed: AP is (being brought) up while STA retries behind it. */
    APP_NET_STATE_FALLBACK_AP,
} app_net_state_t;

/* §5.4: 30 s connect budget, then fallback + background retry. */
#define APP_NET_STA_BUDGET_MS (30u * 1000u)
/* Retry ladder in minutes: 1, 2, 5, then 10 forever. */
#define APP_NET_RETRY_LADDER_LEN 4
/* Switch back to STA only after this long with no client activity. */
#define APP_NET_CLIENT_QUIET_MS (60u * 1000u)

typedef enum {
    APP_NET_EVT_AP_UP = 0,     /* payload: none */
    APP_NET_EVT_STA_UP,        /* payload: ip[4] */
    APP_NET_EVT_STA_LOST,      /* connection lost after being up */
    APP_NET_EVT_FALLBACK,      /* STA failed; AP fallback engaged */
} app_net_evt_t;

typedef struct {
    /* All return 0 on success. Async completions come back as inputs. */
    int (*start_ap)(void *ctx);
    int (*stop_ap)(void *ctx);
    int (*sta_connect)(void *ctx);    /* begin an association attempt */
    int (*sta_disconnect)(void *ctx);
    void (*publish)(void *ctx, app_net_evt_t evt, const uint8_t ip[4]);
} app_net_ops_t;

/* mode: APP_CONFIG_NET_MODE_AP / _STA (the stored net/mode value).
 * forced_ap: the §5.2 path-1/2 boot override — AP for THIS boot only;
 * the core never writes the stored mode back. */
int app_net_core_init(const app_net_ops_t *ops, void *ctx, uint8_t mode,
                      bool forced_ap, uint64_t now_ms);

app_net_state_t app_net_core_state(void);

/* ── Inputs from the glue ── */
void app_net_core_on_ap_started(uint64_t now_ms);
void app_net_core_on_sta_connected(const uint8_t ip[4], uint64_t now_ms);
void app_net_core_on_sta_disconnected(uint64_t now_ms);
/* Stations joining/leaving our AP (drives the switch-back guard). */
void app_net_core_on_ap_client_count(int count);
/* Any HTTP/WebSocket activity (drives the switch-back guard). */
void app_net_core_note_client_activity(uint64_t now_ms);

/* Runtime mode change (§5.2 paths 3–5). The caller persists net/mode via
 * app_config_store; the core only executes the transition. */
int app_net_core_set_mode(uint8_t mode, uint64_t now_ms);

/* Drive timers: the STA budget, the retry ladder, the quiet-guard. Call
 * about once a second. */
void app_net_core_tick(uint64_t now_ms);

/* Exposed for tests: minutes until the next retry attempt, given how
 * many failed attempts have happened (index clamps to the ladder end). */
uint32_t app_net_retry_delay_min(int attempt);

/* ── AP parameters (F8.3) ──
 * SSID "SmokeBridge-XXXX" from the last two MAC bytes: stable per device,
 * distinguishable when two are in range (§5.3). */
#define APP_NET_SSID_MAX 32
void app_net_ap_ssid(const uint8_t mac[6], char out[APP_NET_SSID_MAX]);

#ifdef __cplusplus
}
#endif

#endif /* APP_NET_CORE_H */
