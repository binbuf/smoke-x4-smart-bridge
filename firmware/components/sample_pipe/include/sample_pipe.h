/*
 * sample_pipe.h - parser -> record -> log queue -> live snapshot (T21).
 *
 * The core is plain C11: no ESP-IDF, no heap, no I/O. One received packet is
 * classified by comma count, parsed by sx_protocol, turned into one 18-byte
 * record plus a bridge_state sample, stamped with the record time and handed to
 * the caller's bounded log queue. Nothing on this path allocates or blocks.
 *
 * Delivery order (design 03 section 3.6):
 *   sample_pipe_process()        classify/parse/build/stamp/enqueue
 *   log_writer appends           sample_log_append()
 *   sample_pipe_complete()       bridge_state_update(), then mark_dirty()
 *
 * The snapshot update is deliberately deferred until the record's ring
 * sequence is known, and the UI dirty flag is set only after that update.
 *
 * A full log queue drops the sample (and increments dropped_samples); it never
 * waits for flash. The dropped sample does not publish a snapshot either, so a
 * later completion from the FIFO can never replace newer live values with
 * older ones.
 */
#ifndef SX4_SAMPLE_PIPE_H
#define SX4_SAMPLE_PIPE_H

#include <stdbool.h>
#include <stdint.h>

#include "bridge_state.h"
#include "log_core.h"
#include "sx_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SAMPLE_PIPE_DEVICE_ID_MAX 16u
/* Fixed depth of the sample_pipe -> log_writer queue. */
#define SAMPLE_PIPE_LOG_QUEUE_DEPTH 8u

typedef struct {
    bool paired;
    char device_id[SAMPLE_PIPE_DEVICE_ID_MAX];
    uint8_t num_probes; /* 0 until the first state packet is learned */
} sample_pipe_pairing_t;

/*
 * One queued log write. `rec` is stamped and layout-validated; its ring
 * sequence is assigned by the log writer. `sample` carries the live values that
 * are published once the append succeeds.
 */
typedef struct {
    sx4_sample_rec_t rec;
    bridge_state_sample_t sample;
} sample_pipe_pending_t;

/*
 * Callbacks installed by the firmware adapter (or by a host fixture). Every
 * callback must be non-blocking on the sample path; enqueue_log in particular
 * must return false rather than wait.
 */
typedef struct {
    void *ctx;
    /* Current persisted pairing. False means "not paired yet". */
    bool (*load_pairing)(void *ctx, sample_pipe_pairing_t *out);
    /* Persist the probe count learned from the first state packet (T15). */
    bool (*save_probe_count)(void *ctx, const char *device_id,
                             uint8_t num_probes);
    /* Non-blocking hand-off to the log writer. False means the queue is full. */
    bool (*enqueue_log)(void *ctx, const sample_pipe_pending_t *pending);
    /* Apply the wall clock to the record (bridge_state_stamp_record). */
    bool (*stamp_record)(void *ctx, sx4_sample_rec_t *rec);
    /* Publish the live snapshot (bridge_state_update). */
    void (*publish_snapshot)(void *ctx, const bridge_state_sample_t *sample);
    /* Mark the UI dirty. Must be called only after publish_snapshot. */
    void (*mark_dirty)(void *ctx);
    /* Monotonic milliseconds, used only for the last-packet age. */
    uint64_t (*now_ms)(void *ctx);
} sample_pipe_io_t;

typedef enum {
    SAMPLE_PIPE_IGNORED = 0,     /* ACK, sync beacon, or not paired yet */
    SAMPLE_PIPE_RECORD_QUEUED = 1,
    SAMPLE_PIPE_RECORD_DROPPED = 2, /* bounded queue full */
    SAMPLE_PIPE_REJECTED = 3,    /* malformed, foreign-ID or bad record */
} sample_pipe_result_t;

typedef struct {
    uint32_t valid_state_packets;
    uint32_t parse_failures;
    uint32_t crc_failures;
    uint32_t foreign_device_packets;
    uint32_t sync_beacons;
    uint32_t ack_attempts;
    uint32_t dropped_samples;
    uint32_t log_write_failures;
    uint16_t last_packet_age_s;
    bool have_last_packet;
} sample_pipe_counters_t;

typedef struct {
    sample_pipe_io_t io;
    sample_pipe_counters_t counters;
    uint32_t last_seq;
    bool have_seq;
    bool have_last_packet;
    uint64_t last_packet_ms;
} sample_pipe_t;

/* Install the callbacks and clear counters. All callbacks are required. */
bool sample_pipe_init(sample_pipe_t *pipe, const sample_pipe_io_t *io);

/*
 * Classify and process one received packet. Non-blocking and allocation-free.
 * A 2-comma ACK is ignored, a 6-comma sync beacon is counted, and a 16/26-comma
 * state packet is parsed only when a pairing is loaded. A foreign device ID is
 * counted and rejected. No partial record is ever produced.
 */
sample_pipe_result_t sample_pipe_process(sample_pipe_t *pipe,
                                         const uint8_t *payload,
                                         uint8_t length, int8_t rssi,
                                         int8_t snr);

/*
 * Called by the log writer after one queued record has been handled. `stored`
 * is true when sample_log_append() accepted the record and assigned `seq`.
 * Publishes the live snapshot, then marks the UI dirty. A failed append still
 * publishes the live values but does not advance the live sequence.
 */
void sample_pipe_complete(sample_pipe_t *pipe,
                          const sample_pipe_pending_t *pending, bool stored,
                          uint32_t seq);

/*
 * Counter snapshot. CRC failures and ACK attempts come from sx_protocol (one
 * counter block for link and parser diagnostics); the rest are owned here.
 * `last_packet_age_s` is computed against now_ms().
 */
void sample_pipe_counters(const sample_pipe_t *pipe,
                          sample_pipe_counters_t *out);

#ifdef ESP_PLATFORM
#include "esp_err.h"
/* Boot hook: create the static log queue and the two core-0 tasks. */
esp_err_t sample_pipe_start(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_SAMPLE_PIPE_H */
