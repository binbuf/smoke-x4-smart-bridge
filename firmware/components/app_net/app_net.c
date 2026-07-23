/* app_net — esp_wifi/esp_netif/mdns glue over the host-tested cores (F8).
 *
 * Everything decision-shaped is in app_net_core; this file translates ops
 * to esp_wifi calls, feeds Wi-Fi/IP events back as core inputs, runs the
 * UDP/53 shim task while the AP is up, and keeps the mDNS TXT records live
 * off the bridge_event bus.
 */
#include "app_net.h"

#include <stdlib.h>
#include <string.h>

#include "app_config_store.h"
#include "bridge_event.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lwip/sockets.h"
#include "mdns.h"

static const char *TAG = "app_net";

/* Mirrors the app_net row of main/tasks.h. */
#define NET_TASK_NAME "app_net"
#define NET_TASK_STACK 3072
#define NET_TASK_PRIO 4
#define NET_TASK_CORE 0

static char s_ap_ssid[APP_NET_SSID_MAX];
static char s_sta_ip[16] = "";
static int8_t s_sta_rssi;
static volatile bool s_dns_run;
static int s_dns_sock = -1;
static esp_timer_handle_t s_tick_timer;

static uint64_t now_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

/* ── core ops ──────────────────────────────────────────────────────────── */

static void dns_task_start(void);
static void dns_task_stop(void);
static void mdns_refresh(void);

static int op_start_ap(void *ctx) {
    (void)ctx;
    /* Channel: least congested of 1/6/11 from a quick scan (§5.3). The
     * scan needs STA started, which APSTA mode gives us anyway. */
    uint8_t counts[13] = {0};
    wifi_scan_config_t scan = {.show_hidden = true};
    if (esp_wifi_scan_start(&scan, true) == ESP_OK) {
        uint16_t n = 0;
        esp_wifi_scan_get_ap_num(&n);
        if (n > 0) {
            wifi_ap_record_t *recs = calloc(n, sizeof *recs);
            if (recs && esp_wifi_scan_get_ap_records(&n, recs) == ESP_OK) {
                for (uint16_t i = 0; i < n; i++) {
                    if (recs[i].primary >= 1 && recs[i].primary <= 13) {
                        counts[recs[i].primary - 1]++;
                    }
                }
            }
            free(recs);
        }
    }
    const uint8_t channel = app_net_pick_channel(counts);

    wifi_config_t cfg = {0};
    snprintf((char *)cfg.ap.ssid, sizeof cfg.ap.ssid, "%s", s_ap_ssid);
    cfg.ap.ssid_len = (uint8_t)strlen(s_ap_ssid);
    char psk[APP_CONFIG_PSK_LEN + 1] = "";
    (void)app_config_store_get_str(APP_CONFIG_NET_AP_PSK, psk, sizeof psk);
    snprintf((char *)cfg.ap.password, sizeof cfg.ap.password, "%s", psk);
    cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
    cfg.ap.channel = channel;
    cfg.ap.max_connection = 4;
    /* The PSK's display surface is the OLED Network page (F11, M5);
     * until that exists the serial console is the device's only screen.
     * Same exposure model either way: physical access reads it. */
    ESP_LOGI(TAG, "AP '%s' on channel %u, PSK '%s'", s_ap_ssid, channel,
             psk);
    if (esp_wifi_set_config(WIFI_IF_AP, &cfg) != ESP_OK) {
        return -1;
    }
    return esp_wifi_set_mode(WIFI_MODE_APSTA) == ESP_OK ? 0 : -1;
}

static int op_stop_ap(void *ctx) {
    (void)ctx;
    dns_task_stop();
    return esp_wifi_set_mode(WIFI_MODE_STA) == ESP_OK ? 0 : -1;
}

