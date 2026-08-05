/* app_ui_cook — the app-confirmed cook clock. DISPLAY ONLY.
 *
 * The bridge has no concept of a cook. It receives samples, it records them,
 * and it draws temperatures; deciding that a pile of samples is "a brisket
 * that started at 04:15" is the app's job and always was. The device used to
 * infer it — cook_lifecycle opens a storage session the moment a probe is
 * attached — and then put that inference on the glass as `Elapsed 04:12:30`,
 * which is a confident answer to a question the bridge cannot actually
 * answer: it does not know when you lit the fire, only when it started
 * hearing about it.
 *
 * So the glass shows an elapsed time ONLY when the app says so. This module
 * is the whole of that: the app pushes "the cook is N seconds old right now",
 * the strip renders it, and nothing else in the firmware reads it. Storage,
 * retention, and the sessions API are untouched — the bridge still records
 * continuously whether or not a phone ever confirms a cook.
 *
 * ADJUSTABLE BY DESIGN. Re-setting is not an error, it is the point: you
 * light the fire, you open the app five minutes later, and you tell the
 * bridge the cook is already 5 minutes in rather than starting it at 0:00.
 * The same call moves the clock at any time.
 *
 * NOT PERSISTED. A reboot clears it, and the strip goes back to blank until
 * the app re-confirms. That is deliberate: after a power cut the bridge has
 * no idea whether the cook is still going, and a stale clock counting up
 * through a finished cook is exactly the confident wrong answer this module
 * exists to remove.
 *
 * Pure C11. The state is one word plus a flag, published in an order that
 * lets the render task read it without a lock (see app_ui_cook.c).
 */
#ifndef APP_UI_COOK_H
#define APP_UI_COOK_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 99:59 in seconds. The cap is a LAYOUT constant, not a policy one: the
 * status strip gives hh:mm exactly five columns (07 §7.1), and a clock that
 * reaches 100:00 would push the battery and the alarm glyph sideways. A cook
 * this long means the app forgot to clear it; the display pins rather than
 * reflows. */
#define APP_UI_COOK_MAX_ELAPSED_S (99u * 3600u + 59u * 60u)

/* The app confirms a cook that is `elapsed_s` old AT THIS MOMENT, where
 * `now_uptime_s` is the caller's current uptime. Calling again ADJUSTS the
 * clock. Returns 0, or -1 for an elapsed beyond APP_UI_COOK_MAX_ELAPSED_S,
 * which is refused rather than clamped — a caller sending nonsense should be
 * told, not quietly agreed with. */
int app_ui_cook_set(uint32_t elapsed_s, uint32_t now_uptime_s);

/* The app ended the cook (or never started one). Idempotent. */
void app_ui_cook_clear(void);

/* False when no app has confirmed a cook — which is when the strip draws
 * nothing at all, NOT `--:--`: an unset clock is not an unknown time, it is
 * the absence of a claim. Clamped to [0, MAX]; `elapsed_s` may be NULL. */
bool app_ui_cook_get(uint32_t now_uptime_s, uint32_t *elapsed_s);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_COOK_H */
