/* app_ble_ctrl.c — the write dispatcher for every device_control op (F10.8).
 *
 * There is no wifi_config or Wi-Fi scan characteristic on this BLE-only
 * build. Every write is answered on `result` with `op_echo` set — including
 * security refusals, malformed frames, and unknown ops. "No answer" is never
 * a valid outcome: the app is a state machine waiting on this
 * characteristic, and silence is the one response it cannot recover from.
 */
#include "app_ble_internal.h"

#include <string.h>

#include "app_config_store.h"
#include "app_ui_cook.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"

#define OP_ECHO_NONE 0

void app_ble_ctrl_reset(void) {
    /* A phone pocketed mid-transfer leaves a stream latched, and every
     * later request would answer BUSY until the board rebooted. The
     * disconnect is the one place that knows the stream's owner is gone. */
    app_ble_history_reset();
}

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

static int op_set_battery_saver(const uint8_t *body, size_t body_len) {
    if (body_len < BRIDGE_CTRL_SET_BATTERY_SAVER_SIZE) {
        return APP_BLE_ERR_INVALID;
    }
    bridge_ctrl_set_battery_saver_t s;
    bridge_ctrl_set_battery_saver_decode(body, &s);
    /* off/on/auto — the same tri-state POST /config/device accepts, so the
     * two transports cannot disagree about what "auto" means. */
    if (s.saver != BRIDGE_BATTERY_SAVER_OFF &&
        s.saver != BRIDGE_BATTERY_SAVER_ON &&
        s.saver != BRIDGE_BATTERY_SAVER_AUTO) {
        return APP_BLE_ERR_INVALID;
    }
    return app_config_store_set_u8(APP_CONFIG_DEV_BATTERY_SAVER, s.saver) ==
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
    /* No device-tier alarm engine on this image, so an ack silences nothing
     * — but it still answers ok: a client retrying an ack for an alarm this
     * build never raised should not see a failure. */
    (void)a;
    return APP_BLE_OK;
}

/* The app-confirmed cook clock (app_ui_cook.h). BLE carries it because BLE
 * is the transport that survives a yard with no Wi-Fi — a display feature
 * that only works when the phone can reach the HTTP API would be missing
 * exactly when the glass is the only thing you can read. */
static int op_set_cook_clock(const uint8_t *body, size_t body_len) {
    if (body_len < BRIDGE_CTRL_SET_COOK_CLOCK_SIZE) {
        return APP_BLE_ERR_INVALID;
    }
    bridge_ctrl_set_cook_clock_t c;
    bridge_ctrl_set_cook_clock_decode(body, &c);
    return app_ui_cook_set(c.elapsed_s,
                           (uint32_t)(g_ble_ops->uptime_ms() / 1000ull)) == 0
               ? APP_BLE_OK
               : APP_BLE_ERR_INVALID;
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
    case BRIDGE_CONTROL_OP_SET_BATTERY_SAVER:
        return op_set_battery_saver(body, body_len);
    case BRIDGE_CONTROL_OP_SET_COOK_CLOCK:
        return op_set_cook_clock(body, body_len);
    case BRIDGE_CONTROL_OP_CLEAR_COOK_CLOCK:
        /* No body, and never a failure: clearing a clock that is already
         * clear is what a second `stop` from a retrying client looks like. */
        app_ui_cook_clear();
        return APP_BLE_OK;
    case BRIDGE_CONTROL_OP_IDENTIFY:
        /* Wakes the display and flashes what exists; the LED driver is
         * M5's F11b. Noted as partial rather than faked. */
        return g_ble_ops->identify != NULL ? g_ble_ops->identify()
                                           : APP_BLE_ERR_FAILED;
    case BRIDGE_CONTROL_OP_REBOOT:
    case BRIDGE_CONTROL_OP_FACTORY_RESET:
    case BRIDGE_CONTROL_OP_POWER_OFF:
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

    /* Reboot, factory reset and power off all destroy the link that carries
     * the answer, so they run only after it has been pushed. */
    if (rc == APP_BLE_OK) {
        if (c.op == BRIDGE_CONTROL_OP_FACTORY_RESET) {
            if (g_ble_ops->factory_reset != NULL) {
                (void)g_ble_ops->factory_reset();
            }
        } else if (c.op == BRIDGE_CONTROL_OP_REBOOT) {
            if (g_ble_ops->reboot != NULL) {
                g_ble_ops->reboot();
            }
        } else if (c.op == BRIDGE_CONTROL_OP_POWER_OFF) {
            if (g_ble_ops->power_off != NULL) {
                g_ble_ops->power_off();
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
    case APP_BLE_CH_DEVICE_CONTROL:
        return handle_device_control(data, len);
    case APP_BLE_CH_HISTORY_CTRL:
        /* Answered on history_data, never on `result` (§5.10): result's
         * op_echo space is control_op's, and a stream that died halfway
         * has to be distinguishable from one that finished. */
        return app_ble_history_write(data, len);
    default:
        return APP_BLE_ERR_INVALID;
    }
}
