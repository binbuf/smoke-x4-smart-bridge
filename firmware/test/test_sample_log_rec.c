/*
 * Host tests for the sample-log record codec (T17).
 *
 * Covers the wire layout, CRC, the exact sentinels, attach-bit agreement,
 * Celsius/alarm provenance flags, record_size and no-partial-output rules.
 */

#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "log_core.h"
#include "records.h"

#define PROBE_FLAGS                                                     \
    (SX4_RECORD_FLAG_PROBE1_ATTACHED | SX4_RECORD_FLAG_PROBE2_ATTACHED | \
     SX4_RECORD_FLAG_PROBE3_ATTACHED | SX4_RECORD_FLAG_PROBE4_ATTACHED)

static void record_attached(sx4_sample_rec_t *rec, uint32_t seq) {
    memset(rec, 0, sizeof(*rec));
    sx4_sample_rec_seq_set(rec, seq);
    rec->unix_s = 1720000000u;
    rec->temp[0] = 2250;
    rec->temp[1] = 1652;
    rec->temp[2] = 800;
    rec->temp[3] = 400;
    rec->flags = PROBE_FLAGS | SX4_RECORD_FLAG_CLOCK_VALID;
}

static void test_record_size(void) {
    assert(sample_log_record_size() == 18u);
    assert(SAMPLE_LOG_RECORD_SIZE == 18u);
    assert(SX4_SAMPLE_REC_SIZE == 18u);
    assert(sizeof(sx4_sample_rec_t) == 18u);
    assert(sample_log_record_size() == sizeof(sx4_sample_rec_t));
}

static void test_wire_layout(void) {
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    sx4_sample_rec_seq_set(&rec, 0xABCDEFu);
    rec.unix_s = 0x11223344u;
    rec.temp[0] = 0x0102;
    rec.temp[1] = -1;
    rec.temp[2] = SX4_TEMP_DETACHED;
    rec.temp[3] = SX4_TEMP_INVALID;
    /* probe3 is detached (flag 0); probe4 is present but invalid (flag 1). */
    rec.flags = SX4_RECORD_FLAG_PROBE1_ATTACHED | SX4_RECORD_FLAG_PROBE2_ATTACHED |
                SX4_RECORD_FLAG_PROBE4_ATTACHED | SX4_RECORD_FLAG_CLOCK_VALID;

    uint8_t wire[SAMPLE_LOG_RECORD_SIZE];
    assert(sample_log_record_encode(&rec, wire, sizeof(wire)) == SAMPLE_LOG_OK);

    /* seq: 24-bit little-endian at 0..2 */
    assert(wire[0] == 0xEFu && wire[1] == 0xCDu && wire[2] == 0xABu);
    /* unix_s: 32-bit little-endian at 3..6 */
    assert(wire[3] == 0x44u && wire[4] == 0x33u && wire[5] == 0x22u &&
           wire[6] == 0x11u);
    /* four i16 temperatures, little-endian, at 7, 9, 11, 13 */
    assert(wire[7] == 0x02u && wire[8] == 0x01u);
    assert(wire[9] == 0xFFu && wire[10] == 0xFFu);
    assert(wire[11] == 0x00u && wire[12] == 0x80u); /* -32768 */
    assert(wire[13] == 0x01u && wire[14] == 0x80u); /* -32767 */
    /* flags at 15 */
    assert(wire[15] ==
           (SX4_RECORD_FLAG_PROBE1_ATTACHED | SX4_RECORD_FLAG_PROBE2_ATTACHED |
            SX4_RECORD_FLAG_PROBE4_ATTACHED | SX4_RECORD_FLAG_CLOCK_VALID));
    /* CRC-16/CCITT-FALSE over bytes 0..15, little-endian at 16..17 */
    uint16_t want_crc = sx4_crc16_ccitt_false(wire, 16);
    assert(wire[16] == (uint8_t)(want_crc & 0xFFu));
    assert(wire[17] == (uint8_t)(want_crc >> 8));
}

static void round_trip(const sx4_sample_rec_t *rec) {
    uint8_t wire[SAMPLE_LOG_RECORD_SIZE];
    assert(sample_log_record_encode(rec, wire, sizeof(wire)) == SAMPLE_LOG_OK);

    sx4_sample_rec_t decoded;
    memset(&decoded, 0xA5, sizeof(decoded));
    assert(sample_log_record_decode(wire, sizeof(wire), &decoded) ==
           SAMPLE_LOG_OK);
    assert(sx4_sample_rec_seq_get(&decoded) == sx4_sample_rec_seq_get(rec));
    assert(decoded.unix_s == rec->unix_s);
    assert(decoded.flags == rec->flags);
    for (unsigned i = 0; i < 4u; i++) {
        assert(decoded.temp[i] == rec->temp[i]);
    }

    /* A trailing byte belongs to the next record and must not break decode. */
    uint8_t slice[SAMPLE_LOG_RECORD_SIZE + 1];
    memcpy(slice, wire, sizeof(wire));
    slice[sizeof(wire)] = 0x5A;
    assert(sample_log_record_decode(slice, sizeof(slice), &decoded) ==
           SAMPLE_LOG_OK);
}

