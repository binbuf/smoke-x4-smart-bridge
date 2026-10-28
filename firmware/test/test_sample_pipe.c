/*
 * test_sample_pipe.c - parser -> record -> log queue -> live snapshot (T21).
 *
 * Drives the real sx_protocol parser and the real 18-byte record codec through
 * the sample_pipe core over a RAM ring. No ESP-IDF, no flash, no board. The
 * replay test uses the committed x4-t10-25min capture and the linker wraps
 * malloc/calloc/realloc/free so the sample path proves it never allocates.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log_core.h"
#include "lora_corpus.h"
#include "ram_log_io.h"
#include "sample_pipe.h"
#include "sx_protocol.h"
#include "test_util.h"

#ifndef SX4_FIXTURE_DIR
#error "SX4_FIXTURE_DIR must point at protocol/fixtures/lora"
#endif

#define FIXTURE_LINES 64u
#define RING_SECTORS 4u
#define EVENT_CAPACITY 512u

#define EVENT_SNAPSHOT 1
#define EVENT_DIRTY 2

static const char kDeviceId[] = "LMXC[\\";
static const char kSyncPayload[] = "000000,LMXC[\\,160,50,191,54,";
static const char kStatePayload[] =
    "LMXC[\\,30,1,1,0,826,0,99,47,0,823,0,160,32,0,827,0,160,32,0,825,1,160,"
    "32,0,0,";
/* T56 real frames: probe 4 max == the base target while attached. */
static const char kBillows250Payload[] =
    "LMXC[\\,30,1,2,0,820,0,99,47,0,820,0,160,32,0,820,0,160,32,0,817,1,250,"
    "0,1,0,";
static const char kBillowsDetachedPayload[] =
    "LMXC[\\,30,1,2,0,822,0,99,47,0,819,0,160,32,0,821,0,160,32,0,816,1,160,"
    "32,0,0,";
static const char kBillowsCelsiusTargetPayload[] =
    "LMXC[\\,30,0,1,0,820,0,99,47,0,820,0,160,32,0,820,0,160,32,0,817,1,121,"
    "0,1,0,";

/* -------- allocation guard ------------------------------------------------- */

#if defined(SX4_ALLOC_WRAPPED)
static unsigned long s_alloc_calls;

void *__real_malloc(size_t size);
void *__real_calloc(size_t count, size_t size);
void *__real_realloc(void *ptr, size_t size);
void __real_free(void *ptr);

void *__wrap_malloc(size_t size) {
    s_alloc_calls++;
    return __real_malloc(size);
}
void *__wrap_calloc(size_t count, size_t size) {
    s_alloc_calls++;
    return __real_calloc(count, size);
}
void *__wrap_realloc(void *ptr, size_t size) {
    s_alloc_calls++;
    return __real_realloc(ptr, size);
}
void __wrap_free(void *ptr) { __real_free(ptr); }
#endif

/* -------- fixture ---------------------------------------------------------- */

typedef struct {
    uint64_t now_ms;
    uint32_t base_unix_s;

    sample_pipe_pairing_t pairing;
    uint32_t save_calls;
    bool save_failed;

    sample_pipe_pending_t queue[SAMPLE_PIPE_LOG_QUEUE_DEPTH];
    size_t queue_head;
    size_t queue_count;

    uint8_t ring_storage[RING_SECTORS * SAMPLE_LOG_SECTOR_SIZE];
    ram_log_io_t ram;
    log_io_t io;
    log_ring_t ring;
    bool append_failed;

    uint32_t snapshot_calls;
    uint32_t dirty_calls;
    bool order_ok;
    bridge_state_sample_t last_snapshot;
    unsigned int events[EVENT_CAPACITY];
    size_t event_count;

    sample_pipe_t pipe;
} fixture_t;

static fixture_t g_fixture;

static void fixture_reset(fixture_t *f) {
    memset(f, 0, sizeof(*f));
    f->order_ok = true;
    f->base_unix_s = 1700000000u;
    f->pairing.paired = true;
    snprintf(f->pairing.device_id, sizeof(f->pairing.device_id), "%s",
             kDeviceId);
    f->pairing.num_probes = 0;

    CHECK_EQ_INT(ram_log_io_init(&f->ram, f->ring_storage,
                                 RING_SECTORS * SAMPLE_LOG_SECTOR_SIZE,
                                 SAMPLE_LOG_SECTOR_SIZE),
                 0);
    ram_log_io_as_io(&f->ram, &f->io);
    CHECK_EQ_INT(log_ring_mount(&f->ring, &f->io, false, 0), SAMPLE_LOG_OK);
    CHECK_EQ_INT(log_ring_format(&f->ring, 0x5A5A1234u), SAMPLE_LOG_OK);
}

