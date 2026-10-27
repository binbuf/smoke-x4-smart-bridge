/*
 * ui_button.h - pure-C PRG gesture and boot-hold state machines
 * (design 07 sections 7.4 and 7.7, design 03 section 3.10).
 *
 * The firmware samples GPIO0 every 20 ms and feeds the debounced state machine;
 * host tests inject the same samples with a fake clock. Time is monotonic
 * milliseconds. There is exactly one button: a tap is NEXT, a hold is SELECT.
 *
 * A press that wakes the display is consumed for its whole duration: it wakes
 * the panel but produces no tap and no power-off countdown. The caller passes
 * `consume_press = true` on the sample where the press edge is first seen.
 */
#ifndef SX4_UI_BUTTON_H
#define SX4_UI_BUTTON_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Timing contract from design 07 section 7.4. */
#define UI_BUTTON_SAMPLE_MS 20u
#define UI_BUTTON_DEBOUNCE_MS 30u
#define UI_BUTTON_TAP_MAX_MS 400u
#define UI_BUTTON_HOLD_MS 1500u
#define UI_BUTTON_COUNTDOWN_FROM_MS 400u

typedef enum {
    UI_BUTTON_EVENT_NONE = 0,
    /* The debounced press edge. The caller wakes the display if needed. */
    UI_BUTTON_EVENT_PRESS,
    /* Released before 400 ms: advance to the next page. */
    UI_BUTTON_EVENT_TAP,
    /* Held for ~400 ms: show POWER OFF and start the countdown. */
    UI_BUTTON_EVENT_HOLD_START,
    /* Still held: the countdown digit or "release to confirm" changed. */
    UI_BUTTON_EVENT_HOLD_TICK,
    /* Released between 400 ms and 1.5 s: cancel the power-off. */
    UI_BUTTON_EVENT_HOLD_CANCEL,
    /* Released at/after 1.5 s: commit the power-off. */
    UI_BUTTON_EVENT_HOLD_COMMIT,
} ui_button_event_t;

typedef struct {
    bool raw;               /* last raw sample (true = pressed) */
    bool stable;            /* debounced state (true = pressed) */
    bool candidate;         /* raw value waiting out the debounce window */
    uint64_t candidate_since_ms;
    uint64_t pressed_since_ms;
    bool countdown_shown;
    uint8_t last_countdown_s;
    bool consumed;          /* this press woke the display; suppress gestures */
} ui_button_t;

/*
 * Initialise the machine. If the button is already held at init (the tail of a
 * hold-to-wake confirmation), set `consume_press = true` so releasing it does
 * not fire a tap or power-off.
 */
void ui_button_init(ui_button_t *button, bool pressed, uint64_t now_ms,
                    bool consume_press);

/*
 * Feed one 20 ms sample. `consume_press` is read only when a debounced press
 * edge is emitted: pass true if the display was asleep before this sample.
 * Returns the single highest-priority event for this sample.
 */
ui_button_event_t ui_button_sample(ui_button_t *button, bool pressed,
                                   uint64_t now_ms, bool consume_press);

/* Countdown digit for the power-off overlay: 2 or 1 while held, 0 at/after
 * 1.5 s ("release to confirm") and 0 when no countdown is active. */
uint8_t ui_button_countdown_s(const ui_button_t *button, uint64_t now_ms);

typedef enum {
    UI_BOOT_HOLD_WAIT = 0,
    UI_BOOT_HOLD_CONFIRMED,
    UI_BOOT_HOLD_RELEASED,
} ui_boot_hold_result_t;

typedef struct {
    bool stable;
    bool candidate;
    uint64_t candidate_since_ms;
    uint64_t press_since_ms;
} ui_boot_hold_t;

/*
 * Initialise the post-wake confirmation. `pressed` is the GPIO0 level at entry.
 * If it is already false the first sample reports RELEASED immediately.
 */
void ui_boot_hold_init(ui_boot_hold_t *hold, bool pressed, uint64_t now_ms);

/*
 * Feed one 20 ms sample. RELEASED means the button came up before 1.5 s of
 * continuous hold; the boot path must return to deep sleep without starting
 * BLE or the UI. CONFIRMED means the hold survived the threshold.
 */
ui_boot_hold_result_t ui_boot_hold_sample(ui_boot_hold_t *hold, bool pressed,
                                          uint64_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* SX4_UI_BUTTON_H */
