/* app_ble.c — NimBLE host glue (F10.4) plus bonding, the security
 * profile, and the passkey display path (F10.5).
 *
 * Deliberately thin. Everything decidable without a radio — the registry,
 * the security predicate, every payload, the chunker, the write dispatch —
 * is in app_ble_core.c with 649 host assertions around it. What is left
 * here is the part only a board can prove, which is exactly the part the
 * M3 bench sitting is for.
 *
 * THE STRUCTURAL RULE OF THIS FILE (F10.4, learned from ws_push in M2):
 * notification fan-out runs on its OWN `ble_push` row. Never on the event
 * loop — a 5 ms handler budget (03 §3.2) does not survive an ATT write —
 * and never on the NimBLE host task, whose stack belongs to the stack.
 */
#include "app_ble.h"

#include <string.h>

#include "esp_bt.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "app_ble_core.h"
#include "app_config_store.h"
#include "app_net.h"
#include "bridge_event.h"
#include "esp_app_desc.h"
#include "esp_wifi.h"

static const char *TAG = "app_ble";

/* Mirrors the ble_push row of main/tasks.h (see app_ui.c for why a copy).
 * 4 KB, not 3 KB, is F10.4's argued decision — the analogous ws_push row
 * overflowed at 3072 on the board. */
#define BLE_PUSH_TASK_NAME "ble_push"
#define BLE_PUSH_TASK_STACK 4096
#define BLE_PUSH_TASK_PRIO 4
#define BLE_PUSH_TASK_CORE 0

/* ble_store_config's own init hook (components/bt/host/nimble/esp-hci). */
void ble_store_config_init(void);

static uint8_t s_own_addr_type;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_val_handles[APP_BLE_CH_COUNT];
static QueueHandle_t s_push_q;
static TaskHandle_t s_push_task;

/* What the ble_push row is asked to send. */
typedef enum {
    PUSH_LIVE_STATE = 0,
    PUSH_NET_STATUS,
    PUSH_SCAN_RESULTS,
} push_kind_t;

typedef struct {
    uint8_t kind;
} push_msg_t;

/* ── the core's ops ───────────────────────────────────────────────── */

static void op_sysinfo(app_ble_sysinfo_t *out) {
    memset(out, 0, sizeof *out);
    uint8_t mac[6] = {0};
    (void)esp_wifi_get_mac(WIFI_IF_STA, mac);
    memcpy(out->mac, mac, sizeof mac);
    snprintf(out->id, sizeof out->id, "%02X%02X", mac[4], mac[5]);
    out->model = "heltec-v3";
    const esp_app_desc_t *desc = esp_app_get_description();
    out->fw = desc != NULL ? desc->version : "0.0.0";
    uint8_t probes = 4;
    app_config_pairing_t pairing;
    if (app_config_store_get_pairing(&pairing) == APP_CONFIG_OK &&
        pairing.num_probes != 0) {
        probes = pairing.num_probes;
    }
    out->probes = probes;
    /* wifi_ap | wifi_sta | history_preview. `ota` (b4) lights up in F14,
     * `battery` (b5) in F12 — advertised honestly, never aspirationally
     * (ble-gatt §5.1.1). */
    out->caps = (1u << 0) | (1u << 1) | (1u << 3);
}

static void op_net_status(app_ble_net_snapshot_t *out) {
    /* app_net owns esp_wifi; app_ble reaches the radio only through that
     * seam, which is what keeps app_ble_core ESP-IDF-free. The two structs
     * are deliberately separate types with the same shape — a copy, not a
     * shared header, so neither component pulls in the other's contract. */
    app_net_wire_status_t s;
    app_net_get_wire_status(&s);
    memset(out, 0, sizeof *out);
    out->mode = s.mode;
    out->state = s.state;
    out->rssi = s.rssi;
    memcpy(out->ip, s.ip, sizeof out->ip);
    snprintf(out->ssid, sizeof out->ssid, "%s", s.ssid);
    snprintf(out->host, sizeof out->host, "%s", s.host);
}

static int op_net_request_config(const app_net_pending_cfg_t *cfg) {
    return app_net_request_config(cfg);
}

static int op_scan_start(void) { return app_net_request_scan(); }
static int op_scan_cancel(void) { return app_net_cancel_scan(); }

