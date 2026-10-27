/*
 * ble_gatt_spec.c - the eight characteristic slots from design 05 section 5.1.
 *
 * Values come from the generated protocol contract (records.h) so the firmware
 * and the host test cannot drift from protocol/ble.yaml.  There is deliberately
 * no Wi-Fi, OTA or provisioning entry.
 */
#include "ble_gatt_spec.h"

const ble_gatt_spec_t ble_gatt_specs[] = {
    {
        .slot = SX4_BLE_CHAR_INFO_SLOT,
        .name = "info",
        .uuid = SX4_BLE_CHAR_INFO_UUID,
        .props = SX4_BLE_CHAR_INFO_PROPS,
        .security = SX4_BLE_CHAR_INFO_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_LIVE_SLOT,
        .name = "live",
        .uuid = SX4_BLE_CHAR_LIVE_UUID,
        .props = SX4_BLE_CHAR_LIVE_PROPS,
        .security = SX4_BLE_CHAR_LIVE_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_CONTROL_SLOT,
        .name = "control",
        .uuid = SX4_BLE_CHAR_CONTROL_UUID,
        .props = SX4_BLE_CHAR_CONTROL_PROPS,
        .security = SX4_BLE_CHAR_CONTROL_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_RESULT_SLOT,
        .name = "result",
        .uuid = SX4_BLE_CHAR_RESULT_UUID,
        .props = SX4_BLE_CHAR_RESULT_PROPS,
        .security = SX4_BLE_CHAR_RESULT_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_SYNC_CTRL_SLOT,
        .name = "sync_ctrl",
        .uuid = SX4_BLE_CHAR_SYNC_CTRL_UUID,
        .props = SX4_BLE_CHAR_SYNC_CTRL_PROPS,
        .security = SX4_BLE_CHAR_SYNC_CTRL_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_SYNC_DATA_SLOT,
        .name = "sync_data",
        .uuid = SX4_BLE_CHAR_SYNC_DATA_UUID,
        .props = SX4_BLE_CHAR_SYNC_DATA_PROPS,
        .security = SX4_BLE_CHAR_SYNC_DATA_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_CONFIG_SLOT,
        .name = "config",
        .uuid = SX4_BLE_CHAR_CONFIG_UUID,
        .props = SX4_BLE_CHAR_CONFIG_PROPS,
        .security = SX4_BLE_CHAR_CONFIG_SECURITY,
    },
    {
        .slot = SX4_BLE_CHAR_STATS_SLOT,
        .name = "stats",
        .uuid = SX4_BLE_CHAR_STATS_UUID,
        .props = SX4_BLE_CHAR_STATS_PROPS,
        .security = SX4_BLE_CHAR_STATS_SECURITY,
    },
};

const size_t ble_gatt_spec_count = sizeof(ble_gatt_specs) / sizeof(ble_gatt_specs[0]);

const ble_gatt_spec_t *ble_gatt_spec_by_slot(uint16_t slot) {
    for (size_t i = 0; i < ble_gatt_spec_count; i++) {
        if (ble_gatt_specs[i].slot == slot) {
            return &ble_gatt_specs[i];
        }
    }
    return NULL;
}

bool ble_gatt_spec_needs_cccd(const ble_gatt_spec_t *spec) {
    return spec != NULL && (spec->props & SX4_BLE_PROP_NOTIFY) != 0;
}
