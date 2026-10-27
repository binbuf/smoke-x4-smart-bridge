/*
 * test_ble_live.c - host tests for the T28 live encoder and notification ring.
 *
 * Covers the design 05 section 5.4 example byte for byte, the four-attached /
 * one-detached / all-detached / clock-invalid / Billows-attached states, the
 * 0xFFFFFFFF "no stored sample" sentinel and the billows_output reservation,
 * plus the bounded ble_tx ring (one frame per stored sample and per flag
 * transition, no duplicate for an unchanged snapshot).
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_live.h"
#include "ble_tx.h"
#include "bridge_state.h"
#include "records.h"
#include "test_util.h"

/* 05 section 5.4 reference vector. */
static const uint8_t VECTOR_054[SX4_LIVE_SIZE] = {
    0x01, 0x17, 0xCA, 0x08, 0x74, 0x06, 0x00, 0x80, 0x20, 0x03,
    0xD2, 0x04, 0x00, 0x00, 0xCA, 0x08, 0x57, 0xB9, 0x0C, 0x00,
};

static bridge_state_live_t base_snapshot(void) {
    bridge_state_live_t s;
    memset(&s, 0, sizeof(s));
    s.seq = 1234;
    s.have_seq = true;
    s.flags = SX4_LIVE_FLAG_SMOKE_PAIRED | SX4_LIVE_FLAG_SMOKE_LIVE |
              SX4_LIVE_FLAG_BILLOWS_ATTACHED | SX4_LIVE_FLAG_CLOCK_VALID;
    s.temp_f10[0] = 2250;
    s.temp_f10[1] = 1652;
    s.temp_f10[2] = SX4_TEMP_DETACHED;
    s.temp_f10[3] = 800;
    s.attached_mask = 0x0B; /* P1, P2, P4 */
    s.billows_target_f10 = 2250;
    s.billows_target_valid = true;
    s.battery_pct = 87;
    s.rssi_lora = -71;
    s.age_s = 12;
    return s;
}

static uint32_t read_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void check_reference_vector(void) {
    bridge_state_live_t s = base_snapshot();
    uint8_t out[SX4_LIVE_SIZE];

    memset(out, 0xA5, sizeof(out));
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK(memcmp(out, VECTOR_054, sizeof(out)) == 0);
    CHECK_EQ_UINT(out[0], 1u);
    CHECK_EQ_UINT(out[1], 0x17u);
    CHECK_EQ_UINT(read_u32(out + 10), 1234u);
    CHECK_EQ_INT((int16_t)((uint16_t)out[2] | ((uint16_t)out[3] << 8)), 2250);
    /* P3 is detached even though the snapshot carried a value. */
    CHECK_EQ_INT((int16_t)((uint16_t)out[6] | ((uint16_t)out[7] << 8)),
                 SX4_TEMP_DETACHED);
}

static void check_four_attached(void) {
    bridge_state_live_t s;
    memset(&s, 0, sizeof(s));
    s.seq = 7;
    s.have_seq = true;
    s.flags = SX4_LIVE_FLAG_SMOKE_PAIRED | SX4_LIVE_FLAG_SMOKE_LIVE |
              SX4_LIVE_FLAG_CLOCK_VALID;
    s.temp_f10[0] = 1000;
    s.temp_f10[1] = 1010;
    s.temp_f10[2] = 1020;
    s.temp_f10[3] = 1030;
    s.attached_mask = 0x0F;
    s.battery_pct = 64;
    s.rssi_lora = -60;
    s.age_s = 1;

    static const uint8_t expected[SX4_LIVE_SIZE] = {
        0x01, 0x13, 0xE8, 0x03, 0xF2, 0x03, 0xFC, 0x03, 0x06, 0x04,
        0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0xC4, 0x01, 0x00,
    };
    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK(memcmp(out, expected, sizeof(out)) == 0);
}

static void check_one_detached(void) {
    bridge_state_live_t s;
    memset(&s, 0, sizeof(s));
    s.seq = 1;
    s.have_seq = true;
    s.flags = SX4_LIVE_FLAG_CLOCK_VALID;
    s.temp_f10[0] = 100;
    s.temp_f10[1] = 200;
    s.temp_f10[2] = 300;
    s.temp_f10[3] = 400; /* ignored: P4 is not attached */
    s.attached_mask = 0x07;
    s.battery_pct = SX4_BATTERY_UNKNOWN;
    s.rssi_lora = 0;
    s.age_s = 0;

    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_INT((int16_t)((uint16_t)out[8] | ((uint16_t)out[9] << 8)),
                 SX4_TEMP_DETACHED);
    CHECK_EQ_UINT(out[16], SX4_BATTERY_UNKNOWN);
    CHECK_EQ_INT((int16_t)((uint16_t)out[2] | ((uint16_t)out[3] << 8)), 100);
    CHECK_EQ_INT((int16_t)((uint16_t)out[4] | ((uint16_t)out[5] << 8)), 200);
    CHECK_EQ_INT((int16_t)((uint16_t)out[6] | ((uint16_t)out[7] << 8)), 300);
}

