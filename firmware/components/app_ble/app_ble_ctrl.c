/* app_ble_ctrl.c — the write dispatcher: wifi_config (F10.6), the Wi-Fi
 * scan flow (F10.7), and all eleven device_control ops (F10.8).
 *
 * Every write is answered on `result` with `op_echo` set — including
 * security refusals, malformed frames, and unknown ops. "No answer" is
 * never a valid outcome: the wizard is a state machine waiting on this
 * characteristic, and silence is the one response it cannot recover from.
 */
#include "app_ble_internal.h"

#include <string.h>

#include "app_alarm_svc.h"
#include "app_config_store.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"

/* wifi_config and wifi_scan_ctrl answer with op_echo 0 (ble-gatt §5.9). */
#define OP_ECHO_NONE 0

static bool s_scanning;

void app_ble_ctrl_reset(void) { s_scanning = false; }

int app_ble_answer(uint8_t op_echo, uint8_t status, const char *detail) {
    bridge_result_t r;
    memset(&r, 0, sizeof r);
    r.ver = 1;
    r.op_echo = op_echo;
    r.status = status;
    if (detail != NULL) {
        size_t n = strlen(detail);
        if (n > sizeof r.detail) {
            n = sizeof r.detail;
        }
        r.len = (uint8_t)n;
        memcpy(r.detail, detail, n);
    }
    uint8_t buf[BRIDGE_RESULT_MAX_SIZE];
    const int len = bridge_result_pack(&r, buf, sizeof buf);
    if (len < 0) {
        return APP_BLE_ERR_FAILED;
    }
    return app_ble_notify_chunked(APP_BLE_CH_RESULT, buf, (size_t)len);
}

static uint8_t status_of(int rc) {
    switch (rc) {
    case APP_BLE_OK:
        return BRIDGE_RESULT_STATUS_OK;
    case APP_BLE_ERR_BUSY:
        return BRIDGE_RESULT_STATUS_BUSY;
    case APP_BLE_ERR_INVALID:
        return BRIDGE_RESULT_STATUS_INVALID;
    default:
        return BRIDGE_RESULT_STATUS_FAILED;
    }
}

/* ── wifi_config (F10.6, ble-gatt §5.5) ───────────────────────────── */

static int handle_wifi_config(const uint8_t *data, size_t len) {
    bridge_wifi_config_t c;
    memset(&c, 0, sizeof c);
    if (bridge_wifi_config_unpack(data, len, &c) < 0) {
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                              "malformed wifi_config");
    }
    if (c.mode != BRIDGE_NET_MODE_AP && c.mode != BRIDGE_NET_MODE_STA) {
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                              "mode must be ap|sta");
    }

    app_net_pending_cfg_t cfg;
    memset(&cfg, 0, sizeof cfg);
    /* The wire enum and the stored enum are NOT the same numbers
     * (ble-gatt: off/ap/sta = 0/1/2; app_config: ap/sta = 0/1). Translate
     * once, here, like app_api_core does. */
    cfg.mode = c.mode == BRIDGE_NET_MODE_STA ? APP_CONFIG_NET_MODE_STA
                                             : APP_CONFIG_NET_MODE_AP;
    if (cfg.mode == APP_CONFIG_NET_MODE_STA) {
        if (c.ssid_len == 0) {
            return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                                  "sta mode needs an ssid");
        }
        memcpy(cfg.sta_ssid, c.ssid, c.ssid_len);
        cfg.sta_ssid[c.ssid_len] = '\0';
        memcpy(cfg.sta_psk, c.psk, c.psk_len);
        cfg.sta_psk[c.psk_len] = '\0';
        memcpy(cfg.sta_user, c.user, c.user_len);
        cfg.sta_user[c.user_len] = '\0';
        cfg.sta_auth = c.auth;
    }

    /* ANSWER FIRST, then hand off to the ~500 ms deferred apply F8.4 built
     * for exactly this moment — so the acknowledgement flushes before the
     * radio it rode on reconfigures (05 §5.4). Reversing these two lines
     * is the bug that makes a wrong password unrecoverable from a lawn
     * chair, which is the entire point of the milestone. */
    int rc;
    if (cfg.mode == APP_CONFIG_NET_MODE_AP) {
        /* detail carries the generated AP PSK: the phone needs it to join.
         * This is the ONLY credential any characteristic ever emits — the
         * stored STA PSK is never read back on any path (grep-proofed in
         * test_app_ble.c, the same discipline F9.7 set). */
        char ap_psk[APP_CONFIG_PSK_LEN + 1] = "";
        (void)app_config_store_get_str(APP_CONFIG_NET_AP_PSK, ap_psk,
                                       sizeof ap_psk);
        rc = app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_OK, ap_psk);
    } else {
        rc = app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_OK, NULL);
    }
    if (g_ble_ops->net_request_config != NULL) {
        (void)g_ble_ops->net_request_config(&cfg);
    }
    return rc;
}

