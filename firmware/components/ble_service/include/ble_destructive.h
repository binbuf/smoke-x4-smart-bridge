/*
 * ble_destructive.h - destructive-action link lifecycle and boot recovery (T49).
 *
 * The `control` dispatcher answers first and arms a ~250 ms timer (design 05
 * 5.5/5.12). This module owns the small state machine between "result sent" and
 * "link torn down / reboot / sleep", so the host tests can prove every outcome
 * without NimBLE, NVS, flash or the board. ble_service.c drives it from the GAP
 * and timer callbacks; boot.c uses the boot plan when it decides what to do
 * after a power cut.
 *
 * Invariant: advertising is never true while link_up is true, and an owed
 * reboot/sleep never advertises. ble_destructive_consistent() asserts it.
 */
#ifndef SX4_BLE_DESTRUCTIVE_H
#define SX4_BLE_DESTRUCTIVE_H

#include <stdbool.h>
#include <stdint.h>

#include "ble_control.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BLE_DESTRUCTIVE_PHASE_IDLE = 0, /* no destructive op in flight */
    BLE_DESTRUCTIVE_PHASE_ANSWERED, /* result notified, action timer armed */
    BLE_DESTRUCTIVE_PHASE_RUNNING,  /* action backend is executing */
    BLE_DESTRUCTIVE_PHASE_COMPLETE, /* action done; normal link policy applies */
    BLE_DESTRUCTIVE_PHASE_REBOOT,   /* fully wiped; reboot owed */
    BLE_DESTRUCTIVE_PHASE_SLEEP,    /* power-off; deep sleep owed */
} ble_destructive_phase_t;

typedef enum {
    BLE_DESTRUCTIVE_OUTCOME_NONE = 0,
    BLE_DESTRUCTIVE_OUTCOME_ADVERTISE, /* (re)start advertising now */
    BLE_DESTRUCTIVE_OUTCOME_REBOOT,    /* do not advertise; reboot */
    BLE_DESTRUCTIVE_OUTCOME_SLEEP,     /* do not advertise; deep sleep */
} ble_destructive_outcome_t;

typedef struct {
    ble_destructive_phase_t phase;
    ble_control_action_t action; /* pending/running action, NONE when idle */
    bool result_sent;
    bool link_up;
    bool advertising;
} ble_destructive_state_t;

/* Boot with the host synced: not connected, advertising. */
void ble_destructive_init(ble_destructive_state_t *state, bool synced);

/* A central connected: advertising stops. */
void ble_destructive_on_connect(ble_destructive_state_t *state);

/*
 * The `result` notification has been handed to NimBLE. Remember a destructive
 * action so a link drop cannot lose it. Returns NONE; the action still needs
 * its timer.
 */
ble_destructive_outcome_t ble_destructive_on_result(
    ble_destructive_state_t *state, ble_control_action_t action);

/*
 * The link dropped. A pending action is *kept*; the timer still runs. Forget,
 * clear and unpair re-advertise immediately (the effect does not need a link);
 * factory reset and power off stay silent because reboot/sleep is owed.
 */
ble_destructive_outcome_t ble_destructive_on_disconnect(
    ble_destructive_state_t *state);

/* The action timer fired: return the pending action (NONE if there is none). */
ble_control_action_t ble_destructive_take_action(
    ble_destructive_state_t *state);

/*
 * The backend finished. A failed action falls back to the normal discoverable
 * state so a phone can retry; a successful forget re-advertises, factory reset
 * owes a reboot and power off owes deep sleep.
 */
ble_destructive_outcome_t ble_destructive_on_action_finished(
    ble_destructive_state_t *state, ble_control_action_t action,
    uint8_t status);

bool ble_destructive_pending(const ble_destructive_state_t *state);

/* True while radio policy is coherent: never advertising while connected. */
bool ble_destructive_consistent(const ble_destructive_state_t *state);

/* ---- boot recovery ------------------------------------------------------ */

typedef enum {
    BLE_BOOT_OUTCOME_NORMAL = 0,      /* advertise as usual */
    BLE_BOOT_OUTCOME_CLEAR_THEN_ADVERTISE, /* finish pending wipe, then advertise */
} ble_boot_outcome_t;

/*
 * A power cut during factory reset or clear_history leaves `clear_pending` set.
 * Boot must finish that erase before the first append and only then advertise;
 * it never starts in a half-wiped state. The erase itself is log_flash_open()'s
 * job (T19); this decides the link/radio outcome the caller must apply.
 */
ble_boot_outcome_t ble_destructive_boot_plan(bool clear_pending);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_DESTRUCTIVE_H */
