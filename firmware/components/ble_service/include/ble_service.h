/*
 * ble_service.h - BLE GATT service lifecycle (design 03 section 3.9).
 *
 * T27 registers the custom service and serves the open `info` read. Advertising
 * and security policy are T30.
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
