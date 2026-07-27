/* app_mqtt.c — the ESP-IDF glue for the MQTT / Home Assistant publisher.
 *
 * Deliberately thin: app_mqtt_core.c decides every topic and every byte of
 * JSON and is host-tested; this file owns the esp-mqtt client, the bus
 * subscriptions, and the run/stop lifecycle.
 *
 * Two rules keep it off the 5 ms bridge_event handler guard (03 §3.2):
 *   1. The device snapshot `s_state` is updated by handlers with plain field
 *      writes — near-atomic, and a torn read only costs one stale publish.
 *   2. A publish takes `s_lock` with a **zero timeout** and skips if it cannot
 *      get it, so a handler never blocks behind the one slow operation
 *      (esp_mqtt_client_stop), which runs only from the httpd reconfigure path.
 *
 * `esp_mqtt_client_start()` is non-blocking (it spawns esp-mqtt's own task and
 * returns), so bringing the client up when STA comes up is safe from the event
 * loop; tearing it down is not, so that happens only on a config change.
 */
#include "app_mqtt.h"

#include <string.h>

#include "esp_log.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mqtt_client.h"

#include "app_config_store.h"
#include "app_mqtt_core.h"
#include "app_net_core.h"
#include "bridge_event.h"
#include "record_gen.h"

static const char *TAG = "app_mqtt";

static SemaphoreHandle_t s_lock;
static esp_mqtt_client_handle_t s_client;
static volatile bool s_connected;

static bool s_enabled;
static uint8_t s_ha_disc = 1;
static uint16_t s_port = 1883;
static char s_host[65];
static char s_user[65];
static char s_pass[65];
static char s_prefix[33];
static char s_state_topic[48];
static char s_avail_topic[48];
static char s_node[APP_NET_SSID_MAX + 1];
static char s_name[APP_NET_SSID_MAX + 1];

static app_mqtt_state_t s_state;

/* ── config ─────────────────────────────────────────────────────────── */

static void read_config(void) {
    uint8_t en = 0;
    uint8_t ha = 1;
    (void)app_config_store_get_u8(APP_CONFIG_MQTT_ENABLED, &en);
    (void)app_config_store_get_u8(APP_CONFIG_MQTT_HA_DISCOVERY, &ha);
    s_enabled = en != 0;
    s_ha_disc = ha;

    uint16_t port = 1883;
    (void)app_config_store_get_u16(APP_CONFIG_MQTT_PORT, &port);
    s_port = port;

    s_host[0] = s_user[0] = s_pass[0] = s_prefix[0] = '\0';
    (void)app_config_store_get_str(APP_CONFIG_MQTT_HOST, s_host, sizeof s_host);
    (void)app_config_store_get_str(APP_CONFIG_MQTT_USER, s_user, sizeof s_user);
    (void)app_config_store_get_str(APP_CONFIG_MQTT_PASS, s_pass, sizeof s_pass);
    (void)app_config_store_get_str(APP_CONFIG_MQTT_PREFIX, s_prefix,
                                   sizeof s_prefix);
    if (s_prefix[0] == '\0') {
        strlcpy(s_prefix, "smokebridge", sizeof s_prefix);
    }
    (void)app_mqtt_core_state_topic(s_prefix, s_state_topic,
                                    sizeof s_state_topic);
    (void)app_mqtt_core_avail_topic(s_prefix, s_avail_topic,
                                    sizeof s_avail_topic);
}

/* The stable HA identity, MAC-derived so a reflash keeps the same entities.
 * The AP SSID ("SmokeBridge-A4F2") is the same name every transport shows;
 * the node id is its lowercase, underscore form. */
static void compute_identity(void) {
    uint8_t mac[6] = {0};
    (void)esp_wifi_get_mac(WIFI_IF_STA, mac);
    char ssid[APP_NET_SSID_MAX] = {0};
    app_net_ap_ssid(mac, ssid);
    strlcpy(s_name, ssid, sizeof s_name);
    size_t i = 0;
    for (; ssid[i] != '\0' && i < sizeof s_node - 1; i++) {
        char c = ssid[i];
        if (c == '-') {
            c = '_';
        } else if (c >= 'A' && c <= 'Z') {
            c = (char)(c + 32);
        }
        s_node[i] = c;
    }
    s_node[i] = '\0';
}

/* ── publishing (assumes a live client) ─────────────────────────────── */

