/*
 * board.h - board power rails and pin map owner (design 01 section 1.2,
 * design 03 section 3.4). T04 skeleton: power init hook only.
 */
#ifndef SX4_BOARD_H
#define SX4_BOARD_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Configure Vext, the battery divider enable and the ADC. Call before the I2C
 * bus is created (ui_init). */
esp_err_t board_power_init(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BOARD_H */
