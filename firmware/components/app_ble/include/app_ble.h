/* app_ble — the NimBLE glue for the Bridge Control Service (F10.4, F10.5;
 * design 05 §5.6, 03 §3.3). The contract itself lives in app_ble_core.h
 * and is host-tested; this file owns GAP/GATT registration, the security
 * callbacks, the event-bus subscriptions, and the ble_push task row.
 */
#ifndef APP_BLE_H
#define APP_BLE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Starts NimBLE, registers the service, and brings up advertising and the
 * ble_push row. Returns 0 on success. Not fatal to the boot: a bridge with
 * no BLE still cooks and still serves HTTP (03 §3.4). */
int app_ble_init(void);

/* Clears every stored bond (ble_store_clear). REQUIRED on every factory
 * reset path — app_config_store_factory_reset() does not reach NimBLE's
 * namespace, which is the obligation attached to the 03 §3.6.1 exception. */
int app_ble_forget_bonds(void);

/* Re-arm the 250 ms fast-advertising window (a button press; boot arms it
 * automatically). */
void app_ble_note_activity(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_BLE_H */
