/*
 * ui_sleep.h - display-sleep state machine shared by the firmware task and the
 * host tests (design 07 sections 7.1/7.4, design 01 section 1.5).
 *
 * Time is injected as monotonic milliseconds. The page number is owned by the
 * same view object and is never changed by sleeping or waking, which is the
 * "wake without changing the page" rule. A waking press is consumed by the
 * caller (T23) and only calls ui_view_wake(); it must not also call
 * ui_view_next_page().
 */
#ifndef SX4_UI_SLEEP_H
#define SX4_UI_SLEEP_H

#include <stdbool.h>
#include <stdint.h>

#include "ui_render.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Timeout values accepted from the app (bridge_config). 0 = never sleep. */
#define UI_TIMEOUT_NEVER 0u
#define UI_TIMEOUT_30S 30u
#define UI_TIMEOUT_60S 60u
#define UI_TIMEOUT_120S 120u

typedef struct {
    ui_page_t page;
    bool asleep;
    uint16_t timeout_s; /* 0 = never */
    uint64_t last_activity_ms;
} ui_view_t;

void ui_view_init(ui_view_t *view, ui_page_t page, uint16_t timeout_s,
                  uint64_t now_ms);

/* Any user/connection activity keeps the panel awake and restarts the timer. */
void ui_view_activity(ui_view_t *view, uint64_t now_ms);

/* Advance to the next visible page. Billows is skipped until detected. */
ui_page_t ui_view_next_page(ui_view_t *view, bool billows_visible);

/* Jump to a page (tap/overlay dismissal paths use this). Stays asleep if the
 * display is asleep; the caller wakes first. */
void ui_view_set_page(ui_view_t *view, ui_page_t page);

/*
 * Returns true exactly on the transition to asleep. Sleeping is >= timeout_s;
 * a timeout of 0 never enters sleep.
 */
bool ui_view_tick(ui_view_t *view, uint64_t now_ms);

/* Wake the panel and restart the timeout. Returns true if it was asleep. */
bool ui_view_wake(ui_view_t *view, uint64_t now_ms);

/* Milliseconds until the next tick matters, or UINT64_MAX while asleep/never. */
uint64_t ui_view_next_tick_ms(const ui_view_t *view, uint64_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* SX4_UI_SLEEP_H */