static void publish_state(esp_mqtt_client_handle_t c) {
    char buf[192];
    if (app_mqtt_core_build_state(&s_state, buf, sizeof buf) < 0) {
        return;
    }
    (void)esp_mqtt_client_enqueue(c, s_state_topic, buf, 0, 0, 1, true);
}

static void publish_discovery(esp_mqtt_client_handle_t c) {
    if (!s_ha_disc) {
        return;
    }
    char topic[96];
    char payload[512];
    for (int i = 0;; i++) {
        int r = app_mqtt_core_discovery(i, s_prefix, s_node, s_name,
                                        s_state.num_probes, topic, sizeof topic,
                                        payload, sizeof payload);
        if (r == 0) {
            break; /* past the last entity */
        }
        if (r < 0) {
            continue; /* one doc did not fit — skip it, keep going */
        }
        (void)esp_mqtt_client_enqueue(c, topic, payload, 0, 0, 1, true);
    }
}

static void publish_all(esp_mqtt_client_handle_t c) {
    publish_discovery(c);
    (void)esp_mqtt_client_enqueue(c, s_avail_topic, "online", 0, 1, 1, true);
    publish_state(c);
}

/* Non-blocking publish from a bus handler: skip rather than block behind a
 * reconfigure. */
static void try_publish_state(void) {
    if (xSemaphoreTake(s_lock, 0) != pdTRUE) {
        return;
    }
    if (s_client != NULL && s_connected) {
        publish_state(s_client);
    }
    (void)xSemaphoreGive(s_lock);
}

/* ── esp-mqtt event handler (runs on esp-mqtt's own task) ────────────── */

static void mqtt_event_handler(void *args, esp_event_base_t base, int32_t id,
                               void *data) {
    (void)args;
    (void)base;
    esp_mqtt_event_handle_t e = data;
    switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
        s_connected = true;
        /* Inside the client's own callback the handle cannot be destroyed, so
         * this needs no lock. */
        publish_all(e->client);
        ESP_LOGI(TAG, "connected; published discovery + state");
        break;
    case MQTT_EVENT_DISCONNECTED:
        s_connected = false;
        break;
    default:
        break;
    }
}

/* ── lifecycle ──────────────────────────────────────────────────────── */

static bool sta_up(void) {
    return app_net_core_state() == APP_NET_STATE_STA_UP;
}

/* Caller holds s_lock. Non-blocking. */
static void start_client_locked(void) {
    if (s_client != NULL || s_host[0] == '\0') {
        return;
    }
    char uri[96];
    snprintf(uri, sizeof uri, "mqtt://%s:%u", s_host, (unsigned)s_port);

    esp_mqtt_client_config_t cfg = {0};
    cfg.broker.address.uri = uri;
    if (s_user[0] != '\0') {
        cfg.credentials.username = s_user;
    }
    if (s_pass[0] != '\0') {
        cfg.credentials.authentication.password = s_pass;
    }
    cfg.session.last_will.topic = s_avail_topic;
    cfg.session.last_will.msg = "offline";
    cfg.session.last_will.msg_len = 0; /* 0 → strlen */
    cfg.session.last_will.qos = 1;
    cfg.session.last_will.retain = true;
    /* Heap mitigations (05 §5.7): trim the outbox and the mqtt_task stack. */
    cfg.buffer.size = 1024;
    cfg.buffer.out_size = 512;
    cfg.task.stack_size = 4096;

    s_client = esp_mqtt_client_init(&cfg);
    if (s_client == NULL) {
        ESP_LOGE(TAG, "client init failed");
        return;
    }
    (void)esp_mqtt_client_register_event(s_client, MQTT_EVENT_ANY,
                                         mqtt_event_handler, NULL);
    if (esp_mqtt_client_start(s_client) != ESP_OK) {
        esp_mqtt_client_destroy(s_client);
        s_client = NULL;
        ESP_LOGE(TAG, "client start failed");
        return;
    }
    ESP_LOGI(TAG, "started → %s", uri);
}

/* Caller holds s_lock. Blocking — only ever called from the httpd reconfigure
 * path, never from a bus handler. */
