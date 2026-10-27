/*
 * ble_service.h - BLE GATT service lifecycle (design 03 section 3.9).
 * T04 skeleton: start hook only. Product service work lands in M2.
 */
#ifndef SX4_BLE_SERVICE_H
#define SX4_BLE_SERVICE_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Initialise NimBLE and start advertising. A failure must not stop recording. */
esp_err_t ble_service_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_SERVICE_H */
