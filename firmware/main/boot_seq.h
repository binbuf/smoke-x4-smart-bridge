/* boot_seq.h — the sixteen-step boot sequence of design 03 §3.4, as a pure,
 * host-testable step runner. main.c supplies the real step implementations;
 * host tests supply fakes.
 *
 * Two properties are structural, not stylistic:
 *   1. LoRa (smoke_x) comes up before Wi-Fi and BLE — data capture is the
 *      product; a later subsystem failing must not cost the cook.
 *   2. Only NVS (step 1) and the event loop (step 4) are fatal. Every step
 *      after cook_store is individually failure-tolerant and logged.
 */
#ifndef BOOT_SEQ_H
#define BOOT_SEQ_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BRIDGE_BOOT_STEP_COUNT 16

/* Step numbers per 03 §3.4 (1-based). */
typedef enum {
    BRIDGE_BOOT_NVS = 1,
    BRIDGE_BOOT_BOOT_REASON = 2,
    BRIDGE_BOOT_CONFIG = 3,
    BRIDGE_BOOT_EVENT_LOOP = 4,
    BRIDGE_BOOT_POWER = 5,
    BRIDGE_BOOT_UI = 6,
    BRIDGE_BOOT_RECOVERY_WINDOW = 7, /* 3 s PRG hold — stub until F11 */
    BRIDGE_BOOT_COOK_STORE = 8,
    BRIDGE_BOOT_SMOKE_X_INIT = 9,
    BRIDGE_BOOT_SMOKE_X_START = 10,  /* LoRa RX begins — before net/BLE */
    BRIDGE_BOOT_TIME = 11,
    BRIDGE_BOOT_NET = 12,
    BRIDGE_BOOT_API = 13,
    BRIDGE_BOOT_BLE = 14,
    BRIDGE_BOOT_ALARM = 15,
    BRIDGE_BOOT_OTA_HEALTH_GATE = 16, /* stub until F14 */
} bridge_boot_step_t;

/* A step returns 0 on success, nonzero on failure. NULL steps are skipped
 * (treated as success) so the skeleton boots before subsystems exist. */
typedef int (*bridge_boot_step_fn)(void *ctx);

typedef struct {
    bridge_boot_step_fn steps[BRIDGE_BOOT_STEP_COUNT]; /* index 0 = step 1 */
} bridge_boot_ops_t;

typedef struct {
    /* Highest step number that ran and succeeded with no gap before it. */
    int steps_completed;
    /* Bitmask of failed non-fatal steps; bit (n-1) = step n. */
    uint32_t failed_mask;
    /* 0, or the fatal step number that aborted the sequence. */
    int fatal_step;
} bridge_boot_result_t;

/* Runs steps 1..16 in order. Returns true if the device booted (no fatal
 * failure); non-fatal failures are recorded in result->failed_mask and the
 * sequence continues. */
bool bridge_boot_run(const bridge_boot_ops_t *ops, void *ctx,
                     bridge_boot_result_t *result);

/* Human-readable step name, e.g. for boot logs. */
const char *bridge_boot_step_name(int step);

#ifdef __cplusplus
}
#endif

#endif /* BOOT_SEQ_H */
