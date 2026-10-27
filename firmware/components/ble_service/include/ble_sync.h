/*
 * ble_sync.h - `sync_ctrl` parsing and the framed `sync_data` stream (T31,
 * design 05 sections 5.7/5.8, design 04 section 4.5).
 *
 * Plain C11 and host-testable. The core owns:
 *   - the fixed 10-byte request parser (status/read/cancel);
 *   - the busy policy (one record transfer at a time);
 *   - the logical START / RECORDS / END stream, built into a caller buffer;
 *   - the 4-byte frame header splitter, bounded by the negotiated MTU.
 *
 * The ring is reached only through ble_sync_source_t, so the host test feeds a
 * fake record store and the firmware binds sample_log_read_seq(). No heap, no
 * ESP-IDF, no global state.
 */
#ifndef SX4_BLE_SYNC_H
#define SX4_BLE_SYNC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Largest logical stream: one START, 64 records and one END. The framer never
 * needs a bigger buffer, so the firmware can keep it static.
 */
#define BLE_SYNC_STREAM_MAX                                        \
    (SX4_SYNC_START_SIZE +                                         \
     (size_t)SX4_BLE_SYNC_MAX_RECORDS * (size_t)SX4_RECORD_SIZE +  \
     SX4_SYNC_END_SIZE)

/* Ring extent snapshot. count == 0 means "nothing recorded yet". */
typedef struct {
    uint32_t generation;
    uint32_t min_seq; /* SX4_SEQ_NONE when empty */
    uint32_t max_seq; /* SX4_SEQ_NONE when empty */
    uint32_t count;
} ble_sync_extent_t;

typedef struct {
    /* Fill the extent snapshot. False means the log is unavailable. */
    bool (*get_extent)(void *ctx, ble_sync_extent_t *out);

    /* Read one record as its 18 wire bytes. False means a bad/missing record. */
    bool (*read_record)(void *ctx, uint32_t seq,
                        uint8_t out[SX4_RECORD_SIZE]);

    void *ctx;
} ble_sync_source_t;

typedef struct {
    uint8_t cmd;
    uint8_t direction;
    uint32_t cursor_seq;
    uint16_t max_records; /* normalised: 1..64 (a wire value of 0 reads 32) */
} ble_sync_request_t;

typedef enum {
    BLE_SYNC_REQUEST_OK = 0,
    BLE_SYNC_REQUEST_INVALID = -1, /* bad length, ver, cmd or direction */
} ble_sync_request_status_t;

typedef enum {
    BLE_SYNC_ACTION_NONE = 0, /* ignored (e.g. a read while busy) */
    BLE_SYNC_ACTION_STATUS,   /* build and send a status START/END pair */
    BLE_SYNC_ACTION_READ,     /* build and send the record stream */
    BLE_SYNC_ACTION_CANCEL,   /* abort the transfer in flight, no response */
} ble_sync_action_t;

typedef enum {
    BLE_SYNC_BUILD_OK = 0,
    BLE_SYNC_BUILD_INVALID = -1,
    BLE_SYNC_BUILD_NO_STREAM = -2, /* a cancel: nothing to send */
    BLE_SYNC_BUILD_BUFFER = -3,    /* cap too small for the logical stream */
} ble_sync_build_status_t;

/* Parse the fixed 10-byte sync_ctrl write. Reserved bytes are ignored. */
ble_sync_request_status_t ble_sync_parse_ctrl(const uint8_t *in, size_t len,
                                              ble_sync_request_t *out);

/*
 * Busy policy (design 04 section 4.5): status and cancel are always honoured;
 * a read is ignored while another record transfer is in flight.
 */
ble_sync_action_t ble_sync_plan(bool busy, const ble_sync_request_t *request);

/*
 * Build the logical stream for request into out (BLE_SYNC_STREAM_MAX bytes is
 * always enough). *out_len is the logical byte count and *out_status is the
 * START/END status. A cancel returns BLE_SYNC_BUILD_NO_STREAM.
 *
 * START snapshots generation/min_seq/max_seq; records written afterwards only
 * appear in the next request. A forward cursor older than min_seq - 1 and a
 * backward cursor newer than max_seq + 1 both return status = gap from the
 * nearest live edge. A drained direction returns count = 0, start_seq =
 * cursor_seq and status = ok; an empty whole log returns status = empty.
 */
ble_sync_build_status_t ble_sync_build(const ble_sync_request_t *request,
                                       const ble_sync_source_t *source,
                                       uint8_t *out, size_t cap,
                                       size_t *out_len, uint8_t *out_status);

/* Frame payload cap: min(240, MTU - 3 - 4), never below the MTU 23 value. */
size_t ble_sync_frame_payload_max(size_t mtu);

typedef struct {
    uint8_t next_frame_seq;
} ble_sync_framer_t;

void ble_sync_framer_init(ble_sync_framer_t *framer, uint8_t first_frame_seq);

/*
 * Write the next frame (4-byte header plus up to payload_max bytes) and advance
 * *offset through the logical stream. Returns the frame length, or 0 when the
 * stream is drained. START is set on the first frame and END on the last;
 * `error` adds ERROR to the final frame. Frame boundaries may split a START or
 * a record: the client reassembles by `len` and flags, never per record.
 */
size_t ble_sync_next_frame(ble_sync_framer_t *framer, const uint8_t *stream,
                           size_t stream_len, size_t *offset, size_t mtu,
                           bool error, uint8_t *out, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_SYNC_H */
