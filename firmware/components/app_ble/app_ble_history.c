/* app_ble_history.c — full history over BLE (ble-gatt §5.10–§5.11).
 *
 * The §5.8 preview was written on the assumption that Wi-Fi is how you
 * fetch a cook and Bluetooth is how you watch one. That is backwards for
 * this device's resting state: the bridge sits by the smoker recording
 * since the fire was lit, and the phone that walks up hours later is in a
 * yard with no Wi-Fi. A 12 h cook is 1,440 records — 23 KB — which is
 * seconds on a negotiated link. This file is what makes that transfer
 * possible over the transport that is actually there.
 *
 * TWO RULES, both inherited:
 *
 *  1. Frames serialize through record_gen.h, and `samples`/`marks` carry
 *     the ON-DISK RECORD VERBATIM — CRC included. The bridge never
 *     re-encodes them, so a corrupt record is caught by the phone rather
 *     than laundered into a plausible temperature on the way out.
 *  2. NO FLASH ON THE NIMBLE HOST TASK. The write handler validates and
 *     latches; the streaming runs on the ble_push row, the same structural
 *     rule app_ble.c has carried since F10.4. On the host suite there is
 *     no row and no stack to protect, so the request runs inline.
 */
#include "app_ble_internal.h"

#include <string.h>

#include "cook_store_core.h"

/* The frame is filled to the largest whole number of items that fits, so
 * an item never straddles two frames — the client decodes each frame
 * independently and a dropped one costs exactly that frame. */
#define HIST_PAYLOAD_MAX 237u

/* ── the one in-flight request (§5.10: one stream at a time) ───────── */

typedef struct {
    bool active; /* latched by the write, cleared when the stream ends */
    uint8_t req;
    uint16_t stride;
    uint32_t session_id;
    uint32_t from_t;
    uint32_t to_t;

    /* frame accumulator */
    uint16_t seq;
    uint8_t kind;
    uint8_t items;
    uint16_t used;
    uint8_t payload[HIST_PAYLOAD_MAX];

    bool cancelled;
    int notify_err;
} hist_t;

static hist_t s_h;

void app_ble_history_reset(void) { memset(&s_h, 0, sizeof s_h); }

bool app_ble_history_active(void) { return s_h.active; }

/* ── framing ──────────────────────────────────────────────────────── */

static int emit(uint8_t kind, uint8_t count, const uint8_t *payload,
                uint16_t len, bool last) {
    bridge_history_data_t f;
    memset(&f, 0, sizeof f);
    f.ver = 1;
    f.kind = kind;
    f.seq = s_h.seq++;
    f.flags = last ? BRIDGE_HISTORY_DATA_FLAGS_LAST : 0;
    f.count = count;
    f.len = (uint8_t)len;
    if (len > 0 && payload != NULL) {
        memcpy(f.payload, payload, len);
    }
    uint8_t buf[BRIDGE_HISTORY_DATA_MAX_SIZE];
    const int n = bridge_history_data_pack(&f, buf, sizeof buf);
    if (n < 0) {
        return APP_BLE_ERR_FAILED;
    }
    return app_ble_notify_chunked(APP_BLE_CH_HISTORY_DATA, buf, (size_t)n);
}

/* Flushes whatever the accumulator holds. Never emits an empty frame:
 * "no items" is said once, by the end frame, so a client counting frames
 * cannot be fooled into thinking data arrived. */
static void flush_frame(void) {
    if (s_h.items == 0) {
        return;
    }
    const int rc = emit(s_h.kind, s_h.items, s_h.payload, s_h.used, false);
    if (rc != APP_BLE_OK) {
        s_h.notify_err = rc;
    }
    s_h.items = 0;
    s_h.used = 0;
}

/* Appends one fixed-size item, flushing first when it would not fit. */
static void push_item(uint8_t kind, const uint8_t *item, uint16_t size) {
    if (s_h.notify_err != APP_BLE_OK || s_h.cancelled) {
        return;
    }
    if (s_h.kind != kind || s_h.used + size > HIST_PAYLOAD_MAX) {
        flush_frame();
        s_h.kind = kind;
    }
    memcpy(s_h.payload + s_h.used, item, size);
    s_h.used = (uint16_t)(s_h.used + size);
    s_h.items++;
}

/* The terminator, and the only frame that reports a status (§5.11). A
 * response without exactly one of these is a bug the client can see. */
static void finish(uint8_t status) {
    flush_frame();
    const uint8_t body = status;
    (void)emit(BRIDGE_HISTORY_KIND_END, 0, &body, 1, true);
    s_h.active = false;
}

/* ── the three answers ────────────────────────────────────────────── */

