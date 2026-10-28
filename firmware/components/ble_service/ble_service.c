/*
 * ble_service.c - NimBLE GATT server for the custom Smoke X4 service (T27).
 *
 * The wire contract lives in design 05 and protocol/ble.yaml. This file keeps
 * the callbacks thin: the `info` bytes come from the pure encoder in
 * ble_info.c, and the slot table in ble_gatt_spec.c mirrors the contract.
 *
 * Advertising and the security policy came with T30: the PDU/scan response are
 * built by the pure helpers in ble_adv.c, the passkey lifetime and bond limit
 * live in ble_security.c, and this file owns the NimBLE glue.
 *
 * T31 adds `sync_ctrl`: the request parser and the START/RECORDS/END stream are
 * built by the pure ble_sync.c, while this file owns the ring adapter and the
 * paced sync_data notifications (one frame per timer tick, so `cancel` can land
 * while a transfer is in flight).
 */
#include "ble_service.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ble_control.h"
#include "ble_adv.h"
#include "ble_config.h"
#include "ble_gatt_spec.h"
#include "ble_info.h"
#include "ble_live.h"
#include "ble_security.h"
#include "ble_stats.h"
#include "ble_sync.h"
#include "ble_tx.h"
#include "board_battery.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "host/ble_att.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_id.h"
#include "host/ble_sm.h"
#include "host/ble_store.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "records.h"
#include "sample_log.h"
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

/* T47 config-applied seam (boot.c wires it to the UI). */
static ble_service_config_applied_fn s_config_applied_cb;
static void *s_config_applied_ctx;

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
static esp_timer_handle_t s_action_timer;
static ble_control_action_t s_pending_action;

/* T30 advertising/security state. */
static bool s_adv_active;
static bool s_adv_stopping;    /* our own ble_gap_adv_stop(), not a timeout */
static bool s_adv_restart_pending; /* deferred start/restart on a timer */
static uint8_t s_own_addr_type;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static ble_adv_state_t s_adv_state;
static ble_security_passkey_t s_passkey;
static uint8_t s_bond_count;
static uint32_t s_pending_interval_ms;
static esp_timer_handle_t s_adv_window_timer;
static esp_timer_handle_t s_adv_restart_timer;
static esp_timer_handle_t s_passkey_timer;
static ble_service_passkey_fn s_passkey_cb;
static void *s_passkey_ctx;

/* T31 sync transfer: one record request at a time, paced by a timer. The
 * ~15 ms tick matches the contract's MTU-23 timing note (~50 s for 24 h) and
 * leaves room for a cancel/status write between frames. */
#define BLE_SERVICE_SYNC_TICK_US 15000u
static bool s_sync_subscribed;
static volatile bool s_sync_busy;
static uint8_t s_sync_stream[BLE_SYNC_STREAM_MAX];
static size_t s_sync_stream_len;
static size_t s_sync_offset;
static uint8_t s_sync_status;
static ble_sync_framer_t s_sync_framer;
static ble_sync_request_t s_sync_request;
static esp_timer_handle_t s_sync_timer;
static SemaphoreHandle_t s_sync_mutex;

#define BLE_SERVICE_PASSKEY_TERM_REASON 0x05u /* Authentication Failure */
#define BLE_SERVICE_ADV_RESTART_DELAY_US 10000u

