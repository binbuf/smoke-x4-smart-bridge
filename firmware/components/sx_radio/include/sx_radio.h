/*
 * sx_radio.h - SX1262 owner, RX task and (from T16) pairing state machine
 * (design 03 sections 3.3, 3.5.3 and 3.6).
 *
 * Received packets leave through the pure-C seam in sx_radio_rx.h. The RX path
 * never calls NVS, flash or BLE.
 */
#ifndef SX4_SX_RADIO_H
#define SX4_SX_RADIO_H

#include <stdint.h>

#include "esp_err.h"
#include "sx_radio_params.h"
#include "sx_radio_rx.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Reset and configure the SX1262 with the approved Smoke X parameter block;
 * does not start the receive task. */
esp_err_t sx_radio_init(void);

/* Create the radio_rx task (4096 bytes, priority 6, core 1). */
esp_err_t sx_radio_start(void);

/* Tune to a validated 902-928 MHz operating frequency. The T16 pairing FSM is
 * the intended caller; an out-of-band value is rejected without retuning. */
esp_err_t sx_radio_set_frequency(uint32_t frequency_hz);

/* Currently tuned frequency, in Hz. */
uint32_t sx_radio_frequency(void);

/*
 * Stop the RX task and put the SX1262 into cold sleep for power-off. Called
 * once, immediately before deep sleep; the next boot re-runs sx_radio_init().
 * Safe to call when the radio was never configured (returns ESP_OK).
 */
esp_err_t sx_radio_sleep(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_RADIO_H */