/* Projects the 256 B session_header down to the 56 B the wire carries
 * (§5.11). Lossy on purpose: the header is mostly probe metadata and
 * reserved space, and paying 5× the bytes to send zeroes over a link
 * measured in single-digit KB/s would be exactly the thoughtlessness this
 * contract exists to prevent. */
static void project_session(const bridge_session_header_t *h,
                            bridge_history_session_t *out) {
    memset(out, 0, sizeof *out);
    out->session_id = h->session_id;
    out->started_unix_ms = h->started_unix_ms;
    out->ended_unix_ms = h->ended_unix_ms;
    out->sample_period_s = (uint16_t)h->sample_period_s;
    out->num_probes = h->num_probes;
    out->flags = h->flags;
    memcpy(out->name, h->name, sizeof out->name);
    /* sample_count is authoritative only once the session is closed
     * (04 §4.3); while it is open the store derives it from the file
     * size, and THAT is the number the phone must size its sync against.
     * Trusting the header field here would tell a phone connecting to a
     * live 12 h cook that the session holds 0 samples. */
    out->sample_count =
        (h->flags & BRIDGE_SESSION_HEADER_FLAGS_CLOSED) != 0
            ? h->sample_count
            : (h->session_id == cook_session_active_id() &&
                       cook_session_is_open()
                   ? cook_session_sample_count()
                   : h->sample_count);
}

static void stream_sessions(void) {
    const int n = cook_store_index_count();
    for (int i = 0; i < n && !s_h.cancelled; i++) {
        const cook_index_entry_t *e = cook_store_index_get(i);
        if (e == NULL) {
            continue;
        }
        bridge_session_header_t h;
        if (cook_store_read_header(e->session_id, &h) != COOK_STORE_OK) {
            continue; /* a session the index knows and the file does not */
        }
        bridge_history_session_t s;
        project_session(&h, &s);
        uint8_t item[BRIDGE_HISTORY_SESSION_SIZE];
        bridge_history_session_encode(&s, item);
        push_item(BRIDGE_HISTORY_KIND_SESSION, item, BRIDGE_HISTORY_SESSION_SIZE);
    }
    finish(s_h.notify_err == APP_BLE_OK ? BRIDGE_RESULT_STATUS_OK
                                        : BRIDGE_RESULT_STATUS_FAILED);
}

static int on_sample(void *ctx, const bridge_sample_rec_t *rec) {
    (void)ctx;
    if (s_h.cancelled || s_h.notify_err != APP_BLE_OK) {
        return 1; /* abort the stream */
    }
    /* Verbatim, straight back out: the record the phone gets is the
     * record on flash, byte for byte. */
    uint8_t item[BRIDGE_SAMPLE_REC_SIZE];
    bridge_sample_rec_encode(rec, item);
    push_item(BRIDGE_HISTORY_KIND_SAMPLES, item, BRIDGE_SAMPLE_REC_SIZE);
    return 0;
}

static void stream_samples(void) {
    bridge_session_header_t h;
    if (cook_store_read_header(s_h.session_id, &h) != COOK_STORE_OK) {
        finish(BRIDGE_RESULT_STATUS_INVALID);
        return;
    }
    /* stride 0 is read as 1 rather than refused (§5.10): a client that
     * left the field zero wants every record, and a zero stride has no
     * other sensible reading. */
    const uint16_t stride = s_h.stride == 0 ? 1u : s_h.stride;
    const int rc = cook_store_read(s_h.session_id, s_h.from_t, s_h.to_t,
                                   stride, 0, COOK_AGG_NONE, on_sample, NULL,
                                   NULL);
    if (s_h.cancelled) {
        finish(BRIDGE_RESULT_STATUS_OK);
    } else if (s_h.notify_err != APP_BLE_OK) {
        finish(BRIDGE_RESULT_STATUS_FAILED);
    } else {
        finish(rc == COOK_STORE_OK ? BRIDGE_RESULT_STATUS_OK
                                   : BRIDGE_RESULT_STATUS_FAILED);
    }
}

static int on_mark(void *ctx, const bridge_mark_rec_t *m) {
    (void)ctx;
    if (s_h.cancelled || s_h.notify_err != APP_BLE_OK) {
        return 1;
    }
    if (m->t < s_h.from_t || m->t > s_h.to_t) {
        return 0; /* the same range the samples honoured */
    }
    uint8_t item[BRIDGE_MARK_REC_SIZE];
    bridge_mark_rec_encode(m, item);
    push_item(BRIDGE_HISTORY_KIND_MARKS, item, BRIDGE_MARK_REC_SIZE);
    return 0;
}

static void stream_marks(void) {
    bridge_session_header_t h;
    if (cook_store_read_header(s_h.session_id, &h) != COOK_STORE_OK) {
        finish(BRIDGE_RESULT_STATUS_INVALID);
        return;
    }
    /* A session with no marks answers ok with no data frames — "no marks"
     * rather than a hang, the same rule the §5.4 empty scan follows. */
    (void)cook_store_read_marks(s_h.session_id, on_mark, NULL);
    finish(s_h.notify_err == APP_BLE_OK ? BRIDGE_RESULT_STATUS_OK
                                        : BRIDGE_RESULT_STATUS_FAILED);
}

