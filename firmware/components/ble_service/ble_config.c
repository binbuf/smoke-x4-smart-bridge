/*
 * ble_config.c - pure `config` validator and encoder (T47).
 *
 * Layout knowledge stays in the generated protocol codec (records.h). This
 * file owns the MVP rules from design 05 section 5.9: the whole struct is
 * validated before anything is applied, the name is UTF-8 with a NUL inside
 * its 16-byte field, the timeout is one of four values, units are 0/1, and a
 * Billows control mode is a named `unsupported` refusal.
 */
#include "ble_config.h"

#include <string.h>

#include "bridge_config.h"

/* Mirrors bridge_config's name rules: no control bytes, no NUL, 1..15 bytes. */
static bool utf8_name_valid(const uint8_t *text, size_t len) {
    size_t i = 0;
    if (len == 0u || len > BRIDGE_CONFIG_DEVICE_NAME_MAX) {
        return false;
    }
    while (i < len) {
        uint8_t c = text[i];
        if (c < 0x80u) {
            if (c < 0x20u || c == 0x7Fu) {
                return false;
            }
            i++;
            continue;
        }
        size_t need;
        uint32_t cp;
        if (c >= 0xC2u && c <= 0xDFu) {
            need = 1u;
            cp = (uint32_t)(c & 0x1Fu);
        } else if (c >= 0xE0u && c <= 0xEFu) {
            need = 2u;
            cp = (uint32_t)(c & 0x0Fu);
        } else if (c >= 0xF0u && c <= 0xF4u) {
            need = 3u;
            cp = (uint32_t)(c & 0x07u);
        } else {
            return false; /* continuation byte, overlong or invalid lead */
        }
        if (len - i < need + 1u) {
            return false;
        }
        for (size_t k = 1u; k <= need; k++) {
            if ((text[i + k] & 0xC0u) != 0x80u) {
                return false;
            }
            cp = (cp << 6) | (uint32_t)(text[i + k] & 0x3Fu);
        }
        if ((need == 2u && cp < 0x800u) || (need == 3u && cp < 0x10000u) ||
            cp > 0x10FFFFu || (cp >= 0xD800u && cp <= 0xDFFFu)) {
            return false;
        }
        i += need + 1u;
    }
    return true;
}

static bool timeout_valid(uint16_t seconds) {
    return seconds == BRIDGE_CONFIG_TIMEOUT_NEVER ||
           seconds == BRIDGE_CONFIG_TIMEOUT_30S ||
           seconds == BRIDGE_CONFIG_TIMEOUT_60S ||
           seconds == BRIDGE_CONFIG_TIMEOUT_120S;
}

static bool units_valid(uint8_t units) {
    return units == BRIDGE_CONFIG_UNITS_CELSIUS ||
           units == BRIDGE_CONFIG_UNITS_FAHRENHEIT;
}

ble_config_status_t ble_config_validate(const ble_config_view_t *view) {
    if (view == NULL || !units_valid(view->units) ||
        !timeout_valid(view->display_timeout_s)) {
        return BLE_CONFIG_INVALID;
    }
    size_t len = 0;
    while (len < sizeof(view->device_name) && view->device_name[len] != '\0') {
        len++;
    }
    if (len >= sizeof(view->device_name) ||
        !utf8_name_valid((const uint8_t *)view->device_name, len)) {
        return BLE_CONFIG_INVALID;
    }
    return BLE_CONFIG_OK;
}

ble_config_status_t ble_config_parse(const uint8_t *in, size_t len,
                                     ble_config_view_t *out) {
    if (in == NULL || out == NULL || len != SX4_CONFIG_SIZE) {
        return BLE_CONFIG_INVALID;
    }
    if (in[0] != 1u) {
        return BLE_CONFIG_INVALID;
    }
    /* Reserved Billows control is a named refusal, not a silent clamp. */
    if (in[22] != 0u) {
        return BLE_CONFIG_UNSUPPORTED;
    }

    const uint8_t *name = in + 4;
    const uint8_t *nul = memchr(name, '\0', 16u);
    if (nul == NULL) {
        return BLE_CONFIG_INVALID;
    }
    size_t name_len = (size_t)(nul - name);
    if (!utf8_name_valid(name, name_len)) {
        return BLE_CONFIG_INVALID;
    }

    uint8_t units = in[1];
    uint16_t timeout = sx4_get_u16(in + 2);
    if (!units_valid(units) || !timeout_valid(timeout)) {
        return BLE_CONFIG_INVALID;
    }

    ble_config_view_t view;
    memset(&view, 0, sizeof(view));
    view.units = units;
    view.display_timeout_s = timeout;
    memcpy(view.device_name, name, name_len);
    view.device_name[name_len] = '\0';
    *out = view;
    return BLE_CONFIG_OK;
}

size_t ble_config_encode(const ble_config_view_t *view, uint8_t *out,
                         size_t cap) {
    sx4_config_t config;

    if (out == NULL || cap < SX4_CONFIG_SIZE ||
        ble_config_validate(view) != BLE_CONFIG_OK) {
        return 0;
    }

    memset(&config, 0, sizeof(config));
    config.ver = 1;
    config.units = view->units;
    config.display_timeout_s = view->display_timeout_s;
    size_t name_len = strlen(view->device_name);
    memcpy(config.device_name, view->device_name, name_len);
    config.billows_target_f10 = 0; /* reserved, never written by the MVP */
    config.billows_mode = 0;
    return sx4_config_encode(&config, out, cap);
}
