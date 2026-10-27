/*
 * ble_info.c - pure `info` encoder (T27).
 *
 * All layout knowledge lives in the generated protocol codec
 * (protocol/gen/records.h and records.c). This wrapper only maps the
 * human-facing strings into fixed-size fields and enforces the MVP rules:
 * billows_control is never advertised and bonds_free is 0..4.
 */
#include "ble_info.h"

#include <string.h>

#include "records.h"

static void copy_field(char *dst, size_t dst_size, const char *src) {
    size_t n = 0;
    memset(dst, 0, dst_size);
    if (src == NULL) {
        return;
    }
    while (n < dst_size && src[n] != '\0') {
        n++;
    }
    memcpy(dst, src, n);
}

uint8_t ble_info_caps(uint8_t requested_caps) {
    return (uint8_t)(requested_caps & ~SX4_CAPS_FLAG_BILLOWS_CONTROL);
}

uint8_t ble_info_bonds_free(uint8_t used_bonds) {
    if (used_bonds >= BLE_INFO_MAX_BONDS) {
        return 0;
    }
    return (uint8_t)(BLE_INFO_MAX_BONDS - used_bonds);
}

uint8_t ble_info_probes(bool paired, uint8_t configured_probes) {
    if (paired && (configured_probes == 2u || configured_probes == 4u)) {
        return configured_probes;
    }
    return 4u;
}

size_t ble_info_encode(const ble_info_view_t *view, uint8_t *out, size_t cap) {
    sx4_info_t info;

    if (view == NULL || out == NULL || cap < SX4_INFO_SIZE) {
        return 0;
    }

    memset(&info, 0, sizeof(info));
    info.ver = 1;
    info.proto_major = (uint8_t)SX4_PROTOCOL_MAJOR;
    info.proto_minor = (uint8_t)SX4_PROTOCOL_MINOR;
    info.caps = ble_info_caps(view->caps);
    info.probes = view->probes;
    copy_field(info.device_id, sizeof(info.device_id), view->device_id);
    copy_field(info.fw, sizeof(info.fw), view->fw);
    copy_field(info.model, sizeof(info.model), view->model);
    info.bonds_free = view->bonds_free > BLE_INFO_MAX_BONDS
                          ? (uint8_t)BLE_INFO_MAX_BONDS
                          : view->bonds_free;
    info.reserved0 = 0;
    info.reserved1 = 0;

    return sx4_info_encode(&info, out, cap);
}
