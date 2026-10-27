/*
 * ui.h - OLED, pages and button lifecycle (design 03 section 3.10).
 * T04 skeleton: init/start hooks only.
 */
#ifndef SX4_UI_H
#define SX4_UI_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Bring up Vext/I2C/panel and draw the splash. Runs before sample_log_init so a
 * storage failure has a diagnostic surface. */
esp_err_t ui_init(void);

/* Start the ui task and draw the first page. */
esp_err_t ui_start(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_UI_H */
