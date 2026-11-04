/*
 * test_ble_alarm.c - host vectors for the 20-byte alarm payload and its queue.
 *
 * Covers the active/armed/acked masks, canonical Fahrenheit thresholds, the
 * detached-probe zeroing rule and the ble_tx alarm dedupe.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_alarm.h"
#include "ble_tx.h"
#include "bridge_state.h"
#include "records.h"
#include "test_util.h"

static bridge_state_live_t alarm_snapshot(void) {
    bridge_state_live_t s;
    memset(&s, 0, sizeof(s));
    s.attached_mask = 0x0F;
    s.alarm_active_mask = 0x03;
    s.alarm_armed_mask = 0x0F;
    s.alarm_acked_mask = 0x01;
    s.alarm_high_f10[0] = 1050;
    s.alarm_high_f10[1] = 650;
    s.alarm_high_f10[2] = 1600;
    s.alarm_high_f10[3] = 2250;
    s.alarm_low_f10[0] = 320;
    s.alarm_low_f10[1] = 320;
    s.alarm_low_f10[2] = 320;
    s.alarm_low_f10[3] = 320;
    return s;
}

static void check_vector(void) {
    bridge_state_live_t s = alarm_snapshot();
    static const uint8_t expected[SX4_ALARM_SIZE] = {
        0x01, 0x03, 0x0F, 0x01,
        0x1A, 0x04, 0x8A, 0x02, 0x40, 0x06, 0xCA, 0x08,
        0x40, 0x01, 0x40, 0x01, 0x40, 0x01, 0x40, 0x01,
    };
    uint8_t out[SX4_ALARM_SIZE];

    CHECK_EQ_UINT(ble_alarm_encode(&s, out, sizeof(out)), SX4_ALARM_SIZE);
    CHECK(memcmp(out, expected, sizeof(out)) == 0);
}

static void check_detached_thresholds_zero(void) {
    bridge_state_live_t s = alarm_snapshot();
    s.attached_mask = 0x07; /* P4 detached */
    s.alarm_active_mask = 0x01;
    s.alarm_acked_mask = 0x01;
    uint8_t out[SX4_ALARM_SIZE];

    CHECK_EQ_UINT(ble_alarm_encode(&s, out, sizeof(out)), SX4_ALARM_SIZE);
    CHECK_EQ_UINT(out[3], 0x01u); /* acked only for the active probe */
    CHECK_EQ_INT((int16_t)((uint16_t)out[18] | ((uint16_t)out[19] << 8)), 0);
    CHECK_EQ_INT((int16_t)((uint16_t)out[10] | ((uint16_t)out[11] << 8)), 0);
}

static void check_ack_masks_active_only(void) {
    bridge_state_live_t s = alarm_snapshot();
    s.alarm_active_mask = 0x01;
    s.alarm_acked_mask = 0x0F; /* bogus bits from a caller must be masked */
    uint8_t out[SX4_ALARM_SIZE];

    CHECK_EQ_UINT(ble_alarm_encode(&s, out, sizeof(out)), SX4_ALARM_SIZE);
    CHECK_EQ_UINT(out[1], 0x01u);
    CHECK_EQ_UINT(out[3], 0x01u);
}

static void check_arguments(void) {
    bridge_state_live_t s = alarm_snapshot();
    uint8_t out[SX4_ALARM_SIZE];

    CHECK_EQ_UINT(ble_alarm_encode(NULL, out, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_alarm_encode(&s, NULL, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_alarm_encode(&s, out, SX4_ALARM_SIZE - 1u), 0u);
}

static void check_queue_dedupe(void) {
    ble_tx_core_t tx;
    ble_tx_core_init(&tx);
    bridge_state_live_t s = alarm_snapshot();

    CHECK(ble_tx_core_queue_alarm(&tx, &s));
    CHECK(!ble_tx_core_queue_alarm(&tx, &s)); /* identical: no duplicate */

    ble_tx_frame_t frame;
    CHECK(ble_tx_core_take(&tx, &frame));
    CHECK_EQ_UINT(frame.type, BLE_TX_FRAME_ALARM);
    CHECK_EQ_UINT(frame.len, SX4_ALARM_SIZE);

    s.alarm_active_mask = 0x07;
    CHECK(ble_tx_core_queue_alarm(&tx, &s));
    CHECK(ble_tx_core_take(&tx, &frame));
    CHECK_EQ_UINT(frame.payload[1], 0x07u);

    CHECK(!ble_tx_core_queue_alarm(NULL, &s));
    CHECK(!ble_tx_core_queue_alarm(&tx, NULL));
}

int main(void) {
    check_vector();
    check_detached_thresholds_zero();
    check_ack_masks_active_only();
    check_arguments();
    check_queue_dedupe();
    return sx4_test_summary("ble-alarm");
}
