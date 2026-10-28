/*
 * ble_control_actions.c - deferred destructive action routing (T48).
 *
 * The result notification has already left when this runs; a failure here is
 * reported to the caller/log but cannot rewrite that result. Keeping the
 * routing pure lets the host suite prove ordering, idempotency and failure
 * mapping for every op with fake backends.
 */
#include "ble_control_actions.h"

#include <stddef.h>

#include "records.h"

uint8_t ble_control_actions_run(const ble_control_action_ops_t *ops,
                                ble_control_action_t action) {
    if (ops == NULL) {
        return SX4_RESULT_STATUS_UNSUPPORTED;
    }

    switch (action) {
    case BLE_CONTROL_ACTION_FORGET_PHONE:
        return ops->forget_phone != NULL ? ops->forget_phone(ops->ctx)
                                         : SX4_RESULT_STATUS_UNSUPPORTED;
    case BLE_CONTROL_ACTION_FACTORY_RESET:
        return ops->factory_reset != NULL ? ops->factory_reset(ops->ctx)
                                          : SX4_RESULT_STATUS_UNSUPPORTED;
    case BLE_CONTROL_ACTION_POWER_OFF:
        return ops->power_off != NULL ? ops->power_off(ops->ctx)
                                      : SX4_RESULT_STATUS_UNSUPPORTED;
    case BLE_CONTROL_ACTION_CLEAR_HISTORY:
        return ops->clear_history != NULL ? ops->clear_history(ops->ctx)
                                          : SX4_RESULT_STATUS_UNSUPPORTED;
    case BLE_CONTROL_ACTION_UNPAIR_SMOKE_X:
        return ops->unpair_smoke_x != NULL
                   ? ops->unpair_smoke_x(ops->ctx)
                   : SX4_RESULT_STATUS_UNSUPPORTED;
    case BLE_CONTROL_ACTION_NONE:
    default:
        return SX4_RESULT_STATUS_UNSUPPORTED;
    }
}
