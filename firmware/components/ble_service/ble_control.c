/*
 * ble_control.c - pure `control` dispatcher and `result` encoder (T29).
 *
 * Design 05 5.5/5.6/5.13. The entire op body is validated before any state is
 * touched; set_time is the only live op in V0. Status is the machine branch,
 * detail is only a human hint.
 */
#include "ble_control.h"

#include <stddef.h>
#include <string.h>

#include "bridge_state.h"
#include "records.h"

static ble_control_action_fn s_action_fn;
static void *s_action_ctx;

/* ---- result helpers ------------------------------------------------------ */

const char *ble_control_status_detail(uint8_t status) {
    switch (status) {
    case SX4_RESULT_STATUS_OK:
        return "ok";
    case SX4_RESULT_STATUS_INVALID:
        return "invalid request";
    case SX4_RESULT_STATUS_UNSUPPORTED:
        return "unsupported";
    case SX4_RESULT_STATUS_BUSY:
        return "busy";
    case SX4_RESULT_STATUS_UNAUTHORIZED:
        return "not authorized";
    case SX4_RESULT_STATUS_FAILED:
        return "failed";
    case SX4_RESULT_STATUS_NOT_FOUND:
        return "not found";
    case SX4_RESULT_STATUS_STORAGE:
        return "storage unavailable";
    default:
        return "unknown status";
    }
}

static void result_reset(ble_control_result_t *out, uint8_t status,
                         const char *detail) {
    memset(out, 0, sizeof(*out));
    out->ver = 1;
    out->status = status;
    const char *text = detail != NULL ? detail : ble_control_status_detail(status);
    size_t n = strlen(text);
    if (n > BLE_CONTROL_DETAIL_MAX) {
        n = BLE_CONTROL_DETAIL_MAX;
    }
    memcpy(out->detail, text, n);
    out->detail[n] = '\0';
    out->action = BLE_CONTROL_ACTION_NONE;
    out->action_delay_ms = 0;
}

/*
 * Number of bytes to copy from a NUL-terminated UTF-8 string, capped at `max`.
 * When the cap falls inside a multi-byte sequence, the partial sequence is
 * dropped so the wire never carries an invalid UTF-8 tail.
 */
static size_t utf8_prefix_len(const char *text, size_t max) {
    size_t n = 0;
    while (n < max && text[n] != '\0') {
        n++;
    }
    if (n < max) {
        return n; /* whole string fit */
    }

    size_t start = n;
    while (start > 0 && ((unsigned char)text[start - 1] & 0xC0u) == 0x80u) {
        start--;
    }
    if (start == 0) {
        return n; /* no lead byte in the tail: treat it as opaque bytes */
    }
    unsigned char lead = (unsigned char)text[start - 1];
    size_t need;
    if ((lead & 0xE0u) == 0xC0u) {
        need = 2;
    } else if ((lead & 0xF0u) == 0xE0u) {
        need = 3;
    } else if ((lead & 0xF8u) == 0xF0u) {
        need = 4;
    } else {
        return n;
    }
    size_t have = n - (start - 1);
    return have < need ? start - 1 : n;
}

size_t ble_control_encode_result(const ble_control_result_t *result,
                                 uint8_t *out, size_t cap) {
    if (result == NULL || out == NULL || cap < 5u) {
        return 0;
    }
    size_t max_detail = cap - 5u;
    if (max_detail > BLE_CONTROL_DETAIL_MAX) {
        max_detail = BLE_CONTROL_DETAIL_MAX;
    }
    size_t detail_len = utf8_prefix_len(result->detail, max_detail);

    out[0] = 1u;
    out[1] = result->op;
    out[2] = result->op_id;
    out[3] = result->status;
    out[4] = (uint8_t)detail_len;
    if (detail_len > 0u) {
        memcpy(out + 5, result->detail, detail_len);
    }
    return 5u + detail_len;
}

/* ---- security ------------------------------------------------------------ */

int ble_control_write_security(bool encrypted, bool authenticated) {
    if (!encrypted) {
        return BLE_CONTROL_ATT_INSUFFICIENT_ENC;
    }
    if (!authenticated) {
        return BLE_CONTROL_ATT_INSUFFICIENT_AUTHEN;
    }
    return BLE_CONTROL_ATT_OK;
}

void ble_control_set_action_handler(ble_control_action_fn fn, void *ctx) {
    s_action_fn = fn;
    s_action_ctx = ctx;
}

/* ---- dispatcher ---------------------------------------------------------- */

static uint8_t set_time(uint8_t op_id, const uint8_t *body, size_t body_len,
                        ble_control_result_t *out);
static uint8_t destructive_op(uint8_t op, uint8_t op_id,
                              ble_control_result_t *out);

