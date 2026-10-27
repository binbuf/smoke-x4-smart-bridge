/*
 * board.h - board power rails and pin map owner (design 01 section 1.2,
 * design 03 section 3.4).
 *
 * Vext is active LOW and must be powered before the I2C bus is created or the
 * SSD1306 can wedge (T09 bench finding). `board_power_init()` owns the rail and
 * reset line; `ui_init()` creates the bus and calls the reset pulse.
 */
#ifndef SX4_BOARD_H
#define SX4_BOARD_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Heltec WiFi LoRa 32 V3 wiring (confirmed on the bench by T09). */
#define BOARD_PIN_VEXT 36
#define BOARD_PIN_OLED_RST 21
#define BOARD_PIN_I2C_SDA 17
#define BOARD_PIN_I2C_SCL 18

/* Configure Vext and the OLED reset line. Call before the I2C bus is created
 * (ui_init). Vext is driven LOW (on) and settles. T24 extends this with the
 * battery divider/ADC. */
esp_err_t board_power_init(void);

/* Pulse the panel reset line while Vext is on. The bus may exist; no I2C
 * transfer happens here. */
esp_err_t board_oled_reset_pulse(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BOARD_H */