static int op_sta_connect(void *ctx) {
    (void)ctx;
    wifi_config_t cfg = {0};
    char ssid[33] = "", psk[65] = "";
    (void)app_config_store_get_str(APP_CONFIG_NET_STA_SSID, ssid,
                                   sizeof ssid);
    (void)app_config_store_get_str(APP_CONFIG_NET_STA_PSK, psk, sizeof psk);
    if (ssid[0] == '\0') {
        return -1;
    }
    /* The wifi fields are raw byte arrays (no NUL required): copy with
     * explicit bounds rather than snprintf's truncation semantics. */
    size_t n = strlen(ssid);
    if (n > sizeof cfg.sta.ssid) {
        n = sizeof cfg.sta.ssid;
    }
    memcpy(cfg.sta.ssid, ssid, n);
    n = strlen(psk);
    if (n > sizeof cfg.sta.password) {
        n = sizeof cfg.sta.password;
    }
    memcpy(cfg.sta.password, psk, n);
    cfg.sta.pmf_cfg.capable = true;
    if (esp_wifi_set_config(WIFI_IF_STA, &cfg) != ESP_OK) {
        return -1;
    }
    return esp_wifi_connect() == ESP_OK ? 0 : -1;
}

static int op_sta_disconnect(void *ctx) {
    (void)ctx;
    (void)esp_wifi_disconnect();
    return 0;
}

static void op_publish(void *ctx, app_net_evt_t evt, const uint8_t ip[4]) {
    (void)ctx;
    bridge_evt_net_t out = {0};
    switch (evt) {
        case APP_NET_EVT_AP_UP:
            out.mode = 1; /* BRIDGE_NET_MODE_AP wire value */
            out.state = 2;
            dns_task_start(); /* the shim runs ONLY while the AP is up */
            break;
        case APP_NET_EVT_STA_UP:
            out.mode = 2;
            out.state = 2;
            if (ip) {
                memcpy(out.ip, ip, 4);
                snprintf(s_sta_ip, sizeof s_sta_ip, "%u.%u.%u.%u", ip[0],
                         ip[1], ip[2], ip[3]);
            }
            break;
        case APP_NET_EVT_STA_LOST:
            out.mode = 2;
            out.state = 3;
            s_sta_ip[0] = '\0';
            break;
        case APP_NET_EVT_FALLBACK:
            out.mode = 1;
            out.state = 1;
            break;
    }
    (void)bridge_event_post(BRIDGE_EVT_NET, &out, sizeof out);
    mdns_refresh();
}

static const app_net_ops_t k_ops = {
    .start_ap = op_start_ap,
    .stop_ap = op_stop_ap,
    .sta_connect = op_sta_connect,
    .sta_disconnect = op_sta_disconnect,
    .publish = op_publish,
};

/* ── Wi-Fi / IP events → core inputs ───────────────────────────────────── */

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id,
                               void *data) {
    (void)arg;
    if (base == WIFI_EVENT) {
        switch (id) {
            case WIFI_EVENT_AP_START:
                app_net_core_on_ap_started(now_ms());
                break;
            case WIFI_EVENT_AP_STACONNECTED:
            case WIFI_EVENT_AP_STADISCONNECTED: {
                wifi_sta_list_t list;
                if (esp_wifi_ap_get_sta_list(&list) == ESP_OK) {
                    app_net_core_on_ap_client_count(list.num);
                }
                break;
            }
            case WIFI_EVENT_STA_DISCONNECTED:
                app_net_core_on_sta_disconnected(now_ms());
                break;
            default:
                break;
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        const ip_event_got_ip_t *e = data;
        uint8_t ip[4];
        memcpy(ip, &e->ip_info.ip.addr, 4);
        app_net_core_on_sta_connected(ip, now_ms());
    }
}

/* ── DNS shim task (F8.5 glue) ─────────────────────────────────────────── */

static void dns_task(void *arg) {
    (void)arg;
    const uint8_t our_ip[4] = {192, 168, 4, 1};
    static uint8_t q[512];
    static uint8_t resp[DNS_SHIM_MAX_RESPONSE];
    struct sockaddr_in from;
    socklen_t from_len;

    s_dns_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_dns_sock >= 0) {
        struct sockaddr_in addr = {
            .sin_family = AF_INET,
            .sin_port = htons(53),
            .sin_addr = {.s_addr = htonl(INADDR_ANY)},
        };
        if (bind(s_dns_sock, (struct sockaddr *)&addr, sizeof addr) != 0) {
            close(s_dns_sock);
            s_dns_sock = -1;
        }
    }
    while (s_dns_run && s_dns_sock >= 0) {
        from_len = sizeof from;
        const int n = recvfrom(s_dns_sock, q, sizeof q, 0,
                               (struct sockaddr *)&from, &from_len);
        if (n <= 0) {
            continue;
        }
        const int rn =
            dns_shim_respond(q, (size_t)n, our_ip, resp, sizeof resp);
        if (rn > 0) {
            (void)sendto(s_dns_sock, resp, (size_t)rn, 0,
                         (struct sockaddr *)&from, from_len);
        }
    }
    if (s_dns_sock >= 0) {
        close(s_dns_sock);
        s_dns_sock = -1;
    }
    vTaskDelete(NULL);
}