static void record_event(fixture_t *f, unsigned int event) {
    if (f->event_count < EVENT_CAPACITY) {
        f->events[f->event_count++] = event;
    }
}

static bool fake_load_pairing(void *ctx, sample_pipe_pairing_t *out) {
    fixture_t *f = ctx;
    if (!f->pairing.paired) {
        return false;
    }
    *out = f->pairing;
    return true;
}

static bool fake_save_probe_count(void *ctx, const char *device_id,
                                  uint8_t num_probes) {
    fixture_t *f = ctx;
    f->save_calls++;
    if (f->save_failed) {
        return false;
    }
    if (strcmp(device_id, f->pairing.device_id) != 0) {
        return false;
    }
    f->pairing.num_probes = num_probes;
    return true;
}

static bool fake_enqueue_log(void *ctx, const sample_pipe_pending_t *pending) {
    fixture_t *f = ctx;
    if (f->queue_count >= SAMPLE_PIPE_LOG_QUEUE_DEPTH) {
        return false;
    }
    size_t slot = (f->queue_head + f->queue_count) % SAMPLE_PIPE_LOG_QUEUE_DEPTH;
    f->queue[slot] = *pending;
    f->queue_count++;
    return true;
}

static bool fake_stamp_record(void *ctx, sx4_sample_rec_t *rec) {
    fixture_t *f = ctx;
    rec->unix_s = f->base_unix_s + (uint32_t)(f->now_ms / 1000u);
    rec->flags |= SX4_RECORD_FLAG_CLOCK_VALID;
    return true;
}

static void fake_publish_snapshot(void *ctx,
                                  const bridge_state_sample_t *sample) {
    fixture_t *f = ctx;
    f->last_snapshot = *sample;
    f->snapshot_calls++;
    record_event(f, EVENT_SNAPSHOT);
}

static void fake_mark_dirty(void *ctx) {
    fixture_t *f = ctx;
    if (f->snapshot_calls != f->dirty_calls + 1u) {
        f->order_ok = false;
    }
    f->dirty_calls++;
    record_event(f, EVENT_DIRTY);
}

static uint64_t fake_now_ms(void *ctx) {
    fixture_t *f = ctx;
    return f->now_ms;
}

static const sample_pipe_io_t kIo = {
    .ctx = NULL,
    .load_pairing = fake_load_pairing,
    .save_probe_count = fake_save_probe_count,
    .enqueue_log = fake_enqueue_log,
    .stamp_record = fake_stamp_record,
    .publish_snapshot = fake_publish_snapshot,
    .mark_dirty = fake_mark_dirty,
    .now_ms = fake_now_ms,
};

static void fixture_init_pipe(fixture_t *f) {
    fixture_reset(f);
    sample_pipe_io_t io = kIo;
    io.ctx = f;
    CHECK(sample_pipe_init(&f->pipe, &io));
}

/* Drain the fake log queue, appending each record to the RAM ring. */
static void fixture_drain(fixture_t *f) {
    while (f->queue_count > 0) {
        sample_pipe_pending_t pending = f->queue[f->queue_head];
        f->queue_head = (f->queue_head + 1u) % SAMPLE_PIPE_LOG_QUEUE_DEPTH;
        f->queue_count--;

        sx4_sample_rec_t rec = pending.rec;
        bool stored = false;
        uint32_t seq = 0;
        if (!f->append_failed &&
            log_ring_append(&f->ring, &rec) == SAMPLE_LOG_OK) {
            stored = true;
            seq = sx4_sample_rec_seq_get(&rec);
        }
        sample_pipe_complete(&f->pipe, &pending, stored, seq);
    }
}

static sample_pipe_result_t feed_text(fixture_t *f, const char *text,
                                      int8_t rssi, int8_t snr) {
    return sample_pipe_process(&f->pipe, (const uint8_t *)text,
                               (uint8_t)strlen(text), rssi, snr);
}

static void read_record(fixture_t *f, uint32_t seq, sx4_sample_rec_t *out) {
    CHECK_EQ_INT(log_ring_read_seq(&f->ring, seq, out), SAMPLE_LOG_OK);
    CHECK_EQ_UINT(sx4_sample_rec_seq_get(out), seq);
}

/* -------- replay ----------------------------------------------------------- */