static void test_round_trips(void) {
    /* Attached: every probe numeric, clock valid. */
    sx4_sample_rec_t rec;
    record_attached(&rec, 0);
    round_trip(&rec);

    /* Sequence upper edge (u24 max). */
    record_attached(&rec, 0xFFFFFFu);
    round_trip(&rec);
    assert(sx4_sample_rec_seq_get(&rec) == 0xFFFFFFu);

    /* Detached: all four sentinels, no attach bits, no clock. */
    memset(&rec, 0, sizeof(rec));
    sx4_sample_rec_seq_set(&rec, 1u);
    rec.unix_s = 0;
    for (unsigned i = 0; i < 4u; i++) {
        rec.temp[i] = SX4_TEMP_DETACHED;
    }
    rec.flags = 0;
    round_trip(&rec);

    /* Present but invalid/unmapped: probe 1 attached, TEMP_INVALID. */
    memset(&rec, 0, sizeof(rec));
    sx4_sample_rec_seq_set(&rec, 2u);
    rec.unix_s = 1000u;
    rec.temp[0] = SX4_TEMP_INVALID;
    rec.temp[1] = SX4_TEMP_DETACHED;
    rec.temp[2] = SX4_TEMP_DETACHED;
    rec.temp[3] = SX4_TEMP_DETACHED;
    rec.flags = SX4_RECORD_FLAG_PROBE1_ATTACHED | SX4_RECORD_FLAG_CLOCK_VALID;
    round_trip(&rec);

    /* Celsius source: provenance only, stored temperatures stay Fahrenheit. */
    record_attached(&rec, 3u);
    rec.flags |= SX4_RECORD_FLAG_SOURCE_CELSIUS;
    round_trip(&rec);
    assert(sx4_sample_rec_flags_source_celsius(rec.flags));

    /* Alarm edge: new_alarm is preserved even though the MVP has no alarms. */
    record_attached(&rec, 4u);
    rec.flags |= SX4_RECORD_FLAG_NEW_ALARM | SX4_RECORD_FLAG_BILLOWS_ATTACHED;
    round_trip(&rec);
    assert(sx4_sample_rec_flags_new_alarm(rec.flags));
    assert(sx4_sample_rec_flags_billows_attached(rec.flags));
}

static void test_bad_crc(void) {
    sx4_sample_rec_t rec;
    record_attached(&rec, 10u);
    uint8_t wire[SAMPLE_LOG_RECORD_SIZE];
    assert(sample_log_record_encode(&rec, wire, sizeof(wire)) == SAMPLE_LOG_OK);

    sx4_sample_rec_t out;
    memset(&out, 0x5A, sizeof(out));
    sx4_sample_rec_t before = out;

    /* Flip a payload bit. */
    wire[3] ^= 0x01u;
    assert(sample_log_record_decode(wire, sizeof(wire), &out) ==
           SAMPLE_LOG_ERR_CRC);
    assert(memcmp(&out, &before, sizeof(out)) == 0);

    /* Flip a CRC bit. */
    assert(sample_log_record_encode(&rec, wire, sizeof(wire)) == SAMPLE_LOG_OK);
    wire[17] ^= 0x80u;
    assert(sample_log_record_decode(wire, sizeof(wire), &out) ==
           SAMPLE_LOG_ERR_CRC);
    assert(memcmp(&out, &before, sizeof(out)) == 0);
}

static void test_detached_never_numeric(void) {
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    sx4_sample_rec_seq_set(&rec, 11u);
    for (unsigned i = 0; i < 4u; i++) {
        rec.temp[i] = SX4_TEMP_DETACHED;
    }
    rec.flags = 0;

    uint8_t wire[SAMPLE_LOG_RECORD_SIZE];
    assert(sample_log_record_encode(&rec, wire, sizeof(wire)) == SAMPLE_LOG_OK);

    sx4_sample_rec_t decoded;
    assert(sample_log_record_decode(wire, sizeof(wire), &decoded) ==
           SAMPLE_LOG_OK);
    for (unsigned i = 0; i < 4u; i++) {
        assert(decoded.temp[i] == SX4_TEMP_DETACHED);
        assert(decoded.temp[i] == INT16_MIN);
        assert(sx4_temp_is_detached(decoded.temp[i]));
        assert(!sample_log_record_probe_attached(&decoded, i));
    }
}