static uint32_t now_ms(void) {
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static void passkey_show(const char *digits) {
    if (s_passkey_cb != NULL) {
        s_passkey_cb(digits, s_passkey_ctx);
    }
}

static void refresh_bond_count(void) {
    int used = 0;
    if (ble_store_util_count(BLE_STORE_OBJ_TYPE_PEER_SEC, &used) != 0 ||
        used < 0) {
        used = 0;
    }
    if (used > (int)BLE_SEC_MAX_BONDS) {
        used = (int)BLE_SEC_MAX_BONDS;
    }
    s_bond_count = (uint8_t)used;
}

static bool ensure_timer(esp_timer_handle_t *handle, const char *name,
                         esp_timer_cb_t cb) {
    if (*handle != NULL) {
        return true;
    }
    const esp_timer_create_args_t args = {.callback = cb, .name = name};
    return esp_timer_create(&args, handle) == ESP_OK;
}


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

/* NimBLE stores the identity address least-significant byte first; the OLED,
 * Android display and the contract name use the printed MAC order. */
static void copy_public_addr_display(uint8_t out[6]) {
    uint8_t raw[6] = {0};
    int is_nrpa = 0;

    if (ble_hs_id_copy_addr(BLE_ADDR_PUBLIC, raw, &is_nrpa) == 0) {
        for (size_t i = 0; i < sizeof(raw); i++) {
            out[i] = raw[sizeof(raw) - 1u - i];
        }
    } else {
        memset(out, 0, sizeof(raw));
    }
}

static void format_device_id(char out[5]) {
    uint8_t addr[6];

    copy_public_addr_display(addr);
    /* Same last-two-bytes convention as the SmokeX4-XXXX local name. */
    snprintf(out, 5, "%02X%02X", addr[4], addr[5]);
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

/* ---- config / stats snapshots (T47) ------------------------------------ */

static void build_config(uint8_t out[SX4_CONFIG_SIZE]) {
    bridge_config_device_t device = {
        .units = BRIDGE_CONFIG_DEFAULT_UNITS,
        .display_timeout_s = BRIDGE_CONFIG_DEFAULT_TIMEOUT,
        .device_name = BRIDGE_CONFIG_DEFAULT_DEVICE_NAME,
    };
    ble_config_view_t view;

    (void)bridge_config_get_device(&device);
    memset(&view, 0, sizeof(view));
    view.units = device.units;
    view.display_timeout_s = device.display_timeout_s;
    memcpy(view.device_name, device.device_name, sizeof(view.device_name) - 1u);
    if (ble_config_encode(&view, out, SX4_CONFIG_SIZE) != SX4_CONFIG_SIZE) {
        memset(out, 0, SX4_CONFIG_SIZE);
        out[0] = 1; /* never leave a previous config readable on failure */
    }
}

static uint32_t record_unix_s(uint32_t seq) {
    sx4_sample_rec_t rec;
    if (sample_log_read_seq(seq, &rec) != ESP_OK) {
        return 0;
    }
    return rec.unix_s;
}

static void build_stats(uint8_t out[SX4_STATS_SIZE]) {
    ble_stats_view_t view;
    bridge_state_live_t live;
    log_ring_info_t info;
    bridge_config_stats_t counters;
    board_battery_stats_t battery;
    bool have_live = bridge_state_snapshot(&live) == BRIDGE_STATE_OK;

    memset(&view, 0, sizeof(view));
    if (have_live) {
        view.flags = ble_stats_build_flags(
            (live.flags & SX4_LIVE_FLAG_SMOKE_PAIRED) != 0,
            (live.flags & SX4_LIVE_FLAG_SMOKE_LIVE) != 0,
            ble_service_is_advertising(), s_connected,
            (live.flags & SX4_LIVE_FLAG_CLOCK_VALID) != 0,
            (live.flags & SX4_LIVE_FLAG_STORAGE_OK) != 0,
            (live.flags & SX4_LIVE_FLAG_BILLOWS_ATTACHED) != 0);
        view.uptime_s = live.uptime_s;
        view.battery_mv = live.battery_mv;
        view.battery_pct = live.battery_pct;
        view.lora_rssi = live.rssi_lora;
        view.lora_snr = live.snr_lora;
        view.dropped_samples = live.dropped_samples > UINT16_MAX
                                   ? UINT16_MAX
                                   : (uint16_t)live.dropped_samples;
    } else {
        view.flags = ble_stats_build_flags(false, false,
                                           ble_service_is_advertising(),
                                           s_connected, false, false, false);
        view.battery_pct = BOARD_BATTERY_SOC_UNKNOWN;
    }

    /* One extent snapshot supplies count, min/max and generation. */
    view.records_capacity = BLE_STATS_CAPACITY;
    view.min_seq = BLE_STATS_SEQ_NONE;
    view.max_seq = BLE_STATS_SEQ_NONE;
    if (sample_log_get_info(&info)) {
        view.records_capacity =
            info.sector_count * SAMPLE_LOG_RECORDS_PER_SECTOR;
        /* The generation survives an empty/cleared log; the app uses it for
         * the segment boundary even when there are no records yet. */
        view.generation = info.generation;
        if (info.count > 0u) {
            view.records_stored = info.count;
            view.min_seq = info.min_seq;
            view.max_seq = info.max_seq;
            view.oldest_unix_s = record_unix_s(info.min_seq);
            view.newest_unix_s = record_unix_s(info.max_seq);
        }
    }

    if (bridge_config_stats_get(&counters) == BRIDGE_CONFIG_OK) {
        view.packets_ok = counters.packets_ok;
        view.packets_bad = counters.packets_bad;
    }
    battery = board_battery_stats_get();
    view.battery_mv = battery.millivolts;
    view.battery_pct = battery.percent;

    view.heap_free = (uint32_t)esp_get_free_heap_size();
    view.heap_min = (uint32_t)esp_get_minimum_free_heap_size();

    if (ble_stats_encode(&view, out, SX4_STATS_SIZE) != SX4_STATS_SIZE) {
        memset(out, 0, SX4_STATS_SIZE);
        out[0] = 1;
    }
}

/* ---- advertising and pairing (T30) ------------------------------------- */

static void adv_status_now(ble_adv_status_t *status) {
    bridge_state_live_t live;

    memset(status, 0, sizeof(*status));
    status->battery_pct = BRIDGE_STATE_SOC_UNKNOWN;
    if (bridge_state_snapshot(&live) != BRIDGE_STATE_OK) {
        return;
    }
    status->flags = live.flags;
    /* P4 is the fixed Billows/pit channel (design 05 5.2). */
    status->pit_temp_f10 = live.temp_f10[3];
    status->battery_pct = live.battery_pct;
    status->billows_target_f10 =
        live.billows_target_valid ? live.billows_target_f10 : 0;
    status->age_s = live.age_s;
}

static void adv_build_data(uint8_t *adv, size_t adv_cap, size_t *adv_len,
                           uint8_t *rsp, size_t rsp_cap, size_t *rsp_len) {
    uint8_t mac[6] = {0};
    char name[BLE_ADV_NAME_MAX];
    ble_adv_status_t status;

    (void)adv_cap;
    (void)rsp_cap;
    *adv_len = 0;
    *rsp_len = 0;

    copy_public_addr_display(mac);
    if (ble_adv_format_name(name, mac) == 0) {
        memcpy(name, "SmokeX4-0000", sizeof("SmokeX4-0000"));
    }
    adv_status_now(&status);
    *adv_len = ble_adv_build_pdu(adv, BLE_ADV_PDU_SIZE);
    *rsp_len = ble_adv_build_scan_rsp(name, &status, rsp,
                                      BLE_ADV_SCAN_RSP_SIZE);
}

/* Start/restart advertising with the given interval. Must run outside a GAP
 * callback and must not be called while connected. */
static void adv_start_with(uint32_t interval_ms) {
    uint8_t adv[BLE_ADV_PDU_SIZE];
    uint8_t rsp[BLE_ADV_SCAN_RSP_SIZE];
    size_t adv_len = 0;
    size_t rsp_len = 0;
    uint16_t units = ble_adv_interval_units(interval_ms);

    s_adv_restart_pending = false;
    if (!s_synced || s_connected) {
        s_adv_active = false;
        return;
    }

    if (ble_gap_adv_active()) {
        s_adv_stopping = true;
        (void)ble_gap_adv_stop();
        s_adv_stopping = false;
    }

    adv_build_data(adv, sizeof(adv), &adv_len, rsp, sizeof(rsp), &rsp_len);
    int rc = ble_gap_adv_set_data(adv, (int)adv_len);
    if (rc != 0) {
        ESP_LOGW(TAG, "adv data rejected (%d)", rc);
    }
    rc = ble_gap_adv_rsp_set_data(rsp, (int)rsp_len);
    if (rc != 0) {
        ESP_LOGW(TAG, "scan response rejected (%d)", rc);
    }

    const struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
        .itvl_min = units,
        .itvl_max = units,
    };
    /* NimBLE only routes connection-scoped events (PASSKEY_ACTION,
     * PARING_COMPLETE, ENC_CHANGE, SUBSCRIBE) to the advertising callback. A
     * global listener alone never receives PASSKEY_ACTION, which is why the
     * phone could start pairing and then time out without ever seeing a code. */
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &params,
                           ble_service_gap_event, NULL);
    if (rc == 0) {
        s_adv_active = true;
        ESP_LOGI(TAG, "advertising at %u ms (adv %u B, rsp %u B)",
                 (unsigned)interval_ms, (unsigned)adv_len,
                 (unsigned)rsp_len);
    } else {
        s_adv_active = false;
        ESP_LOGW(TAG, "advertising start failed (%d)", rc);
    }
}

