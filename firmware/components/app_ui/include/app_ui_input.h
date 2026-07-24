/* app_ui_input — the button gesture machine (F11b.7; design 07 §7.4).
 *
 * A pure function of (level, timestamp). No GPIO, no timers, no globals a
 * test cannot reach: a host test feeds a synthesised level trace and reads
 * gestures out.
 *
 * TWO PROPERTIES ARE THE WHOLE POINT, and each has its own test:
 *
 *   1. HOLD ACTIONS COMMIT ON RELEASE, not on reaching the threshold. The
 *      countdown gives a visible cancel path — let go early and nothing
 *      happens. A one-button UI without this is one pocket-press away from
 *      taking a bridge off the network 12 hours into a cook.
 *
 *   2. A WAKE PRESS IS CONSUMED. Waking a sleeping display never also
 *      changes the page, so the user always sees the state they left
 *      before acting on it.
 *
 * The output vocabulary is D3's three-button one even though one button
 * ships, so fitting switches on GPIO47/48 stays a driver and a Kconfig
 * flag rather than a UI rewrite (07 §7.4).
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
#define APP_UI_DOUBLE_GAP_MS 400
#define APP_UI_HOLD_MS 2000
#define APP_UI_FACTORY_MS 10000

typedef enum {
    APP_UI_GESTURE_NONE = 0,
    APP_UI_GESTURE_TAP,
    APP_UI_GESTURE_DOUBLE_TAP,
    /* Emitted on RELEASE after ≥ 2 s — never on reaching the threshold. */
    APP_UI_GESTURE_HOLD,
    /* Emitted on RELEASE after ≥ 10 s. */
    APP_UI_GESTURE_FACTORY,
} app_ui_gesture_t;

/* D3's vocabulary, so the three-button variant is a driver change. */
typedef enum {
    APP_UI_INPUT_NONE = 0,
    APP_UI_INPUT_NEXT,   /* tap */
    APP_UI_INPUT_BACK,   /* double-tap */
    APP_UI_INPUT_SELECT, /* hold */
} app_ui_input_t;

typedef enum {
    APP_UI_BTN_IDLE = 0,
    APP_UI_BTN_PRESSED,
    APP_UI_BTN_TAP_WAIT,
    APP_UI_BTN_HOLD_CONFIRM,
    APP_UI_BTN_FACTORY_ARM,
} app_ui_btn_state_t;

typedef struct {
    uint8_t state; /* app_ui_btn_state_t */
    bool level;    /* debounced logical level: true = pressed */
    bool raw;      /* last raw sample */
    uint32_t raw_since_ms;
    uint32_t press_ms;   /* when the current press was debounced down */
    uint32_t release_ms; /* when the last tap released */
    bool consume_next;   /* the wake press, to be swallowed */
    bool have_pending_tap;
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

/* How long the current press has been held, for the confirm countdown.
 * 0 when nothing is held. */
uint32_t app_ui_input_held_ms(const app_ui_input_t_state *in,
                              uint32_t now_ms);

app_ui_input_t app_ui_input_vocabulary(app_ui_gesture_t g);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_INPUT_H */
