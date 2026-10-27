/*
 * ble_sync.c - pure C11 sync_ctrl parser, logical sync stream builder and
 * sync_data framer (T31, design 05 sections 5.7/5.8, design 04 section 4.5).
 *
 * No heap and no ESP-IDF: the ring is a pair of callbacks. The firmware adapter
 * in ble_service.c pumps the frames out; the host tests reassemble them.
 */
#include "ble_sync.h"

#include <string.h>

_Static_assert(BLE_SYNC_STREAM_MAX <= 1200u,
               "one sync response still fits a small static buffer");
_Static_assert(SX4_SYNC_START_SIZE == 20u, "START payload is 20 bytes");
_Static_assert(SX4_SYNC_END_SIZE == 13u, "END payload is 13 bytes");
_Static_assert(SX4_RECORD_SIZE == 18u, "record size is 18 bytes");

static uint16_t normalize_max_records(uint16_t value) {
    if (value == 0u) {
        return (uint16_t)SX4_BLE_SYNC_DEFAULT_RECORDS;
    }
    if (value > (uint16_t)SX4_BLE_SYNC_MAX_RECORDS) {
        return (uint16_t)SX4_BLE_SYNC_MAX_RECORDS;
    }
    return value;
}

ble_sync_request_status_t ble_sync_parse_ctrl(const uint8_t *in, size_t len,
                                              ble_sync_request_t *out) {
    if (in == NULL || out == NULL || len != SX4_SYNC_CTRL_SIZE) {
        return BLE_SYNC_REQUEST_INVALID;
    }
    if (in[0] != SX4_PROTOCOL_MAJOR) {
        return BLE_SYNC_REQUEST_INVALID;
    }
    if (in[1] != (uint8_t)SX4_SYNC_CMD_STATUS &&
        in[1] != (uint8_t)SX4_SYNC_CMD_READ &&
        in[1] != (uint8_t)SX4_SYNC_CMD_CANCEL) {
        return BLE_SYNC_REQUEST_INVALID;
    }
    if (in[2] != (uint8_t)SX4_SYNC_DIRECTION_FORWARD &&
        in[2] != (uint8_t)SX4_SYNC_DIRECTION_BACKWARD) {
        return BLE_SYNC_REQUEST_INVALID;
    }

    sx4_sync_ctrl_t decoded;
    if (!sx4_sync_ctrl_decode(in, SX4_SYNC_CTRL_SIZE, &decoded)) {
        return BLE_SYNC_REQUEST_INVALID;
    }

    out->cmd = decoded.cmd;
    out->direction = decoded.direction;
    out->cursor_seq = decoded.cursor_seq;
    out->max_records = normalize_max_records(decoded.max_records);
    return BLE_SYNC_REQUEST_OK;
}

ble_sync_action_t ble_sync_plan(bool busy,
                                const ble_sync_request_t *request) {
    if (request == NULL) {
        return BLE_SYNC_ACTION_NONE;
    }
    switch (request->cmd) {
    case SX4_SYNC_CMD_STATUS:
        /* Status is allowed while a transfer is in flight. */
        return BLE_SYNC_ACTION_STATUS;
    case SX4_SYNC_CMD_CANCEL:
        /* Cancel is allowed while a transfer is in flight. */
        return BLE_SYNC_ACTION_CANCEL;
    case SX4_SYNC_CMD_READ:
        return busy ? BLE_SYNC_ACTION_NONE : BLE_SYNC_ACTION_READ;
    default:
        return BLE_SYNC_ACTION_NONE;
    }
}

size_t ble_sync_frame_payload_max(size_t mtu) {
    if (mtu < (size_t)SX4_BLE_MTU_DEFAULT) {
        mtu = (size_t)SX4_BLE_MTU_DEFAULT;
    }
    /* ATT notification = MTU - 3; the 4-byte frame header is ours. */
    size_t payload = mtu > 7u ? mtu - 7u : 0u;
    if (payload > (size_t)SX4_BLE_SYNC_FRAME_MAX_PAYLOAD) {
        payload = (size_t)SX4_BLE_SYNC_FRAME_MAX_PAYLOAD;
    }
    return payload;
}

typedef struct {
    uint32_t first_seq;
    uint32_t last_seq;
    uint32_t count;
    uint8_t status; /* ok, gap, or empty is handled by the caller */
} sync_window_t;

/*
 * Choose the ascending sequence window for a read.
 *
 * Forward: `seq > cursor`, lowest first, but a cursor older than `min_seq - 1`
 * is a gap and restarts at `min_seq`. `min_seq == 0` can never be a gap, and
 * `min_seq - 1` is never computed for it. A non-empty log with a cursor at or
 * beyond `max_seq` is drained: count 0, start/next cursor unchanged.
 *
 * Backward: the highest records with `seq < cursor`, emitted ascending. A cursor
 * beyond `max_seq + 1` is a gap and restarts at `max_seq + 1`. A cursor at 0 has
 * nothing before it, but `seq = 0` remains a real record reachable from a later
 * cursor because `next_seq` is an exclusive cursor, not a stop sentinel.
 */
