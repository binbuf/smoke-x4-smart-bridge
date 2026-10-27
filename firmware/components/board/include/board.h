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

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Heltec WiFi LoRa 32 V3 wiring (confirmed on the bench by T09). */
#define BOARD_PIN_VEXT 36
#define BOARD_PIN_OLED_RST 21
#define BOARD_PIN_I2C_SDA 17
#define BOARD_PIN_I2C_SCL 18

/* PRG is the single user button: active LOW, with the board's external pull-up.
 * It is also the GPIO0 ROM strap, so it is only read after boot. */
#define BOARD_PIN_PRG 0

/* Configure Vext and the OLED reset line. Call before the I2C bus is created
 * (ui_init). Vext is driven LOW (on) and settles. T24 extends this with the
 * battery divider/ADC. */
esp_err_t board_power_init(void);

/* Configure PRG as a pulled-up input. Safe to call repeatedly; the boot-hold
 * confirmation calls it before board_power_init(). */
esp_err_t board_prg_init(void);

/* Debounced level is owned by ui_button; this is the raw active-LOW read.
 * Returns true while the button is pressed. */
bool board_prg_pressed(void);

/* Drive Vext HIGH (rail off). The panel and its I2C bus are unusable after
 * this until board_power_init() runs again. */
esp_err_t board_power_off_vext(void);

/* Turn Vext off, arm GPIO0 active-LOW EXT1 wake, and enter deep sleep. Does
 * not return on success; returns the wake-arm error and stays awake otherwise. */
esp_err_t board_enter_deep_sleep(void);

/* Pulse the panel reset line while Vext is on. The bus may exist; no I2C
 * transfer happens here. */
esp_err_t board_oled_reset_pulse(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BOARD_H */