static void test_replay_t10_capture(void) {
    fixture_t *f = &g_fixture;
    fixture_init_pipe(f);

    sx4_loralog_line_t lines[FIXTURE_LINES];
    size_t line_count = 0;
    CHECK_EQ_INT(sx4_loralog_read(SX4_FIXTURE_DIR "/x4-t10-25min.loralog",
                                  lines, FIXTURE_LINES, &line_count),
                 0);
    CHECK_EQ_UINT(line_count, 44u);

    sx_protocol_counters_reset();
#if defined(SX4_ALLOC_WRAPPED)
    s_alloc_calls = 0;
#endif

    size_t state_frames = 0;
    for (size_t i = 0; i < line_count; i++) {
        f->now_ms = lines[i].t_ms;
        sample_pipe_result_t result =
            feed_text(f, lines[i].payload, (int8_t)lines[i].rssi,
                      (int8_t)lines[i].snr);
        if (strcmp(lines[i].cls, "state26") == 0) {
            state_frames++;
            CHECK_EQ_INT(result, SAMPLE_PIPE_RECORD_QUEUED);
        } else if (strcmp(lines[i].cls, "sync6") == 0) {
            CHECK_EQ_INT(result, SAMPLE_PIPE_IGNORED);
        } else if (strcmp(lines[i].cls, "ack2") == 0) {
            CHECK_EQ_INT(result, SAMPLE_PIPE_IGNORED);
        }
        fixture_drain(f);
    }

#if defined(SX4_ALLOC_WRAPPED)
    CHECK_EQ_UINT(s_alloc_calls, 0u);
#endif

    CHECK_EQ_UINT(state_frames, 41u);
    CHECK_EQ_UINT(f->save_calls, 1u);
    CHECK_EQ_UINT(f->pairing.num_probes, 4u);

    log_ring_info_t info;
    log_ring_info(&f->ring, &info);
    CHECK_EQ_UINT(info.count, 41u);
    CHECK_EQ_UINT(info.next_seq, 41u);
    CHECK_EQ_UINT(info.min_seq, 0u);
    CHECK_EQ_UINT(info.max_seq, 40u);

    sample_pipe_counters_t counters;
    sample_pipe_counters(&f->pipe, &counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 41u);
    CHECK_EQ_UINT(counters.parse_failures, 0u);
    CHECK_EQ_UINT(counters.foreign_device_packets, 0u);
    CHECK_EQ_UINT(counters.sync_beacons, 1u);
    CHECK_EQ_UINT(counters.dropped_samples, 0u);
    CHECK_EQ_UINT(counters.log_write_failures, 0u);
    CHECK(counters.have_last_packet);
    CHECK_EQ_UINT(counters.last_packet_age_s, 0u);

    /* First state frame: all four probes attached, canonical °F. */
    sx4_sample_rec_t rec;
    read_record(f, 0, &rec);
    CHECK_EQ_UINT(rec.unix_s, f->base_unix_s + 143u);
    CHECK_EQ_INT(rec.temp[0], 826);
    CHECK_EQ_INT(rec.temp[1], 823);
    CHECK_EQ_INT(rec.temp[2], 827);
    CHECK_EQ_INT(rec.temp[3], 825);
    CHECK_EQ_UINT(rec.flags & 0x0Fu, 0x0Fu);
    CHECK(sx4_sample_rec_flags_clock_valid(rec.flags));
    CHECK(!sx4_sample_rec_flags_source_celsius(rec.flags));

    /* Probe 2 detaches: sentinel, attach bit clear. */
    read_record(f, 1, &rec);
    CHECK_EQ_INT(rec.temp[1], SX4_TEMP_DETACHED);
    CHECK(!sx4_sample_rec_flags_probe2_attached(rec.flags));
    CHECK_EQ_UINT(rec.flags & 0x0Fu, 0x0Du);

    /* Celsius packet becomes Fahrenheit tenths and keeps provenance. */
    read_record(f, 6, &rec);
    CHECK(sx4_sample_rec_flags_source_celsius(rec.flags));
    CHECK_EQ_INT(rec.temp[0], 824);
    CHECK_EQ_INT(rec.temp[1], 820);
    CHECK_EQ_INT(rec.temp[2], 824);
    CHECK_EQ_INT(rec.temp[3], 820);

    /* Last frame: live values and the final ring sequence agree. */
    read_record(f, 40, &rec);
    CHECK_EQ_INT(rec.temp[0], 805);
    CHECK_EQ_INT(rec.temp[1], 800);
    CHECK_EQ_INT(rec.temp[2], 807);
    CHECK_EQ_INT(rec.temp[3], 801);

    CHECK_EQ_UINT(f->snapshot_calls, 41u);
    CHECK_EQ_UINT(f->dirty_calls, 41u);
    CHECK(f->order_ok);
    CHECK_EQ_UINT(f->last_snapshot.seq, 40u);
    CHECK_EQ_INT(f->last_snapshot.temp_f10[0], 805);
    CHECK_EQ_INT(f->last_snapshot.temp_f10[1], 800);
    CHECK_EQ_INT(f->last_snapshot.temp_f10[2], 807);
    CHECK_EQ_INT(f->last_snapshot.temp_f10[3], 801);
    CHECK_EQ_UINT(f->last_snapshot.attached_mask, 0x0Fu);
    CHECK_EQ_INT(f->last_snapshot.rssi_lora, -31);
    CHECK_EQ_INT(f->last_snapshot.snr_lora, 10);

    /* Age is measured from the last accepted state packet. */
    f->now_ms += 5000u;
    sample_pipe_counters(&f->pipe, &counters);
    CHECK_EQ_UINT(counters.last_packet_age_s, 5u);
}