static int op_notify(app_ble_char_t ch, const uint8_t *buf, size_t len) {
    if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE ||
        ch < 0 || ch >= APP_BLE_CH_COUNT) {
        return -1;
    }
    struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, (uint16_t)len);
    if (om == NULL) {
        return -1;
    }
    return ble_gatts_notify_custom(s_conn_handle, s_val_handles[ch], om);
}

static int op_identify(void) {
    /* Wakes the display and flashes what exists; the LED driver is M5's
     * F11b. Partial by design, and said so in the task plan. */
    app_ble_note_activity();
    return 0;
}

static void op_reboot(void) { esp_restart(); }

static int op_factory_reset(void) {
    /* Both halves, because they live in different NVS namespaces — the
     * obligation attached to the 03 §3.6.1 exception. */
    (void)app_ble_forget_bonds();
    return app_config_store_factory_reset() == APP_CONFIG_OK ? 0 : -1;
}

static uint64_t op_uptime_ms(void) { return (uint64_t)esp_log_timestamp(); }

static const app_ble_ops_t k_ops = {
    .sysinfo = op_sysinfo,
    .net_status = op_net_status,
    .net_request_config = op_net_request_config,
    .scan_start = op_scan_start,
    .scan_cancel = op_scan_cancel,
    .notify = op_notify,
    .identify = op_identify,
    .reboot = op_reboot,
    .factory_reset = op_factory_reset,
    .uptime_ms = op_uptime_ms,
};

/* ── GATT access ──────────────────────────────────────────────────── */

static app_ble_link_t link_state(uint16_t conn_handle) {
    app_ble_link_t link = {0};
    struct ble_gap_conn_desc desc;
    if (ble_gap_conn_find(conn_handle, &desc) == 0) {
        link.encrypted = desc.sec_state.encrypted;
        link.authenticated = desc.sec_state.authenticated;
    }
    return link;
}