/* ── wifi_scan_ctrl / wifi_scan_result (F10.7, §5.3–§5.4) ─────────── */

static int handle_scan_ctrl(const uint8_t *data, size_t len) {
    if (len < BRIDGE_WIFI_SCAN_CTRL_SIZE) {
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                              "short wifi_scan_ctrl");
    }
    bridge_wifi_scan_ctrl_t c;
    bridge_wifi_scan_ctrl_decode(data, &c);

    if (c.cmd == BRIDGE_SCAN_CMD_CANCEL) {
        s_scanning = false;
        if (g_ble_ops->scan_cancel != NULL) {
            (void)g_ble_ops->scan_cancel();
        }
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_OK, NULL);
    }
    if (c.cmd != BRIDGE_SCAN_CMD_START) {
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                              "cmd must be start|cancel");
    }
    /* A scan already running answers busy WITHOUT disturbing it — the
     * running scan's results are still on their way to whoever asked. */
    if (s_scanning) {
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_BUSY,
                              "scan in progress");
    }
    const int rc =
        g_ble_ops->scan_start != NULL ? g_ble_ops->scan_start() : APP_BLE_ERR_FAILED;
    if (rc == APP_BLE_OK) {
        s_scanning = true;
    }
    return app_ble_answer(OP_ECHO_NONE, status_of(rc), NULL);
}

bool app_ble_scan_active(void) { return s_scanning; }

int app_ble_scan_deliver(const app_ble_scan_ap_t *aps, int n) {
    if (!s_scanning) {
        return APP_BLE_OK; /* cancelled before the results arrived */
    }
    if (n < 0) {
        n = 0;
    }
    if (n > 255) {
        n = 255; /* index/total are u8; a 256-AP scan is not a real place */
    }
    /* An empty scan still completes: total 0 means "nothing found", which
     * the wizard must render as an empty list, not as a hang. */
    for (int i = 0; i < n; i++) {
        if (!s_scanning) {
            break; /* cancelled mid-stream: stop, do not finish the list */
        }
        bridge_wifi_scan_result_t r;
        memset(&r, 0, sizeof r);
        r.ver = 1;
        r.index = (uint8_t)i;
        r.total = (uint8_t)n;
        r.rssi = aps[i].rssi;
        r.auth = aps[i].auth;
        r.channel = aps[i].channel;
        size_t ssid_len = strnlen(aps[i].ssid, sizeof aps[i].ssid - 1);
        if (ssid_len > sizeof r.ssid) {
            ssid_len = sizeof r.ssid;
        }
        r.ssid_len = (uint8_t)ssid_len;
        memcpy(r.ssid, aps[i].ssid, ssid_len);

        uint8_t buf[BRIDGE_WIFI_SCAN_RESULT_MAX_SIZE];
        const int len = bridge_wifi_scan_result_pack(&r, buf, sizeof buf);
        if (len < 0) {
            continue;
        }
        (void)app_ble_notify_chunked(APP_BLE_CH_WIFI_SCAN_RESULT, buf,
                                     (size_t)len);
    }
    s_scanning = false;
    return APP_BLE_OK;
}

/* ── device_control (F10.8, §5.6) ─────────────────────────────────── */

