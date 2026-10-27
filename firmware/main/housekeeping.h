/*
 * housekeeping.h - periodic non-radio/non-sample work (design 03 section 3.3).
 *
 * T24 gives the housekeeping task its first real job: battery sampling and the
 * bridge_state clock-persistence tick. The task is deliberately separate from
 * radio_rx and sample_pipe so an ADC read or an NVS write can never sit in
 * front of a sample.
 */
#ifndef SX4_HOUSEKEEPING_H
#define SX4_HOUSEKEEPING_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Loop period. Battery sampling is slower than the loop so the divider is
 * enabled for only a few milliseconds every battery period. */
#define HOUSEKEEPING_TICK_MS 1000u
#define HOUSEKEEPING_BATTERY_PERIOD_MS 10000u

/* Create the static housekeeping task (3072/2/core 0, matching tasks.h). */
esp_err_t housekeeping_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_HOUSEKEEPING_H */
