/*
 * ble_service.c - NimBLE GATT server for the custom Smoke X4 service (T27).
 *
 * The wire contract lives in design 05 and protocol/ble.yaml. This file keeps
 * the callbacks thin: the `info` bytes come from the pure encoder in
 * ble_info.c, and the slot table in ble_gatt_spec.c mirrors the contract.
 *
 * Advertising is deliberately NOT started here. T30 owns the advertising PDU,
 * scan response, intervals, passkey/bonding policy and restart-on-disconnect.
 * This task registers the service, serves the open `info` read and exposes the
 * GAP event callback that T30 will hand to ble_gap_adv_start().
 */
#include "ble_service.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_control.h"
#include "ble_gatt_spec.h"
#include "ble_info.h"
#include "ble_live.h"
#include "ble_tx.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "host/ble_att.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "host/ble_uuid.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "records.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "sx4.ble";

/* The control contract's ATT values are the NimBLE ones (design 05 5.5). */
_Static_assert(BLE_CONTROL_ATT_OK == 0, "ATT success must be zero");
_Static_assert(BLE_CONTROL_ATT_INSUFFICIENT_ENC == BLE_ATT_ERR_INSUFFICIENT_ENC,
               "control: insufficient encryption code drifted");
_Static_assert(
    BLE_CONTROL_ATT_INSUFFICIENT_AUTHEN == BLE_ATT_ERR_INSUFFICIENT_AUTHEN,
    "control: insufficient authentication code drifted");

/*
 * 128-bit UUIDs, least-significant byte first (NimBLE's BLE_UUID128_INIT order).
 * The text form is 7f9b00SS-4c5b-4b0f-9a3d-1c2e3f405162.
 */
static const ble_uuid128_t s_svc_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x00, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_info_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x01, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_live_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x02, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_control_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x03, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_result_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x04, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_sync_ctrl_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x05, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_sync_data_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x06, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_config_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x07, 0x00, 0x9b, 0x7f);
static const ble_uuid128_t s_stats_uuid = BLE_UUID128_INIT(
    0x62, 0x51, 0x40, 0x3f, 0x2e, 0x1c, 0x3d, 0x9a, 0x0f, 0x4b, 0x5b, 0x4c,
    0x08, 0x00, 0x9b, 0x7f);

/* V0 placeholder values. T47/T51 replace config/stats with real snapshots. */
static const uint8_t s_config_value[SX4_CONFIG_SIZE] = {1};
static const uint8_t s_stats_value[SX4_STATS_SIZE] = {1};

static uint16_t s_info_handle;
static uint16_t s_live_handle;
static uint16_t s_control_handle;
static uint16_t s_result_handle;
static uint16_t s_sync_ctrl_handle;
static uint16_t s_sync_data_handle;
static uint16_t s_config_handle;
static uint16_t s_stats_handle;

static bool s_started;
static bool s_synced;
static bool s_connected;
static bool s_result_subscribed;
static struct ble_gap_event_listener s_gap_listener;
static esp_timer_handle_t s_action_timer;
static ble_control_action_t s_pending_action;

static int ble_service_access(uint16_t conn_handle, uint16_t attr_handle,
                              struct ble_gatt_access_ctxt *ctxt, void *arg);

/*
 * NimBLE adds the standard CCCD automatically for every characteristic with
 * the Notify property. The NOTIFY_INDICATE_ENC flag below is what makes a CCCD
 * write require the same encryption level as the characteristic value.
 * `info` is the only open slot; every other slot needs encryption, and
 * control/config need an authenticated bond as well.
 */