static sync_window_t sync_window(const ble_sync_request_t *request,
                                 const ble_sync_extent_t *extent) {
    sync_window_t window;
    window.first_seq = request->cursor_seq;
    window.last_seq = request->cursor_seq;
    window.count = 0u;
    window.status = (uint8_t)SX4_SYNC_STATUS_OK;

    uint32_t limit = normalize_max_records(request->max_records);
    uint64_t min_seq = (uint64_t)extent->min_seq;
    uint64_t max_seq = (uint64_t)extent->max_seq;

    if (request->direction == SX4_SYNC_DIRECTION_FORWARD) {
        uint64_t cursor = (uint64_t)request->cursor_seq;
        uint64_t first;
        if (min_seq > 1u && cursor + 1u < min_seq) {
            /* cursor < min_seq - 1, without ever forming min_seq - 1 at 0. */
            window.status = (uint8_t)SX4_SYNC_STATUS_GAP;
            first = min_seq;
        } else if (cursor >= max_seq) {
            return window; /* drained: count 0, start/next seq = cursor */
        } else {
            first = cursor + 1u;
            if (first < min_seq) {
                first = min_seq;
            }
        }
        uint64_t last = first + (uint64_t)limit - 1u;
        if (last > max_seq) {
            last = max_seq;
        }
        window.first_seq = (uint32_t)first;
        window.last_seq = (uint32_t)last;
        window.count = (uint32_t)(last - first + 1u);
        return window;
    }

    /* Backward. max_seq + 1 is computed in 64 bits so 0xFFFFFFFF is safe. */
    uint64_t cursor = (uint64_t)request->cursor_seq;
    uint64_t max_plus_one = max_seq + 1u;
    uint64_t end;
    if (cursor > max_plus_one) {
        window.status = (uint8_t)SX4_SYNC_STATUS_GAP;
        end = max_seq;
    } else {
        if (cursor == 0u) {
            return window; /* nothing before seq 0 */
        }
        end = cursor - 1u;
        if (end > max_seq) {
            end = max_seq;
        }
        if (end < min_seq) {
            return window; /* drained: count 0, start/next seq = cursor */
        }
    }
    uint64_t first = 0u;
    if (end + 1u > (uint64_t)limit) {
        first = end + 1u - (uint64_t)limit;
    }
    if (first < min_seq) {
        first = min_seq;
    }
    window.first_seq = (uint32_t)first;
    window.last_seq = (uint32_t)end;
    window.count = (uint32_t)(end - first + 1u);
    return window;
}

static size_t encode_start(uint8_t *out, size_t cap, uint32_t generation,
                           uint32_t min_seq, uint32_t max_seq,
                           uint32_t start_seq, uint16_t count,
                           uint8_t status) {
    sx4_sync_start_t start;
    memset(&start, 0, sizeof(start));
    start.generation = generation;
    start.min_seq = min_seq;
    start.max_seq = max_seq;
    start.start_seq = start_seq;
    start.count = count;
    start.record_size = (uint8_t)SX4_RECORD_SIZE;
    start.status = status;
    return sx4_sync_start_encode(&start, out, cap);
}

