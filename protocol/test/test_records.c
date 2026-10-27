/*
 * Host test for the generated protocol codecs.
 *
 * The `live` vector is the normative example in docs/design/05-ble-contract.md
 * §5.4. The record and framing cases guard the rest of the generated contract.
 */

#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "records.h"

static const uint8_t LIVE_VECTOR[20] = {
    0x01, 0x17, 0xCA, 0x08, 0x74, 0x06, 0x00, 0x80, 0x20, 0x03,
    0xD2, 0x04, 0x00, 0x00, 0xCA, 0x08, 0x57, 0xB9, 0x0C, 0x00,
};

static void test_crc16(void) {
    static const uint8_t check[] = "123456789";
    assert(sx4_crc16_ccitt_false(check, 9) == 0x29B1u);
}

static void test_seq24(void) {
    uint8_t b[3];
    sx4_seq24_write(b, 0x123456u);
    assert(b[0] == 0x56u && b[1] == 0x34u && b[2] == 0x12u);
    assert(sx4_seq24_read(b) == 0x123456u);
    sx4_seq24_write(b, 0xFFFFFFu);
    assert(b[0] == 0xFFu && b[1] == 0xFFu && b[2] == 0xFFu);
    assert(sx4_seq24_read(b) == 0xFFFFFFu);
}

static void test_live_vector(void) {
    sx4_live_t live;
    assert(sx4_live_decode(LIVE_VECTOR, sizeof LIVE_VECTOR, &live));
    assert(live.ver == 1u);
    assert(live.flags == 0x17u);
    assert(sx4_live_flags_smoke_paired(live.flags));
    assert(sx4_live_flags_smoke_live(live.flags));
    assert(sx4_live_flags_billows_attached(live.flags));
    assert(sx4_live_flags_clock_valid(live.flags));
    assert(!sx4_live_flags_storage_ok(live.flags));
    assert(live.temp[0] == 2250);
    assert(live.temp[1] == 1652);
    assert(live.temp[2] == SX4_TEMP_DETACHED);
    assert(sx4_temp_is_detached(live.temp[2]));
    assert(live.temp[3] == 800);
    assert(live.seq == 1234u);
    assert(live.billows_target_f10 == 2250);
    assert(live.battery_pct == 87u);
    assert(live.rssi_lora == -71);
    assert(live.age_s == 12u);

    uint8_t out[20];
    assert(sx4_live_encode(&live, out, sizeof out) == sizeof out);
    assert(memcmp(out, LIVE_VECTOR, sizeof out) == 0);

    /* A short read must be rejected, never partially decoded. */
    assert(!sx4_live_decode(LIVE_VECTOR, sizeof LIVE_VECTOR - 1, &live));
    assert(!sx4_live_decode(LIVE_VECTOR, sizeof LIVE_VECTOR, NULL));
}

static void test_sample_rec_round_trip(void) {
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof rec);
    sx4_sample_rec_seq_set(&rec, 0xABCDEFu);
    rec.unix_s = 1720000000u;
    rec.temp[0] = 2250;
    rec.temp[1] = 1652;
    rec.temp[2] = SX4_TEMP_DETACHED;
    rec.temp[3] = SX4_TEMP_INVALID;
    rec.flags = SX4_RECORD_FLAG_PROBE1_ATTACHED | SX4_RECORD_FLAG_PROBE2_ATTACHED |
                SX4_RECORD_FLAG_CLOCK_VALID;

    uint8_t wire[SX4_SAMPLE_REC_SIZE];
    assert(sx4_sample_rec_encode(&rec, wire, sizeof wire) == sizeof wire);
    assert(wire[0] == 0xEFu && wire[1] == 0xCDu && wire[2] == 0xABu);

    sx4_sample_rec_t decoded;
    assert(sx4_sample_rec_decode(wire, sizeof wire, &decoded));
    assert(sx4_sample_rec_seq_get(&decoded) == 0xABCDEFu);
    assert(decoded.unix_s == 1720000000u);
    assert(decoded.temp[0] == 2250 && decoded.temp[1] == 1652);
    assert(decoded.temp[2] == SX4_TEMP_DETACHED);
    assert(decoded.temp[3] == SX4_TEMP_INVALID);
    assert(decoded.flags == rec.flags);

    /* Flip a payload bit: the CRC must reject the record. */
    wire[3] ^= 0x01u;
    assert(!sx4_sample_rec_decode(wire, sizeof wire, &decoded));
}

