/*
 * ble_security.h - bond limit and passkey lifetime (design 05 section 5.11,
 * design 07 section 7.3, T30).
 *
 * Pure C11: the firmware injects esp_random() and the monotonic clock, and
 * mirrors the resulting digits onto the OLED. The module owns the two rules
 * that must not drift:
 *   - four bonds maximum and no eviction of an existing phone;
 *   - a six-digit code is valid until bonding ends or 60 s elapse.
 */
#ifndef SX4_BLE_SECURITY_H
#define SX4_BLE_SECURITY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_SEC_MAX_BONDS 4u
#define BLE_SEC_PASSKEY_DIGITS 6u
#define BLE_SEC_PASSKEY_SIZE (BLE_SEC_PASSKEY_DIGITS + 1u)
#define BLE_SEC_PASSKEY_TIMEOUT_MS 60000u

/* A new bond is allowed exactly while a slot is free. No eviction. */
bool ble_security_can_bond(uint8_t used_bonds);

/* Free slots clamped to 0..4. */
uint8_t ble_security_bonds_free(uint8_t used_bonds);

/*
 * Format a fresh six-digit code from an injected random value. The value is
 * reduced modulo 1,000,000 (including 000000). Returns 6, or 0 on bad args.
 */
size_t ble_security_format_passkey(uint32_t random,
                                   char out[BLE_SEC_PASSKEY_SIZE]);

typedef struct {
    bool active;
    uint32_t started_ms;
    char digits[BLE_SEC_PASSKEY_SIZE];
} ble_security_passkey_t;

void ble_security_passkey_init(ble_security_passkey_t *passkey);

/*
 * Start a new attempt: always a fresh code, replacing any previous one.
 * Returns false on a bad argument.
 */
bool ble_security_passkey_start(ble_security_passkey_t *passkey,
                                uint32_t random, uint32_t now_ms);

/*
 * True exactly once when an active code has reached its 60 s deadline; the
 * code is cleared before returning. Disarmed codes return false.
 */
bool ble_security_passkey_tick(ble_security_passkey_t *passkey,
                               uint32_t now_ms);

/* Bonding ended (success, failure or disconnect): clear the code. */
void ble_security_passkey_cancel(ble_security_passkey_t *passkey);

bool ble_security_passkey_active(const ble_security_passkey_t *passkey);

/* Six ASCII digits while active, otherwise an empty string. */
const char *ble_security_passkey_digits(
    const ble_security_passkey_t *passkey);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_SECURITY_H */