/* -------- Billows target gate (T57/T56) ------------------------------------ */

static void test_billows_target_gate(void) {
    fixture_t *f = &g_fixture;
    fixture_init_pipe(f);
    f->pairing.num_probes = 4u;

    /* Attached at 250 °F: probe 4 max becomes the live target. */
    CHECK_EQ_INT(feed_text(f, kBillows250Payload, -40, 10),
                 SAMPLE_PIPE_RECORD_QUEUED);
    fixture_drain(f);
    sx4_sample_rec_t rec;
    read_record(f, 0, &rec);
    CHECK(sx4_sample_rec_flags_billows_attached(rec.flags));
    CHECK(f->last_snapshot.billows_attached);
    CHECK(f->last_snapshot.billows_target_valid);
    CHECK_EQ_INT(f->last_snapshot.billows_target_f10, 2500);

    /* Detached: the X4's 160/32 non-fan defaults must not become a target. */
    CHECK_EQ_INT(feed_text(f, kBillowsDetachedPayload, -40, 10),
                 SAMPLE_PIPE_RECORD_QUEUED);
    fixture_drain(f);
    read_record(f, 1, &rec);
    CHECK(!sx4_sample_rec_flags_billows_attached(rec.flags));
    CHECK(!f->last_snapshot.billows_attached);
    CHECK(!f->last_snapshot.billows_target_valid);
    CHECK_EQ_INT(f->last_snapshot.billows_target_f10, 0);

    /* °C packet: the whole-degree target converts to canonical F tenths. */
    CHECK_EQ_INT(feed_text(f, kBillowsCelsiusTargetPayload, -40, 10),
                 SAMPLE_PIPE_RECORD_QUEUED);
    fixture_drain(f);
    CHECK(f->last_snapshot.billows_attached);
    CHECK(f->last_snapshot.billows_target_valid);
    CHECK_EQ_INT(f->last_snapshot.billows_target_f10, 2498);
}

/* -------- packet counters -------------------------------------------------- */

static void test_packet_counters(void) {
    fixture_t *f = &g_fixture;
    fixture_init_pipe(f);
    f->pairing.num_probes = 4u; /* no learning write expected */
    f->now_ms = 10000u;
    sx_protocol_counters_reset();

    /* Valid state. */
    CHECK_EQ_INT(feed_text(f, kStatePayload, -40, 10),
                 SAMPLE_PIPE_RECORD_QUEUED);
    fixture_drain(f);

    /* Malformed state: same shape, one non-numeric temperature. */
    char malformed[128];
    snprintf(malformed, sizeof(malformed), "%s", kStatePayload);
    char *temp = strstr(malformed, "826");
    CHECK(temp != NULL);
    memcpy(temp, "bad", 3);
    CHECK_EQ_INT(feed_text(f, malformed, -40, 10), SAMPLE_PIPE_REJECTED);

    /* Foreign ID: syntactically valid, different device. */
    char foreign[128];
    snprintf(foreign, sizeof(foreign), "%s", kStatePayload);
    memcpy(foreign, "ABCDEF", 6);
    CHECK_EQ_INT(feed_text(f, foreign, -40, 10), SAMPLE_PIPE_REJECTED);

    /* Sync beacon, ACK, and a shape the parser cannot classify. */
    CHECK_EQ_INT(feed_text(f, kSyncPayload, -30, 9), SAMPLE_PIPE_IGNORED);
    CHECK_EQ_INT(feed_text(f, "LMXC[\\,SUCCESS,", 0, 0),
                 SAMPLE_PIPE_IGNORED);
    CHECK_EQ_INT(feed_text(f, "not-a-frame,", -40, 0),
                 SAMPLE_PIPE_REJECTED);

    sx_protocol_note_crc_failure();
    char ack[32];
    CHECK(sx_protocol_format_ack(kDeviceId, ack, sizeof(ack)) > 0);

    f->now_ms += 5000u;
    sample_pipe_counters_t counters;
    sample_pipe_counters(&f->pipe, &counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 1u);
    CHECK_EQ_UINT(counters.parse_failures, 2u);
    CHECK_EQ_UINT(counters.foreign_device_packets, 1u);
    CHECK_EQ_UINT(counters.sync_beacons, 1u);
    CHECK_EQ_UINT(counters.crc_failures, 1u);
    CHECK_EQ_UINT(counters.ack_attempts, 1u);
    CHECK_EQ_UINT(counters.dropped_samples, 0u);
    CHECK_EQ_UINT(counters.last_packet_age_s, 5u);
    CHECK_EQ_UINT(f->save_calls, 0u);
}