static void check_all_detached(void) {
    bridge_state_live_t s;
    memset(&s, 0, sizeof(s));
    s.have_seq = false;
    s.flags = SX4_LIVE_FLAG_SMOKE_PAIRED;
    for (unsigned int i = 0; i < 4; i++) {
        s.temp_f10[i] = 451;
    }
    s.attached_mask = 0x00;
    s.battery_pct = SX4_BATTERY_UNKNOWN;
    s.rssi_lora = -120;
    s.age_s = 65535;

    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    for (unsigned int i = 0; i < 4; i++) {
        CHECK_EQ_INT((int16_t)((uint16_t)out[2 + i * 2] |
                               ((uint16_t)out[3 + i * 2] << 8)),
                     SX4_TEMP_DETACHED);
    }
    CHECK_EQ_UINT(read_u32(out + 10), SX4_SEQ_NONE);
    CHECK_EQ_UINT(out[19], 0xFFu); /* age = 65535 upper byte */
    CHECK_EQ_UINT(out[18], 0xFFu);
}

static void check_clock_invalid(void) {
    bridge_state_live_t s = base_snapshot();
    s.flags = (uint8_t)(s.flags & ~SX4_LIVE_FLAG_CLOCK_VALID);

    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_UINT(out[1] & SX4_LIVE_FLAG_CLOCK_VALID, 0u);
    CHECK_EQ_UINT(out[1] & SX4_LIVE_FLAG_SMOKE_PAIRED,
                  SX4_LIVE_FLAG_SMOKE_PAIRED);

    s.flags |= SX4_LIVE_FLAG_CLOCK_VALID;
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_UINT(out[1] & SX4_LIVE_FLAG_CLOCK_VALID,
                  SX4_LIVE_FLAG_CLOCK_VALID);
}

static void check_billows_attached(void) {
    bridge_state_live_t s = base_snapshot();
    s.billows_target_valid = false; /* unknown target must encode 0 */

    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_UINT(out[1] & SX4_LIVE_FLAG_BILLOWS_ATTACHED,
                  SX4_LIVE_FLAG_BILLOWS_ATTACHED);
    CHECK_EQ_UINT((uint16_t)out[14] | ((uint16_t)out[15] << 8), 0u);

    s.billows_target_valid = true;
    s.billows_target_f10 = 2250;
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_INT((int16_t)((uint16_t)out[14] | ((uint16_t)out[15] << 8)), 2250);
}

static void check_seq_none_and_reserved_bit(void) {
    bridge_state_live_t s;
    memset(&s, 0, sizeof(s));
    s.have_seq = true;
    s.seq = 0; /* sequence 0 is a real first record */
    s.attached_mask = 0x0F;
    s.battery_pct = SX4_BATTERY_UNKNOWN;
    s.flags = SX4_LIVE_FLAG_BILLOWS_OUTPUT;

    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_UINT(read_u32(out + 10), 0u);
    /* bit 3 is reserved and never leaves the bridge. */
    CHECK_EQ_UINT(out[1] & SX4_LIVE_FLAG_BILLOWS_OUTPUT, 0u);
    CHECK_EQ_UINT(out[0], 1u);

    s.have_seq = false;
    CHECK_EQ_UINT(ble_live_encode(&s, out, sizeof(out)), SX4_LIVE_SIZE);
    CHECK_EQ_UINT(read_u32(out + 10), SX4_SEQ_NONE);
}