static int op_mark(const uint8_t *body, size_t body_len) {
    if (!cook_session_is_open()) {
        return APP_BLE_ERR_INVALID; /* marks land on the active session */
    }
    bridge_ctrl_mark_t m;
    memset(&m, 0, sizeof m);
    if (bridge_ctrl_mark_unpack(body, body_len, &m) < 0) {
        return APP_BLE_ERR_INVALID;
    }
    /* UTF-8 truncation lives in the store (F5.9); the handler only
     * validates, exactly as the REST path does. */
    char text[25];
    size_t n = m.len;
    if (n > sizeof text - 1) {
        n = sizeof text - 1;
    }
    memcpy(text, m.text, n);
    text[n] = '\0';
    const cook_ring_sample_t *newest = cook_ring_get(0);
    const uint32_t t = newest != NULL ? newest->t : 0;
    return cook_session_mark(t, m.kind, 0, text) == COOK_STORE_OK
               ? APP_BLE_OK
               : APP_BLE_ERR_FAILED;
}

static int op_set_time(const uint8_t *body, size_t body_len) {
    if (body_len < BRIDGE_CTRL_SET_TIME_SIZE) {
        return APP_BLE_ERR_INVALID;
    }
    bridge_ctrl_set_time_t t;
    bridge_ctrl_set_time_decode(body, &t);
    if (t.unix_ms == 0) {
        return APP_BLE_ERR_INVALID;
    }
    (void)app_config_store_set_i32(APP_CONFIG_TIME_TZ_OFFSET_MIN,
                                   t.tz_offset_min);
    /* The `phone` source. F6.1 arbitration decides whether it is adopted;
     * F6.2's back-patch rides the acquisition event, already built and
     * tested — which is why the wizard's step 3 dates a session from its
     * first sample rather than from whenever the phone showed up. */
    (void)app_time_core_set(APP_TIME_PHONE, t.unix_ms,
                            g_ble_ops->uptime_ms());
    return APP_BLE_OK;
}

static int op_set_units(const uint8_t *body, size_t body_len) {
    if (body_len < BRIDGE_CTRL_SET_UNITS_SIZE) {
        return APP_BLE_ERR_INVALID;
    }
    bridge_ctrl_set_units_t u;
    bridge_ctrl_set_units_decode(body, &u);
    if (u.units != BRIDGE_UNITS_CELSIUS && u.units != BRIDGE_UNITS_FAHRENHEIT) {
        return APP_BLE_ERR_INVALID;
    }
    return app_config_store_set_u8(APP_CONFIG_DEV_UNITS, u.units) ==
                   APP_CONFIG_OK
               ? APP_BLE_OK
               : APP_BLE_ERR_FAILED;
}

static int op_ack_alarm(const uint8_t *body, size_t body_len) {
    if (body_len < BRIDGE_CTRL_ACK_ALARM_SIZE) {
        return APP_BLE_ERR_INVALID;
    }
    bridge_ctrl_ack_alarm_t a;
    bridge_ctrl_ack_alarm_decode(body, &a);
    /* F13.8 — routed. An unknown or already-acked id silences nothing and
     * still answers ok: HTTP, BLE and the PRG button can all send the same
     * ack for the same alarm, and none of them should see a failure for
     * being second. */
    (void)app_alarm_svc_ack(a.alarm_id);
    return APP_BLE_OK;
}