static void stop_client_locked(void) {
    if (s_client == NULL) {
        return;
    }
    if (s_connected) {
        /* Say goodbye gracefully; the LWT only fires on an ungraceful drop. */
        (void)esp_mqtt_client_enqueue(s_client, s_avail_topic, "offline", 0, 1,
                                      1, true);
    }
    (void)esp_mqtt_client_stop(s_client);
    (void)esp_mqtt_client_destroy(s_client);
    s_client = NULL;
    s_connected = false;
    ESP_LOGI(TAG, "stopped");
}

/* Opportunistic, non-blocking: bring the client up if wanted. Safe from a bus
 * handler — start is non-blocking, and the try-lock never stalls. */
static void ensure_started(void) {
    if (!s_enabled || s_client != NULL || !sta_up() || s_host[0] == '\0') {
        return;
    }
    if (xSemaphoreTake(s_lock, 0) != pdTRUE) {
        return; /* a reconfigure is in flight; the next sample retries */
    }
    start_client_locked();
    (void)xSemaphoreGive(s_lock);
}

/* ── bus handlers: field-write the snapshot, then publish/ensure ─────── */

static void on_sample(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    const bridge_evt_sample_t *e = data;
    if (e == NULL) {
        return;
    }
    for (int i = 0; i < 4; i++) {
        s_state.temp_f10[i] = e->temp_f10[i];
    }
    s_state.num_probes = e->num_probes;
    s_state.lora_rssi = e->rssi;
    ensure_started();
    try_publish_state();
}

static void on_net(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    (void)data;
    ensure_started(); /* STA may have just come up */
    try_publish_state();
}

static void on_power(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    const bridge_evt_power_t *e = data;
    if (e == NULL) {
        return;
    }
    s_state.soc_pct = e->soc_pct;
    s_state.charging = e->charging;
    try_publish_state();
}

static void on_session(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    const bridge_evt_session_t *e = data;
    if (e == NULL) {
        return;
    }
    s_state.session_active = e->action == BRIDGE_SESSION_STARTED;
    s_state.session_id = e->session_id;
    try_publish_state();
}

static void on_base_lost(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    (void)data;
    s_state.base_lost = true;
    try_publish_state();
}

static void on_base_found(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    (void)data;
    s_state.base_lost = false;
    try_publish_state();
}

static void on_pairing(void *a, esp_event_base_t b, int32_t id, void *data) {
    (void)a;
    (void)b;
    (void)id;
    const bridge_evt_pairing_t *e = data;
    if (e == NULL) {
        return;
    }
    s_state.paired = e->state == BRIDGE_PAIRING_PAIRED;
}

/* ── public API ─────────────────────────────────────────────────────── */

int app_mqtt_init(void) {
    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) {
        return -1;
    }

    for (int i = 0; i < 4; i++) {
        s_state.temp_f10[i] = BRIDGE_TEMP_DETACHED;
    }
    s_state.num_probes = 4;
    s_state.soc_pct = BRIDGE_SOC_UNKNOWN;

    read_config();
    compute_identity();

    if (bridge_event_handler_register(BRIDGE_EVT_SAMPLE, on_sample, NULL,
                                      "app_mqtt.sample") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_NET, on_net, NULL,
                                      "app_mqtt.net") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_POWER, on_power, NULL,
                                      "app_mqtt.power") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_SESSION, on_session, NULL,
                                      "app_mqtt.session") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_BASE_LOST, on_base_lost, NULL,
                                      "app_mqtt.base_lost") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_BASE_FOUND, on_base_found,
                                      NULL, "app_mqtt.base_found") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_PAIRING, on_pairing, NULL,
                                      "app_mqtt.pairing") != ESP_OK) {
        return -1;
    }

    /* Start now if STA is already up; otherwise on_net brings it up. */
    ensure_started();
    ESP_LOGI(TAG, "up: %s%s", s_enabled ? "enabled" : "disabled",
             s_enabled && s_host[0] == '\0' ? " (no broker set)" : "");
    return 0;
}

bool app_mqtt_is_connected(void) { return s_connected; }

void app_mqtt_reconfigure(void) {
    if (s_lock == NULL) {
        return;
    }
    read_config();
    /* Blocking is fine here — this runs on the httpd task, never a bus
     * handler. A full restart picks up new credentials/host/prefix. */
    (void)xSemaphoreTake(s_lock, portMAX_DELAY);
    stop_client_locked();
    if (app_mqtt_core_should_run(s_enabled, sta_up())) {
        start_client_locked();
    }
    (void)xSemaphoreGive(s_lock);
}
