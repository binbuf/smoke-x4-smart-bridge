/*
 * test_ble_config.c - host vectors for the T47 `config` characteristic.
 *
 * Covers the 80-byte round trip at the min/max device name, every accepted
 * timeout, both units, the reserved target/reserved bytes being ignored, every
 * invalid case, the reserved control-mode refusal, and Read Blob reassembly at
 * the default ATT MTU 23.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_config.h"
#include "records.h"
#include "test_util.h"

#define MTU23_PAYLOAD 20u

static void build_write(uint8_t out[SX4_CONFIG_SIZE], uint8_t units,
                        uint16_t timeout, const char *name) {
    memset(out, 0xA5, SX4_CONFIG_SIZE); /* reserved bytes are ignored */
    out[0] = 1;
    out[1] = units;
    out[2] = (uint8_t)(timeout & 0xFFu);
    out[3] = (uint8_t)(timeout >> 8);
    memset(out + 4, 0, 16);
    size_t len = strlen(name);
    memcpy(out + 4, name, len);
    /* target + billows mode are real validated fields; only 23..79 and the
     * former probe-name/role area (none left) are reserved. */
    memset(out + 20, 0, 3);
}

static void check_names_and_timeouts(void) {
    const uint16_t timeouts[] = {0u, 30u, 60u, 120u};
    const char *names[] = {"A", "ABCDEFGHIJKLMNO"};

    for (size_t n = 0; n < sizeof(names) / sizeof(names[0]); n++) {
        for (size_t t = 0; t < sizeof(timeouts) / sizeof(timeouts[0]); t++) {
            for (uint8_t units = 0; units <= 1u; units++) {
                uint8_t wire[SX4_CONFIG_SIZE];
                uint8_t out[SX4_CONFIG_SIZE];
                ble_config_view_t view;

                build_write(wire, units, timeouts[t], names[n]);
                memset(&view, 0, sizeof(view));
                CHECK_EQ_INT(ble_config_parse(wire, sizeof(wire), &view),
                             BLE_CONFIG_OK);
                CHECK_EQ_UINT(view.units, units);
                CHECK_EQ_UINT(view.display_timeout_s, timeouts[t]);
                CHECK_STR_EQ(view.device_name, names[n]);

                CHECK_EQ_UINT(ble_config_encode(&view, out, sizeof(out)),
                              SX4_CONFIG_SIZE);
                CHECK_EQ_UINT(out[0], 1u);
                CHECK_EQ_UINT(out[1], units);
                CHECK_EQ_UINT(out[2] | ((uint16_t)out[3] << 8), timeouts[t]);
                CHECK(memcmp(out + 4, names[n], strlen(names[n])) == 0);
                CHECK_EQ_UINT(out[4 + strlen(names[n])], 0u);
                /* Reserved target/mode and all 57 reserved bytes stay zero. */
                CHECK_EQ_UINT(out[20], 0u);
                CHECK_EQ_UINT(out[21], 0u);
                CHECK_EQ_UINT(out[22], 0u);
                for (size_t i = 23; i < SX4_CONFIG_SIZE; i++) {
                    CHECK_EQ_UINT(out[i], 0u);
                }
            }
        }
    }
}

static void check_reserved_ignored(void) {
    uint8_t wire[SX4_CONFIG_SIZE];
    ble_config_view_t view;

    build_write(wire, 1, 60, "Bridge");
    /* A reserved target and probe-name/role bytes must not affect the write. */
    wire[20] = 0xFF;
    wire[21] = 0x7F;
    wire[23] = 0xAA;
    wire[79] = 0x55;

    CHECK_EQ_INT(ble_config_parse(wire, sizeof(wire), &view), BLE_CONFIG_OK);
    CHECK_STR_EQ(view.device_name, "Bridge");
    CHECK_EQ_UINT(view.display_timeout_s, 60u);
}

static void expect_invalid(const uint8_t *wire, size_t len) {
    ble_config_view_t view;
    memset(&view, 0xCC, sizeof(view));
    CHECK_EQ_INT(ble_config_parse(wire, len, &view), BLE_CONFIG_INVALID);
}