static void test_sector_header(void) {
    sx4_sector_header_t header;
    memset(&header, 0, sizeof header);
    sx4_sector_header_first_seq_set(&header, 0x010203u);
    header.generation = 0x11223344u;
    uint8_t wire[SX4_SECTOR_HEADER_SIZE];
    assert(sx4_sector_header_encode(&header, wire, sizeof wire) == sizeof wire);
    assert(memcmp(wire, "SX4L", 4) == 0);
    assert(wire[4] == 1u);
    assert(wire[6] == 0x03u && wire[7] == 0x02u && wire[8] == 0x01u);
    sx4_sector_header_t decoded;
    assert(sx4_sector_header_decode(wire, sizeof wire, &decoded));
    assert(sx4_sector_header_first_seq_get(&decoded) == 0x010203u);
    assert(decoded.generation == 0x11223344u);
    wire[9] ^= 0x01u;
    assert(!sx4_sector_header_decode(wire, sizeof wire, &decoded));
}

static void test_ble_round_trips(void) {
    sx4_sync_ctrl_t ctrl;
    memset(&ctrl, 0, sizeof ctrl);
    ctrl.ver = 1;
    ctrl.cmd = SX4_SYNC_CMD_READ;
    ctrl.direction = SX4_SYNC_DIRECTION_BACKWARD;
    ctrl.cursor_seq = 4000;
    ctrl.max_records = 32;
    uint8_t wire[32];
    assert(sx4_sync_ctrl_encode(&ctrl, wire, sizeof wire) == SX4_SYNC_CTRL_SIZE);
    sx4_sync_ctrl_t ctrl2;
    assert(sx4_sync_ctrl_decode(wire, SX4_SYNC_CTRL_SIZE, &ctrl2));
    assert(ctrl2.cmd == SX4_SYNC_CMD_READ);
    assert(ctrl2.direction == SX4_SYNC_DIRECTION_BACKWARD);
    assert(ctrl2.cursor_seq == 4000);
    assert(ctrl2.max_records == 32);

    sx4_sync_start_t start;
    memset(&start, 0, sizeof start);
    start.generation = 0xDEADBEEFu;
    start.min_seq = 10;
    start.max_seq = 20;
    start.start_seq = 15;
    start.count = 6;
    start.status = SX4_SYNC_STATUS_OK;
    assert(sx4_sync_start_encode(&start, wire, sizeof wire) == SX4_SYNC_START_SIZE);
    sx4_sync_start_t start2;
    assert(sx4_sync_start_decode(wire, SX4_SYNC_START_SIZE, &start2));
    assert(start2.generation == 0xDEADBEEFu);
    assert(start2.record_size == SX4_RECORD_SIZE);
    assert(start2.status == SX4_SYNC_STATUS_OK);

    sx4_result_t result;
    memset(&result, 0, sizeof result);
    result.ver = 1;
    result.op = SX4_CONTROL_OP_SET_TIME;
    result.op_id = 9;
    result.status = SX4_RESULT_STATUS_INVALID;
    memcpy(result.detail, "clock out of range", 18);
    assert(sx4_result_encode(&result, wire, sizeof wire) == 23u);
    assert(wire[4] == 18u);
    sx4_result_t result2;
    assert(sx4_result_decode(wire, 23, &result2));
    assert(result2.op == SX4_CONTROL_OP_SET_TIME);
    assert(result2.op_id == 9);
    assert(result2.status == SX4_RESULT_STATUS_INVALID);
    assert(result2.len == 18u);
    assert(memcmp(result2.detail, "clock out of range", 18) == 0);

    /* Truncating the detail must be rejected. */
    assert(!sx4_result_decode(wire, 22, &result2));
}

static void test_info_strings(void) {
    sx4_info_t info;
    memset(&info, 0, sizeof info);
    info.ver = 1;
    info.proto_major = 1;
    info.proto_minor = 0;
    info.caps = SX4_CAPS_FLAG_BILLOWS_OBSERVE | SX4_CAPS_FLAG_HISTORY |
                SX4_CAPS_FLAG_BATTERY | SX4_CAPS_FLAG_CONFIG;
    info.probes = 4;
    memcpy(info.device_id, "A4F2", 4);
    memcpy(info.fw, "0.1.0", 5);
    memcpy(info.model, "heltec3", 7);
    info.bonds_free = 3;

    uint8_t wire[SX4_INFO_SIZE];
    assert(sx4_info_encode(&info, wire, sizeof wire) == SX4_INFO_SIZE);
    assert(memcmp(wire + 6, "A4F2", 4) == 0);
    assert(memcmp(wire + 10, "0.1.0", 5) == 0);
    sx4_info_t info2;
    assert(sx4_info_decode(wire, SX4_INFO_SIZE, &info2));
    assert(memcmp(info2.device_id, "A4F2", 4) == 0);
    assert(memcmp(info2.fw, "0.1.0", 5) == 0);
    assert(!sx4_info_caps_billows_control(info2.caps));
    assert(sx4_info_caps_billows_observe(info2.caps));
}

int main(void) {
    test_crc16();
    test_seq24();
    test_live_vector();
    test_sample_rec_round_trip();
    test_sector_header();
    test_ble_round_trips();
    test_info_strings();
    return 0;
}
