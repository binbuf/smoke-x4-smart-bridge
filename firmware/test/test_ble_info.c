/*
 * test_ble_info.c - host byte-vector tests for the T27 BLE surface.
 *
 * Covers the fixed 32-byte `info` payload (all caps and billows_control = 0)
 * and the static GATT slot table: eight slots, the contract's properties and
 * security levels, a CCCD on every Notify characteristic, no Wi-Fi/OTA slot.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_gatt_spec.h"
#include "ble_info.h"
#include "records.h"
#include "test_util.h"

/*
 * info: ver 1, proto 1.0, caps 0xFD, probes 4, reserved 0,
 * device_id "A4F2", fw "0.1.0", model "heltec3", bonds_free 2, reserved 0.
 */
static const uint8_t VECTOR_INFO_ALL_CAPS[SX4_INFO_SIZE] = {
    0x01, 0x01, 0x00, 0xFD, 0x04, 0x00,
    0x41, 0x34, 0x46, 0x32,
    0x30, 0x2E, 0x31, 0x2E, 0x30, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x68, 0x65, 0x6C, 0x74, 0x65, 0x63, 0x33, 0x00,
    0x02, 0x00,
};

static void check_info_vector(void) {
    uint8_t out[SX4_INFO_SIZE];
    memset(out, 0xA5, sizeof(out));
    ble_info_view_t view = {
        .device_id = "A4F2",
        .fw = "0.1.0",
        .model = "heltec3",
        .probes = 4,
        .caps = BLE_INFO_CAPS_ALL, /* 0xFF requested; billows_control cleared */
        .bonds_free = 2,
    };

    CHECK_EQ_UINT(ble_info_encode(&view, out, sizeof(out)), SX4_INFO_SIZE);
    CHECK(memcmp(out, VECTOR_INFO_ALL_CAPS, sizeof(out)) == 0);
    CHECK_EQ_UINT(out[0], 1u);
    CHECK_EQ_UINT(out[1], SX4_PROTOCOL_MAJOR);
    CHECK_EQ_UINT(out[2], SX4_PROTOCOL_MINOR);
    CHECK_EQ_UINT(out[3], 0xFDu);
    CHECK_EQ_UINT(out[5], 0u);
    CHECK_EQ_UINT(out[30], 2u);
    CHECK_EQ_UINT(out[31], 0u);
}

static void check_info_billows_control_zero(void) {
    uint8_t out[SX4_INFO_SIZE];
    /* Every capability requested except billows_control. */
    ble_info_view_t view = {
        .device_id = "A4F2",
        .fw = "0.1.0",
        .model = "heltec3",
        .probes = 4,
        .caps = (uint8_t)(BLE_INFO_CAPS_ALL & ~SX4_CAPS_FLAG_BILLOWS_CONTROL),
        .bonds_free = 2,
    };

    CHECK_EQ_UINT(ble_info_encode(&view, out, sizeof(out)), SX4_INFO_SIZE);
    CHECK(memcmp(out, VECTOR_INFO_ALL_CAPS, sizeof(out)) == 0);

    /* Asking for control explicitly still cannot publish it. */
    view.caps = (uint8_t)SX4_CAPS_FLAG_BILLOWS_CONTROL;
    CHECK_EQ_UINT(ble_info_encode(&view, out, sizeof(out)), SX4_INFO_SIZE);
    CHECK_EQ_UINT(out[3] & SX4_CAPS_FLAG_BILLOWS_CONTROL, 0u);
    CHECK_EQ_UINT(ble_info_caps(0xFFu), 0xFDu);
}

static void check_info_field_rules(void) {
    uint8_t out[SX4_INFO_SIZE];
    ble_info_view_t view = {
        .device_id = "ABCDEF",       /* truncated to 4 */
        .fw = "0123456789ABCDEF",    /* truncated to 12, no NUL */
        .model = "123456789",        /* truncated to 8, no NUL */
        .probes = 2,
        .caps = 0,
        .bonds_free = 9,             /* clamped to 4 free */
    };

    CHECK_EQ_UINT(ble_info_encode(&view, out, sizeof(out)), SX4_INFO_SIZE);
    CHECK(memcmp(out + 6, "ABCD", 4) == 0);
    CHECK(memcmp(out + 10, "0123456789AB", 12) == 0);
    CHECK(memcmp(out + 22, "12345678", 8) == 0);
    CHECK_EQ_UINT(out[4], 2u);
    CHECK_EQ_UINT(out[30], 4u);
    CHECK_EQ_UINT(ble_info_bonds_free(0), 4u);
    CHECK_EQ_UINT(ble_info_bonds_free(3), 1u);
    CHECK_EQ_UINT(ble_info_bonds_free(4), 0u);
    CHECK_EQ_UINT(ble_info_bonds_free(200), 0u);
}

static void check_info_short_and_padded_fields(void) {
    uint8_t out[SX4_INFO_SIZE];
    ble_info_view_t view = {
        .device_id = "A1",
        .fw = "1",
        .model = "x",
        .probes = 4,
        .caps = SX4_CAPS_FLAG_HISTORY,
        .bonds_free = 4,
    };

    CHECK_EQ_UINT(ble_info_encode(&view, out, sizeof(out)), SX4_INFO_SIZE);
    CHECK_EQ_UINT(out[6], 'A');
    CHECK_EQ_UINT(out[7], '1');
    CHECK_EQ_UINT(out[8], 0u);
    CHECK_EQ_UINT(out[9], 0u);
    for (size_t i = 11; i < 22; i++) {
        CHECK_EQ_UINT(out[i], 0u);
    }
    for (size_t i = 23; i < 30; i++) {
        CHECK_EQ_UINT(out[i], 0u);
    }
    CHECK_EQ_UINT(out[30], 4u);
}