static void check_invalid_cases(void) {
    uint8_t wire[SX4_CONFIG_SIZE];

    /* Wrong length: a partial write never merges into the stored struct. */
    build_write(wire, 1, 60, "Bridge");
    expect_invalid(wire, SX4_CONFIG_SIZE - 1u);
    expect_invalid(wire, SX4_CONFIG_SIZE + 1u);

    /* Wrong version. */
    build_write(wire, 1, 60, "Bridge");
    wire[0] = 2;
    expect_invalid(wire, sizeof(wire));

    /* Units outside 0/1. */
    build_write(wire, 2, 60, "Bridge");
    expect_invalid(wire, sizeof(wire));

    /* Timeout outside 0/30/60/120. */
    build_write(wire, 1, 45, "Bridge");
    expect_invalid(wire, sizeof(wire));
    build_write(wire, 1, 121, "Bridge");
    expect_invalid(wire, sizeof(wire));

    /* Empty and unterminated names. */
    build_write(wire, 1, 60, "");
    expect_invalid(wire, sizeof(wire));
    build_write(wire, 1, 60, "ABCDEFGHIJKLMNO");
    wire[19] = 'P'; /* 16 non-NUL bytes: no terminator within the field */
    expect_invalid(wire, sizeof(wire));

    /* Bad UTF-8: a stray continuation byte and a truncated 2-byte sequence. */
    build_write(wire, 1, 60, "A");
    wire[5] = 0x80;
    expect_invalid(wire, sizeof(wire));
    build_write(wire, 1, 60, "A");
    wire[5] = 0xC3;
    wire[6] = 0x28;
    expect_invalid(wire, sizeof(wire));
    /* Overlong encoding (C0 AF) is not valid UTF-8. */
    build_write(wire, 1, 60, "A");
    wire[5] = 0xC0;
    wire[6] = 0xAF;
    expect_invalid(wire, sizeof(wire));

    /* Control bytes are not part of a device name. */
    build_write(wire, 1, 60, "A");
    wire[5] = 0x07;
    expect_invalid(wire, sizeof(wire));
}

static void check_control_mode_refused(void) {
    uint8_t wire[SX4_CONFIG_SIZE];
    ble_config_view_t view;

    build_write(wire, 1, 60, "Bridge");
    memset(&view, 0xCC, sizeof(view));
    wire[22] = 1; /* billows_mode = control */
    CHECK_EQ_INT(ble_config_parse(wire, sizeof(wire), &view),
                 BLE_CONFIG_UNSUPPORTED);
    /* The refusal changes nothing: out was not touched. */
    CHECK_EQ_UINT(((const uint8_t *)&view)[0], 0xCCu);

    wire[22] = 0xFF;
    CHECK_EQ_INT(ble_config_parse(wire, sizeof(wire), &view),
                 BLE_CONFIG_UNSUPPORTED);
}

static void check_blob_mtu23(void) {
    uint8_t wire[SX4_CONFIG_SIZE];
    uint8_t encoded[SX4_CONFIG_SIZE];
    uint8_t rebuilt[SX4_CONFIG_SIZE];
    ble_config_view_t view;

    build_write(wire, 0, 120, "Smoke X4 Bridge");
    CHECK_EQ_INT(ble_config_parse(wire, sizeof(wire), &view), BLE_CONFIG_OK);
    CHECK_EQ_UINT(ble_config_encode(&view, encoded, sizeof(encoded)),
                  SX4_CONFIG_SIZE);

    /* A Read Blob at MTU 23 returns MTU-1 bytes per response. */
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
    CHECK_EQ_UINT(responses, 4u);
    CHECK_EQ_UINT(offset, SX4_CONFIG_SIZE);
    CHECK(memcmp(rebuilt, encoded, sizeof(encoded)) == 0);
    CHECK_EQ_INT(ble_config_parse(rebuilt, sizeof(rebuilt), &view),
                 BLE_CONFIG_OK);
    CHECK_STR_EQ(view.device_name, "Smoke X4 Bridge");
}

static void check_encode_rejects_bad_view(void) {
    uint8_t out[SX4_CONFIG_SIZE];
    ble_config_view_t view = {
        .units = 1,
        .display_timeout_s = 60,
        .device_name = "Bridge",
    };

    CHECK_EQ_UINT(ble_config_encode(&view, out, sizeof(out) - 1u), 0u);
    view.units = 5;
    CHECK_EQ_UINT(ble_config_encode(&view, out, sizeof(out)), 0u);
    view.units = 1;
    view.display_timeout_s = 61;
    CHECK_EQ_UINT(ble_config_encode(&view, out, sizeof(out)), 0u);
    view.display_timeout_s = 60;
    memset(view.device_name, 'A', sizeof(view.device_name)); /* no NUL */
    CHECK_EQ_UINT(ble_config_encode(&view, out, sizeof(out)), 0u);
}

int main(void) {
    check_names_and_timeouts();
    check_reserved_ignored();
    check_invalid_cases();
    check_control_mode_refused();
    check_blob_mtu23();
    check_encode_rejects_bad_view();
    return sx4_test_summary("ble-config");
}
