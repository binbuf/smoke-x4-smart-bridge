/*
 * ble_adv.c - pure advertising/scan-response builders and interval state
 * machine (T30). No ESP-IDF, NimBLE or heap dependency.
 */
#include "ble_adv.h"

#include <stdio.h>
#include <string.h>

/* AD type values from the Bluetooth Assigned Numbers. */
#define AD_TYPE_FLAGS 0x01u
#define AD_TYPE_UUID128_COMPLETE 0x07u
#define AD_TYPE_LOCAL_NAME_COMPLETE 0x09u
#define AD_TYPE_MANUFACTURER 0xFFu

/* LE General Discoverable Mode | BR/EDR Not Supported. */
#define AD_FLAGS_LE_GENERAL_DISCOVERABLE 0x06u

static void put_u16le(uint8_t *out, uint16_t value) {
    out[0] = (uint8_t)(value & 0xFFu);
    out[1] = (uint8_t)(value >> 8);
}

size_t ble_adv_status_encode(const ble_adv_status_t *status, uint8_t *out,
                             size_t cap) {
    if (status == NULL || out == NULL || cap < BLE_ADV_STATUS_SIZE) {
        return 0;
    }

    out[0] = 1; /* ver */
    out[1] = status->flags;
    put_u16le(&out[2], (uint16_t)status->pit_temp_f10);
    out[4] = status->battery_pct;
    put_u16le(&out[5], (uint16_t)status->billows_target_f10);
    out[7] = status->age_s > 255u ? 255u : (uint8_t)status->age_s;
    out[8] = 0; /* reserved */
    return BLE_ADV_STATUS_SIZE;
}

size_t ble_adv_format_name(char out[BLE_ADV_NAME_MAX], const uint8_t mac[6]) {
    static const char hex[] = "0123456789ABCDEF";

    if (out == NULL || mac == NULL) {
        return 0;
    }

    memcpy(out, BLE_ADV_NAME_PREFIX, sizeof(BLE_ADV_NAME_PREFIX) - 1u);
    size_t pos = sizeof(BLE_ADV_NAME_PREFIX) - 1u;
    out[pos++] = hex[(mac[4] >> 4) & 0x0Fu];
    out[pos++] = hex[mac[4] & 0x0Fu];
    out[pos++] = hex[(mac[5] >> 4) & 0x0Fu];
    out[pos++] = hex[mac[5] & 0x0Fu];
    out[pos] = '\0';
    return pos;
}

size_t ble_adv_build_pdu(uint8_t *out, size_t cap) {
    static const uint8_t service_uuid[16] = BLE_ADV_SERVICE_UUID_LE;

    if (out == NULL || cap < BLE_ADV_PDU_SIZE) {
        return 0;
    }

    size_t pos = 0;

    out[pos++] = 2; /* length: type + value */
    out[pos++] = AD_TYPE_FLAGS;
    out[pos++] = AD_FLAGS_LE_GENERAL_DISCOVERABLE;

    out[pos++] = 17; /* length: type + 16-byte UUID */
    out[pos++] = AD_TYPE_UUID128_COMPLETE;
    memcpy(&out[pos], service_uuid, sizeof(service_uuid));
    pos += sizeof(service_uuid);

    return pos;
}

size_t ble_adv_build_scan_rsp(const char *name,
                              const ble_adv_status_t *status, uint8_t *out,
                              size_t cap) {
    uint8_t blob[BLE_ADV_STATUS_SIZE];
    size_t name_len = 0;

    if (out == NULL || status == NULL ||
        ble_adv_status_encode(status, blob, sizeof(blob)) !=
            BLE_ADV_STATUS_SIZE) {
        return 0;
    }
    if (name != NULL) {
        name_len = strlen(name);
        if (name_len > 0xFFu) {
            name_len = 0;
        }
    }

    size_t total = 0;
    if (name_len > 0u) {
        total += 2u + name_len;
    }
    total += 2u + 2u + BLE_ADV_STATUS_SIZE; /* len+type+company+blob */
    if (cap < total) {
        return 0;
    }

    size_t pos = 0;
    if (name_len > 0u) {
        out[pos++] = (uint8_t)(1u + name_len);
        out[pos++] = AD_TYPE_LOCAL_NAME_COMPLETE;
        memcpy(&out[pos], name, name_len);
        pos += name_len;
    }

    out[pos++] = (uint8_t)(1u + 2u + BLE_ADV_STATUS_SIZE);
    out[pos++] = AD_TYPE_MANUFACTURER;
    put_u16le(&out[pos], BLE_ADV_COMPANY_ID); /* little-endian on the air */
    pos += 2u;
    memcpy(&out[pos], blob, sizeof(blob));
    pos += sizeof(blob);

    return pos;
}

uint16_t ble_adv_interval_units(uint32_t interval_ms) {
    uint32_t units = (interval_ms * 8u) / 5u;
    if (units > 0xFFFFu) {
        units = 0xFFFFu;
    }
    return (uint16_t)units;
}

void ble_adv_state_init(ble_adv_state_t *state) {
    if (state == NULL) {
        return;
    }
    state->phase = BLE_ADV_PHASE_OFF;
    state->fast_until_ms = 0;
}

static ble_adv_action_t action_for(uint32_t interval_ms, bool advertise) {
    ble_adv_action_t action = {.advertise = advertise,
                               .interval_ms = advertise ? interval_ms : 0u};
    return action;
}

ble_adv_action_t ble_adv_state_event(ble_adv_state_t *state,
                                     ble_adv_event_t event, uint32_t now_ms) {
    ble_adv_action_t no_action = {.advertise = false, .interval_ms = 0u};

    if (state == NULL) {
        return no_action;
    }

    switch (event) {
    case BLE_ADV_EVENT_BOOT:
    case BLE_ADV_EVENT_DISCONNECT:
    case BLE_ADV_EVENT_CONNECT_FAILED:
        state->phase = BLE_ADV_PHASE_FAST;
        state->fast_until_ms = now_ms + BLE_ADV_FAST_WINDOW_MS;
        return action_for(BLE_ADV_FAST_INTERVAL_MS, true);

    case BLE_ADV_EVENT_TIMEOUT:
        /* Restart without extending the fast window. */
        if (state->phase == BLE_ADV_PHASE_FAST &&
            now_ms < state->fast_until_ms) {
            return action_for(BLE_ADV_FAST_INTERVAL_MS, true);
        }
        state->phase = BLE_ADV_PHASE_SLOW;
        return action_for(BLE_ADV_SLOW_INTERVAL_MS, true);

    case BLE_ADV_EVENT_CONNECTED:
    case BLE_ADV_EVENT_STOP:
        state->phase = BLE_ADV_PHASE_OFF;
        state->fast_until_ms = 0;
        return no_action;

    default:
        return no_action;
    }
}

ble_adv_action_t ble_adv_state_tick(ble_adv_state_t *state, uint32_t now_ms) {
    ble_adv_action_t no_action = {.advertise = false, .interval_ms = 0u};

    if (state == NULL || state->phase != BLE_ADV_PHASE_FAST) {
        return no_action;
    }
    if (now_ms < state->fast_until_ms) {
        return no_action;
    }

    state->phase = BLE_ADV_PHASE_SLOW;
    return action_for(BLE_ADV_SLOW_INTERVAL_MS, true);
}
