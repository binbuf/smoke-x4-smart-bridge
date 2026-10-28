/*
 * ble_service.h - BLE GATT service lifecycle (design 03 section 3.9).
 *
 * T27 registers the custom service and serves the open `info` read. T30 adds
 * advertising, the passkey overlay seam and the bond limit.
 */
#ifndef SX4_BLE_SERVICE_H
#define SX4_BLE_SERVICE_H

#include <stdbool.h>
#include <stdint.h>

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

/*
 * True while the bridge is advertising and no central is connected. The OLED
 * uses this to show the blinking "looking for a phone" indicator.
 */
bool ble_service_is_advertising(void);

/*
 * Safety net for discovery: if the host is synced, idle, and advertising has
 * stopped for any reason, restart it at the current interval. Called by the
 * periodic housekeeping task; it never runs while connected and never extends
 * the fast-advertising window.
 */
void ble_service_keep_advertising(void);

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
 * Config-applied seam (T47). Called after an accepted 80-byte config write has
 * been persisted, with the new units and display timeout. boot.c wires it to
 * the UI so the OLED changes without a reboot; ble_service cannot call ui
 * directly because ui already depends on ble_service.
 */
typedef void (*ble_service_config_applied_fn)(uint8_t units,
                                              uint16_t display_timeout_s,
                                              void *ctx);
void ble_service_set_config_applied_callback(
    ble_service_config_applied_fn fn, void *ctx);

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
 * GAP event callback seam. It is passed as the advertising callback to
 * ble_gap_adv_start(); NimBLE routes PASSKEY_ACTION and PARING_COMPLETE only to
 * that connection callback, not to ble_gap_event_listener_register().
 */
struct ble_gap_event;
int ble_service_gap_event(struct ble_gap_event *event, void *arg);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_SERVICE_H */
