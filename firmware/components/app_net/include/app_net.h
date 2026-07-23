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

#ifdef __cplusplus
}
#endif

#endif /* APP_NET_H */