static int gatt_access(uint16_t conn_handle, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg) {
    (void)attr_handle;
    const app_ble_char_t ch = (app_ble_char_t)(intptr_t)arg;
    const app_ble_link_t link = link_state(conn_handle);

    /* The stack enforces the declared permission bits too; this is the
     * belt to that pair of braces, and it is the layer the host suite
     * tests, so the two can never drift. */
    if (!app_ble_access_allowed(ch, &link)) {
        return BLE_ATT_ERR_INSUFFICIENT_AUTHEN;
    }

    switch (ctxt->op) {
    case BLE_GATT_ACCESS_OP_READ_CHR: {
        uint8_t buf[BRIDGE_HISTORY_PREVIEW_MAX_SIZE];
        const int len = app_ble_core_read(ch, buf, sizeof buf);
        if (len < 0) {
            return BLE_ATT_ERR_UNLIKELY;
        }
        /* Read Blob is the stack's job from here (§4). */
        return os_mbuf_append(ctxt->om, buf, (uint16_t)len) == 0
                   ? 0
                   : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    case BLE_GATT_ACCESS_OP_WRITE_CHR: {
        uint8_t buf[BRIDGE_WIFI_CONFIG_MAX_SIZE];
        uint16_t len = 0;
        /* Long writes arrive already reassembled by Prepare/Execute. */
        if (ble_hs_mbuf_to_flat(ctxt->om, buf, sizeof buf, &len) != 0) {
            (void)app_ble_core_write(ch, &link, buf, sizeof buf + 1);
            return 0; /* the core answered `invalid` on `result` */
        }
        (void)app_ble_core_write(ch, &link, buf, len);
        return 0;
    }
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

/* One entry per characteristic, generated from the core's registry so the
 * UUIDs, properties, and security levels have exactly one definition. */
static ble_uuid128_t s_uuids[APP_BLE_CH_COUNT + 1];
static struct ble_gatt_chr_def s_chr_defs[APP_BLE_CH_COUNT + 1];
static struct ble_gatt_svc_def s_svc_defs[2];

static void build_service_table(void) {
    app_ble_uuid128(APP_BLE_SERVICE_UUID16, s_uuids[APP_BLE_CH_COUNT].value);
    s_uuids[APP_BLE_CH_COUNT].u.type = BLE_UUID_TYPE_128;

    for (int i = 0; i < APP_BLE_CH_COUNT; i++) {
        const app_ble_char_def_t *def = app_ble_char_def((app_ble_char_t)i);
        app_ble_uuid128(def->uuid16, s_uuids[i].value);
        s_uuids[i].u.type = BLE_UUID_TYPE_128;

        ble_gatt_chr_flags flags = 0;
        if (def->props & APP_BLE_PROP_READ) {
            flags |= BLE_GATT_CHR_F_READ;
            if (def->sec == APP_BLE_SEC_ENCRYPTED) {
                flags |= BLE_GATT_CHR_F_READ_ENC;
            } else if (def->sec == APP_BLE_SEC_AUTHENTICATED) {
                flags |= BLE_GATT_CHR_F_READ_ENC | BLE_GATT_CHR_F_READ_AUTHEN;
            }
        }
        if (def->props & APP_BLE_PROP_WRITE) {
            flags |= BLE_GATT_CHR_F_WRITE;
            if (def->sec == APP_BLE_SEC_ENCRYPTED) {
                flags |= BLE_GATT_CHR_F_WRITE_ENC;
            } else if (def->sec == APP_BLE_SEC_AUTHENTICATED) {
                flags |= BLE_GATT_CHR_F_WRITE_ENC | BLE_GATT_CHR_F_WRITE_AUTHEN;
            }
        }
        if (def->props & APP_BLE_PROP_NOTIFY) {
            flags |= BLE_GATT_CHR_F_NOTIFY;
        }

        s_chr_defs[i] = (struct ble_gatt_chr_def){
            .uuid = &s_uuids[i].u,
            .access_cb = gatt_access,
            .arg = (void *)(intptr_t)i,
            .flags = flags,
            .val_handle = &s_val_handles[i],
        };
    }
    s_svc_defs[0] = (struct ble_gatt_svc_def){
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_uuids[APP_BLE_CH_COUNT].u,
        .characteristics = s_chr_defs,
    };
}

/* ── advertising ──────────────────────────────────────────────────── */

static int gap_event(struct ble_gap_event *event, void *arg);

static void start_advertising(void) {
    uint8_t adv[APP_BLE_ADV_MAX];
    uint8_t rsp[APP_BLE_ADV_MAX];
    const int adv_len = app_ble_build_adv(adv, sizeof adv);
    const int rsp_len = app_ble_build_scan_rsp(rsp, sizeof rsp);
    if (adv_len < 0 || rsp_len < 0) {
        ESP_LOGE(TAG, "advertising payload build failed");
        return;
    }
    (void)ble_gap_adv_set_data(adv, adv_len);
    (void)ble_gap_adv_rsp_set_data(rsp, rsp_len);

    const uint16_t interval_ms = app_ble_adv_interval_ms(op_uptime_ms());
    struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
        /* NimBLE counts advertising intervals in 0.625 ms units. */
        .itvl_min = (uint16_t)(interval_ms * 8 / 5),
        .itvl_max = (uint16_t)(interval_ms * 8 / 5),
    };
    (void)ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &params,
                            gap_event, NULL);
}

void app_ble_note_activity(void) {
    app_ble_adv_note_fast(op_uptime_ms());
    if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        (void)ble_gap_adv_stop();
        start_advertising();
    }
}

/* ── GAP events, bonding, and the passkey (F10.5) ─────────────────── */

static void publish_ble(uint8_t action, uint32_t passkey) {
    const bridge_evt_ble_t evt = {
        .action = action,
        .passkey = passkey,
        .conns = s_conn_handle == BLE_HS_CONN_HANDLE_NONE ? 0 : 1,
        .bonds = app_ble_bond_count(),
    };
    (void)bridge_event_post(BRIDGE_EVT_BLE, &evt, sizeof evt);
}

static void refresh_bond_count(void) {
    int count = 0;
    (void)ble_store_util_count(BLE_STORE_OBJ_TYPE_OUR_SEC, &count);
    app_ble_set_bond_count((uint8_t)count);
}

