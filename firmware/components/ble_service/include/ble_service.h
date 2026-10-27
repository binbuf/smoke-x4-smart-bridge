/*
 * ble_service.h - BLE GATT service lifecycle (design 03 section 3.9).
 *
 * T27 registers the custom service and serves the open `info` read. T30 adds
 * advertising, the passkey overlay seam and the bond limit.
 */
#ifndef SX4_BLE_SERVICE_H
#define SX4_BLE_SERVICE_H

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Initialise NimBLE and register the GATT service. Does not start advertising;
 * T30 owns the advertising policy. A failure must not stop recording.
 */
esp_err_t ble_service_start(void);

/*
 * Bring the BLE host/controller down before deep sleep: stop and deinit
 * NimBLE. Idempotent; safe when start was never called.
 */
esp_err_t ble_service_stop(void);

/* True while a central is connected (the MVP allows one). */
bool ble_service_is_connected(void);

/* Number of phone bonds currently stored, 0..4 (cached, updated on sync/enc). */
uint8_t ble_service_bond_count(void);

/*
 * Passkey display seam. ble_service calls this with six ASCII digits when a
 * bond starts and with NULL when the attempt ends, expires or is cancelled. The
 * boot sequence wires it to ui_set_passkey(); the host build never links it.
 */
typedef void (*ble_service_passkey_fn)(const char *digits, void *ctx);
void ble_service_set_passkey_callback(ble_service_passkey_fn fn, void *ctx);

/*
 * Re-open the 250 ms advertising window after user/button activity. No-op
 * while connected or before the host is synced.
 */
void ble_service_boost_advertising(void);

/*
 * Tap-to-cancel seam for the OLED overlay: clear the code, stop its 60 s timer
 * and drop the link so the phone sees a failed bond.
 */
void ble_service_cancel_pairing(void);

/*
 * GAP event callback seam. T27 registers it with ble_gap_event_listener_register()
 * to track connect/disconnect; T30 also passes it to ble_gap_adv_start().
 */
struct ble_gap_event;
int ble_service_gap_event(struct ble_gap_event *event, void *arg);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_SERVICE_H */