/* -------- bounded queue ---------------------------------------------------- */

static void test_full_queue_drops_without_blocking(void) {
    fixture_t *f = &g_fixture;
    fixture_init_pipe(f);
    f->pairing.num_probes = 4u;
    f->now_ms = 100000u;

    for (unsigned int i = 0; i < SAMPLE_PIPE_LOG_QUEUE_DEPTH; i++) {
        CHECK_EQ_INT(feed_text(f, kStatePayload, -40, 10),
                     SAMPLE_PIPE_RECORD_QUEUED);
    }
    /* The ninth sample finds the queue full: counted drop, no snapshot, and
     * enqueue_log returned immediately. */
    CHECK_EQ_INT(feed_text(f, kStatePayload, -41, 11),
                 SAMPLE_PIPE_RECORD_DROPPED);

    sample_pipe_counters_t counters;
    sample_pipe_counters(&f->pipe, &counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 9u);
    CHECK_EQ_UINT(counters.dropped_samples, 1u);
    CHECK_EQ_UINT(f->snapshot_calls, 0u);
    CHECK_EQ_UINT(f->dirty_calls, 0u);

    /* The radio path never blocked; draining the queue still lands 8 records. */
    fixture_drain(f);
    log_ring_info_t info;
    log_ring_info(&f->ring, &info);
    CHECK_EQ_UINT(info.count, 8u);
    CHECK_EQ_UINT(info.next_seq, 8u);
    CHECK_EQ_UINT(f->snapshot_calls, 8u);
    CHECK_EQ_UINT(f->dirty_calls, 8u);
    CHECK(f->order_ok);
    CHECK_EQ_UINT(f->last_snapshot.seq, 7u);
    CHECK_EQ_INT(f->last_snapshot.rssi_lora, -40);
}

/* -------- snapshot before dirty -------------------------------------------- */

static void test_snapshot_precedes_dirty_on_append_failure(void) {
    fixture_t *f = &g_fixture;
    fixture_init_pipe(f);
    f->pairing.num_probes = 4u;
    f->append_failed = true;

    CHECK_EQ_INT(feed_text(f, kStatePayload, -40, 10),
                 SAMPLE_PIPE_RECORD_QUEUED);
    fixture_drain(f);

    sample_pipe_counters_t counters;
    sample_pipe_counters(&f->pipe, &counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 1u);
    CHECK_EQ_UINT(counters.log_write_failures, 1u);
    CHECK_EQ_UINT(f->snapshot_calls, 1u);
    CHECK_EQ_UINT(f->dirty_calls, 1u);
    CHECK(f->order_ok);
    CHECK(f->event_count >= 2u);
    CHECK_EQ_UINT(f->events[f->event_count - 2u], EVENT_SNAPSHOT);
    CHECK_EQ_UINT(f->events[f->event_count - 1u], EVENT_DIRTY);
    CHECK_EQ_UINT(f->last_snapshot.seq, 0u);
}

int main(void) {
    test_replay_t10_capture();
    test_billows_target_gate();
    test_packet_counters();
    test_full_queue_drops_without_blocking();
    test_snapshot_precedes_dirty_on_append_failure();
    return sx4_test_summary("sample-pipe");
}