static void adv_window_stop(void) {
    if (s_adv_window_timer != NULL) {
        (void)esp_timer_stop(s_adv_window_timer);
    }
}

static void adv_restart_timer_cb(void *arg) {
    (void)arg;
    s_adv_restart_pending = false;
    adv_start_with(s_pending_interval_ms);
}

static void adv_schedule(uint32_t interval_ms) {
    s_pending_interval_ms = interval_ms;
    if (!ensure_timer(&s_adv_restart_timer, "ble_adv_restart",
                      adv_restart_timer_cb)) {
        /* A failed timer allocation still leaves advertising stopped; retry
         * synchronously from a non-GAP context is not possible here. */
        return;
    }
    (void)esp_timer_stop(s_adv_restart_timer);
    if (esp_timer_start_once(s_adv_restart_timer,
                             BLE_SERVICE_ADV_RESTART_DELAY_US) == ESP_OK) {
        s_adv_restart_pending = true;
    }
}

static void passkey_timer_cb(void *arg);

static void adv_window_timer_cb(void *arg) {
    (void)arg;
    ble_adv_action_t action = ble_adv_state_tick(&s_adv_state, now_ms());
    if (action.advertise) {
        adv_schedule(action.interval_ms);
    }
}

static void adv_window_arm_real(void) {
    if (!ensure_timer(&s_adv_window_timer, "ble_fast_adv",
                      adv_window_timer_cb)) {
        return;
    }
    (void)esp_timer_stop(s_adv_window_timer);
    (void)esp_timer_start_once(s_adv_window_timer,
                               (uint64_t)BLE_ADV_FAST_WINDOW_MS * 1000u);
}

/* Shared by the boot/sync path (direct) and GAP callbacks (deferred). */
static void adv_apply_event(ble_adv_event_t event, bool direct) {
    ble_adv_action_t action =
        ble_adv_state_event(&s_adv_state, event, now_ms());

    switch (event) {
    case BLE_ADV_EVENT_BOOT:
    case BLE_ADV_EVENT_DISCONNECT:
    case BLE_ADV_EVENT_CONNECT_FAILED:
        adv_window_arm_real();
        break;
    case BLE_ADV_EVENT_CONNECTED:
    case BLE_ADV_EVENT_STOP:
        adv_window_stop();
        s_adv_restart_pending = false;
        s_adv_active = false;
        break;
    default:
        break;
    }

    if (!action.advertise) {
        return;
    }
    if (direct) {
        adv_start_with(action.interval_ms);
    } else {
        adv_schedule(action.interval_ms);
    }
}

static void passkey_clear(void) {
    if (s_passkey_timer != NULL) {
        (void)esp_timer_stop(s_passkey_timer);
    }
    ble_security_passkey_cancel(&s_passkey);
    passkey_show(NULL);
}

static void passkey_timer_cb(void *arg) {
    (void)arg;
    if (!ble_security_passkey_tick(&s_passkey, now_ms())) {
        return;
    }
    ESP_LOGW(TAG, "passkey expired after 60 s");
    passkey_show(NULL);
    if (s_connected && s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        (void)ble_gap_terminate(s_conn_handle,
                                BLE_SERVICE_PASSKEY_TERM_REASON);
    }
}

