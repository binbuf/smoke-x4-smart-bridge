/*
 * ui.h - OLED, pages and button lifecycle (design 03 section 3.10).
 * T04 skeleton: init/start hooks only.
 */
#ifndef SX4_UI_H
#define SX4_UI_H

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Bring up Vext/I2C/panel and draw the splash. Runs before sample_log_init so a
 * storage failure has a diagnostic surface. */
esp_err_t ui_init(void);

/* Start the ui task and draw the first page. */
esp_err_t ui_start(void);

/*
 * Cross-task dirty flag (T21 produces, T22 consumes). Marking is set-only and
 * cheap; the renderer takes the flag atomically so a sample that arrives
 * during a render is not lost.
 */
void ui_mark_dirty(void);
bool ui_dirty_take(void);
bool ui_dirty_pending(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_UI_H */
