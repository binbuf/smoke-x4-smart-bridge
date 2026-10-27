/*
 * sample_pipe.c - one validated state packet becomes one record plus one live
 * snapshot (T21). Plain C11: no ESP-IDF, no heap, no I/O.
 *
 * The parser owns payload validation and canonicalisation (T14). This module
 * owns the pipeline contract: records are built only from a successful parse,
 * the probe count is learned once, detached probes stay detached, the record is
 * stamped before it is queued, and the live snapshot is published only after
 * the ring assigned a sequence.
 */
#include "sample_pipe.h"

#include <stddef.h>
#include <string.h>

/* -------- small helpers --------------------------------------------------- */

static bool payload_to_text(const uint8_t *payload, uint8_t length, char *out,
                            size_t out_size) {
    if (payload == NULL || length == 0 || (size_t)length >= out_size) {
        return false;
    }
    memcpy(out, payload, length);
    out[length] = '\0';
    /* A NUL inside the frame would make the parser see a shorter payload. */
    return memchr(out, '\0', length) == NULL;
}

/* Celsius whole degrees -> Fahrenheit tenths. Only used for a future valid
 * Billows target; the MVP parser never marks one valid. */
static int16_t celsius_deg_to_f10(int16_t c_deg) {
    int32_t f10 = (int32_t)c_deg * 18 + 320;
    if (f10 > INT16_MAX) {
        f10 = INT16_MAX;
    }
    if (f10 < INT16_MIN) {
        f10 = INT16_MIN;
    }
    return (int16_t)f10;
}

static void build_pending(const sx_protocol_state_t *state, int8_t rssi,
                          int8_t snr, sample_pipe_pending_t *pending) {
    memset(pending, 0, sizeof(*pending));

    uint8_t attached_mask = 0;
    for (unsigned int i = 0; i < BRIDGE_STATE_NUM_PROBES; i++) {
        int16_t temp = SX4_TEMP_DETACHED;
        bool attached = false;
        if (i < state->num_probes) {
            attached = state->probes[i].attached;
            /* Detached probes must never carry the X4's frozen wire value. */
            temp = attached ? state->probes[i].temp_f10 : SX4_TEMP_DETACHED;
        }
        pending->rec.temp[i] = temp;
        pending->sample.temp_f10[i] = temp;
        if (attached) {
            attached_mask |= (uint8_t)(1u << i);
        }
    }

    pending->rec.flags = attached_mask;
    if (state->billows_attached) {
        pending->rec.flags |= SX4_RECORD_FLAG_BILLOWS_ATTACHED;
    }
    if (state->source_celsius) {
        pending->rec.flags |= SX4_RECORD_FLAG_SOURCE_CELSIUS;
    }
    if (state->new_alarm) {
        pending->rec.flags |= SX4_RECORD_FLAG_NEW_ALARM;
    }

    pending->sample.attached_mask = attached_mask;
    pending->sample.billows_attached = state->billows_attached;
    pending->sample.billows_target_valid = state->billows_target_valid;
    pending->sample.billows_target_f10 = 0;
    if (state->billows_target_valid) {
        pending->sample.billows_target_f10 =
            state->billows_target_units == SX_PROTOCOL_UNITS_FAHRENHEIT
                ? (int16_t)(state->billows_target_deg * 10)
                : celsius_deg_to_f10(state->billows_target_deg);
    }
    pending->sample.rssi_lora = rssi;
    pending->sample.snr_lora = snr;
}

static void publish_snapshot(sample_pipe_t *pipe,
                             const sample_pipe_pending_t *pending,
                             bool stored, uint32_t seq) {
    bridge_state_sample_t sample = pending->sample;
    if (stored) {
        pipe->last_seq = seq;
        pipe->have_seq = true;
        sample.seq = seq;
    } else {
        sample.seq = pipe->have_seq ? pipe->last_seq : 0;
        pipe->counters.log_write_failures++;
    }
    pipe->io.publish_snapshot(pipe->io.ctx, &sample);
    /* UI rendering is T22's; this only says "a new snapshot is available". */
    pipe->io.mark_dirty(pipe->io.ctx);
}

/* -------- counter helpers ------------------------------------------------- */

static void count_parse_failure(sample_pipe_t *pipe) {
    pipe->counters.parse_failures++;
}

/* -------- public API ------------------------------------------------------ */

bool sample_pipe_init(sample_pipe_t *pipe, const sample_pipe_io_t *io) {
    if (pipe == NULL || io == NULL || io->load_pairing == NULL ||
        io->save_probe_count == NULL || io->enqueue_log == NULL ||
        io->stamp_record == NULL || io->publish_snapshot == NULL ||
        io->mark_dirty == NULL || io->now_ms == NULL) {
        return false;
    }
    memset(pipe, 0, sizeof(*pipe));
    pipe->io = *io;
    return true;
}