static void start_passkey(uint16_t conn_handle) {
    struct ble_sm_io io = {0};
    uint32_t random = esp_random();

    if (!ble_security_passkey_start(&s_passkey, random, now_ms())) {
        ESP_LOGE(TAG, "could not generate a passkey");
        (void)ble_gap_terminate(conn_handle, BLE_SERVICE_PASSKEY_TERM_REASON);
        return;
    }

    io.action = BLE_SM_IOACT_DISP;
    io.passkey = (uint32_t)strtoul(s_passkey.digits, NULL, 10);
    if (ble_sm_inject_io(conn_handle, &io) != 0) {
        ESP_LOGE(TAG, "passkey injection failed");
        passkey_clear();
        (void)ble_gap_terminate(conn_handle, BLE_SERVICE_PASSKEY_TERM_REASON);
        return;
    }

    if (ensure_timer(&s_passkey_timer, "ble_passkey", passkey_timer_cb)) {
        (void)esp_timer_stop(s_passkey_timer);
        (void)esp_timer_start_once(s_passkey_timer,
                                   (uint64_t)BLE_SEC_PASSKEY_TIMEOUT_MS *
                                       1000u);
    }
    passkey_show(s_passkey.digits);
    ESP_LOGI(TAG, "passkey displayed for conn %u", conn_handle);
}

/* ---- GATT access ------------------------------------------------------- */

static int check_access_security(uint16_t conn_handle,
                                 const ble_gatt_spec_t *spec) {    struct ble_gap_conn_desc desc;

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
    uint8_t config[SX4_CONFIG_SIZE];
    uint8_t stats[SX4_STATS_SIZE];
    const uint8_t *data = NULL;
    size_t len = 0;

    (void)conn_handle;
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
        build_config(config);
        data = config;
        len = sizeof(config);
        break;
    case SX4_BLE_CHAR_STATS_SLOT:
        build_stats(stats);
        data = stats;
        len = sizeof(stats);
        break;
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }

    if (ctxt->offset >= len) {
        return BLE_ATT_ERR_INVALID_OFFSET;
    }

    /*
     * NimBLE owns the ATT offset/MTU slicing:
     *  - offset 0: the value goes into the response mbuf and the ATT layer
     *    truncates it to MTU-1 before transmitting;
     *  - offset N: NimBLE puts the callback output in a temporary mbuf and
     *    copies value[N..] itself (see ble_gatts_val_access()).
     * The callback must always append the complete value. Chunking here makes
     * NimBLE compute `len(returned) - offset`, which goes negative on the
     * second Read Blob and surfaces as GATT_INVALID_OFFSET (0x07).
     */
    if (os_mbuf_append(ctxt->om, data, (uint16_t)len) != 0) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    return 0;
}