uint8_t ble_control_handle(const uint8_t *in, size_t in_len,
                           ble_control_result_t *out) {
    if (out == NULL) {
        return SX4_RESULT_STATUS_INVALID;
    }
    result_reset(out, SX4_RESULT_STATUS_INVALID, NULL);

    if (in == NULL || in_len < SX4_CONTROL_SIZE) {
        /* Echo whatever part of the envelope arrived so the client can match. */
        result_reset(out, SX4_RESULT_STATUS_INVALID, "malformed control");
        if (in != NULL && in_len >= 2u) {
            out->op = in[1];
        }
        if (in != NULL && in_len >= 3u) {
            out->op_id = in[2];
        }
        return out->status;
    }

    out->op = in[1];
    out->op_id = in[2];

    if (in[0] != 1u) {
        result_reset(out, SX4_RESULT_STATUS_INVALID, "unsupported version");
        out->op = in[1];
        out->op_id = in[2];
        return out->status;
    }

    const uint8_t *body = in + SX4_CONTROL_SIZE;
    size_t body_len = in_len - SX4_CONTROL_SIZE;

    switch (out->op) {
    case SX4_CONTROL_OP_SET_TIME:
        return set_time(out->op_id, body, body_len, out);
    case SX4_CONTROL_OP_FORGET_PHONE:
    case SX4_CONTROL_OP_FACTORY_RESET:
    case SX4_CONTROL_OP_POWER_OFF:
    case SX4_CONTROL_OP_CLEAR_HISTORY:
    case SX4_CONTROL_OP_UNPAIR_SMOKE_X:
        if (body_len != 0u) {
            result_reset(out, SX4_RESULT_STATUS_INVALID, "unexpected body");
            out->op = in[1];
            out->op_id = in[2];
            return out->status;
        }
        return destructive_op(out->op, out->op_id, out);
    case SX4_CONTROL_OP_SET_BILLOWS_TARGET:
        if (body_len != SX4_CONTROL_SET_BILLOWS_TARGET_BODY_SIZE) {
            result_reset(out, SX4_RESULT_STATUS_INVALID, "bad body length");
            out->op = in[1];
            out->op_id = in[2];
            return out->status;
        }
        result_reset(out, SX4_RESULT_STATUS_UNSUPPORTED,
                     "billows control unavailable");
        out->op = in[1];
        out->op_id = in[2];
        return out->status;
    default:
        result_reset(out, SX4_RESULT_STATUS_UNSUPPORTED, "unknown op");
        out->op = in[1];
        out->op_id = in[2];
        return out->status;
    }
}

static uint8_t destructive_op(uint8_t op, uint8_t op_id,
                              ble_control_result_t *out) {
    /*
     * T48 registers the handler. Until then the feature is absent and the app
     * is told so; once a handler exists the dispatcher plans the reply-first
     * action and the adapter runs it after the result notification.
     */
    if (s_action_fn == NULL) {
        result_reset(out, SX4_RESULT_STATUS_UNSUPPORTED,
                     "not available in this build");
        out->op = op;
        out->op_id = op_id;
        return out->status;
    }

    uint8_t action;
    switch (op) {
    case SX4_CONTROL_OP_FORGET_PHONE:
        action = BLE_CONTROL_ACTION_FORGET_PHONE;
        break;
    case SX4_CONTROL_OP_FACTORY_RESET:
        action = BLE_CONTROL_ACTION_FACTORY_RESET;
        break;
    case SX4_CONTROL_OP_POWER_OFF:
        action = BLE_CONTROL_ACTION_POWER_OFF;
        break;
    case SX4_CONTROL_OP_CLEAR_HISTORY:
        action = BLE_CONTROL_ACTION_CLEAR_HISTORY;
        break;
    case SX4_CONTROL_OP_UNPAIR_SMOKE_X:
        action = BLE_CONTROL_ACTION_UNPAIR_SMOKE_X;
        break;
    default:
        result_reset(out, SX4_RESULT_STATUS_UNSUPPORTED, "unknown op");
        out->op = op;
        out->op_id = op_id;
        return out->status;
    }

    result_reset(out, SX4_RESULT_STATUS_OK, "accepted");
    out->op = op;
    out->op_id = op_id;
    out->action = action;
    out->action_delay_ms = BLE_CONTROL_ACTION_DELAY_MS;
    return out->status;
}

static uint8_t set_time(uint8_t op_id, const uint8_t *body, size_t body_len,
                        ble_control_result_t *out) {
    if (body_len != SX4_CONTROL_SET_TIME_BODY_SIZE) {
        result_reset(out, SX4_RESULT_STATUS_INVALID, "bad set_time length");
        out->op = SX4_CONTROL_OP_SET_TIME;
        out->op_id = op_id;
        return out->status;
    }

    sx4_control_set_time_body_t request;
    if (!sx4_control_set_time_body_decode(body, body_len, &request)) {
        result_reset(out, SX4_RESULT_STATUS_INVALID, "malformed set_time");
        out->op = SX4_CONTROL_OP_SET_TIME;
        out->op_id = op_id;
        return out->status;
    }

    /* tz_offset_min is advisory for the app: the bridge keeps UTC only. */
    uint64_t unix_s = request.unix_ms / 1000u;
    if (request.unix_ms == 0u || unix_s == 0u) {
        result_reset(out, SX4_RESULT_STATUS_INVALID, "clock out of range");
        out->op = SX4_CONTROL_OP_SET_TIME;
        out->op_id = op_id;
        return out->status;
    }

    bridge_state_result_t rc = bridge_state_set_time(unix_s);
    switch (rc) {
    case BRIDGE_STATE_OK:
        result_reset(out, SX4_RESULT_STATUS_OK, "clock set");
        break;
    case BRIDGE_STATE_ERR_TIME:
    case BRIDGE_STATE_ERR_ARGUMENT:
        result_reset(out, SX4_RESULT_STATUS_INVALID, "clock out of range");
        break;
    case BRIDGE_STATE_ERR_STORAGE:
        result_reset(out, SX4_RESULT_STATUS_STORAGE, "clock not saved");
        break;
    default:
        result_reset(out, SX4_RESULT_STATUS_FAILED, "clock update failed");
        break;
    }
    out->op = SX4_CONTROL_OP_SET_TIME;
    out->op_id = op_id;
    return out->status;
}

/*
 * Intentionally unused in T29: T48 registers a handler and starts filling
 * result.action. Kept here so the reply-first seam lives with the dispatcher.
 */
void ble_control_run_action(ble_control_action_t action) {
    if (s_action_fn != NULL && action != BLE_CONTROL_ACTION_NONE) {
        s_action_fn(action, s_action_ctx);
    }
}
