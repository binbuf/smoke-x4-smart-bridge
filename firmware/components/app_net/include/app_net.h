/* app_net — device glue for the Wi-Fi state machine (F8). The logic lives
 * in app_net_core/dns_shim/app_net_txt (host-tested); this surface is the
 * esp_wifi/esp_netif/mdns binding plus status for the API. */
#ifndef APP_NET_H
#define APP_NET_H

#include <stdbool.h>
#include <stdint.h>

#include "app_net_core.h"
#include "app_net_txt.h"
#include "dns_shim.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Boot step 12. forced_ap = the §5.2 path-1/2 override for this boot. */
int app_net_start(bool forced_ap);

/* Snapshot for GET /api/v1/status's net section. */
typedef struct {
    char mode[4];  /* "ap" | "sta" */
    char state[12]; /* "up" | "connecting" | "fallback" | "starting" */
    char ssid[33];
    int8_t rssi;   /* STA RSSI; 0 in AP mode */
    char ip[16];
    char host[24];
    int ap_clients;
} app_net_status_t;

void app_net_get_status(app_net_status_t *out);

/* The API layer notes client activity (feeds the switch-back guard) and
 * requests deferred reconfiguration (F8.4). */
void app_net_note_activity(void);
int app_net_request_config(const app_net_pending_cfg_t *cfg);

/* Wi-Fi power save control for the WebSocket path (06 §6.3). */
void app_net_set_low_latency(bool on);

/* ── The BLE provisioning surface (M3: F10.2, F10.6, F10.7) ───────────
 *
 * app_ble needs two things esp_wifi owns and app_net already wraps: a
 * numeric status snapshot, and an on-demand AP scan. Both live here
 * rather than in app_ble so the esp_wifi dependency stays in one
 * component — app_ble reaches the radio only through this seam, which is
 * what keeps its core ESP-IDF-free and host-testable. */

/* The same facts as app_net_status_t, but in the BLE wire's vocabulary:
 * bridge_net_mode_t / bridge_net_state_t values and raw IPv4 octets, so
 * app_ble does no string parsing to build net_status (ble-gatt §5.2). */
typedef struct {
    uint8_t mode;  /* bridge_net_mode_t: 0 off · 1 AP · 2 STA */
    uint8_t state; /* bridge_net_state_t: 0 idle · 1 connecting · 2 up · 3 failed */
    int8_t rssi;
    uint8_t ip[4];
    char ssid[33];
    char host[23];
} app_net_wire_status_t;

void app_net_get_wire_status(app_net_wire_status_t *out);

#define APP_NET_SCAN_MAX 20

typedef struct {
    char ssid[33];
    int8_t rssi;
    uint8_t auth;    /* ESP-IDF wifi_auth_mode_t, which ble-gatt §5.4.1 mirrors */
    uint8_t channel;
} app_net_scan_ap_t;

/* Fired from the Wi-Fi event task when a requested scan finishes. The
 * callee must not block: app_ble posts to its ble_push queue and returns. */
typedef void (*app_net_scan_done_t)(void *ctx);
void app_net_set_scan_done_cb(app_net_scan_done_t cb, void *ctx);

/* Starts an asynchronous scan. Scanning from AP mode is not free on this
 * chip — app_net arranges the temporary APSTA state — so the empirical
 * cost of a mid-AP scan is a named observation for the M3 bench sitting,
 * not a surprise. Returns 0, or -2 (busy) if a scan is already running. */
int app_net_request_scan(void);
int app_net_cancel_scan(void);
/* Drains the last completed scan into `out`; returns the count. */
int app_net_take_scan_results(app_net_scan_ap_t *out, int max);

#ifdef __cplusplus
}
#endif

#endif /* APP_NET_H */