static void action_timer_cb(void *arg) {
    (void)arg;
    ble_control_action_t action = s_pending_action;
    s_pending_action = BLE_CONTROL_ACTION_NONE;
    uint8_t status = ble_control_run_action(action);
    if (status != SX4_RESULT_STATUS_OK) {
        /* Answer-first: the result already said ok; only the log can report
         * a late backend failure. */
        ESP_LOGW(TAG, "control action %u failed late (status %u)",
                 (unsigned)action, (unsigned)status);
    }
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

/* ---- sync_ctrl / sync_data (T31) --------------------------------------- */

static bool sync_get_extent(void *ctx, ble_sync_extent_t *out) {
    log_ring_info_t info;
    (void)ctx;
    if (!sample_log_get_info(&info)) {
        return false;
    }
    out->generation = info.generation;
    out->count = info.count;
    out->min_seq = info.min_seq;
    out->max_seq = info.max_seq;
    return true;
}

static bool sync_read_record(void *ctx, uint32_t seq,
                             uint8_t out[SX4_RECORD_SIZE]) {
    sx4_sample_rec_t rec;
    (void)ctx;
    if (sample_log_read_seq(seq, &rec) != ESP_OK) {
        return false;
    }
    return sample_log_record_encode(&rec, out, SX4_RECORD_SIZE) ==
           SAMPLE_LOG_OK;
}

static const ble_sync_source_t s_sync_source = {
    .get_extent = sync_get_extent,
    .read_record = sync_read_record,
    .ctx = NULL,
};

static bool notify_sync_payload(const uint8_t *data, size_t len) {
    if (!s_sync_subscribed || s_sync_data_handle == 0u ||
        s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        return false;
    }
    struct os_mbuf *om = ble_hs_mbuf_from_flat(data, len);
    if (om == NULL) {
        ESP_LOGW(TAG, "no mbuf for sync_data frame");
        return false;
    }
    int rc = ble_gatts_notify_custom(s_conn_handle, s_sync_data_handle, om);
    if (rc != 0) {
        ESP_LOGD(TAG, "sync_data notify failed (%d)", rc);
        return false;
    }
    return true;
}

/* Keeps a status response contiguous when it interleaves with a read. */
static bool sync_lock(void) {
    return s_sync_mutex == NULL ||
           xSemaphoreTake(s_sync_mutex, portMAX_DELAY) == pdTRUE;
}

static void sync_unlock(void) {
    if (s_sync_mutex != NULL) {
        (void)xSemaphoreGive(s_sync_mutex);
    }
}

static void sync_transfer_finish(void) {
    if (s_sync_timer != NULL) {
        (void)esp_timer_stop(s_sync_timer);
    }
    if (s_sync_busy) {
        ESP_LOGI(TAG, "sync transfer ended (status %u)",
                 (unsigned)s_sync_status);
    }
    s_sync_busy = false;
    s_sync_stream_len = 0;
    s_sync_offset = 0;
    /* Clears live.flags.sync_active through the bridge_state hook. */
    bridge_state_set_sync_active(false);
}

static void sync_pump(void) {
    if (!s_sync_busy) {
        return;
    }
    if (s_sync_stream_len == 0u) {
        size_t len = 0;
        uint8_t status = SX4_SYNC_STATUS_ERROR;
        ble_sync_build_status_t built =
            ble_sync_build(&s_sync_request, &s_sync_source, s_sync_stream,
                           sizeof(s_sync_stream), &len, &status);
        if (built != BLE_SYNC_BUILD_OK) {
            ESP_LOGW(TAG, "sync build failed (%d)", (int)built);
            sync_transfer_finish();
            return;
        }
        s_sync_stream_len = len;
        s_sync_status = status;
        ble_sync_framer_init(&s_sync_framer, 0u);
        ESP_LOGI(TAG, "sync frame_seq snapshot: %u B, status %u",
                 (unsigned)len, (unsigned)status);
    }

    uint16_t mtu = s_conn_handle == BLE_HS_CONN_HANDLE_NONE
                       ? BLE_ATT_MTU_DFLT
                       : ble_att_mtu(s_conn_handle);
    uint8_t frame[SX4_SYNC_FRAME_SIZE + SX4_BLE_SYNC_FRAME_MAX_PAYLOAD];
    bool error = s_sync_status == SX4_SYNC_STATUS_ERROR;
    size_t n = ble_sync_next_frame(&s_sync_framer, s_sync_stream,
                                   s_sync_stream_len, &s_sync_offset, mtu,
                                   error, frame, sizeof(frame));
    if (n == 0u) {
        sync_transfer_finish();
        return;
    }
    bool sent = sync_lock();
    if (sent) {
        sent = notify_sync_payload(frame, n);
        sync_unlock();
    }
    if (!sent) {
        /* No ACK exists, so a failed notification ends the batch; the app
         * notices the missing frame_seq and re-requests. */
        ESP_LOGW(TAG, "sync frame dropped at offset %u",
                 (unsigned)s_sync_offset);
        sync_transfer_finish();
        return;
    }
    if (s_sync_offset >= s_sync_stream_len) {
        sync_transfer_finish();
        return;
    }
    /* The timer is one-shot: without this the first frame left s_sync_busy
     * true forever and every later sync_ctrl read was dropped. */
    if (esp_timer_start_once(s_sync_timer, BLE_SERVICE_SYNC_TICK_US) !=
        ESP_OK) {
        sync_transfer_finish();
    }
}

static void sync_timer_cb(void *arg) {
    (void)arg;
    sync_pump();
}

static bool sync_start_transfer(const ble_sync_request_t *request) {
    if (s_sync_busy) {
        return false;
    }
    if (!ensure_timer(&s_sync_timer, "ble_sync", sync_timer_cb)) {
        ESP_LOGW(TAG, "no timer for sync transfer");
        return false;
    }
    s_sync_request = *request;
    s_sync_busy = true;
    s_sync_stream_len = 0;
    s_sync_offset = 0;
    s_sync_status = SX4_SYNC_STATUS_ERROR;
    bridge_state_set_sync_active(true);
    (void)esp_timer_stop(s_sync_timer);
    if (esp_timer_start_once(s_sync_timer, BLE_SERVICE_SYNC_TICK_US) !=
        ESP_OK) {
        sync_transfer_finish();
        return false;
    }
    return true;
}

static void sync_cancel(void) {
    if (!s_sync_busy) {
        return;
    }
    ESP_LOGI(TAG, "sync transfer cancelled");
    sync_transfer_finish();
}

/* Status is small (33 B) and may run while a record transfer is in flight. */
static void sync_send_status(uint16_t conn_handle,
                             const ble_sync_request_t *request) {
    uint8_t stream[SX4_SYNC_START_SIZE + SX4_SYNC_END_SIZE];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_ERROR;
    if (ble_sync_build(request, &s_sync_source, stream, sizeof(stream), &len,
                       &status) != BLE_SYNC_BUILD_OK) {
        return;
    }
    ble_sync_framer_t framer;
    ble_sync_framer_init(&framer, 0u);
    uint16_t mtu = conn_handle == BLE_HS_CONN_HANDLE_NONE
                       ? BLE_ATT_MTU_DFLT
                       : ble_att_mtu(conn_handle);
    uint8_t frame[SX4_SYNC_FRAME_SIZE + SX4_BLE_SYNC_FRAME_MAX_PAYLOAD];
    size_t offset = 0;
    bool locked = sync_lock();
    for (;;) {
        size_t n = ble_sync_next_frame(
            &framer, stream, len, &offset, mtu,
            status == SX4_SYNC_STATUS_ERROR, frame, sizeof(frame));
        if (n == 0u) {
            break;
        }
        if (!notify_sync_payload(frame, n)) {
            break;
        }
    }
    if (locked) {
        sync_unlock();
    }
}

static int write_sync_ctrl(uint16_t conn_handle,
                           struct ble_gatt_access_ctxt *ctxt) {
    uint8_t scratch[SX4_SYNC_CTRL_SIZE];
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    uint16_t written = 0;

    if (len != sizeof(scratch)) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (ble_hs_mbuf_to_flat(ctxt->om, scratch, sizeof(scratch), &written) !=
        0) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    ble_sync_request_t request;
    if (ble_sync_parse_ctrl(scratch, len, &request) != BLE_SYNC_REQUEST_OK) {
        ESP_LOGD(TAG, "malformed sync_ctrl ignored");
        return 0;
    }

    switch (ble_sync_plan(s_sync_busy, &request)) {
    case BLE_SYNC_ACTION_STATUS:
        sync_send_status(conn_handle, &request);
        break;
    case BLE_SYNC_ACTION_CANCEL:
        sync_cancel();
        break;
    case BLE_SYNC_ACTION_READ:
        if (!s_sync_subscribed) {
            ESP_LOGD(TAG, "sync read ignored: no sync_data subscriber");
            break;
        }
        (void)sync_start_transfer(&request);
        break;
    case BLE_SYNC_ACTION_NONE:
    default:
        ESP_LOGD(TAG, "sync read ignored while busy");
        break;
    }
    return 0;
}

/* T47: one full 80-byte config struct. Queued (Prepare/Execute) writes are
 * reassembled by NimBLE before this callback, so a partial body is a length
 * error rather than a merge. */
static int write_config(struct ble_gatt_access_ctxt *ctxt) {
    uint8_t scratch[SX4_CONFIG_SIZE];
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    uint16_t written = 0;

    if (len != SX4_CONFIG_SIZE) {
        return BLE_CONFIG_ATT_INVALID;
    }
    if (ble_hs_mbuf_to_flat(ctxt->om, scratch, sizeof(scratch), &written) !=
        0) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    ble_config_view_t view;
    ble_config_status_t status = ble_config_parse(scratch, len, &view);
    if (status == BLE_CONFIG_UNSUPPORTED) {
        ESP_LOGW(TAG, "config write refused: billows control unsupported");
        return BLE_CONFIG_ATT_UNSUPPORTED;
    }
    if (status != BLE_CONFIG_OK) {
        ESP_LOGW(TAG, "config write refused: invalid body");
        return BLE_CONFIG_ATT_INVALID;
    }

    bridge_config_device_t device;
    memset(&device, 0, sizeof(device));
    device.units = view.units;
    device.display_timeout_s = view.display_timeout_s;
    memcpy(device.device_name, view.device_name, sizeof(device.device_name));
    if (bridge_config_set_device(&device) != BRIDGE_CONFIG_OK) {
        ESP_LOGW(TAG, "config write failed to persist");
        return BLE_CONFIG_ATT_STORAGE;
    }

    ESP_LOGI(TAG, "config applied: units %u, timeout %u s, name %s",
             (unsigned)view.units, (unsigned)view.display_timeout_s,
             view.device_name);
    ble_service_config_applied_fn cb = s_config_applied_cb;
    if (cb != NULL) {
        cb(view.units, view.display_timeout_s, s_config_applied_ctx);
    }
    return 0;
}

static int write_value(uint16_t conn_handle,
                       struct ble_gatt_access_ctxt *ctxt,
                       const ble_gatt_spec_t *spec) {
    if (spec->slot == SX4_BLE_CHAR_CONTROL_SLOT) {
        return write_control(conn_handle, ctxt);
    }
    if (spec->slot == SX4_BLE_CHAR_SYNC_CTRL_SLOT) {
        return write_sync_ctrl(conn_handle, ctxt);
    }
    if (spec->slot == SX4_BLE_CHAR_CONFIG_SLOT) {
        return write_config(ctxt);
    }
    /* `stats` is read-only; NimBLE rejects a write by its flags. */
    return BLE_ATT_ERR_WRITE_NOT_PERMITTED;
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
            s_conn_handle = event->connect.conn_handle;
            s_result_subscribed = false;
            s_sync_subscribed = false;
            ble_tx_on_connect(event->connect.conn_handle);
            adv_apply_event(BLE_ADV_EVENT_CONNECTED, false);
            bridge_state_set_sync_active(false);
            ESP_LOGI(TAG, "central connected (handle %u)",
                     event->connect.conn_handle);
        } else {
            s_connected = false;
            s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
            passkey_clear();
            ESP_LOGW(TAG, "connection failed (%d)", event->connect.status);
            adv_apply_event(BLE_ADV_EVENT_CONNECT_FAILED, false);
        }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        s_connected = false;
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        s_result_subscribed = false;
        s_sync_subscribed = false;
        /* A history transfer cannot outlive the link. */
        sync_cancel();
        ble_tx_on_disconnect();
        passkey_clear();
        /* A history transfer cannot outlive the link. */
        bridge_state_set_sync_active(false);
        ESP_LOGI(TAG, "central disconnected (reason 0x%02x)",
                 event->disconnect.reason);
        adv_apply_event(BLE_ADV_EVENT_DISCONNECT, false);
        break;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        /* Our own stop (interval change) is silent. A real controller timeout
         * restarts at the current interval without extending the fast window. */
        if (!s_adv_stopping && !s_connected) {
            s_adv_active = false;
            ESP_LOGW(TAG, "advertising complete (reason %d); restarting",
                     event->adv_complete.reason);
            adv_apply_event(BLE_ADV_EVENT_TIMEOUT, false);
        }
        break;
    case BLE_GAP_EVENT_PASSKEY_ACTION:
        if (event->passkey.params.action == BLE_SM_IOACT_DISP) {
            start_passkey(event->passkey.conn_handle);
        } else {
            /* DisplayOnly never accepts numeric comparison or peer input; a
             * phone that cannot do passkey entry is refused rather than
             * silently downgraded to Just Works. */
            ESP_LOGE(TAG, "unsupported pairing action %u; refusing",
                     event->passkey.params.action);
            (void)ble_gap_terminate(event->passkey.conn_handle,
                                    BLE_SERVICE_PASSKEY_TERM_REASON);
        }
        break;
    case BLE_GAP_EVENT_ENC_CHANGE: {
        struct ble_gap_conn_desc desc;
        passkey_clear();
        refresh_bond_count();
        if (event->enc_change.status == 0 &&
            ble_gap_conn_find(event->enc_change.conn_handle, &desc) == 0) {
            if (!desc.sec_state.authenticated) {
                /* Defence in depth: sm_mitm=1 should already make this
                 * impossible. Never leave a Just Works link usable. */
                ESP_LOGE(TAG, "link encrypted without authentication; "
                              "terminating");
                (void)ble_gap_terminate(event->enc_change.conn_handle,
                                        BLE_SERVICE_PASSKEY_TERM_REASON);
            } else {
                ESP_LOGI(TAG, "link secured (authenticated, %u bond(s))",
                         (unsigned)s_bond_count);
            }
        }
        break;
    }
    case BLE_GAP_EVENT_PARING_COMPLETE:
        passkey_clear();
        refresh_bond_count();
        ESP_LOGI(TAG, "pairing complete (status %d, %u bond(s))",
                 event->pairing_complete.status, (unsigned)s_bond_count);
        break;
    case BLE_GAP_EVENT_REPEAT_PAIRING: {
        struct ble_gap_conn_desc desc;
        uint16_t conn = event->repeat_pairing.conn_handle;
        if (ble_gap_conn_find(conn, &desc) == 0) {
            /* A phone that lost its keys may replace its own bond. This is not
             * an eviction: only the peer asking again is removed. */
            (void)ble_store_util_delete_peer(&desc.peer_id_addr);
            refresh_bond_count();
            ESP_LOGI(TAG, "repeat pairing: replaced this phone's bond");
            return BLE_GAP_REPEAT_PAIRING_RETRY;
        }
        return BLE_GAP_REPEAT_PAIRING_IGNORE;
    }
    case BLE_GAP_EVENT_SUBSCRIBE:
        /* The encrypted CCCD was enforced by the characteristic flags before
         * this event. A live subscription primes the queue with the current
         * snapshot so the app has the same value as a read would give. */
        if (event->subscribe.attr_handle == s_live_handle) {
            ble_tx_on_live_subscribe(event->subscribe.cur_notify != 0);
        } else if (event->subscribe.attr_handle == s_result_handle) {
            s_result_subscribed = event->subscribe.cur_notify != 0;
        } else if (event->subscribe.attr_handle == s_sync_data_handle) {
            s_sync_subscribed = event->subscribe.cur_notify != 0;
            if (!s_sync_subscribed) {
                sync_cancel();
            }
        }
        break;
    default:
        break;
    }
    return 0;
}