ble_sync_build_status_t ble_sync_build(const ble_sync_request_t *request,
                                       const ble_sync_source_t *source,
                                       uint8_t *out, size_t cap,
                                       size_t *out_len, uint8_t *out_status) {
    if (request == NULL || source == NULL || source->get_extent == NULL ||
        source->read_record == NULL || out == NULL || out_len == NULL ||
        out_status == NULL) {
        return BLE_SYNC_BUILD_INVALID;
    }
    if (request->cmd == SX4_SYNC_CMD_CANCEL) {
        return BLE_SYNC_BUILD_NO_STREAM;
    }
    if (request->cmd != SX4_SYNC_CMD_STATUS &&
        request->cmd != SX4_SYNC_CMD_READ) {
        return BLE_SYNC_BUILD_INVALID;
    }
    if (request->direction != SX4_SYNC_DIRECTION_FORWARD &&
        request->direction != SX4_SYNC_DIRECTION_BACKWARD) {
        return BLE_SYNC_BUILD_INVALID;
    }

    /* Direct callers get the same 1..64 rules as the wire parser. */
    ble_sync_request_t normalised = *request;
    normalised.max_records = normalize_max_records(request->max_records);

    ble_sync_extent_t extent;
    memset(&extent, 0, sizeof(extent));
    bool have_extent = source->get_extent(source->ctx, &extent);
    uint32_t generation = have_extent ? extent.generation : 0u;
    uint32_t min_seq = SX4_SEQ_NONE;
    uint32_t max_seq = SX4_SEQ_NONE;
    uint8_t status = SX4_SYNC_STATUS_ERROR;

    uint32_t requested = 0;
    uint32_t first_seq = normalised.cursor_seq;
    uint32_t last_seq = normalised.cursor_seq;

    if (have_extent) {
        /* This snapshot is the only extent read for the whole response. */
        generation = extent.generation;
        if (extent.count == 0u) {
            status = (uint8_t)SX4_SYNC_STATUS_EMPTY;
        } else {
            min_seq = extent.min_seq;
            max_seq = extent.max_seq;
            status = (uint8_t)SX4_SYNC_STATUS_OK;
            if (normalised.cmd == SX4_SYNC_CMD_READ) {
                sync_window_t window = sync_window(&normalised, &extent);
                requested = window.count;
                first_seq = window.first_seq;
                last_seq = window.last_seq;
                status = window.status;
            }
        }
    }

    /*
     * Worst case is every requested record; rejecting early keeps a partial
     * stream from ever being framed. The count actually emitted can be smaller
     * when the log is short or a record read fails.
     */
    size_t needed = (size_t)SX4_SYNC_START_SIZE +
                    (size_t)requested * (size_t)SX4_RECORD_SIZE +
                    (size_t)SX4_SYNC_END_SIZE;
    if (cap < needed) {
        return BLE_SYNC_BUILD_BUFFER;
    }

    size_t offset = 0;
    size_t written = encode_start(out + offset, cap - offset, generation,
                                  min_seq, max_seq, first_seq, 0u, status);
    if (written != SX4_SYNC_START_SIZE) {
        return BLE_SYNC_BUILD_BUFFER;
    }
    offset += written;

    uint16_t emitted = 0;
    if (requested != 0u) {
        /* A gap still carries records: it starts at min/max+1 and says why. */
        for (uint32_t i = 0; i < requested; i++) {
            uint32_t seq = first_seq + i;
            if (!source->read_record(source->ctx, seq, out + offset)) {
                /* Never emit a hole: end the batch before the bad record. */
                status = (uint8_t)SX4_SYNC_STATUS_ERROR;
                break;
            }
            offset += SX4_RECORD_SIZE;
            emitted++;
            last_seq = seq;
        }
        /* The START header carries the count actually emitted. */
        (void)encode_start(out, cap, generation, min_seq, max_seq, first_seq,
                           emitted, status);
    }

    /*
     * On ok/gap the cursor advances to the next record in this direction.
     * count == 0 keeps start_seq/next_seq equal to the request cursor, so a
     * drained direction (including seq 0) is unambiguous. On error the cursor
     * stays put so the app re-requests the whole batch.
     */
    uint32_t next_seq = normalised.cursor_seq;
    if (emitted != 0u) {
        if (status == (uint8_t)SX4_SYNC_STATUS_OK ||
            status == (uint8_t)SX4_SYNC_STATUS_GAP) {
            next_seq = normalised.direction == SX4_SYNC_DIRECTION_FORWARD
                           ? last_seq + 1u
                           : first_seq;
        }
    }

    sx4_sync_end_t end;
    memset(&end, 0, sizeof(end));
    end.status = status;
    end.next_seq = next_seq;
    end.min_seq = min_seq;
    end.max_seq = max_seq;
    written = sx4_sync_end_encode(&end, out + offset, cap - offset);
    if (written != SX4_SYNC_END_SIZE) {
        return BLE_SYNC_BUILD_BUFFER;
    }
    offset += written;

    *out_len = offset;
    *out_status = status;
    return BLE_SYNC_BUILD_OK;
}

void ble_sync_framer_init(ble_sync_framer_t *framer, uint8_t first_frame_seq) {
    if (framer != NULL) {
        framer->next_frame_seq = first_frame_seq;
    }
}

size_t ble_sync_next_frame(ble_sync_framer_t *framer, const uint8_t *stream,
                           size_t stream_len, size_t *offset, size_t mtu,
                           bool error, uint8_t *out, size_t cap) {
    if (framer == NULL || stream == NULL || offset == NULL || out == NULL) {
        return 0;
    }
    if (*offset >= stream_len) {
        return 0;
    }

    size_t payload_max = ble_sync_frame_payload_max(mtu);
    if (payload_max == 0u) {
        return 0;
    }
    size_t chunk = stream_len - *offset;
    if (chunk > payload_max) {
        chunk = payload_max;
    }
    if (cap < SX4_SYNC_FRAME_SIZE + chunk) {
        return 0;
    }

    uint8_t flags = 0;
    if (*offset == 0u) {
        flags |= (uint8_t)SX4_SYNC_FRAME_FLAG_START;
    }
    if (*offset + chunk == stream_len) {
        flags |= (uint8_t)SX4_SYNC_FRAME_FLAG_END;
        if (error) {
            flags |= (uint8_t)SX4_SYNC_FRAME_FLAG_ERROR;
        }
    }

    sx4_sync_frame_t header;
    header.ver = (uint8_t)SX4_PROTOCOL_MAJOR;
    header.frame_seq = framer->next_frame_seq;
    header.flags = flags;
    header.len = (uint8_t)chunk;
    if (sx4_sync_frame_encode(&header, out, cap) != SX4_SYNC_FRAME_SIZE) {
        return 0;
    }
    memmove(out + SX4_SYNC_FRAME_SIZE, stream + *offset, chunk);

    framer->next_frame_seq++;
    *offset += chunk;
    return (size_t)SX4_SYNC_FRAME_SIZE + chunk;
}