static int dispatch_op(uint8_t op, const uint8_t *body, size_t body_len) {
    switch (op) {
    case BRIDGE_CONTROL_OP_PAIR:
        /* Re-enter sync/scan toward the base station. Touches nothing
         * outside this device — an invariant two milestones old (§2.5). */
        return smoke_x_ctrl_unpair() == 0 ? APP_BLE_OK : APP_BLE_ERR_FAILED;
    case BRIDGE_CONTROL_OP_UNPAIR:
        return smoke_x_ctrl_unpair() == 0 ? APP_BLE_OK : APP_BLE_ERR_FAILED;
    case BRIDGE_CONTROL_OP_SESSION_START:
        if (cook_session_is_open()) {
            return APP_BLE_ERR_BUSY; /* same refusal as the REST group */
        }
        return cook_store_request_start() == COOK_STORE_OK ? APP_BLE_OK
                                                           : APP_BLE_ERR_FAILED;
    case BRIDGE_CONTROL_OP_SESSION_STOP:
        if (!cook_session_is_open()) {
            return APP_BLE_ERR_INVALID;
        }
        return cook_store_request_stop() == COOK_STORE_OK ? APP_BLE_OK
                                                          : APP_BLE_ERR_FAILED;
    case BRIDGE_CONTROL_OP_SET_TIME:
        return op_set_time(body, body_len);
    case BRIDGE_CONTROL_OP_MARK:
        return op_mark(body, body_len);
    case BRIDGE_CONTROL_OP_SET_UNITS:
        return op_set_units(body, body_len);
    case BRIDGE_CONTROL_OP_ACK_ALARM:
        return op_ack_alarm(body, body_len);
    case BRIDGE_CONTROL_OP_IDENTIFY:
        /* Wakes the display and flashes what exists; the LED driver is
         * M5's F11b. Noted as partial rather than faked. */
        return g_ble_ops->identify != NULL ? g_ble_ops->identify()
                                           : APP_BLE_ERR_FAILED;
    case BRIDGE_CONTROL_OP_REBOOT:
    case BRIDGE_CONTROL_OP_FACTORY_RESET:
        return APP_BLE_OK; /* answered first, executed after — see below */
    default:
        return APP_BLE_ERR_INVALID;
    }
}

static int handle_device_control(const uint8_t *data, size_t len) {
    bridge_device_control_t c;
    memset(&c, 0, sizeof c);
    if (bridge_device_control_unpack(data, len, &c) < 0) {
        /* Short or over-length: answer invalid rather than crash. The
         * version byte is NEVER a rejection reason (the additive-growth
         * rule at the top of ble-gatt.md). */
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                              "malformed device_control");
    }

    const int rc = dispatch_op(c.op, c.body, c.body_len);
    const int answered = app_ble_answer(c.op, status_of(rc), NULL);

    /* Reboot and factory reset destroy the link that carries the answer,
     * so they run only after it has been pushed. */
    if (rc == APP_BLE_OK) {
        if (c.op == BRIDGE_CONTROL_OP_FACTORY_RESET) {
            if (g_ble_ops->factory_reset != NULL) {
                (void)g_ble_ops->factory_reset();
            }
        } else if (c.op == BRIDGE_CONTROL_OP_REBOOT) {
            if (g_ble_ops->reboot != NULL) {
                g_ble_ops->reboot();
            }
        }
    }
    return answered;
}

/* ── entry point ──────────────────────────────────────────────────── */

int app_ble_core_write(app_ble_char_t ch, const app_ble_link_t *link,
                       const uint8_t *data, size_t len) {
    const app_ble_char_def_t *def = app_ble_char_def(ch);
    if (def == NULL || (def->props & APP_BLE_PROP_WRITE) == 0) {
        return APP_BLE_ERR_INVALID;
    }
    /* The security layer, not the handler: a write that fails here never
     * reaches the code that would act on it (F10.5). */
    if (!app_ble_access_allowed(ch, link)) {
        return app_ble_answer(OP_ECHO_NONE,
                              BRIDGE_RESULT_STATUS_UNAUTHORIZED,
                              "insufficient link security");
    }
    if (data == NULL || len > def->max_len) {
        return app_ble_answer(OP_ECHO_NONE, BRIDGE_RESULT_STATUS_INVALID,
                              "over-length write");
    }
    switch (ch) {
    case APP_BLE_CH_WIFI_SCAN_CTRL:
        return handle_scan_ctrl(data, len);
    case APP_BLE_CH_WIFI_CONFIG:
        return handle_wifi_config(data, len);
    case APP_BLE_CH_DEVICE_CONTROL:
        return handle_device_control(data, len);
    default:
        return APP_BLE_ERR_INVALID;
    }
}