uint8_t ble_service_forget_current_peer(void) {
    if (!s_connected || s_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
        return SX4_RESULT_STATUS_NOT_FOUND;
    }
    struct ble_gap_conn_desc desc;
    if (ble_gap_conn_find(s_conn_handle, &desc) != 0) {
        return SX4_RESULT_STATUS_NOT_FOUND;
    }

    int rc = ble_store_util_delete_peer(&desc.peer_id_addr);
    refresh_bond_count();
    if (rc == BLE_HS_ENOENT) {
        return SX4_RESULT_STATUS_NOT_FOUND;
    }
    if (rc != 0) {
        ESP_LOGW(TAG, "forget: bond delete failed (%d)", rc);
        return SX4_RESULT_STATUS_FAILED;
    }

    /* Other phone bonds stay. The disconnect event re-advertises. */
    if (ble_gap_terminate(s_conn_handle, 0x13 /* Remote User Terminated */) !=
        0) {
        ESP_LOGW(TAG, "forget: link termination failed");
        return SX4_RESULT_STATUS_FAILED;
    }
    ESP_LOGI(TAG, "forget: current peer bond removed, %u bond(s) remain",
             (unsigned)s_bond_count);
    return SX4_RESULT_STATUS_OK;
}

bool ble_service_is_connected(void) { return s_connected; }

