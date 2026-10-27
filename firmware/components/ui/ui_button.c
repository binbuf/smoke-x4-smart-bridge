#include "ui_button.h"

#include <stddef.h>

static uint64_t elapsed_since(uint64_t now_ms, uint64_t since_ms) {
    return now_ms >= since_ms ? now_ms - since_ms : 0u;
}

void ui_button_init(ui_button_t *button, bool pressed, uint64_t now_ms,
                    bool consume_press) {
    if (button == NULL) {
        return;
    }
    button->raw = pressed;
    button->stable = pressed;
    button->candidate = pressed;
    button->candidate_since_ms = now_ms;
    button->pressed_since_ms = now_ms;
    button->countdown_shown = false;
    button->last_countdown_s = 0;
    button->consumed = pressed && consume_press;
}

uint8_t ui_button_countdown_s(const ui_button_t *button, uint64_t now_ms) {
    if (button == NULL || !button->stable || button->consumed) {
        return 0;
    }
    uint64_t elapsed = elapsed_since(now_ms, button->pressed_since_ms);
    if (elapsed < UI_BUTTON_COUNTDOWN_FROM_MS || elapsed >= UI_BUTTON_HOLD_MS) {
        return 0;
    }
    uint64_t remaining = (uint64_t)UI_BUTTON_HOLD_MS - elapsed;
    uint64_t seconds = (remaining + 999u) / 1000u;
    if (seconds > 9u) {
        seconds = 9u;
    }
    return (uint8_t)seconds;
}

/* Update the debounced level. Returns true when `stable` changed. */
static bool update_debounce(ui_button_t *button, bool pressed,
                            uint64_t now_ms) {
    if (pressed != button->candidate) {
        button->candidate = pressed;
        button->candidate_since_ms = now_ms;
        return false;
    }
    if (pressed == button->stable) {
        return false;
    }
    if (elapsed_since(now_ms, button->candidate_since_ms) <
        UI_BUTTON_DEBOUNCE_MS) {
        return false;
    }
    button->stable = pressed;
    return true;
}

ui_button_event_t ui_button_sample(ui_button_t *button, bool pressed,
                                   uint64_t now_ms, bool consume_press) {
    if (button == NULL) {
        return UI_BUTTON_EVENT_NONE;
    }
    button->raw = pressed;
    bool changed = update_debounce(button, pressed, now_ms);

    if (changed && button->stable) {
        /* Press edge: timing starts at the raw edge, not at debounce expiry. */
        button->pressed_since_ms = button->candidate_since_ms;
        button->countdown_shown = false;
        button->last_countdown_s = 0;
        button->consumed = consume_press;
        return UI_BUTTON_EVENT_PRESS;
    }

    if (changed && !button->stable) {
        uint64_t released_at = button->candidate_since_ms;
        uint64_t held_ms = elapsed_since(released_at, button->pressed_since_ms);
        bool consumed = button->consumed;
        button->countdown_shown = false;
        button->last_countdown_s = 0;
        button->consumed = false;
        if (consumed) {
            return UI_BUTTON_EVENT_NONE;
        }
        if (held_ms >= UI_BUTTON_HOLD_MS) {
            return UI_BUTTON_EVENT_HOLD_COMMIT;
        }
        if (held_ms >= UI_BUTTON_TAP_MAX_MS) {
            return UI_BUTTON_EVENT_HOLD_CANCEL;
        }
        return UI_BUTTON_EVENT_TAP;
    }

    if (!button->stable || button->consumed) {
        return UI_BUTTON_EVENT_NONE;
    }

    uint64_t held_ms = elapsed_since(now_ms, button->pressed_since_ms);
    if (held_ms < UI_BUTTON_COUNTDOWN_FROM_MS) {
        return UI_BUTTON_EVENT_NONE;
    }
    uint8_t countdown = ui_button_countdown_s(button, now_ms);
    if (!button->countdown_shown) {
        button->countdown_shown = true;
        button->last_countdown_s = countdown;
        return UI_BUTTON_EVENT_HOLD_START;
    }
    if (countdown != button->last_countdown_s) {
        button->last_countdown_s = countdown;
        return UI_BUTTON_EVENT_HOLD_TICK;
    }
    return UI_BUTTON_EVENT_NONE;
}

void ui_boot_hold_init(ui_boot_hold_t *hold, bool pressed, uint64_t now_ms) {
    if (hold == NULL) {
        return;
    }
    hold->stable = pressed;
    hold->candidate = pressed;
    hold->candidate_since_ms = now_ms;
    hold->press_since_ms = now_ms;
}

ui_boot_hold_result_t ui_boot_hold_sample(ui_boot_hold_t *hold, bool pressed,
                                          uint64_t now_ms) {
    if (hold == NULL) {
        return UI_BOOT_HOLD_RELEASED;
    }
    /* The button is held through the reset that woke us. Any sample that shows
     * it up before the threshold is an early release: go back to sleep without
     * trying to debounce a wake that is already over. */
    if (!pressed) {
        return UI_BOOT_HOLD_RELEASED;
    }

    if (pressed != hold->candidate) {
        hold->candidate = pressed;
        hold->candidate_since_ms = now_ms;
    } else if (pressed != hold->stable &&
               elapsed_since(now_ms, hold->candidate_since_ms) >=
                   UI_BUTTON_DEBOUNCE_MS) {
        hold->stable = pressed;
        if (pressed) {
            hold->press_since_ms = hold->candidate_since_ms;
        }
    }

    if (!hold->stable) {
        return UI_BOOT_HOLD_RELEASED;
    }
    if (elapsed_since(now_ms, hold->press_since_ms) >= UI_BUTTON_HOLD_MS) {
        return UI_BOOT_HOLD_CONFIRMED;
    }
    return UI_BOOT_HOLD_WAIT;
}
