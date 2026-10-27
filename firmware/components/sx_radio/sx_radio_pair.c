/*
 * sx_radio_pair.c - Smoke X pairing FSM (design 02 section 2.7).
 *
 * Pure C11, no heap, no I/O. The sync-beacon branch of
 * sx4_radio_pair_on_packet() contains the single call to io->send_ack(); the
 * host test guards both that call site and the runtime behaviour.
 *
 * Validation order for a beacon is: parse -> 902-928 MHz range -> format ACK
 * -> tune -> transmit -> commit state. Any failure before the transmit leaves
 * the FSM state untouched; a transmit failure restores the previous tuning.
 */
#include "sx_radio_pair.h"

#include <string.h>

#include "sx_protocol.h"
#include "sx_radio_params.h"

typedef struct {
    sx4_radio_pair_io_t io;
    sx4_pair_state_t state;
    sx4_pair_record_t record; /* pending in SYNC_RECEIVED, persisted after */
    uint32_t tuned_hz;
    uint32_t scan_hz;
    uint64_t last_scan_ms;
    uint64_t last_valid_ms; /* last accepted state packet */
} pair_ctx_t;

static pair_ctx_t s_pair;
static sx4_radio_pair_counters_t s_counters;

static bool record_valid(const sx4_pair_record_t *record) {
    if (record == NULL) {
        return false;
    }
    size_t id_len = strnlen(record->device_id, SX4_PAIR_DEVICE_ID_MAX);
    if (id_len == 0 || id_len == SX4_PAIR_DEVICE_ID_MAX) {
        return false;
    }
    if (!sx4_radio_frequency_valid(record->frequency_hz)) {
        return false;
    }
    return record->num_probes == 2u || record->num_probes == 4u;
}

static bool tune(uint32_t frequency_hz) {
    if (s_pair.io.tune == NULL) {
        return false;
    }
    if (!s_pair.io.tune(s_pair.io.ctx, frequency_hz)) {
        return false;
    }
    s_pair.tuned_hz = frequency_hz;
    return true;
}

static bool copy_payload(const uint8_t *payload, size_t length, char *out) {
    /* The parser takes a NUL-terminated string and rejects >= 128 bytes. */
    if (payload == NULL || length == 0 ||
        length >= SX_PROTOCOL_MAX_PAYLOAD) {
        return false;
    }
    memcpy(out, payload, length);
    out[length] = '\0';
    return true;
}

/*
 * The only path to the radio TX callback. Called once per accepted beacon.
 */
static bool handle_sync(const char *text, uint64_t now_ms) {
    sx_protocol_sync_t sync;
    if (sx_protocol_parse_sync(text, &sync) != SX_PROTOCOL_OK) {
        s_counters.rejected_syncs++;
        return false;
    }
    if (!sx4_radio_frequency_valid(sync.frequency_hz)) {
        /* Out of band: never retune, never transmit, state unchanged. */
        s_counters.rejected_syncs++;
        return false;
    }

    char ack[SX_PROTOCOL_DEVICE_ID_LEN + 16u];
    int ack_len = sx_protocol_format_ack(sync.device_id, ack, sizeof ack);
    if (ack_len <= 0) {
        s_counters.rejected_syncs++;
        return false;
    }

    uint32_t previous_hz = s_pair.tuned_hz;
    if (!tune(sync.frequency_hz)) {
        s_counters.rejected_syncs++;
        return false;
    }
    if (!s_pair.io.send_ack(s_pair.io.ctx, ack, (size_t)ack_len)) {
        /* Not accepted: leave the FSM unpaired and restore scan tuning. */
        (void)tune(previous_hz);
        s_counters.rejected_syncs++;
        return false;
    }

    memset(&s_pair.record, 0, sizeof s_pair.record);
    size_t id_len = strnlen(sync.device_id, sizeof sync.device_id);
    memcpy(s_pair.record.device_id, sync.device_id, id_len);
    s_pair.record.frequency_hz = sync.frequency_hz;
    s_pair.record.num_probes = 0; /* learned from the first state packet */
    s_pair.state = SX4_PAIR_SYNC_RECEIVED;
    s_pair.last_valid_ms = now_ms;

    s_counters.sync_accepted++;
    s_counters.acks_sent++;
    return true;
}

/* A state packet while SYNC_RECEIVED confirms the pending pairing. */
static bool confirm_pending(uint64_t now_ms) {
    sx4_pair_record_t candidate = s_pair.record;
    if (candidate.num_probes != 2u && candidate.num_probes != 4u) {
        return false;
    }
    if (s_pair.io.save == NULL ||
        !s_pair.io.save(s_pair.io.ctx, &candidate)) {
        s_counters.save_failures++;
        return false;
    }
    s_pair.record = candidate;
    s_pair.state = SX4_PAIR_PAIRED;
    s_pair.last_valid_ms = now_ms;
    s_counters.confirmations++;
    return true;
}

