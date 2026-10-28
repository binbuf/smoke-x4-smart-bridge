/*
 * test_ble_stats.c - host vectors for the T47 `stats` characteristic.
 *
 * Covers the empty log and a full ring: exact 60 bytes, the flag byte, the
 * min/max sentinels, capacity, signed RSSI/SNR, unknown battery, zero
 * oldest/newest, reserved bytes and Read Blob reassembly at MTU 23.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_stats.h"
#include "records.h"
#include "test_util.h"

#define MTU23_PAYLOAD 20u

static void check_empty_log(void) {
    ble_stats_view_t view;
    uint8_t out[SX4_STATS_SIZE];
    sx4_stats_t decoded;

    memset(&view, 0, sizeof(view));
    view.flags = ble_stats_build_flags(false, false, true, false, false, true,
                                       false);
    view.uptime_s = 120u;
    view.records_stored = 0u;
    view.records_capacity = BLE_STATS_CAPACITY;
    view.min_seq = BLE_STATS_SEQ_NONE;
    view.max_seq = BLE_STATS_SEQ_NONE;
    view.generation = 0u;
    view.battery_pct = SX4_BATTERY_UNKNOWN;
    view.heap_free = 120000u;
    view.heap_min = 100000u;
    /* Empty log: oldest/newest are 0 even though the clock may be valid. */

    CHECK_EQ_UINT(ble_stats_encode(&view, out, sizeof(out)), SX4_STATS_SIZE);
    CHECK_EQ_UINT(out[0], 1u);
    CHECK_EQ_UINT(out[1], SX4_STATS_FLAG_ADVERTISING | SX4_STATS_FLAG_STORAGE_OK);
    CHECK_EQ_UINT((uint32_t)out[6] | ((uint32_t)out[7] << 8) |
                      ((uint32_t)out[8] << 16) | ((uint32_t)out[9] << 24),
                  0u);
    CHECK_EQ_UINT((uint32_t)out[10] | ((uint32_t)out[11] << 8) |
                      ((uint32_t)out[12] << 16) | ((uint32_t)out[13] << 24),
                  BLE_STATS_CAPACITY);
    CHECK_EQ_UINT((uint32_t)out[14] | ((uint32_t)out[15] << 8) |
                      ((uint32_t)out[16] << 16) | ((uint32_t)out[17] << 24),
                  0xFFFFFFFFu);
    CHECK_EQ_UINT((uint32_t)out[18] | ((uint32_t)out[19] << 8) |
                      ((uint32_t)out[20] << 16) | ((uint32_t)out[21] << 24),
                  0xFFFFFFFFu);
    CHECK_EQ_UINT(out[36], SX4_BATTERY_UNKNOWN);
    CHECK_EQ_UINT((uint32_t)out[52] | ((uint32_t)out[53] << 8) |
                      ((uint32_t)out[54] << 16) | ((uint32_t)out[55] << 24),
                  0u);
    CHECK_EQ_UINT((uint32_t)out[56] | ((uint32_t)out[57] << 8) |
                      ((uint32_t)out[58] << 16) | ((uint32_t)out[59] << 24),
                  0u);
    CHECK_EQ_UINT(out[39], 0u);
    CHECK_EQ_UINT(out[50], 0u);
    CHECK_EQ_UINT(out[51], 0u);

    CHECK(sx4_stats_decode(out, sizeof(out), &decoded));
    CHECK_EQ_UINT(decoded.ver, 1u);
    CHECK_EQ_UINT(decoded.min_seq, 0xFFFFFFFFu);
    CHECK_EQ_UINT(decoded.max_seq, 0xFFFFFFFFu);
    CHECK_EQ_UINT(decoded.oldest_unix_s, 0u);
    CHECK_EQ_UINT(decoded.newest_unix_s, 0u);
    CHECK_EQ_UINT(decoded.battery_pct, 255u);
}