static const struct ble_gatt_chr_def s_characteristics[] = {
    {
        .uuid = &s_info_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_INFO_SLOT,
        .flags = BLE_GATT_CHR_F_READ,
        .val_handle = &s_info_handle,
    },
    {
        .uuid = &s_live_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_LIVE_SLOT,
        .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY |
                 BLE_GATT_CHR_F_READ_ENC |
                 BLE_GATT_CHR_F_NOTIFY_INDICATE_ENC,
        .val_handle = &s_live_handle,
    },
    {
        .uuid = &s_control_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_CONTROL_SLOT,
        .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_AUTHEN,
        .val_handle = &s_control_handle,
    },
    {
        .uuid = &s_result_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_RESULT_SLOT,
        .flags = BLE_GATT_CHR_F_NOTIFY |
                 BLE_GATT_CHR_F_NOTIFY_INDICATE_ENC,
        .val_handle = &s_result_handle,
    },
    {
        .uuid = &s_sync_ctrl_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_SYNC_CTRL_SLOT,
        .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC,
        .val_handle = &s_sync_ctrl_handle,
    },
    {
        .uuid = &s_sync_data_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_SYNC_DATA_SLOT,
        .flags = BLE_GATT_CHR_F_NOTIFY |
                 BLE_GATT_CHR_F_NOTIFY_INDICATE_ENC,
        .val_handle = &s_sync_data_handle,
    },
    {
        .uuid = &s_config_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_CONFIG_SLOT,
        .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE |
                 BLE_GATT_CHR_F_READ_AUTHEN | BLE_GATT_CHR_F_WRITE_AUTHEN,
        .val_handle = &s_config_handle,
    },
    {
        .uuid = &s_stats_uuid.u,
        .access_cb = ble_service_access,
        .arg = (void *)(uintptr_t)SX4_BLE_CHAR_STATS_SLOT,
        .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_READ_ENC,
        .val_handle = &s_stats_handle,
    },
    {
        /* No more characteristics in this service. */
        .uuid = NULL,
    },
};

static const struct ble_gatt_svc_def s_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_svc_uuid.u,
        .characteristics = s_characteristics,
    },
    {
        /* No more services. */
        .uuid = NULL,
    },
};

static void format_device_id(char out[5]) {
    uint8_t addr[6];
    int is_nrpa = 0;

    if (ble_hs_id_copy_addr(BLE_ADDR_PUBLIC, addr, &is_nrpa) == 0) {
        /* Same last-two-bytes convention as the SmokeX4-XXXX local name. */
        snprintf(out, 5, "%02X%02X", addr[4], addr[5]);
    } else {
        snprintf(out, 5, "0000");
    }
}

static void build_info(uint8_t out[SX4_INFO_SIZE]) {
    bridge_config_pairing_t pairing;
    bool paired = false;
    uint8_t configured_probes = 0;
    int used_bonds = 0;
    char device_id[5];

    if (bridge_config_get_pairing(&pairing) == BRIDGE_CONFIG_OK) {
        paired = pairing.paired;
        configured_probes = pairing.num_probes;
    }
    if (ble_store_util_count(BLE_STORE_OBJ_TYPE_PEER_SEC, &used_bonds) != 0) {
        used_bonds = 0;
    }

    format_device_id(device_id);
    ble_info_view_t view = {
        .device_id = device_id,
        .fw = BLE_INFO_FW_VERSION,
        .model = BLE_INFO_MODEL,
        .probes = ble_info_probes(paired, configured_probes),
        .caps = BLE_INFO_CAPS_ALL,
        .bonds_free = ble_info_bonds_free((uint8_t)used_bonds),
    };
    (void)ble_info_encode(&view, out, SX4_INFO_SIZE);
}

static int check_access_security(uint16_t conn_handle,
                                 const ble_gatt_spec_t *spec) {
    struct ble_gap_conn_desc desc;

    if (spec->security == SX4_BLE_SEC_OPEN ||
        conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        return 0;
    }
    if (ble_gap_conn_find(conn_handle, &desc) != 0) {
        return BLE_CONTROL_ATT_INSUFFICIENT_ENC;
    }
    if (spec->security == SX4_BLE_SEC_AUTHENTICATED) {
        return ble_control_write_security(desc.sec_state.encrypted,
                                          desc.sec_state.authenticated);
    }
    if (!desc.sec_state.encrypted) {
        return BLE_CONTROL_ATT_INSUFFICIENT_ENC;
    }
    return BLE_CONTROL_ATT_OK;
}