bool ble_service_is_advertising(void) { return s_adv_active && !s_connected; }

void ble_service_keep_advertising(void) {
    if (!s_synced || s_connected || s_adv_stopping || s_adv_restart_pending) {
        return;
    }
    if (s_adv_active && ble_gap_adv_active()) {
        return;
    }
    s_adv_active = false;
    if (s_adv_state.phase == BLE_ADV_PHASE_OFF) {
        /* The disconnect/boot event was missed; reopen the fast window. */
        adv_apply_event(BLE_ADV_EVENT_DISCONNECT, false);
        return;
    }
    adv_start_with(s_adv_state.phase == BLE_ADV_PHASE_FAST
                       ? BLE_ADV_FAST_INTERVAL_MS
                       : BLE_ADV_SLOW_INTERVAL_MS);
}

uint8_t ble_service_bond_count(void) { return s_bond_count; }

void ble_service_set_passkey_callback(ble_service_passkey_fn fn, void *ctx) {
    s_passkey_cb = fn;
    s_passkey_ctx = ctx;
}

void ble_service_set_config_applied_callback(
    ble_service_config_applied_fn fn, void *ctx) {
    s_config_applied_cb = fn;
    s_config_applied_ctx = ctx;
}

void ble_service_boost_advertising(void) {
    if (!s_synced || s_connected) {
        return;
    }
    adv_apply_event(BLE_ADV_EVENT_BOOT, false);
}

