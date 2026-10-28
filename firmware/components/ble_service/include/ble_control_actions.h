/*
 * ble_control_actions.h - backend routing for the `control` destructive ops
 * (T48).
 *
 * ble_control.c owns the wire decision and the reply-first timer. This module
 * routes one deferred action to the platform backend and keeps the mapping
 * host-testable without NimBLE, NVS, flash or the board.
 *
 * Every backend callback returns an SX4_RESULT_STATUS_* value (design 05 5.6),
 * never a raw ESP-IDF/NimBLE error. The caller cannot change the already-sent
 * `result`: the returned status is for the log and for the host tests.
 */
#ifndef SX4_BLE_CONTROL_ACTIONS_H
#define SX4_BLE_CONTROL_ACTIONS_H

#include <stdint.h>

#include "ble_control.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    void *ctx;
    /* Remove only the current peer's bond, then drop the link. */
    uint8_t (*forget_phone)(void *ctx);
    /* Wipe config, generation/clear flag and all bonds; the reboot follows. */
    uint8_t (*factory_reset)(void *ctx);
    /* Enter deep sleep. */
    uint8_t (*power_off)(void *ctx);
    /* New generation + erase the ring; pairing/config survive. */
    uint8_t (*clear_history)(void *ctx);
    /* Clear the stored Smoke X4 id/frequency and restart the 915/920 scan. */
    uint8_t (*unpair_smoke_x)(void *ctx);
} ble_control_action_ops_t;

/*
 * Run one deferred destructive action. Returns SX4_RESULT_STATUS_OK when the
 * backend reports success, its status code when it fails, or
 * SX4_RESULT_STATUS_UNSUPPORTED for a missing/unknown action or callback.
 */
uint8_t ble_control_actions_run(const ble_control_action_ops_t *ops,
                                ble_control_action_t action);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_CONTROL_ACTIONS_H */
