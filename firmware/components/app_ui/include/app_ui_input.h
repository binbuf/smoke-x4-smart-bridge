/* app_ui_input — the button gesture machine (design 07 §7.4).
 *
 * A pure function of (level, timestamp). No GPIO, no timers, no globals a
 * test cannot reach: a host test feeds a synthesised level trace and reads
 * gestures out.
 *
 * THE BRIDGE IS A PASSTHROUGH. Every control moved to the app, so the one
 * button carries exactly two meanings and nothing else:
 *
 *   TAP  — the next info view. Emitted on RELEASE, immediately: with no
 *          double-tap left to disambiguate against, a tap no longer waits
 *          out a 400 ms window before it counts.
 *   HOLD — power off. Still COMMITS ON RELEASE, not on reaching the
 *          threshold, so letting go early is a visible cancel path. A
 *          one-button UI without that is one pocket-press away from killing
 *          a bridge 12 hours into a cook.
 *
 * A WAKE PRESS IS CONSUMED: waking a sleeping display never also changes the
 * view, so the user always sees the state they left.
 */
#ifndef APP_UI_INPUT_H
#define APP_UI_INPUT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 07 §7.4: sampled at 20 ms with a 30 ms debounce. */
#define APP_UI_SAMPLE_MS 20
#define APP_UI_DEBOUNCE_MS 30
#define APP_UI_TAP_MAX_MS 400
#define APP_UI_HOLD_MS 2000 /* power off */

typedef enum {
    APP_UI_GESTURE_NONE = 0,
    /* Released under APP_UI_TAP_MAX_MS: the next info view. */
    APP_UI_GESTURE_TAP,
    /* Released after ≥ APP_UI_HOLD_MS: power off. */
    APP_UI_GESTURE_HOLD,
} app_ui_gesture_t;

/* D3's vocabulary, kept so the reserved three-button variant (GPIO47/48)
 * stays a driver change. BACK has no gesture on the one-button board. */
typedef enum {
    APP_UI_INPUT_NONE = 0,
    APP_UI_INPUT_NEXT,   /* tap */
    APP_UI_INPUT_BACK,   /* reserved */
    APP_UI_INPUT_SELECT, /* hold */
} app_ui_input_t;

typedef enum {
    APP_UI_BTN_IDLE = 0,
    APP_UI_BTN_PRESSED,
    APP_UI_BTN_HOLD_CONFIRM,
} app_ui_btn_state_t;

typedef struct {
    uint8_t state; /* app_ui_btn_state_t */
    bool level;    /* debounced logical level: true = pressed */
    bool raw;      /* last raw sample */
    uint32_t raw_since_ms;
    uint32_t press_ms; /* when the current press was debounced down */
    bool consume_next; /* the wake press, to be swallowed */
} app_ui_input_t_state;

void app_ui_input_reset(app_ui_input_t_state *in);

/* Mark the NEXT press as a wake press: it changes nothing else. Called by
 * the model when the panel is asleep and a press arrives. */
void app_ui_input_consume_next(app_ui_input_t_state *in);

/* Feed one 20 ms sample. `pressed` is the raw, active-LOW-corrected level
 * (true = the button is down). Returns the gesture that COMPLETED at this
 * instant, or APP_UI_GESTURE_NONE. */
app_ui_gesture_t app_ui_input_sample(app_ui_input_t_state *in, bool pressed,
                                     uint32_t now_ms);

/* How long the current press has been held, for the power-off countdown.
 * 0 when nothing is held. */
uint32_t app_ui_input_held_ms(const app_ui_input_t_state *in,
                              uint32_t now_ms);

app_ui_input_t app_ui_input_vocabulary(app_ui_gesture_t g);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_INPUT_H */
