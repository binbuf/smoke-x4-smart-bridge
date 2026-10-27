/*
 * bridge_state.h - live snapshot, wall clock and counters (design 03 sections
 * 3.5, 3.8). T04 skeleton: init hook only.
 */
#ifndef SX4_BRIDGE_STATE_H
#define SX4_BRIDGE_STATE_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Initialise the process-wide snapshot/counters. Called before tasks start. */
esp_err_t bridge_state_init(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BRIDGE_STATE_H */