static bool handle_state(const char *text, uint64_t now_ms) {
    if (s_pair.state == SX4_PAIR_UNPAIRED) {
        /* No pairing yet: discovery only. Never confirm from a stray frame. */
        return false;
    }

    sx_protocol_state_t state;
    const char *expected_id = s_pair.record.device_id;
    if (sx_protocol_parse_state(text, expected_id, &state) != SX_PROTOCOL_OK) {
        return false;
    }
    s_counters.state_packets++;

    if (s_pair.state == SX4_PAIR_SYNC_RECEIVED) {
        s_pair.record.num_probes = state.num_probes;
        return confirm_pending(now_ms);
    }

    s_pair.last_valid_ms = now_ms;
    if (s_pair.state == SX4_PAIR_LOST) {
        s_pair.state = SX4_PAIR_PAIRED;
        s_counters.lost_recoveries++;
    }
    return true;
}

bool sx4_radio_pair_init(const sx4_radio_pair_io_t *io, uint64_t now_ms) {
    if (io == NULL || io->tune == NULL || io->send_ack == NULL ||
        io->save == NULL || io->clear == NULL) {
        return false;
    }

    memset(&s_pair, 0, sizeof s_pair);
    memset(&s_counters, 0, sizeof s_counters);
    s_pair.io = *io;
    s_pair.state = SX4_PAIR_UNPAIRED;
    s_pair.scan_hz = SX4_PAIR_SYNC_CHANNEL_A_HZ;
    s_pair.last_scan_ms = now_ms;
    s_pair.last_valid_ms = now_ms;

    if (io->load != NULL) {
        sx4_pair_record_t stored;
        memset(&stored, 0, sizeof stored);
        if (io->load(io->ctx, &stored) && record_valid(&stored)) {
            if (!tune(stored.frequency_hz)) {
                return false;
            }
            s_pair.record = stored;
            s_pair.state = SX4_PAIR_PAIRED;
            s_pair.last_valid_ms = now_ms;
            return true;
        }
    }

    /* Unpaired: start the alternating sync scan on 915 MHz. */
    if (!tune(s_pair.scan_hz)) {
        return false;
    }
    return true;
}

sx4_pair_state_t sx4_radio_pair_state(void) { return s_pair.state; }

bool sx4_radio_pair_record(sx4_pair_record_t *out) {
    if (out == NULL || s_pair.state == SX4_PAIR_UNPAIRED) {
        return false;
    }
    *out = s_pair.record;
    return true;
}

uint32_t sx4_radio_pair_scan_frequency_hz(void) { return s_pair.scan_hz; }

uint32_t sx4_radio_pair_tuned_frequency_hz(void) { return s_pair.tuned_hz; }

bool sx4_radio_pair_on_packet(const uint8_t *payload, size_t length,
                              uint64_t now_ms) {
    char text[SX_PROTOCOL_MAX_PAYLOAD];
    if (!copy_payload(payload, length, text)) {
        return false;
    }

    unsigned int commas = sx_protocol_count_commas(text);
    if (commas == SX_PROTOCOL_NUM_COMMAS_SYNC) {
        /* Rule 1: once accepted, ignore beacons until an explicit unpair. */
        if (s_pair.state != SX4_PAIR_UNPAIRED) {
            return false;
        }
        return handle_sync(text, now_ms);
    }
    if (commas == SX_PROTOCOL_NUM_COMMAS_X4 ||
        commas == SX_PROTOCOL_NUM_COMMAS_X2) {
        return handle_state(text, now_ms);
    }
    /* 2-comma ACKs (from a stock receiver or another bridge) are not input. */
    return false;
}

void sx4_radio_pair_tick(uint64_t now_ms) {
    if (s_pair.state == SX4_PAIR_UNPAIRED) {
        if (now_ms - s_pair.last_scan_ms < SX4_PAIR_SCAN_INTERVAL_MS) {
            return;
        }
        uint32_t next_hz = s_pair.scan_hz == SX4_PAIR_SYNC_CHANNEL_A_HZ
                               ? SX4_PAIR_SYNC_CHANNEL_B_HZ
                               : SX4_PAIR_SYNC_CHANNEL_A_HZ;
        if (tune(next_hz)) {
            s_pair.scan_hz = next_hz;
        }
        s_pair.last_scan_ms = now_ms;
        return;
    }

    if (s_pair.state == SX4_PAIR_PAIRED &&
        now_ms - s_pair.last_valid_ms >= SX4_PAIR_LOST_TIMEOUT_MS) {
        /* LOST is status only: pairing is kept and the radio stays tuned. */
        s_pair.state = SX4_PAIR_LOST;
        s_counters.lost_entries++;
    }
}

bool sx4_radio_pair_unpair(uint64_t now_ms) {
    if (s_pair.io.clear == NULL || !s_pair.io.clear(s_pair.io.ctx)) {
        return false;
    }

    memset(&s_pair.record, 0, sizeof s_pair.record);
    s_pair.state = SX4_PAIR_UNPAIRED;
    s_pair.scan_hz = SX4_PAIR_SYNC_CHANNEL_A_HZ;
    s_pair.last_scan_ms = now_ms;
    s_pair.last_valid_ms = now_ms;
    (void)tune(s_pair.scan_hz);
    return true;
}

void sx4_radio_pair_counters_get(sx4_radio_pair_counters_t *out) {
    if (out != NULL) {
        *out = s_counters;
    }
}

void sx4_radio_pair_counters_reset(void) {
    memset(&s_counters, 0, sizeof s_counters);
}
