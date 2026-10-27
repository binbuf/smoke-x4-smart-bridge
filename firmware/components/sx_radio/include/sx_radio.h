/*
 * sx_radio.h - SX1262 owner and pairing state machine (design 03 sections 3.5.3,
 * 3.6). T04 skeleton: init/start hooks only.
 */
#ifndef SX4_SX_RADIO_H
#define SX4_SX_RADIO_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Reset and configure the SX1262; does not receive yet. */
esp_err_t sx_radio_init(void);

/* Start the radio_rx task: paired tune + RX, or the unpaired 915/920 scan. */
esp_err_t sx_radio_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_RADIO_H */
