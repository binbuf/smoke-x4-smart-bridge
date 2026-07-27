/* app_ui_input.c — the 07 §7.4 gesture machine: tap = next view, hold =
 * power off. Nothing else lives on the button; the app owns control. */
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
    case APP_UI_GESTURE_HOLD:
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

    if (edge_down) {
        if (in->consume_next) {
            /* THE WAKE PRESS. It is swallowed whole — including the
             * release — so waking the panel never also changes the view. */
            in->state = APP_UI_BTN_IDLE;
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
        in->state = APP_UI_BTN_IDLE;
        if (held >= APP_UI_HOLD_MS) {
            /* Commit on RELEASE. */
            return APP_UI_GESTURE_HOLD;
        }
        if (held < APP_UI_TAP_MAX_MS) {
            /* Emitted immediately — with double-tap gone there is nothing
             * left to disambiguate against, so view-cycling has no lag. */
            return APP_UI_GESTURE_TAP;
        }
        /* Between 400 ms and the hold threshold: released too late to be a
         * tap and too early to be a hold. Deliberately nothing — the
         * countdown was showing and the user let go. */
        return APP_UI_GESTURE_NONE;
    }

    if (in->level && now_ms - in->press_ms >= APP_UI_HOLD_MS) {
        in->state = APP_UI_BTN_HOLD_CONFIRM;
    }
    return APP_UI_GESTURE_NONE;
}
