/*
 * ble_security.c - pure bond-limit and passkey-lifetime rules (T30).
 */
#include "ble_security.h"

#include <stdio.h>
#include <string.h>

bool ble_security_can_bond(uint8_t used_bonds) {
    return used_bonds < BLE_SEC_MAX_BONDS;
}

uint8_t ble_security_bonds_free(uint8_t used_bonds) {
    if (used_bonds >= BLE_SEC_MAX_BONDS) {
        return 0;
    }
    return (uint8_t)(BLE_SEC_MAX_BONDS - used_bonds);
}

size_t ble_security_format_passkey(uint32_t random,
                                   char out[BLE_SEC_PASSKEY_SIZE]) {
    if (out == NULL) {
        return 0;
    }
    unsigned value = (unsigned)(random % 1000000u);
    int written = snprintf(out, BLE_SEC_PASSKEY_SIZE, "%06u", value);
    return written == (int)BLE_SEC_PASSKEY_DIGITS
               ? BLE_SEC_PASSKEY_DIGITS
               : 0;
}

void ble_security_passkey_init(ble_security_passkey_t *passkey) {
    if (passkey == NULL) {
        return;
    }
    memset(passkey, 0, sizeof(*passkey));
}

bool ble_security_passkey_start(ble_security_passkey_t *passkey,
                                uint32_t random, uint32_t now_ms) {
    if (passkey == NULL) {
        return false;
    }
    if (ble_security_format_passkey(random, passkey->digits) !=
        BLE_SEC_PASSKEY_DIGITS) {
        ble_security_passkey_cancel(passkey);
        return false;
    }
    passkey->active = true;
    passkey->started_ms = now_ms;
    return true;
}

bool ble_security_passkey_tick(ble_security_passkey_t *passkey,
                               uint32_t now_ms) {
    if (passkey == NULL || !passkey->active) {
        return false;
    }
    /* Unsigned subtraction stays correct across the 32-bit millisecond wrap. */
    if ((uint32_t)(now_ms - passkey->started_ms) <
        BLE_SEC_PASSKEY_TIMEOUT_MS) {
        return false;
    }
    ble_security_passkey_cancel(passkey);
    return true;
}

void ble_security_passkey_cancel(ble_security_passkey_t *passkey) {
    if (passkey == NULL) {
        return;
    }
    passkey->active = false;
    passkey->started_ms = 0;
    memset(passkey->digits, 0, sizeof(passkey->digits));
}

bool ble_security_passkey_active(const ble_security_passkey_t *passkey) {
    return passkey != NULL && passkey->active;
}

const char *ble_security_passkey_digits(
    const ble_security_passkey_t *passkey) {
    static const char empty[1] = "";
    if (passkey == NULL || !passkey->active) {
        return empty;
    }
    return passkey->digits;
}
