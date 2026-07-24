/* app_ui_input.c — the 07 §7.4 gesture state machine (F11b.7). */
#include "app_ui_input.h"

#include <string.h>

void app_ui_input_reset(app_ui_input_t_state *in) {
    if (in != NULL) {
        memset(in, 0, sizeof *in);
    }
}

void app_ui_input_consume_next(app_ui_input_t_state *in) {
    if (in != NULL) {
        in->consume_next = true;
    }
}

uint32_t app_ui_input_held_ms(const app_ui_input_t_state *in,
                              uint32_t now_ms) {
    if (in == NULL || !in->level) {
        return 0;
    }
    return now_ms - in->press_ms;
}

app_ui_input_t app_ui_input_vocabulary(app_ui_gesture_t g) {
    switch (g) {
    case APP_UI_GESTURE_TAP:
        return APP_UI_INPUT_NEXT;
    case APP_UI_GESTURE_DOUBLE_TAP:
        return APP_UI_INPUT_BACK;
    case APP_UI_GESTURE_HOLD:
    case APP_UI_GESTURE_FACTORY:
        return APP_UI_INPUT_SELECT;
    default:
        return APP_UI_INPUT_NONE;
    }
}

app_ui_gesture_t app_ui_input_sample(app_ui_input_t_state *in, bool pressed,
                                     uint32_t now_ms) {
    if (in == NULL) {
        return APP_UI_GESTURE_NONE;
    }

    /* ── debounce: a level must hold for 30 ms to count ────────────────
     * GPIO0 is the boot strapping pin and V1.4 measured it clean, but a
     * 25 ms bounce burst must still resolve to nothing. */
    if (pressed != in->raw) {
        in->raw = pressed;
        in->raw_since_ms = now_ms;
    }
    const bool stable = now_ms - in->raw_since_ms >= APP_UI_DEBOUNCE_MS;
    const bool was = in->level;
    if (stable && in->level != in->raw) {
        in->level = in->raw;
        if (in->level) {
            in->press_ms = now_ms;
        }
    }
    const bool edge_down = !was && in->level;
    const bool edge_up = was && !in->level;

    app_ui_gesture_t out = APP_UI_GESTURE_NONE;

    if (edge_down) {
        if (in->consume_next) {
            /* THE WAKE PRESS. It is swallowed whole — including the
             * release — so waking the panel never also advances the page.
             * The state machine goes back to IDLE and this press is
             * simply not a gesture. */
            in->state = APP_UI_BTN_IDLE;
            in->have_pending_tap = false;
            return APP_UI_GESTURE_NONE;
        }
        in->state = APP_UI_BTN_PRESSED;
    }

    if (in->consume_next) {
        if (edge_up) {
            in->consume_next = false;
        }
        return APP_UI_GESTURE_NONE;
    }

    if (edge_up) {
        const uint32_t held = now_ms - in->press_ms;
        if (held >= APP_UI_FACTORY_MS) {
            /* Commit on RELEASE. */
            out = APP_UI_GESTURE_FACTORY;
            in->have_pending_tap = false;
            in->state = APP_UI_BTN_IDLE;
        } else if (held >= APP_UI_HOLD_MS) {
            out = APP_UI_GESTURE_HOLD;
            in->have_pending_tap = false;
            in->state = APP_UI_BTN_IDLE;
        } else if (held < APP_UI_TAP_MAX_MS) {
            if (in->have_pending_tap &&
                now_ms - in->release_ms <= APP_UI_DOUBLE_GAP_MS) {
                out = APP_UI_GESTURE_DOUBLE_TAP;
                in->have_pending_tap = false;
                in->state = APP_UI_BTN_IDLE;
            } else {
                /* Held, not emitted: a tap only becomes a TAP once the
                 * double-tap window has passed without a second press. */
                in->have_pending_tap = true;
                in->release_ms = now_ms;
                in->state = APP_UI_BTN_TAP_WAIT;
            }
        } else {
            /* Between 400 ms and 2 s: released too late to be a tap and
             * too early to be a hold. Deliberately nothing — the
             * countdown was showing and the user let go. */
            in->have_pending_tap = false;
            in->state = APP_UI_BTN_IDLE;
        }
        return out;
    }

    if (in->have_pending_tap && !in->level &&
        now_ms - in->release_ms > APP_UI_DOUBLE_GAP_MS) {
        in->have_pending_tap = false;
        in->state = APP_UI_BTN_IDLE;
        return APP_UI_GESTURE_TAP;
    }

    if (in->level) {
        const uint32_t held = now_ms - in->press_ms;
        if (held >= APP_UI_FACTORY_MS) {
            in->state = APP_UI_BTN_FACTORY_ARM;
        } else if (held >= APP_UI_HOLD_MS) {
            in->state = APP_UI_BTN_HOLD_CONFIRM;
        }
    }
    return APP_UI_GESTURE_NONE;
}