static void test_attach_flag_mismatch(void) {
    /* Attached=0 with a numeric temperature must be rejected on encode. */
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    rec.temp[0] = 2250;
    rec.temp[1] = SX4_TEMP_DETACHED;
    rec.temp[2] = SX4_TEMP_DETACHED;
    rec.temp[3] = SX4_TEMP_DETACHED;
    rec.flags = SX4_RECORD_FLAG_PROBE2_ATTACHED |
                SX4_RECORD_FLAG_PROBE3_ATTACHED |
                SX4_RECORD_FLAG_PROBE4_ATTACHED;
    uint8_t wire[SAMPLE_LOG_RECORD_SIZE];
    memset(wire, 0xCC, sizeof(wire));
    uint8_t before[SAMPLE_LOG_RECORD_SIZE];
    memcpy(before, wire, sizeof(wire));
    assert(sample_log_record_encode(&rec, wire, sizeof(wire)) ==
           SAMPLE_LOG_ERR_LAYOUT);
    assert(memcmp(wire, before, sizeof(wire)) == 0);

    /* Attached=1 with TEMP_DETACHED must also be rejected. */
    memset(&rec, 0, sizeof(rec));
    for (unsigned i = 0; i < 4u; i++) {
        rec.temp[i] = SX4_TEMP_DETACHED;
    }
    rec.temp[1] = 1652;
    rec.flags = PROBE_FLAGS;
    assert(sample_log_record_encode(&rec, wire, sizeof(wire)) ==
           SAMPLE_LOG_ERR_LAYOUT);

    /* A decoded record with the same disagreement is corrupt. Build the wire
     * with the generated encoder (which does not apply the semantic rule). */
    sx4_sample_rec_t bad;
    memset(&bad, 0, sizeof(bad));
    bad.temp[0] = 100;
    bad.temp[1] = 200;
    bad.temp[3] = 300;
    bad.temp[2] = SX4_TEMP_INVALID;
    bad.flags = PROBE_FLAGS & (uint8_t)~SX4_RECORD_FLAG_PROBE3_ATTACHED;
    assert(sx4_sample_rec_encode(&bad, wire, sizeof(wire)) == sizeof(wire));

    sx4_sample_rec_t out;
    memset(&out, 0x33, sizeof(out));
    sx4_sample_rec_t out_before = out;
    assert(sample_log_record_decode(wire, sizeof(wire), &out) ==
           SAMPLE_LOG_ERR_LAYOUT);
    assert(memcmp(&out, &out_before, sizeof(out)) == 0);

    /* One mismatch per probe, both directions. */
    for (unsigned probe = 0; probe < 4u; probe++) {
        memset(&rec, 0, sizeof(rec));
        for (unsigned i = 0; i < 4u; i++) {
            rec.temp[i] = SX4_TEMP_DETACHED;
        }
        rec.flags = (uint8_t)(PROBE_FLAGS & (uint8_t)~(1u << probe));
        rec.temp[probe] = 700; /* flag 0, numeric temp */
        assert(sample_log_record_encode(&rec, wire, sizeof(wire)) ==
               SAMPLE_LOG_ERR_LAYOUT);
        rec.temp[probe] = SX4_TEMP_DETACHED;
        rec.flags = (uint8_t)(rec.flags | (1u << probe)); /* flag 1, detached */
        assert(sample_log_record_encode(&rec, wire, sizeof(wire)) ==
               SAMPLE_LOG_ERR_LAYOUT);
    }
}

static void test_bounds_and_arguments(void) {
    sx4_sample_rec_t rec;
    record_attached(&rec, 12u);
    uint8_t wire[SAMPLE_LOG_RECORD_SIZE];

    assert(sample_log_record_encode(NULL, wire, sizeof(wire)) ==
           SAMPLE_LOG_ERR_ARGUMENT);
    assert(sample_log_record_encode(&rec, NULL, sizeof(wire)) ==
           SAMPLE_LOG_ERR_ARGUMENT);
    assert(sample_log_record_encode(&rec, wire, SAMPLE_LOG_RECORD_SIZE - 1u) ==
           SAMPLE_LOG_ERR_SIZE);

    memset(wire, 0, sizeof(wire));
    assert(sample_log_record_decode(NULL, sizeof(wire), &rec) ==
           SAMPLE_LOG_ERR_ARGUMENT);
    assert(sample_log_record_decode(wire, sizeof(wire), NULL) ==
           SAMPLE_LOG_ERR_ARGUMENT);
    assert(sample_log_record_decode(wire, SAMPLE_LOG_RECORD_SIZE - 1u, &rec) ==
           SAMPLE_LOG_ERR_SIZE);

    assert(!sample_log_record_validate(NULL));
    assert(!sample_log_record_probe_attached(NULL, 0));
    assert(!sample_log_record_probe_attached(&rec, 4u));
    assert(sample_log_record_probe_attached(&rec, 0));
    assert(sample_log_record_probe_attached(&rec, 3));
}

int main(void) {
    test_record_size();
    test_wire_layout();
    test_round_trips();
    test_bad_crc();
    test_detached_never_numeric();
    test_attach_flag_mismatch();
    test_bounds_and_arguments();
    return 0;
}