static int gap_event(struct ble_gap_event *event, void *arg) {
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_conn_handle = event->connect.conn_handle;
            /* We are peripheral-only, so we do not INITIATE the MTU
             * exchange — the central does, and ble-gatt §4's "request 247"
             * is the client's half (A6.3). Our half is to OFFER 247, which
             * CONFIG_BT_NIMBLE_ATT_PREFERRED_MTU does, and then to use
             * whatever comes back on BLE_GAP_EVENT_MTU. Accepting reality
             * rather than assuming it is the whole R7 mitigation. */
            publish_ble(BRIDGE_BLE_CONNECTED, 0);
        } else {
            start_advertising();
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        app_ble_set_mtu(APP_BLE_MTU_DEFAULT);
        app_ble_passkey_clear();
        publish_ble(BRIDGE_BLE_DISCONNECTED, 0);
        start_advertising();
        return 0;

    case BLE_GAP_EVENT_MTU:
        app_ble_set_mtu(event->mtu.value);
        ESP_LOGI(TAG, "negotiated ATT MTU %u (chunk %u)",
                 (unsigned)app_ble_mtu(), (unsigned)app_ble_notify_chunk());
        return 0;

    case BLE_GAP_EVENT_PASSKEY_ACTION: {
        if (event->passkey.params.action != BLE_SM_IOACT_DISP) {
            return 0; /* DisplayOnly never asks for input or confirmation */
        }
        /* The fourth phone is refused until a slot is freed (§3). The
         * check is here, before a key is displayed, so the user is not
         * asked to type a code that was never going to be accepted. */
        refresh_bond_count();
        if (!app_ble_bond_slot_available()) {
            ESP_LOGW(TAG, "bond slots full (%u) — refusing pairing",
                     (unsigned)app_ble_bond_count());
            (void)ble_gap_terminate(event->passkey.conn_handle,
                                    BLE_ERR_REM_USER_CONN_TERM);
            return 0;
        }
        struct ble_sm_io io = {.action = BLE_SM_IOACT_DISP};
        io.passkey = esp_random() % 1000000u;
        app_ble_passkey_set(io.passkey);
        /* app_ui subscribes to this and draws the §7.3 overlay; app_ble
         * never learns that a display exists. */
        publish_ble(BRIDGE_BLE_PASSKEY_SHOW, app_ble_passkey());
        (void)ble_sm_inject_io(event->passkey.conn_handle, &io);
        return 0;
    }

    case BLE_GAP_EVENT_ENC_CHANGE:
        /* Bonded, failed, or timed out — every one of them clears the
         * code off the glass. */
        app_ble_passkey_clear();
        refresh_bond_count();
        publish_ble(event->enc_change.status == 0 ? BRIDGE_BLE_BONDED
                                                  : BRIDGE_BLE_PASSKEY_CLEAR,
                    0);
        return 0;

    case BLE_GAP_EVENT_REPEAT_PAIRING:
        /* The peer lost our key. Delete the stale bond and let pairing
         * proceed, which is what turns "it just won't connect" into a
         * re-bond (the client half is A6.4's typed condition). */
        {
            struct ble_gap_conn_desc desc;
            if (ble_gap_conn_find(event->repeat_pairing.conn_handle, &desc) ==
                0) {
                (void)ble_store_util_delete_peer(&desc.peer_id_addr);
            }
        }
        refresh_bond_count();
        return BLE_GAP_REPEAT_PAIRING_RETRY;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        start_advertising();
        return 0;

    default:
        return 0;
    }
}

int app_ble_forget_bonds(void) {
    const int rc = ble_store_clear();
    app_ble_set_bond_count(0);
    return rc;
}

void app_ble_link_status(bool *advertising, uint8_t *connections,
                         uint8_t *bonded) {
    if (advertising) {
        /* Ask NimBLE rather than tracking a shadow flag: advertising also
         * stops on its own when a central connects. */
        *advertising = ble_gap_adv_active() != 0;
    }
    if (connections) {
        *connections = s_conn_handle == BLE_HS_CONN_HANDLE_NONE ? 0 : 1;
    }
    if (bonded) {
        *bonded = app_ble_bond_count();
    }
}

/* ── the ble_push row (F10.4) ─────────────────────────────────────── */

static void ble_push_task(void *arg) {
    (void)arg;
    push_msg_t msg;
    for (;;) {
        if (xQueueReceive(s_push_q, &msg, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
            continue;
        }
        switch (msg.kind) {
        case PUSH_LIVE_STATE:
            (void)app_ble_notify_live_state();
            break;
        case PUSH_NET_STATUS:
            (void)app_ble_notify_net_status();
            /* A network transition also changes the advertised blob. */
            if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
                start_advertising();
            }
            break;
        case PUSH_SCAN_RESULTS: {
            app_net_scan_ap_t raw[APP_NET_SCAN_MAX];
            const int n = app_net_take_scan_results(raw, APP_NET_SCAN_MAX);
            app_ble_scan_ap_t aps[APP_NET_SCAN_MAX];
            for (int i = 0; i < n; i++) {
                memset(&aps[i], 0, sizeof aps[i]);
                snprintf(aps[i].ssid, sizeof aps[i].ssid, "%s", raw[i].ssid);
                aps[i].rssi = raw[i].rssi;
                /* ESP-IDF's wifi_auth_mode_t is what ble-gatt §5.4.1
                 * mirrors, so this is a copy, not a mapping table. */
                aps[i].auth = raw[i].auth;
                aps[i].channel = raw[i].channel;
            }
            (void)app_ble_scan_deliver(aps, n);
            break;
        }
        default:
            break;
        }
    }
}