/* ── the two entry points ─────────────────────────────────────────── */

void app_ble_history_run(void) {
    if (!s_h.active) {
        return;
    }
    s_h.seq = 0;
    s_h.items = 0;
    s_h.used = 0;
    s_h.kind = BRIDGE_HISTORY_KIND_END;
    s_h.notify_err = APP_BLE_OK;
    s_h.cancelled = false;

    switch (s_h.req) {
    case BRIDGE_HISTORY_REQ_SESSIONS:
        stream_sessions();
        break;
    case BRIDGE_HISTORY_REQ_SAMPLES:
        stream_samples();
        break;
    case BRIDGE_HISTORY_REQ_MARKS:
        stream_marks();
        break;
    default:
        finish(BRIDGE_RESULT_STATUS_INVALID);
        break;
    }
}

int app_ble_history_write(const uint8_t *data, size_t len) {
    bridge_history_ctrl_t c;
    memset(&c, 0, sizeof c);
    if (len < BRIDGE_HISTORY_CTRL_SIZE) {
        /* Malformed requests still get an end frame. Silence is the one
         * answer a client waiting on a stream cannot recover from — the
         * same reason every device_control write lands on `result`. */
        s_h.seq = 0;
        (void)emit(BRIDGE_HISTORY_KIND_END, 0,
                   (const uint8_t[]){BRIDGE_RESULT_STATUS_INVALID}, 1, true);
        return APP_BLE_OK;
    }
    bridge_history_ctrl_decode(data, &c);

    if (c.req == BRIDGE_HISTORY_REQ_CANCEL) {
        /* Always ok, including with nothing running: that is what a
         * retrying client's second cancel looks like. */
        s_h.cancelled = true;
        s_h.active = false;
        s_h.seq = 0;
        (void)emit(BRIDGE_HISTORY_KIND_END, 0,
                   (const uint8_t[]){BRIDGE_RESULT_STATUS_OK}, 1, true);
        return APP_BLE_OK;
    }
    if (c.req != BRIDGE_HISTORY_REQ_SESSIONS &&
        c.req != BRIDGE_HISTORY_REQ_SAMPLES &&
        c.req != BRIDGE_HISTORY_REQ_MARKS) {
        s_h.seq = 0;
        (void)emit(BRIDGE_HISTORY_KIND_END, 0,
                   (const uint8_t[]){BRIDGE_RESULT_STATUS_INVALID}, 1, true);
        return APP_BLE_OK;
    }
    if (s_h.active) {
        /* Busy WITHOUT disturbing the stream in flight — its frames are
         * still on their way to whoever asked (§5.3's rule for scans).
         * Answered on a seq the running stream will never use, so the
         * client can tell this refusal from one of its own frames. */
        bridge_history_data_t f;
        memset(&f, 0, sizeof f);
        f.ver = 1;
        f.kind = BRIDGE_HISTORY_KIND_END;
        f.seq = UINT16_MAX;
        f.flags = BRIDGE_HISTORY_DATA_FLAGS_LAST;
        f.count = 0;
        f.len = 1;
        f.payload[0] = BRIDGE_RESULT_STATUS_BUSY;
        uint8_t buf[BRIDGE_HISTORY_DATA_MAX_SIZE];
        const int n = bridge_history_data_pack(&f, buf, sizeof buf);
        if (n > 0) {
            (void)app_ble_notify_chunked(APP_BLE_CH_HISTORY_DATA, buf,
                                         (size_t)n);
        }
        return APP_BLE_OK;
    }

    s_h.active = true;
    s_h.cancelled = false;
    s_h.req = c.req;
    s_h.stride = c.stride;
    s_h.session_id = c.session_id;
    s_h.from_t = c.from_t;
    s_h.to_t = c.to_t;

    /* Hand off to the ble_push row — reading a 12 h session is hundreds of
     * flash reads and the NimBLE host task's stack is the stack's. With no
     * row bound (the host suite) run it here, where there is nothing to
     * protect and a test wants the answer synchronously. */
    if (g_ble_ops != NULL && g_ble_ops->history_defer != NULL) {
        if (g_ble_ops->history_defer() != 0) {
            s_h.active = false;
            s_h.seq = 0;
            (void)emit(BRIDGE_HISTORY_KIND_END, 0,
                       (const uint8_t[]){BRIDGE_RESULT_STATUS_FAILED}, 1, true);
        }
        return APP_BLE_OK;
    }
    app_ble_history_run();
    return APP_BLE_OK;
}
