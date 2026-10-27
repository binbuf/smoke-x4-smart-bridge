/*
 * test_ble_adv.c - host tests for the T30 advertising and security cores.
 *
 * Pins the scan-response blob and both AD structures byte-for-byte, then walks
 * the advertising state machine through boot, connect, disconnect, failed
 * connect and timeout. The bond limit and passkey lifetime are covered in the
 * second half. No ESP-IDF or NimBLE is linked.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_adv.h"
#include "ble_security.h"
#include "test_util.h"

static void check_status_blob(void) {
    ble_adv_status_t status = {
        .flags = 0x95,
        .pit_temp_f10 = 2250, /* 225.0 degF -> CA 08 */
        .battery_pct = 87,
        .billows_target_f10 = 2250,
        .age_s = 300, /* clamped to 255 */
    };
    static const uint8_t expected[BLE_ADV_STATUS_SIZE] = {
        0x01, 0x95, 0xCA, 0x08, 0x57, 0xCA, 0x08, 0xFF, 0x00,
    };
    uint8_t out[BLE_ADV_STATUS_SIZE];
    memset(out, 0xA5, sizeof(out));

    CHECK_EQ_UINT(ble_adv_status_encode(&status, out, sizeof(out)),
                  BLE_ADV_STATUS_SIZE);
    CHECK(memcmp(out, expected, sizeof(expected)) == 0);

    /* Unknown battery, unknown target, negative tenths and expired age. */
    status.flags = 0;
    status.pit_temp_f10 = -123; /* 0xFF85 */
    status.battery_pct = 255;
    status.billows_target_f10 = 0;
    status.age_s = 65535;
    CHECK_EQ_UINT(ble_adv_status_encode(&status, out, sizeof(out)),
                  BLE_ADV_STATUS_SIZE);
    CHECK_EQ_UINT(out[0], 1u);
    CHECK_EQ_UINT(out[1], 0u);
    CHECK_EQ_UINT(out[2], 0x85u);
    CHECK_EQ_UINT(out[3], 0xFFu);
    CHECK_EQ_UINT(out[4], 255u);
    CHECK_EQ_UINT(out[5], 0u);
    CHECK_EQ_UINT(out[6], 0u);
    CHECK_EQ_UINT(out[7], 255u);
    CHECK_EQ_UINT(out[8], 0u);

    CHECK_EQ_UINT(ble_adv_status_encode(NULL, out, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_adv_status_encode(&status, out, 8), 0u);
}

static void check_local_name(void) {
    static const uint8_t mac_a4f2[6] = {0x01, 0x02, 0x03, 0x04, 0xA4, 0xF2};
    static const uint8_t mac_0abc[6] = {0x01, 0x02, 0x03, 0x04, 0x0A, 0xBC};
    char name[BLE_ADV_NAME_MAX];

    CHECK_EQ_UINT(ble_adv_format_name(name, mac_a4f2), BLE_ADV_NAME_LEN);
    CHECK_STR_EQ(name, "SmokeX4-A4F2");
    CHECK_EQ_UINT(ble_adv_format_name(name, mac_0abc), BLE_ADV_NAME_LEN);
    CHECK_STR_EQ(name, "SmokeX4-0ABC");
    CHECK_EQ_UINT(strlen(name), BLE_ADV_NAME_LEN);
    CHECK_EQ_UINT(ble_adv_format_name(NULL, mac_a4f2), 0u);
    CHECK_EQ_UINT(ble_adv_format_name(name, NULL), 0u);
}