sample_pipe_result_t sample_pipe_process(sample_pipe_t *pipe,
                                         const uint8_t *payload,
                                         uint8_t length, int8_t rssi,
                                         int8_t snr) {
    if (pipe == NULL) {
        return SAMPLE_PIPE_REJECTED;
    }

    char text[SX_PROTOCOL_MAX_PAYLOAD];
    if (!payload_to_text(payload, length, text, sizeof(text))) {
        count_parse_failure(pipe);
        return SAMPLE_PIPE_REJECTED;
    }

    const unsigned int commas = sx_protocol_count_commas(text);
    if (commas == SX_PROTOCOL_NUM_COMMAS_ACK) {
        /* Our own or the stock receiver's ACK is not sample input. */
        return SAMPLE_PIPE_IGNORED;
    }

    if (commas == SX_PROTOCOL_NUM_COMMAS_SYNC) {
        sx_protocol_sync_t sync;
        if (sx_protocol_parse_sync(text, &sync) != SX_PROTOCOL_OK) {
            count_parse_failure(pipe);
            return SAMPLE_PIPE_REJECTED;
        }
        pipe->counters.sync_beacons++;
        /* Pairing/ACK/TX are T16's; the pipeline only observes the beacon. */
        return SAMPLE_PIPE_IGNORED;
    }

    if (commas != SX_PROTOCOL_NUM_COMMAS_X4 &&
        commas != SX_PROTOCOL_NUM_COMMAS_X2) {
        count_parse_failure(pipe);
        return SAMPLE_PIPE_REJECTED;
    }

    sample_pipe_pairing_t pairing;
    memset(&pairing, 0, sizeof(pairing));
    if (!pipe->io.load_pairing(pipe->io.ctx, &pairing) || !pairing.paired) {
        /* Discovery is T16's; an unpaired state frame is not a record. */
        return SAMPLE_PIPE_IGNORED;
    }

    sx_protocol_state_t state;
    const sx_protocol_result_t parsed =
        sx_protocol_parse_state(text, pairing.device_id, &state);
    if (parsed == SX_PROTOCOL_ERR_FOREIGN_DEVICE) {
        pipe->counters.foreign_device_packets++;
        return SAMPLE_PIPE_REJECTED;
    }
    if (parsed != SX_PROTOCOL_OK) {
        count_parse_failure(pipe);
        return SAMPLE_PIPE_REJECTED;
    }

    pipe->counters.valid_state_packets++;
    pipe->have_last_packet = true;
    pipe->last_packet_ms = pipe->io.now_ms(pipe->io.ctx);

    /* First state packet after pairing (or a changed model) teaches T15 the
     * probe count. The pairing FSM normally persists it too; this call is
     * idempotent and keeps the pipeline correct when it is wired alone. */
    if (pairing.num_probes != state.num_probes) {
        (void)pipe->io.save_probe_count(pipe->io.ctx, state.device_id,
                                        state.num_probes);
    }

    sample_pipe_pending_t pending;
    build_pending(&state, rssi, snr, &pending);
    (void)pipe->io.stamp_record(pipe->io.ctx, &pending.rec);

    if (!sample_log_record_validate(&pending.rec)) {
        /* The parser and record builder disagree; never queue a bad record. */
        count_parse_failure(pipe);
        return SAMPLE_PIPE_REJECTED;
    }

    if (!pipe->io.enqueue_log(pipe->io.ctx, &pending)) {
        /* Full queue: counted drop, never a stall on flash. The sample is not
         * published either, so live values can never move backwards when the
         * earlier queued records finish. */
        pipe->counters.dropped_samples++;
        return SAMPLE_PIPE_RECORD_DROPPED;
    }
    return SAMPLE_PIPE_RECORD_QUEUED;
}

void sample_pipe_complete(sample_pipe_t *pipe,
                          const sample_pipe_pending_t *pending, bool stored,
                          uint32_t seq) {
    if (pipe == NULL || pending == NULL) {
        return;
    }
    publish_snapshot(pipe, pending, stored, seq);
}

void sample_pipe_counters(const sample_pipe_t *pipe,
                          sample_pipe_counters_t *out) {
    if (pipe == NULL || out == NULL) {
        return;
    }
    memset(out, 0, sizeof(*out));
    out->valid_state_packets = pipe->counters.valid_state_packets;
    out->parse_failures = pipe->counters.parse_failures;
    out->foreign_device_packets = pipe->counters.foreign_device_packets;
    out->sync_beacons = pipe->counters.sync_beacons;
    out->dropped_samples = pipe->counters.dropped_samples;
    out->log_write_failures = pipe->counters.log_write_failures;

    sx_protocol_counters_t protocol;
    sx_protocol_counters_get(&protocol);
    out->crc_failures = protocol.crc_failures;
    out->ack_attempts = protocol.ack_attempts;

    out->have_last_packet = pipe->have_last_packet;
    if (pipe->have_last_packet) {
        const uint64_t now = pipe->io.now_ms(pipe->io.ctx);
        uint64_t age_s =
            now >= pipe->last_packet_ms
                ? (now - pipe->last_packet_ms) / 1000u
                : 0u;
        if (age_s > UINT16_MAX) {
            age_s = UINT16_MAX;
        }
        out->last_packet_age_s = (uint16_t)age_s;
    }
}
