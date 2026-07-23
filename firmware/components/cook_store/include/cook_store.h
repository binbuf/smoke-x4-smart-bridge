/* cook_store — device-facing entry point (design 03 §3.1, 04 §4.3).
 *
 * The full API lives in cook_store_core.h (host-testable) plus cook_ring.h
 * and cook_lifecycle.h; this header carries only the LittleFS mount and
 * wiring that must run on the device. */
#ifndef COOK_STORE_H
#define COOK_STORE_H

#include "cook_lifecycle.h"
#include "cook_novelty_log.h"
#include "cook_ring.h"
#include "cook_store_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Mounts the `cooks` LittleFS partition at /cooks, then runs
 * cook_store_core_init (index rebuild + §4.5 recovery). app_config must be
 * initialised first (boot step 8 comes after step 3). Returns 0 on
 * success. */
int cook_store_init(void);

/* Starts the drain task (03 §3.2 rule 2): BRIDGE_EVT_SAMPLE handlers only
 * enqueue; the task owns every flash write, lifecycle decision, ring push,
 * and the F6.2 back-patch on BRIDGE_EVT_TIME. Requires the event loop. */
int cook_store_task_start(void);

#ifdef __cplusplus
}
#endif

#endif /* COOK_STORE_H */