static int read_value(uint16_t conn_handle, struct ble_gatt_access_ctxt *ctxt,
                      const ble_gatt_spec_t *spec) {
    uint8_t info[SX4_INFO_SIZE];
    uint8_t live[SX4_LIVE_SIZE];
    const uint8_t *data = NULL;
    size_t len = 0;
    uint16_t mtu;

    switch (spec->slot) {
    case SX4_BLE_CHAR_INFO_SLOT:
        build_info(info);
        data = info;
        len = sizeof(info);
        break;
    case SX4_BLE_CHAR_LIVE_SLOT:
        /* Read fallback: the latest snapshot, never a queued notification. */
        {
            bridge_state_live_t snapshot;
            if (bridge_state_snapshot(&snapshot) != BRIDGE_STATE_OK ||
                ble_live_encode(&snapshot, live, sizeof(live)) !=
                    SX4_LIVE_SIZE) {
                return BLE_ATT_ERR_UNLIKELY;
            }
        }
        data = live;
        len = sizeof(live);
        break;
    case SX4_BLE_CHAR_CONFIG_SLOT:
        data = s_config_value;
        len = sizeof(s_config_value);
        break;
    case SX4_BLE_CHAR_STATS_SLOT:
        data = s_stats_value;
        len = sizeof(s_stats_value);
        break;
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }

    if (ctxt->offset >= len) {
        return BLE_ATT_ERR_INVALID_OFFSET;
    }

    /* Read Blob: NimBLE asks for the next offset while the value is longer
     * than the negotiated ATT MTU. One response carries at most MTU-1 bytes. */
    mtu = conn_handle == BLE_HS_CONN_HANDLE_NONE ? BLE_ATT_MTU_DFLT
                                                 : ble_att_mtu(conn_handle);
    if (mtu < BLE_ATT_MTU_DFLT) {
        mtu = BLE_ATT_MTU_DFLT;
    }
    size_t chunk = len - ctxt->offset;
    size_t max_chunk = (size_t)mtu - 1u;
    if (chunk > max_chunk) {
        chunk = max_chunk;
    }
    /* NimBLE slices a Read Blob from `offset` after the callback returns, so
     * append the prefix up to the end of this MTU-1 window. */
    size_t append_len = ctxt->offset + chunk;
    if (os_mbuf_append(ctxt->om, data, append_len) != 0) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    return 0;
}

static void action_timer_cb(void *arg) {
    (void)arg;
    ble_control_action_t action = s_pending_action;
    s_pending_action = BLE_CONTROL_ACTION_NONE;
    ble_control_run_action(action);
}

/*
 * Destructive ops answer first: the write callback sends the result and only
 * then arms this one-shot timer. T48 registers the action handler.
 */
static void schedule_control_action(const ble_control_result_t *result) {
    if (result->action == BLE_CONTROL_ACTION_NONE) {
        return;
    }
    if (s_action_timer == NULL) {
        const esp_timer_create_args_t args = {
            .callback = action_timer_cb,
            .name = "ble_action",
        };
        if (esp_timer_create(&args, &s_action_timer) != ESP_OK) {
            s_action_timer = NULL;
            ESP_LOGW(TAG, "no timer for deferred control action");
            return;
        }
    }
    uint32_t delay_ms = result->action_delay_ms != 0u
                            ? result->action_delay_ms
                            : BLE_CONTROL_ACTION_DELAY_MS;
    s_pending_action = (ble_control_action_t)result->action;
    (void)esp_timer_stop(s_action_timer);
    (void)esp_timer_start_once(s_action_timer, (uint64_t)delay_ms * 1000u);
}