static void dns_task_start(void) {
    if (s_dns_run) {
        return;
    }
    s_dns_run = true;
    xTaskCreatePinnedToCore(dns_task, NET_TASK_NAME, NET_TASK_STACK, NULL,
                            NET_TASK_PRIO, NULL, NET_TASK_CORE);
}

static void dns_task_stop(void) {
    s_dns_run = false;
    if (s_dns_sock >= 0) {
        shutdown(s_dns_sock, SHUT_RDWR); /* unblock recvfrom */
    }
}

/* ── mDNS with live TXT (F8.6 glue) ────────────────────────────────────── */

static bool s_mdns_up;

static void mdns_refresh(void) {
    if (!s_mdns_up) {
        return;
    }
    app_net_txt_state_t st = {
        .model = "heltec-v3",
        .fw = "1.0.0",
    };
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(st.id, sizeof st.id, "%02X%02X", mac[4], mac[5]);
    app_config_pairing_t p;
    if (app_config_store_get_pairing(&p) == APP_CONFIG_OK) {
        st.paired = true;
        st.probes = (uint8_t)p.num_probes;
    }
    uint32_t active = 0;
    (void)app_config_store_get_u32(APP_CONFIG_SESSION_ACTIVE_ID, &active);
    st.session_id = active;
    st.sta_mode = app_net_core_state() == APP_NET_STATE_STA_UP;

    app_net_txt_record_t recs[APP_NET_TXT_COUNT];
    const int n = app_net_txt_build(&st, recs);
    mdns_txt_item_t items[APP_NET_TXT_COUNT];
    for (int i = 0; i < n; i++) {
        items[i].key = recs[i].key;
        items[i].value = recs[i].value;
    }
    (void)mdns_service_txt_set("_smokebridge", "_tcp", items, (uint8_t)n);
}

static void on_bus_event(void *arg, esp_event_base_t base, int32_t id,
                         void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    /* Pairing/session transitions change the TXT story (§5.5): rebuild. */
    mdns_refresh();
}

static void mdns_start(void) {
    if (mdns_init() != ESP_OK) {
        ESP_LOGW(TAG, "mdns init failed — discovery degraded, API still up");
        return;
    }
    (void)mdns_hostname_set("smokebridge");
    (void)mdns_service_add(NULL, "_smokebridge", "_tcp", 80, NULL, 0);
    (void)mdns_service_add(NULL, "_http", "_tcp", 80, NULL, 0);
    s_mdns_up = true;
    mdns_refresh();
}

/* ── public surface ────────────────────────────────────────────────────── */

void app_net_note_activity(void) {
    app_net_core_note_client_activity(now_ms());
}