static void check_advertising_pdu(void) {
    static const uint8_t expected[BLE_ADV_PDU_SIZE] = {
        0x02, 0x01, 0x06, /* Flags: LE general discoverable, no BR/EDR */
        0x11, 0x07,       /* complete 128-bit UUID list, 16-byte payload */
        0x62, 0x51, 0x40, 0x3F, 0x2E, 0x1C, 0x3D, 0x9A,
        0x0F, 0x4B, 0x5B, 0x4C, 0x00, 0x00, 0x9B, 0x7F,
    };
    uint8_t out[31];
    memset(out, 0xA5, sizeof(out));

    CHECK_EQ_UINT(ble_adv_build_pdu(out, sizeof(out)), BLE_ADV_PDU_SIZE);
    CHECK(memcmp(out, expected, sizeof(expected)) == 0);
    CHECK_EQ_UINT(ble_adv_build_pdu(out, BLE_ADV_PDU_SIZE - 1), 0u);
    CHECK_EQ_UINT(ble_adv_build_pdu(NULL, sizeof(out)), 0u);
}

static void check_scan_response(void) {
    ble_adv_status_t status = {
        .flags = 0x95,
        .pit_temp_f10 = 2250,
        .battery_pct = 87,
        .billows_target_f10 = 2250,
        .age_s = 300,
    };
    static const uint8_t expected[BLE_ADV_SCAN_RSP_SIZE] = {
        /* Complete local name: len 13, type 0x09, "SmokeX4-A4F2" */
        0x0D, 0x09, 0x53, 0x6D, 0x6F, 0x6B, 0x65, 0x58, 0x34, 0x2D,
        0x41, 0x34, 0x46, 0x32,
        /* Manufacturer specific: len 12, 0xFF, company FFFF, 9-byte blob */
        0x0C, 0xFF, 0xFF, 0xFF,
        0x01, 0x95, 0xCA, 0x08, 0x57, 0xCA, 0x08, 0xFF, 0x00,
    };
    uint8_t out[31];
    memset(out, 0xA5, sizeof(out));

    CHECK_EQ_UINT(ble_adv_build_scan_rsp("SmokeX4-A4F2", &status, out,
                                         sizeof(out)),
                  BLE_ADV_SCAN_RSP_SIZE);
    CHECK(memcmp(out, expected, sizeof(expected)) == 0);
    CHECK_EQ_UINT(out[0], 13u);
    CHECK_EQ_UINT(out[1], 0x09u);
    CHECK_EQ_UINT(out[15], 0xFFu);
    CHECK_EQ_UINT(out[14], 12u);
    CHECK_EQ_UINT(out[16], 0xFFu);
    CHECK_EQ_UINT(out[17], 0xFFu);
    CHECK_EQ_UINT(out[BLE_ADV_SCAN_RSP_SIZE - 1], 0u); /* reserved */

    /* A name is optional; the manufacturer block still encodes alone. */
    CHECK_EQ_UINT(ble_adv_build_scan_rsp(NULL, &status, out, sizeof(out)),
                  13u);
    CHECK_EQ_UINT(out[0], 12u);
    CHECK_EQ_UINT(out[1], 0xFFu);

    CHECK_EQ_UINT(ble_adv_build_scan_rsp("SmokeX4-A4F2", &status, out,
                                         BLE_ADV_SCAN_RSP_SIZE - 1),
                  0u);
    CHECK_EQ_UINT(ble_adv_build_scan_rsp(NULL, NULL, out, sizeof(out)), 0u);
}

static void check_interval_units(void) {
    CHECK_EQ_UINT(ble_adv_interval_units(BLE_ADV_FAST_INTERVAL_MS), 400u);
    CHECK_EQ_UINT(ble_adv_interval_units(BLE_ADV_SLOW_INTERVAL_MS), 1600u);
    CHECK_EQ_UINT(ble_adv_interval_units(20), 32u);
    CHECK_EQ_UINT(ble_adv_interval_units(60000), 0xFFFFu); /* clamped */
    CHECK_EQ_UINT(ble_adv_interval_units(0), 0u);
}