/* `result` is a logical byte stream; notifications split at MTU-3. */
static void notify_result(uint16_t conn_handle, const uint8_t *data,
                          size_t len) {
    if (!s_result_subscribed || s_result_handle == 0u ||
        conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        ESP_LOGD(TAG, "result dropped: no subscriber");
        return;
    }
    uint16_t mtu = ble_att_mtu(conn_handle);
    size_t max_payload =
        mtu > 3u ? (size_t)mtu - 3u : (size_t)BLE_ATT_MTU_DFLT - 3u;

    size_t offset = 0;
    while (offset < len) {
        size_t chunk = len - offset;
        if (chunk > max_payload) {
            chunk = max_payload;
        }
        struct os_mbuf *om = ble_hs_mbuf_from_flat(data + offset, chunk);
        if (om == NULL) {
            ESP_LOGW(TAG, "no mbuf for result notification");
            return;
        }
        int rc = ble_gatts_notify_custom(conn_handle, s_result_handle, om);
        if (rc != 0) {
            ESP_LOGD(TAG, "result notify failed (%d)", rc);
            return;
        }
        offset += chunk;
    }
}

static int write_control(uint16_t conn_handle,
                         struct ble_gatt_access_ctxt *ctxt) {
    uint8_t scratch[SX4_RESULT_SIZE];
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    uint16_t written = 0;

    if (len > sizeof(scratch)) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (ble_hs_mbuf_to_flat(ctxt->om, scratch, sizeof(scratch), &written) !=
        0) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    ble_control_result_t result;
    (void)ble_control_handle(scratch, len, &result);

    uint8_t encoded[SX4_RESULT_SIZE];
    size_t encoded_len =
        ble_control_encode_result(&result, encoded, sizeof(encoded));
    if (encoded_len > 0u) {
        ESP_LOGI(TAG, "control op %u id %u -> status %u (%u B)",
                 (unsigned)result.op, (unsigned)result.op_id,
                 (unsigned)result.status, (unsigned)encoded_len);
        notify_result(conn_handle, encoded, encoded_len);
    }
    schedule_control_action(&result);
    return 0;
}

static int write_value(uint16_t conn_handle,
                       struct ble_gatt_access_ctxt *ctxt,
                       const ble_gatt_spec_t *spec) {
    uint8_t scratch[SX4_CONFIG_SIZE];
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    uint16_t written = 0;

    if (spec->slot == SX4_BLE_CHAR_CONTROL_SLOT) {
        return write_control(conn_handle, ctxt);
    }

    /*
     * T31 (sync_ctrl) and T47 (config) replace these no-op handlers. Draining
     * the mbuf here keeps the GATT attribute write legal.
     */
    if (len > sizeof(scratch)) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (ble_hs_mbuf_to_flat(ctxt->om, scratch, sizeof(scratch), &written) !=
        0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    ESP_LOGD(TAG, "write slot %04x (%u B) staged for a later task", spec->slot,
             (unsigned)len);
    return 0;
}

static int ble_service_access(uint16_t conn_handle, uint16_t attr_handle,
                              struct ble_gatt_access_ctxt *ctxt, void *arg) {
    (void)attr_handle;
    uint16_t slot = (uint16_t)(uintptr_t)arg;
    const ble_gatt_spec_t *spec = ble_gatt_spec_by_slot(slot);
    int rc;

    if (spec == NULL) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    rc = check_access_security(conn_handle, spec);
    if (rc != 0) {
        return rc;
    }

    switch (ctxt->op) {
    case BLE_GATT_ACCESS_OP_READ_CHR:
        return read_value(conn_handle, ctxt, spec);
    case BLE_GATT_ACCESS_OP_WRITE_CHR:
        return write_value(conn_handle, ctxt, spec);
    default:
        /* Notify-only characteristics and the auto CCCD are handled by
         * NimBLE; no application descriptor exists yet. */
        return BLE_ATT_ERR_UNLIKELY;
    }
}

int ble_service_gap_event(struct ble_gap_event *event, void *arg) {
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_connected = true;
            s_result_subscribed = false;
            ble_tx_on_connect(event->connect.conn_handle);
            ESP_LOGI(TAG, "central connected (handle %u)",
                     event->connect.conn_handle);
        } else {
            s_connected = false;
            ESP_LOGW(TAG, "connection failed (%d)", event->connect.status);
        }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        s_connected = false;
        s_result_subscribed = false;
        ble_tx_on_disconnect();
        ESP_LOGI(TAG, "central disconnected (reason 0x%02x)",
                 event->disconnect.reason);
        /* T30 owns restarting advertising from here. */
        break;
    case BLE_GAP_EVENT_SUBSCRIBE:
        /* The encrypted CCCD was enforced by the characteristic flags before
         * this event. A live subscription primes the queue with the current
         * snapshot so the app has the same value as a read would give. */
        if (event->subscribe.attr_handle == s_live_handle) {
            ble_tx_on_live_subscribe(event->subscribe.cur_notify != 0);
        } else if (event->subscribe.attr_handle == s_result_handle) {
            s_result_subscribed = event->subscribe.cur_notify != 0;
        }
        break;
    default:
        break;
    }
    return 0;
}

