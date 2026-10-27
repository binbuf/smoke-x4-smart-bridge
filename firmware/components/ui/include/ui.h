/*
 * ui.h - OLED, pages, overlays and display sleep (design 03 section 3.10,
 * design 07 sections 7.1-7.5).
 *
 * The renderer itself is pure C (ui_render.h); this header is the firmware
 * lifecycle and cross-task control surface. The UI task renders a snapshot of
 * bridge_state/bridge_config/sample_log and only flushes when the 1 KB
 * framebuffer changes.
 */
#ifndef SX4_UI_H
#define SX4_UI_H

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "ui_render.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Bring up Vext/I2C/panel and draw the splash. Runs before sample_log_init so a
 * storage failure has a diagnostic surface. Vext itself is configured by
 * board_power_init(), which the boot sequence runs first. */
esp_err_t ui_init(void);

/* Start the ui task and draw the first page. */
esp_err_t ui_start(void);

/*
 * Cross-task dirty flag (T21 produces, T22 consumes). Marking is set-only and
 * cheap; the renderer takes the flag atomically so a sample that arrives
 * during a render is not lost. Marking while the panel is asleep does not wake
 * it; the next wake redraws.
 */
void ui_mark_dirty(void);
bool ui_dirty_take(void);
bool ui_dirty_pending(void);

/* Display sleep (T23 owns the PRG gesture; BLE/pairing call activity). */
bool ui_display_asleep(void);
/* Wake the panel without changing the page. Returns true if it was asleep. */
bool ui_wake(void);
/* External activity that should wake/keep the panel: BLE connect, pairing
 * start, an app action. Samples use ui_mark_dirty() instead. */
void ui_display_activity(void);
void ui_set_display_timeout(uint16_t timeout_s);

/* Page selection. T23 maps a PRG tap here. */
ui_page_t ui_page(void);
void ui_set_page(ui_page_t page);
ui_page_t ui_page_next(void);

/* Overlay control for later tasks. The renderer applies the design priority
 * regardless of the order these are set. */
void ui_set_overlay_mask(uint8_t mask);
void ui_set_passkey(const char *digits); /* six ASCII digits; NULL clears */
void ui_set_power_off(uint8_t countdown_s, bool visible);
/* T23 tap on the storage overlay: hide it for this boot. The status strip
 * continues to show the `!` warning until the next boot. */
void ui_dismiss_storage_failure(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_UI_H */