static void check_advertising_state(void) {
    ble_adv_state_t state;
    ble_adv_state_init(&state);
    CHECK(state.phase == BLE_ADV_PHASE_OFF);

    /* Boot starts a 250 ms fast window. */
    ble_adv_action_t action =
        ble_adv_state_event(&state, BLE_ADV_EVENT_BOOT, 1000);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_FAST_INTERVAL_MS);
    CHECK(state.phase == BLE_ADV_PHASE_FAST);

    /* Still fast one millisecond before the 60 s deadline. */
    action = ble_adv_state_tick(&state, 1000 + BLE_ADV_FAST_WINDOW_MS - 1);
    CHECK(!action.advertise);
    CHECK(state.phase == BLE_ADV_PHASE_FAST);

    /* At the deadline the interval changes and the caller restarts. */
    action = ble_adv_state_tick(&state, 1000 + BLE_ADV_FAST_WINDOW_MS);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_SLOW_INTERVAL_MS);
    CHECK(state.phase == BLE_ADV_PHASE_SLOW);

    /* Slow advertising is stable. */
    action = ble_adv_state_tick(&state, 1000000);
    CHECK(!action.advertise);

    /* A connection stops advertising, even if a timer fires late. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_CONNECTED, 1000);
    CHECK(!action.advertise);
    CHECK(state.phase == BLE_ADV_PHASE_OFF);
    action = ble_adv_state_tick(&state, 999999);
    CHECK(!action.advertise);

    /* Disconnect restarts the fast window. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_DISCONNECT, 2000);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_FAST_INTERVAL_MS);
    CHECK_EQ_UINT(state.fast_until_ms, 2000 + BLE_ADV_FAST_WINDOW_MS);

    /* A failed connect behaves like a disconnect. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_CONNECT_FAILED, 3000);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_FAST_INTERVAL_MS);
    CHECK_EQ_UINT(state.fast_until_ms, 3000 + BLE_ADV_FAST_WINDOW_MS);

    /* An advertising timeout inside the window restarts fast, no extension. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_TIMEOUT, 4000);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_FAST_INTERVAL_MS);
    CHECK_EQ_UINT(state.fast_until_ms, 3000 + BLE_ADV_FAST_WINDOW_MS);

    /* After the window, a timeout restarts slow. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_TIMEOUT,
                                 3000 + BLE_ADV_FAST_WINDOW_MS);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_SLOW_INTERVAL_MS);
    CHECK(state.phase == BLE_ADV_PHASE_SLOW);

    /* Timeout while already slow stays slow. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_TIMEOUT, 900000);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_SLOW_INTERVAL_MS);

    /* Explicit stop is silent. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_STOP, 900001);
    CHECK(!action.advertise);
    CHECK(state.phase == BLE_ADV_PHASE_OFF);
    CHECK_EQ_UINT(state.fast_until_ms, 0u);

    /* A button/boot restart after stop opens a fresh window. */
    action = ble_adv_state_event(&state, BLE_ADV_EVENT_BOOT, 900002);
    CHECK(action.advertise);
    CHECK_EQ_UINT(action.interval_ms, BLE_ADV_FAST_INTERVAL_MS);
    CHECK_EQ_UINT(state.fast_until_ms,
                  900002 + BLE_ADV_FAST_WINDOW_MS);
}

static void check_bond_limit(void) {
    for (uint8_t used = 0; used < BLE_SEC_MAX_BONDS; used++) {
        CHECK(ble_security_can_bond(used));
        CHECK_EQ_UINT(ble_security_bonds_free(used),
                      BLE_SEC_MAX_BONDS - used);
    }
    /* A fifth phone is refused; nothing is evicted. */
    CHECK(!ble_security_can_bond(4));
    CHECK(!ble_security_can_bond(5));
    CHECK(!ble_security_can_bond(200));
    CHECK_EQ_UINT(ble_security_bonds_free(4), 0u);
    CHECK_EQ_UINT(ble_security_bonds_free(200), 0u);
}