void ble_service_cancel_pairing(void) {    if (!ble_security_passkey_active(&s_passkey)) {
        return;
    }
    ESP_LOGI(TAG, "pairing cancelled by tap");
    passkey_clear();
    if (s_connected && s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        (void)ble_gap_terminate(s_conn_handle,
                                BLE_SERVICE_PASSKEY_TERM_REASON);
    }
}

static void on_reset(int reason) {
    ESP_LOGW(TAG, "host reset (%d)", reason);
    s_synced = false;
    s_connected = false;
    s_result_subscribed = false;
    s_sync_subscribed = false;
    s_sync_busy = false;
    s_adv_active = false;
    s_adv_restart_pending = false;
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    ble_adv_state_init(&s_adv_state);
    passkey_clear();
}

static void on_sync(void) {
    s_synced = true;
    /* The advertising callback owns every connection event. A second global
     * listener would double-deliver connect/encrypt/subscribe events and still
     * miss PASSKEY_ACTION. */

    /* NimBLE examples call this before infer_auto. Without it the controller's
     * static random address can win the infer (the random type is preferred)
     * and advertising starts on an address the name/info suffix does not
     * describe. The contract's identity is the public address. */
    int addr_rc = ble_hs_util_ensure_addr(0);
    if (addr_rc != 0) {
        ESP_LOGW(TAG, "no usable identity address (%d)", addr_rc);
    }
    if (ble_hs_id_copy_addr(BLE_ADDR_PUBLIC, NULL, NULL) == 0) {
        s_own_addr_type = BLE_OWN_ADDR_PUBLIC;
    } else if (ble_hs_id_infer_auto(0, &s_own_addr_type) != 0) {
        s_own_addr_type = BLE_OWN_ADDR_PUBLIC;
        ESP_LOGW(TAG, "no identity address; advertising as public");
    }
    /* Keep the GAP-service name in step with the scan-response name. Android
     * caches the GAP name after pairing and otherwise shows just "SmokeX4-". */
    uint8_t name_mac[6] = {0};
    char local_name[BLE_ADV_NAME_MAX];
    copy_public_addr_display(name_mac);
    if (ble_adv_format_name(local_name, name_mac) > 0) {
        (void)ble_svc_gap_device_name_set(local_name);
    }
    refresh_bond_count();
    ble_adv_state_init(&s_adv_state);
    /* Boot with free slots: advertise immediately. A full bond store still
     * advertises so a phone can read `info` and explain `bonds_free == 0`. */
    adv_apply_event(BLE_ADV_EVENT_BOOT, true);
    ESP_LOGI(TAG, "host synced; %u/%u bond slot(s) used",
             (unsigned)s_bond_count, (unsigned)BLE_SEC_MAX_BONDS);
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

    if (s_sync_mutex == NULL) {
        s_sync_mutex = xSemaphoreCreateMutex();
        if (s_sync_mutex == NULL) {
            ESP_LOGW(TAG, "no mutex for sync_data framing");
        }
    }

    err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nimble_port_init failed (%s)", esp_err_to_name(err));
        return err;
    }

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;

    /* Design 05 5.11: LE Secure Connections, Passkey Entry, DisplayOnly.
     * sm_mitm + sm_sc_only refuse a Just Works / legacy downgrade. The store
     * callback stays NULL on purpose: a full store aborts the new bond instead
     * of NimBLE's default evict-oldest policy. */
    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_DISP_ONLY;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_mitm = 1;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_sc_only = 1;
    ble_hs_cfg.sm_our_key_dist =
        BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist =
        BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.store_status_cb = NULL;

    ble_security_passkey_init(&s_passkey);
    ble_adv_state_init(&s_adv_state);
    s_bond_count = 0;

    /* Device name is only a GAP-service fallback; the scan response carries
     * the real SmokeX4-XXXX name set by adv_build_data(). */
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
    s_sync_subscribed = false;
    sync_cancel();
    s_pending_action = BLE_CONTROL_ACTION_NONE;
    if (s_action_timer != NULL) {
        (void)esp_timer_stop(s_action_timer);
        (void)esp_timer_delete(s_action_timer);
        s_action_timer = NULL;
    }
    if (s_adv_window_timer != NULL) {
        (void)esp_timer_stop(s_adv_window_timer);
        (void)esp_timer_delete(s_adv_window_timer);
        s_adv_window_timer = NULL;
    }
    if (s_adv_restart_timer != NULL) {
        (void)esp_timer_stop(s_adv_restart_timer);
        (void)esp_timer_delete(s_adv_restart_timer);
        s_adv_restart_timer = NULL;
    }
    passkey_clear();
    if (s_passkey_timer != NULL) {
        (void)esp_timer_delete(s_passkey_timer);
        s_passkey_timer = NULL;
    }
    if (s_sync_timer != NULL) {
        (void)esp_timer_delete(s_sync_timer);
        s_sync_timer = NULL;
    }
    if (s_sync_mutex != NULL) {
        vSemaphoreDelete(s_sync_mutex);
        s_sync_mutex = NULL;
    }
    ble_adv_state_init(&s_adv_state);
    s_adv_active = false;
    s_adv_restart_pending = false;
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    if (nimble_port_stop() == 0) {
        (void)nimble_port_deinit();
    }
    s_started = false;
    s_synced = false;
    s_connected = false;
    return ESP_OK;
}