int app_net_request_config(const app_net_pending_cfg_t *cfg) {
    return app_net_core_apply_later(cfg, now_ms());
}

void app_net_set_low_latency(bool on) {
    (void)esp_wifi_set_ps(on ? WIFI_PS_NONE : WIFI_PS_MIN_MODEM);
}

void app_net_get_status(app_net_status_t *out) {
    memset(out, 0, sizeof *out);
    const app_net_state_t st = app_net_core_state();
    const bool sta =
        st == APP_NET_STATE_STA_UP || st == APP_NET_STATE_STA_CONNECTING;
    snprintf(out->mode, sizeof out->mode, "%s", sta ? "sta" : "ap");
    const char *state;
    switch (st) {
        case APP_NET_STATE_STA_UP:
        case APP_NET_STATE_AP_UP:
            state = "up";
            break;
        case APP_NET_STATE_STA_CONNECTING:
            state = "connecting";
            break;
        case APP_NET_STATE_FALLBACK_AP:
            state = "fallback";
            break;
        default:
            state = "starting";
            break;
    }
    snprintf(out->state, sizeof out->state, "%s", state);
    if (sta) {
        char ssid[33] = "";
        (void)app_config_store_get_str(APP_CONFIG_NET_STA_SSID, ssid,
                                       sizeof ssid);
        snprintf(out->ssid, sizeof out->ssid, "%s", ssid);
        wifi_ap_record_t ap;
        if (esp_wifi_sta_get_ap_info(&ap) == ESP_OK) {
            s_sta_rssi = ap.rssi;
        }
        out->rssi = s_sta_rssi;
        snprintf(out->ip, sizeof out->ip, "%s", s_sta_ip);
    } else {
        snprintf(out->ssid, sizeof out->ssid, "%s", s_ap_ssid);
        snprintf(out->ip, sizeof out->ip, "192.168.4.1");
    }
    snprintf(out->host, sizeof out->host, "smokebridge.local");
    wifi_sta_list_t list;
    if (esp_wifi_ap_get_sta_list(&list) == ESP_OK) {
        out->ap_clients = list.num;
    }
}

static void tick_cb(void *arg) {
    (void)arg;
    app_net_core_tick(now_ms());
}

int app_net_start(bool forced_ap) {
    const esp_err_t err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return -1;
    }
    (void)esp_netif_create_default_wifi_ap();
    (void)esp_netif_create_default_wifi_sta();
    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    if (esp_wifi_init(&init) != ESP_OK) {
        return -1;
    }
    (void)esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                     wifi_event_handler, NULL);
    (void)esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                     wifi_event_handler, NULL);

    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    app_net_ap_ssid(mac, s_ap_ssid);

    uint8_t mode = APP_CONFIG_NET_MODE_AP;
    (void)app_config_store_get_u8(APP_CONFIG_NET_MODE, &mode);

    /* APSTA from the start: the fallback ladder retries STA behind a live
     * AP, and the AP path needs STA up for the channel scan. */
    (void)esp_wifi_set_mode(WIFI_MODE_APSTA);
    if (esp_wifi_start() != ESP_OK) {
        return -1;
    }
    (void)esp_wifi_set_ps(WIFI_PS_MIN_MODEM);

    if (app_net_core_init(&k_ops, NULL, mode, forced_ap, now_ms()) != 0) {
        return -1;
    }
    (void)bridge_event_handler_register(BRIDGE_EVT_PAIRING, on_bus_event,
                                        NULL, "net_txt_pairing");
    (void)bridge_event_handler_register(BRIDGE_EVT_SESSION, on_bus_event,
                                        NULL, "net_txt_session");
    mdns_start();

    const esp_timer_create_args_t targs = {.callback = tick_cb,
                                           .name = "app_net_tick"};
    if (esp_timer_create(&targs, &s_tick_timer) == ESP_OK) {
        (void)esp_timer_start_periodic(s_tick_timer, 1000000);
    }
    return 0;
}