static void check_passkey_format(void) {
    char digits[BLE_SEC_PASSKEY_SIZE];

    CHECK_EQ_UINT(ble_security_format_passkey(0, digits),
                  BLE_SEC_PASSKEY_DIGITS);
    CHECK_STR_EQ(digits, "000000");
    CHECK_EQ_UINT(ble_security_format_passkey(123456, digits),
                  BLE_SEC_PASSKEY_DIGITS);
    CHECK_STR_EQ(digits, "123456");
    CHECK_EQ_UINT(ble_security_format_passkey(7, digits),
                  BLE_SEC_PASSKEY_DIGITS);
    CHECK_STR_EQ(digits, "000007");
    CHECK_EQ_UINT(ble_security_format_passkey(999999, digits),
                  BLE_SEC_PASSKEY_DIGITS);
    CHECK_STR_EQ(digits, "999999");
    CHECK_EQ_UINT(ble_security_format_passkey(1000000, digits),
                  BLE_SEC_PASSKEY_DIGITS);
    CHECK_STR_EQ(digits, "000000");
    CHECK_EQ_UINT(ble_security_format_passkey(0xFFFFFFFFu, digits),
                  BLE_SEC_PASSKEY_DIGITS);
    CHECK_STR_EQ(digits, "967295");
    CHECK_EQ_UINT(ble_security_format_passkey(1, NULL), 0u);
}

static void check_passkey_lifetime(void) {
    ble_security_passkey_t passkey;
    ble_security_passkey_init(&passkey);
    CHECK(!ble_security_passkey_active(&passkey));
    CHECK_STR_EQ(ble_security_passkey_digits(&passkey), "");

    CHECK(ble_security_passkey_start(&passkey, 418302, 5000));
    CHECK(ble_security_passkey_active(&passkey));
    CHECK_STR_EQ(ble_security_passkey_digits(&passkey), "418302");

    /* One millisecond before 60 s. */
    CHECK(!ble_security_passkey_tick(
        &passkey, 5000 + BLE_SEC_PASSKEY_TIMEOUT_MS - 1));
    CHECK(ble_security_passkey_active(&passkey));

    /* At 60 s it expires exactly once. */
    CHECK(ble_security_passkey_tick(&passkey,
                                    5000 + BLE_SEC_PASSKEY_TIMEOUT_MS));
    CHECK(!ble_security_passkey_active(&passkey));
    CHECK_STR_EQ(ble_security_passkey_digits(&passkey), "");
    CHECK(!ble_security_passkey_tick(
        &passkey, 5000 + BLE_SEC_PASSKEY_TIMEOUT_MS + 1));

    /* Bonding ended early clears the code. */
    CHECK(ble_security_passkey_start(&passkey, 1, 100));
    CHECK_STR_EQ(ble_security_passkey_digits(&passkey), "000001");
    ble_security_passkey_cancel(&passkey);
    CHECK(!ble_security_passkey_active(&passkey));
    CHECK_STR_EQ(ble_security_passkey_digits(&passkey), "");

    /* A second attempt gets a fresh code and a fresh deadline. */
    CHECK(ble_security_passkey_start(&passkey, 1, 100));
    CHECK(ble_security_passkey_start(&passkey, 2, 200));
    CHECK_STR_EQ(ble_security_passkey_digits(&passkey), "000002");
    CHECK(!ble_security_passkey_tick(&passkey, 60098));
    CHECK(ble_security_passkey_tick(&passkey, 200 + BLE_SEC_PASSKEY_TIMEOUT_MS));

    /* The 32-bit millisecond clock wrap is handled without expiry. */
    CHECK(ble_security_passkey_start(&passkey, 42, 0xFFFFF000u));
    CHECK(!ble_security_passkey_tick(&passkey, 0x00001000u));
    CHECK(ble_security_passkey_active(&passkey));

    CHECK(!ble_security_passkey_start(NULL, 1, 1));
    ble_security_passkey_init(NULL);
    ble_security_passkey_cancel(NULL);
    CHECK(!ble_security_passkey_active(NULL));
    CHECK_STR_EQ(ble_security_passkey_digits(NULL), "");
}

int main(void) {
    check_status_blob();
    check_local_name();
    check_advertising_pdu();
    check_scan_response();
    check_interval_units();
    check_advertising_state();
    check_bond_limit();
    check_passkey_format();
    check_passkey_lifetime();
    return sx4_test_summary("ble-adv");
}