static void check_info_probe_rule(void) {
    CHECK_EQ_UINT(ble_info_probes(true, 2), 2u);
    CHECK_EQ_UINT(ble_info_probes(true, 4), 4u);
    CHECK_EQ_UINT(ble_info_probes(true, 0), 4u);  /* not learned yet */
    CHECK_EQ_UINT(ble_info_probes(true, 3), 4u);  /* invalid */
    CHECK_EQ_UINT(ble_info_probes(false, 2), 4u); /* unpaired */
}

static void check_info_arguments(void) {
    uint8_t out[SX4_INFO_SIZE];
    ble_info_view_t view = {.device_id = "A4F2", .probes = 4};
    uint8_t too_small[SX4_INFO_SIZE - 1];

    CHECK_EQ_UINT(ble_info_encode(NULL, out, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_info_encode(&view, NULL, sizeof(out)), 0u);
    CHECK_EQ_UINT(ble_info_encode(&view, too_small, sizeof(too_small)), 0u);
}

static const struct {
    uint16_t slot;
    const char *name;
    uint8_t props;
    uint8_t security;
} EXPECTED[] = {
    {0x0001, "info", SX4_BLE_PROP_READ, SX4_BLE_SEC_OPEN},
    {0x0002, "live", SX4_BLE_PROP_READ | SX4_BLE_PROP_NOTIFY,
     SX4_BLE_SEC_ENCRYPTED},
    {0x0003, "control", SX4_BLE_PROP_WRITE, SX4_BLE_SEC_AUTHENTICATED},
    {0x0004, "result", SX4_BLE_PROP_NOTIFY, SX4_BLE_SEC_ENCRYPTED},
    {0x0005, "sync_ctrl", SX4_BLE_PROP_WRITE, SX4_BLE_SEC_ENCRYPTED},
    {0x0006, "sync_data", SX4_BLE_PROP_NOTIFY, SX4_BLE_SEC_ENCRYPTED},
    {0x0007, "config", SX4_BLE_PROP_READ | SX4_BLE_PROP_WRITE,
     SX4_BLE_SEC_AUTHENTICATED},
    {0x0008, "stats", SX4_BLE_PROP_READ, SX4_BLE_SEC_ENCRYPTED},
};

static void check_gatt_spec(void) {
    CHECK_EQ_UINT(ble_gatt_spec_count, 8u);
    CHECK_EQ_UINT(sizeof(EXPECTED) / sizeof(EXPECTED[0]), 8u);

    for (size_t i = 0; i < ble_gatt_spec_count; i++) {
        const ble_gatt_spec_t *spec = &ble_gatt_specs[i];
        CHECK_EQ_UINT(spec->slot, EXPECTED[i].slot);
        CHECK_STR_EQ(spec->name, EXPECTED[i].name);
        CHECK_EQ_UINT(spec->props, EXPECTED[i].props);
        CHECK_EQ_UINT(spec->security, EXPECTED[i].security);
        CHECK(spec->uuid != NULL);
        CHECK(strncmp(spec->uuid, "7f9b00", 6) == 0);
        CHECK(ble_gatt_spec_by_slot(spec->slot) == spec);

        /* The CCCD is required exactly for Notify and inherits its security. */
        bool notify = (spec->props & SX4_BLE_PROP_NOTIFY) != 0;
        CHECK_EQ_INT(ble_gatt_spec_needs_cccd(spec), notify);
        if (notify) {
            CHECK(spec->security == SX4_BLE_SEC_ENCRYPTED ||
                  spec->security == SX4_BLE_SEC_AUTHENTICATED);
        }

        /* No network/OTA/provisioning slot may hide in the service. */
        CHECK(strstr(spec->name, "wifi") == NULL);
        CHECK(strstr(spec->name, "ota") == NULL);
        CHECK(strstr(spec->name, "dfu") == NULL);
        CHECK(strstr(spec->name, "prov") == NULL);
    }

    CHECK(ble_gatt_spec_by_slot(0x0000) == NULL);
    CHECK(ble_gatt_spec_by_slot(0x0009) == NULL);
    CHECK(ble_gatt_spec_by_slot(0x7f9b) == NULL);
    CHECK(!ble_gatt_spec_needs_cccd(NULL));
    CHECK_STR_EQ(ble_gatt_specs[0].uuid, SX4_BLE_CHAR_INFO_UUID);
    CHECK_STR_EQ(ble_gatt_specs[7].uuid, SX4_BLE_CHAR_STATS_UUID);
    CHECK_STR_EQ(SX4_BLE_SERVICE_UUID, "7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162");
}

int main(void) {
    check_info_vector();
    check_info_billows_control_zero();
    check_info_field_rules();
    check_info_short_and_padded_fields();
    check_info_probe_rule();
    check_info_arguments();
    check_gatt_spec();
    return sx4_test_summary("ble-info");
}
