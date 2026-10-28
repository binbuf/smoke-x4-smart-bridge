/*
 * ble_destructive.c - pure destructive-action lifecycle (T49).
 *
 * See ble_destructive.h and design 05 5.12. No NimBLE, NVS, flash or board
 * dependency: the same transitions run in the firmware and the host tests.
 */
#include "ble_destructive.h"

#include <string.h>

void ble_destructive_init(ble_destructive_state_t *state, bool synced) {
    if (state == NULL) {
        return;
    }
    memset(state, 0, sizeof(*state));
    state->phase = BLE_DESTRUCTIVE_PHASE_IDLE;
    state->action = BLE_CONTROL_ACTION_NONE;
    state->link_up = false;
    state->advertising = synced;
}

void ble_destructive_on_connect(ble_destructive_state_t *state) {
    if (state == NULL) {
        return;
    }
    state->link_up = true;
    /* A connection always stops advertising, even if an earlier action is
     * still pending: the pending action survives, the radio follows the link. */
    state->advertising = false;
}

ble_destructive_outcome_t ble_destructive_on_result(
    ble_destructive_state_t *state, ble_control_action_t action) {
    if (state == NULL || action == BLE_CONTROL_ACTION_NONE) {
        return BLE_DESTRUCTIVE_OUTCOME_NONE;
    }
    state->action = action;
    state->result_sent = true;
    state->phase = BLE_DESTRUCTIVE_PHASE_ANSWERED;
    state->advertising = false; /* still connected, or already torn down */
    return BLE_DESTRUCTIVE_OUTCOME_NONE;
}

ble_destructive_outcome_t ble_destructive_on_disconnect(
    ble_destructive_state_t *state) {
    if (state == NULL) {
        return BLE_DESTRUCTIVE_OUTCOME_NONE;
    }
    state->link_up = false;

    if (state->phase == BLE_DESTRUCTIVE_PHASE_REBOOT ||
        state->phase == BLE_DESTRUCTIVE_PHASE_SLEEP) {
        state->advertising = false;
        return state->phase == BLE_DESTRUCTIVE_PHASE_REBOOT
                   ? BLE_DESTRUCTIVE_OUTCOME_REBOOT
                   : BLE_DESTRUCTIVE_OUTCOME_SLEEP;
    }

    if (state->phase == BLE_DESTRUCTIVE_PHASE_ANSWERED ||
        state->phase == BLE_DESTRUCTIVE_PHASE_RUNNING) {
        /* Keep the action: the timer is not cancelled by a link drop. Factory
         * reset and power off will be silent until they reboot/sleep. */
        switch (state->action) {
        case BLE_CONTROL_ACTION_FACTORY_RESET:
        case BLE_CONTROL_ACTION_POWER_OFF:
            state->advertising = false;
            return BLE_DESTRUCTIVE_OUTCOME_NONE;
        default:
            state->advertising = true;
            return BLE_DESTRUCTIVE_OUTCOME_ADVERTISE;
        }
    }

    /* Normal disconnect (app closed, out of range, failed connect, timeout). */
    state->advertising = true;
    return BLE_DESTRUCTIVE_OUTCOME_ADVERTISE;
}

ble_control_action_t ble_destructive_take_action(
    ble_destructive_state_t *state) {
    if (state == NULL || state->action == BLE_CONTROL_ACTION_NONE) {
        return BLE_CONTROL_ACTION_NONE;
    }
    state->result_sent = false;
    state->phase = BLE_DESTRUCTIVE_PHASE_RUNNING;
    return state->action;
}

ble_destructive_outcome_t ble_destructive_on_action_finished(
    ble_destructive_state_t *state, ble_control_action_t action,
    uint8_t status) {
    if (state == NULL) {
        return BLE_DESTRUCTIVE_OUTCOME_NONE;
    }
    state->action = BLE_CONTROL_ACTION_NONE;
    state->result_sent = false;

    if (status != SX4_RESULT_STATUS_OK) {
        /* The answer already said ok. A failed effect must still leave the
         * bridge findable so the app can reconnect and retry. */
        state->phase = BLE_DESTRUCTIVE_PHASE_COMPLETE;
        state->advertising = !state->link_up;
        return state->advertising ? BLE_DESTRUCTIVE_OUTCOME_ADVERTISE
                                  : BLE_DESTRUCTIVE_OUTCOME_NONE;
    }

    switch (action) {
    case BLE_CONTROL_ACTION_FORGET_PHONE:
        /* The current bond is gone and the link was dropped. */
        state->phase = BLE_DESTRUCTIVE_PHASE_COMPLETE;
        state->link_up = false;
        state->advertising = true;
        return BLE_DESTRUCTIVE_OUTCOME_ADVERTISE;
    case BLE_CONTROL_ACTION_FACTORY_RESET:
        state->phase = BLE_DESTRUCTIVE_PHASE_REBOOT;
        state->advertising = false;
        return BLE_DESTRUCTIVE_OUTCOME_REBOOT;
    case BLE_CONTROL_ACTION_POWER_OFF:
        state->phase = BLE_DESTRUCTIVE_PHASE_SLEEP;
        state->advertising = false;
        return BLE_DESTRUCTIVE_OUTCOME_SLEEP;
    case BLE_CONTROL_ACTION_CLEAR_HISTORY:
    case BLE_CONTROL_ACTION_UNPAIR_SMOKE_X:
    default:
        state->phase = BLE_DESTRUCTIVE_PHASE_COMPLETE;
        state->advertising = !state->link_up;
        return state->advertising ? BLE_DESTRUCTIVE_OUTCOME_ADVERTISE
                                  : BLE_DESTRUCTIVE_OUTCOME_NONE;
    }
}

bool ble_destructive_pending(const ble_destructive_state_t *state) {
    return state != NULL && state->action != BLE_CONTROL_ACTION_NONE &&
           (state->phase == BLE_DESTRUCTIVE_PHASE_ANSWERED ||
            state->phase == BLE_DESTRUCTIVE_PHASE_RUNNING);
}

bool ble_destructive_consistent(const ble_destructive_state_t *state) {
    if (state == NULL) {
        return true;
    }
    if (state->link_up && state->advertising) {
        return false;
    }
    if ((state->phase == BLE_DESTRUCTIVE_PHASE_REBOOT ||
         state->phase == BLE_DESTRUCTIVE_PHASE_SLEEP) &&
        state->advertising) {
        return false;
    }
    return true;
}

ble_boot_outcome_t ble_destructive_boot_plan(bool clear_pending) {
    return clear_pending ? BLE_BOOT_OUTCOME_CLEAR_THEN_ADVERTISE
                         : BLE_BOOT_OUTCOME_NORMAL;
}