static void enqueue(push_kind_t kind) {
    if (s_push_q == NULL) {
        return;
    }
    const push_msg_t msg = {.kind = (uint8_t)kind};
    /* Non-blocking from an event handler, always: the 03 §3.2 duration
     * guard is the whole reason this queue exists. */
    (void)xQueueSend(s_push_q, &msg, 0);
}

static void on_sample(void *arg, esp_event_base_t base, int32_t id,
                      void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    enqueue(PUSH_LIVE_STATE);
}

static void on_alarm(void *arg, esp_event_base_t base, int32_t id,
                     void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    /* Immediately on any alarm transition, not on the next sample. Wired
     * now so F13 (M5) changes nothing in app_ble. */
    enqueue(PUSH_LIVE_STATE);
}

static void on_net(void *arg, esp_event_base_t base, int32_t id, void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    enqueue(PUSH_NET_STATUS);
}

/* Fired by app_net from the Wi-Fi event task; all it may do is post. */
static void on_scan_done(void *ctx) {
    (void)ctx;
    enqueue(PUSH_SCAN_RESULTS);
}

/* ── init ─────────────────────────────────────────────────────────── */

static void on_sync(void) {
    (void)ble_hs_util_ensure_addr(0);
    if (ble_hs_id_infer_auto(0, &s_own_addr_type) != 0) {
        ESP_LOGE(TAG, "no usable BLE identity address");
        return;
    }
    refresh_bond_count();
    /* 250 ms for 60 s after a fresh boot (§2). */
    app_ble_adv_note_fast(op_uptime_ms());
    start_advertising();
}

static void on_reset(int reason) {
    ESP_LOGE(TAG, "NimBLE host reset, reason %d", reason);
}

static void host_task(void *param) {
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

int app_ble_init(void) {
    if (app_ble_core_init(&k_ops) != APP_BLE_OK) {
        return -1;
    }
    if (nimble_port_init() != ESP_OK) {
        return -1;
    }

    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    /* DisplayOnly + MITM + Secure Connections + bonding: the four flags
     * that together mean "the six digits on the OLED are load-bearing"
     * (§3). Dropping any one of them silently downgrades to Just Works. */
    ble_hs_cfg.sm_io_cap = BLE_HS_IO_DISPLAY_ONLY;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_mitm = 1;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_our_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;

    build_service_table();
    ble_svc_gap_init();
    ble_svc_gatt_init();
    if (ble_gatts_count_cfg(s_svc_defs) != 0 ||
        ble_gatts_add_svcs(s_svc_defs) != 0) {
        return -1;
    }

    uint8_t mac[6] = {0};
    (void)esp_wifi_get_mac(WIFI_IF_STA, mac);
    char name[APP_BLE_NAME_MAX];
    app_ble_local_name(mac, name);
    if (ble_svc_gap_device_name_set(name) != 0) {
        return -1;
    }

    /* NimBLE's own NVS namespace — the documented 03 §3.6.1 exception. */
    ble_store_config_init();

    s_push_q = xQueueCreate(8, sizeof(push_msg_t));
    if (s_push_q == NULL) {
        return -1;
    }
    if (xTaskCreatePinnedToCore(ble_push_task, BLE_PUSH_TASK_NAME,
                                BLE_PUSH_TASK_STACK, NULL, BLE_PUSH_TASK_PRIO,
                                &s_push_task, BLE_PUSH_TASK_CORE) != pdPASS) {
        return -1;
    }

    (void)bridge_event_handler_register(BRIDGE_EVT_SAMPLE, on_sample, NULL,
                                        "app_ble.sample");
    (void)bridge_event_handler_register(BRIDGE_EVT_ALARM, on_alarm, NULL,
                                        "app_ble.alarm");
    (void)bridge_event_handler_register(BRIDGE_EVT_NET, on_net, NULL,
                                        "app_ble.net");
    app_net_set_scan_done_cb(on_scan_done, NULL);

    nimble_port_freertos_init(host_task);
    ESP_LOGI(TAG, "NimBLE up: %s, %u bond(s) stored", name,
             (unsigned)app_ble_bond_count());
    return 0;
}