static void check_encoder_arguments(void) {
    bridge_state_live_t s = base_snapshot();
    uint8_t out[SX4_LIVE_SIZE];
    CHECK_EQ_UINT(ble_live_encode(NULL, out, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_live_encode(&s, NULL, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_live_encode(&s, out, SX4_LIVE_SIZE - 1u), 0u);
}

static void check_notify_one_per_sample(void) {
    ble_tx_core_t tx;
    ble_tx_core_init(&tx);
    bridge_state_live_t s = base_snapshot();

    /* Eight stored samples, no flag change: eight frames in order. */
    for (uint32_t i = 0; i < 8u; i++) {
        s.seq = 100u + i;
        CHECK(ble_tx_core_queue_live(&tx, &s));
    }
    CHECK_EQ_UINT(tx.queued, 8u);
    CHECK_EQ_UINT(tx.dropped, 0u);

    for (uint32_t i = 0; i < 8u; i++) {
        ble_tx_frame_t frame;
        CHECK(ble_tx_core_take(&tx, &frame));
        CHECK_EQ_UINT(frame.len, SX4_LIVE_SIZE);
        CHECK_EQ_UINT(read_u32(frame.payload + 10), 100u + i);
        /* The read fallback and the notification use the same encoder. */
        bridge_state_live_t expect = s;
        expect.seq = 100u + i;
        uint8_t read_out[SX4_LIVE_SIZE];
        CHECK_EQ_UINT(ble_live_encode(&expect, read_out, sizeof(read_out)),
                      SX4_LIVE_SIZE);
        CHECK(memcmp(frame.payload, read_out, SX4_LIVE_SIZE) == 0);
    }
    CHECK(!ble_tx_core_take(&tx, &(ble_tx_frame_t){0}));
}

static void check_notify_on_flag_change(void) {
    ble_tx_core_t tx;
    ble_tx_core_init(&tx);
    bridge_state_live_t s = base_snapshot();
    s.seq = 5;
    ble_tx_frame_t frame;
    uint32_t frames = 0;

    CHECK(ble_tx_core_queue_live(&tx, &s));
    /* Identical snapshot: no duplicate notification. */
    CHECK(!ble_tx_core_queue_live(&tx, &s));
    CHECK(ble_tx_core_take(&tx, &frame));
    frames++;

    static const uint8_t bits[] = {
        SX4_LIVE_FLAG_SMOKE_PAIRED, SX4_LIVE_FLAG_SMOKE_LIVE,
        SX4_LIVE_FLAG_BILLOWS_ATTACHED, SX4_LIVE_FLAG_CLOCK_VALID,
        SX4_LIVE_FLAG_STORAGE_OK, SX4_LIVE_FLAG_DISPLAY_ON,
        SX4_LIVE_FLAG_SYNC_ACTIVE,
    };
    for (size_t i = 0; i < sizeof(bits); i++) {
        s.flags = (uint8_t)(s.flags ^ bits[i]);
        CHECK(ble_tx_core_queue_live(&tx, &s));
        CHECK(ble_tx_core_take(&tx, &frame));
        CHECK_EQ_UINT(frame.payload[1], s.flags);
        frames++;

        s.flags = (uint8_t)(s.flags ^ bits[i]);
        CHECK(ble_tx_core_queue_live(&tx, &s));
        CHECK(ble_tx_core_take(&tx, &frame));
        CHECK_EQ_UINT(frame.payload[1], s.flags);
        frames++;
    }

    /* The reserved output bit is masked on the wire, so it is not a change. */
    s.flags = (uint8_t)(s.flags | SX4_LIVE_FLAG_BILLOWS_OUTPUT);
    CHECK(!ble_tx_core_queue_live(&tx, &s));

    CHECK_EQ_UINT(frames, 15u);
}

static void check_notify_queue_bounded_and_clear(void) {
    ble_tx_core_t tx;
    ble_tx_core_init(&tx);
    bridge_state_live_t s = base_snapshot();

    for (uint32_t i = 0; i < BLE_TX_QUEUE_DEPTH; i++) {
        s.seq = i;
        CHECK(ble_tx_core_queue_live(&tx, &s));
    }
    s.seq = 999;
    CHECK(!ble_tx_core_queue_live(&tx, &s));
    CHECK_EQ_UINT(tx.dropped, 1u);
    CHECK_EQ_UINT(tx.queued, BLE_TX_QUEUE_DEPTH);

    ble_tx_core_clear(&tx);
    CHECK_EQ_UINT(tx.count, 0u);
    CHECK(!ble_tx_core_take(&tx, &(ble_tx_frame_t){0}));
    /* Clear forgets dedupe state so a re-subscribe gets the current frame. */
    s.seq = 42;
    CHECK(ble_tx_core_queue_live(&tx, &s));

    CHECK(!ble_tx_core_queue_live(NULL, &s));
    CHECK(!ble_tx_core_queue_live(&tx, NULL));
    CHECK(!ble_tx_core_take(NULL, &(ble_tx_frame_t){0}));
    CHECK(!ble_tx_core_take(&tx, NULL));
}

int main(void) {
    check_reference_vector();
    check_four_attached();
    check_one_detached();
    check_all_detached();
    check_clock_invalid();
    check_billows_attached();
    check_seq_none_and_reserved_bit();
    check_encoder_arguments();
    check_notify_one_per_sample();
    check_notify_on_flag_change();
    check_notify_queue_bounded_and_clear();
    return sx4_test_summary("ble-live");
}