bool ble_service_is_connected(void) { return s_connected; }

static void on_reset(int reason) {
    ESP_LOGW(TAG, "host reset (%d)", reason);
    s_synced = false;
    s_connected = false;
    s_result_subscribed = false;
}

static void on_sync(void) {
    s_synced = true;
    if (ble_gap_event_listener_register(&s_gap_listener, ble_service_gap_event,
                                        NULL) != 0) {
        ESP_LOGW(TAG, "GAP listener already registered");
    }
    ESP_LOGI(TAG, "host synced; service ready (advertising is T30)");
}

static void host_task(void *param) {
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

esp_err_t ble_service_start(void) {
    esp_err_t err;
    int rc;

    if (s_started) {
        return ESP_OK;
    }

    err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nimble_port_init failed (%s)", esp_err_to_name(err));
        return err;
    }

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    /* Default device name only; T30 owns the advertising name. */
    ble_svc_gap_init();
    (void)ble_svc_gap_device_name_set(SX4_BLE_LOCAL_NAME_PREFIX);
    ble_svc_gatt_init();

    rc = ble_gatts_count_cfg(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_count_cfg failed (%d)", rc);
        (void)nimble_port_deinit();
        return ESP_FAIL;
    }
    rc = ble_gatts_add_svcs(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_add_svcs failed (%d)", rc);
        (void)nimble_port_deinit();
        return ESP_FAIL;
    }
    ble_tx_set_live_handle(s_live_handle);
    if (ble_att_set_preferred_mtu(SX4_BLE_MTU_REQUEST) != 0) {
        ESP_LOGW(TAG, "preferred MTU %u rejected", SX4_BLE_MTU_REQUEST);
    }

    nimble_port_freertos_init(host_task);
    s_started = true;
    ESP_LOGI(TAG, "GATT service registered (%u slots), host starting",
             (unsigned)ble_gatt_spec_count);
    return ESP_OK;
}

esp_err_t ble_service_stop(void) {
    if (!s_started) {
        return ESP_OK;
    }
    ble_tx_on_disconnect();
    s_result_subscribed = false;
    s_pending_action = BLE_CONTROL_ACTION_NONE;
    if (s_action_timer != NULL) {
        (void)esp_timer_stop(s_action_timer);
        (void)esp_timer_delete(s_action_timer);
        s_action_timer = NULL;
    }
    if (s_synced) {
        (void)ble_gap_event_listener_unregister(&s_gap_listener);
    }
    if (nimble_port_stop() == 0) {
        (void)nimble_port_deinit();
    }
    s_started = false;
    s_synced = false;
    s_connected = false;
    return ESP_OK;
}