static void check_full_ring(void) {
    ble_stats_view_t view;
    uint8_t out[SX4_STATS_SIZE];
    sx4_stats_t decoded;

    memset(&view, 0, sizeof(view));
    view.flags = ble_stats_build_flags(true, true, true, true, true, true,
                                       true);
    view.uptime_s = 86400u;
    view.records_stored = BLE_STATS_CAPACITY;
    view.records_capacity = BLE_STATS_CAPACITY;
    view.min_seq = 100u;
    view.max_seq = 338499u;
    view.generation = 0x12345678u;
    view.packets_ok = 5000u;
    view.packets_bad = 7u;
    view.battery_mv = 4012u;
    view.battery_pct = 91u;
    view.lora_rssi = -71;
    view.lora_snr = -7;
    view.heap_free = 123456u;
    view.heap_min = 100000u;
    view.dropped_samples = 65535u;
    view.oldest_unix_s = 1700000000u;
    view.newest_unix_s = 1700100000u;

    CHECK_EQ_UINT(ble_stats_encode(&view, out, sizeof(out)), SX4_STATS_SIZE);
    /* All seven defined flag bits, and never the reserved control bit. */
    CHECK_EQ_UINT(out[1], 0x7Fu);
    CHECK_EQ_UINT(out[1] & SX4_STATS_FLAG_BILLOWS_CONTROL, 0u);

    CHECK(sx4_stats_decode(out, sizeof(out), &decoded));
    CHECK_EQ_UINT(decoded.flags, 0x7Fu);
    CHECK_EQ_UINT(decoded.uptime_s, 86400u);
    CHECK_EQ_UINT(decoded.records_stored, BLE_STATS_CAPACITY);
    CHECK_EQ_UINT(decoded.records_capacity, BLE_STATS_CAPACITY);
    CHECK_EQ_UINT(decoded.min_seq, 100u);
    CHECK_EQ_UINT(decoded.max_seq, 338499u);
    CHECK_EQ_UINT(decoded.generation, 0x12345678u);
    CHECK_EQ_UINT(decoded.packets_ok, 5000u);
    CHECK_EQ_UINT(decoded.packets_bad, 7u);
    CHECK_EQ_UINT(decoded.battery_mv, 4012u);
    CHECK_EQ_UINT(decoded.battery_pct, 91u);
    CHECK_EQ_INT(decoded.lora_rssi, -71);
    CHECK_EQ_INT(decoded.lora_snr, -7);
    CHECK_EQ_UINT(decoded.heap_free, 123456u);
    CHECK_EQ_UINT(decoded.heap_min, 100000u);
    CHECK_EQ_UINT(decoded.dropped_samples, 65535u);
    CHECK_EQ_UINT(decoded.oldest_unix_s, 1700000000u);
    CHECK_EQ_UINT(decoded.newest_unix_s, 1700100000u);
    /* Signed bytes survive on the wire as two's complement. */
    CHECK_EQ_UINT(out[37], 0xB9u);
    CHECK_EQ_UINT(out[38], 0xF9u);
    CHECK_EQ_UINT(out[39], 0u);
    CHECK_EQ_UINT(out[50], 0u);
    CHECK_EQ_UINT(out[51], 0u);
}

static void check_flags(void) {
    /* Bit 7 can never be set even if every MVP flag is true. */
    CHECK_EQ_UINT(ble_stats_build_flags(true, true, true, true, true, true,
                                        true),
                  0x7Fu);
    CHECK_EQ_UINT(ble_stats_build_flags(false, false, false, false, false,
                                        false, false),
                  0u);
    CHECK_EQ_UINT(ble_stats_build_flags(true, false, true, false, true, false,
                                        true),
                  SX4_STATS_FLAG_SMOKE_PAIRED | SX4_STATS_FLAG_ADVERTISING |
                      SX4_STATS_FLAG_CLOCK_VALID |
                      SX4_STATS_FLAG_BILLOWS_ATTACHED);
}

static void check_control_bit_masked(void) {
    ble_stats_view_t view;
    uint8_t out[SX4_STATS_SIZE];
    memset(&view, 0, sizeof(view));
    view.flags = 0xFFu; /* a caller cannot publish the reserved control bit */
    view.records_capacity = BLE_STATS_CAPACITY;
    CHECK_EQ_UINT(ble_stats_encode(&view, out, sizeof(out)), SX4_STATS_SIZE);
    CHECK_EQ_UINT(out[1], 0x7Fu);
}

static void check_blob_mtu23(void) {
    ble_stats_view_t view;
    uint8_t encoded[SX4_STATS_SIZE];
    uint8_t rebuilt[SX4_STATS_SIZE];

    memset(&view, 0, sizeof(view));
    view.records_capacity = BLE_STATS_CAPACITY;
    view.records_stored = 12u;
    view.min_seq = 1u;
    view.max_seq = 12u;
    view.generation = 9u;
    view.battery_pct = SX4_BATTERY_UNKNOWN;
    CHECK_EQ_UINT(ble_stats_encode(&view, encoded, sizeof(encoded)),
                  SX4_STATS_SIZE);

    size_t offset = 0;
    size_t responses = 0;
    while (offset < sizeof(encoded)) {
        size_t chunk = sizeof(encoded) - offset;
        if (chunk > MTU23_PAYLOAD) {
            chunk = MTU23_PAYLOAD;
        }
        memcpy(rebuilt + offset, encoded + offset, chunk);
        offset += chunk;
        responses++;
    }
    CHECK_EQ_UINT(responses, 3u);
    CHECK_EQ_UINT(offset, SX4_STATS_SIZE);
    CHECK(memcmp(rebuilt, encoded, sizeof(encoded)) == 0);
}

static void check_bad_arguments(void) {
    uint8_t out[SX4_STATS_SIZE];
    ble_stats_view_t view;
    memset(&view, 0, sizeof(view));
    CHECK_EQ_UINT(ble_stats_encode(NULL, out, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_stats_encode(&view, NULL, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_stats_encode(&view, out, sizeof(out) - 1u), 0u);
}

int main(void) {
    check_empty_log();
    check_full_ring();
    check_flags();
    check_control_bit_masked();
    check_blob_mtu23();
    check_bad_arguments();
    return sx4_test_summary("ble-stats");
}
