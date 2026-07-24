/* app_ui_model.c — page navigation, context actions, and the sleep policy
 * (F11b.8, F11b.9; design 07 §7.1, §7.2, §7.4).
 */
#include "app_ui_model.h"

#include <stdio.h>
#include <string.h>

static const app_ui_model_ops_t *s_ops_default;

static app_ui_action_t action_for_page(uint8_t page) {
    switch (page) {
    case APP_UI_PAGE_PROBES:
        return APP_UI_ACTION_TOGGLE_UNITS;
    case APP_UI_PAGE_COOK:
        return APP_UI_ACTION_SESSION_TOGGLE;
    case APP_UI_PAGE_NETWORK:
        return APP_UI_ACTION_NET_TOGGLE;
    case APP_UI_PAGE_RADIO:
        return APP_UI_ACTION_RADIO_TOGGLE;
    case APP_UI_PAGE_SYSTEM:
        return APP_UI_ACTION_SAVER_TOGGLE;
    default:
        return APP_UI_ACTION_NONE;
    }
}

const char *app_ui_action_prompt(app_ui_action_t a, const app_ui_state_t *st) {
    switch (a) {
    case APP_UI_ACTION_TOGGLE_UNITS:
        return st != NULL && st->celsius ? "Switch to F?" : "Switch to C?";
    case APP_UI_ACTION_SESSION_TOGGLE:
        return st != NULL && st->session_active ? "Stop this cook?"
                                                : "Start a cook?";
    case APP_UI_ACTION_NET_TOGGLE:
        /* Naming the TARGET is the point: the screen already shows what
         * you are switching from, and this says what you get. */
        return st != NULL && st->net_mode == APP_UI_NET_AP
                   ? "Switch to joining?"
                   : "Switch to hosting?";
    case APP_UI_ACTION_RADIO_TOGGLE:
        return st != NULL && st->paired ? "Unpair the base?"
                                        : "Re-scan for a base?";
    case APP_UI_ACTION_SAVER_TOGGLE:
        return st != NULL && st->saver ? "Turn saver off?" : "Turn saver on?";
    case APP_UI_ACTION_FACTORY_RESET:
        return "ERASE EVERYTHING?";
    default:
        return "";
    }
}

void app_ui_model_init(app_ui_model_t *m, const app_ui_model_ops_t *ops) {
    if (m == NULL) {
        return;
    }
    memset(m, 0, sizeof *m);
    app_ui_input_reset(&m->input);
    /* "It resets to page 1 on boot" (07 §7.2). */
    m->page = APP_UI_PAGE_PROBES;
    m->awake = true;
    s_ops_default = ops;
    if (ops != NULL && ops->panel_power != NULL) {
        ops->panel_power(ops->ctx, true);
    }
}

bool app_ui_model_awake(const app_ui_model_t *m) {
    return m != NULL && m->awake;
}

uint8_t app_ui_model_page(const app_ui_model_t *m) {
    return m != NULL ? m->page : 0;
}

static void set_awake(app_ui_model_t *m, bool on, uint32_t now_ms) {
    if (m->awake == on) {
        return;
    }
    m->awake = on;
    if (on) {
        m->last_activity_ms = now_ms;
    }
    if (s_ops_default != NULL && s_ops_default->panel_power != NULL) {
        s_ops_default->panel_power(s_ops_default->ctx, on);
    }
}

void app_ui_model_wake(app_ui_model_t *m, uint32_t now_ms) {
    if (m == NULL) {
        return;
    }
    m->last_activity_ms = now_ms;
    set_awake(m, true, now_ms);
}

void app_ui_model_on_alarm(app_ui_model_t *m, app_ui_state_t *st,
                           uint32_t now_ms) {
    if (m == NULL) {
        return;
    }
    /* "The current page ... resets to page 1 ... whenever an alarm fires"
     * (07 §7.2), and an alarm outranks anything else on the glass. */
    m->page = APP_UI_PAGE_PROBES;
    m->pending = APP_UI_ACTION_NONE;
    m->alarm_overlay = true;
    m->alarm_shown_ms = now_ms;
    app_ui_model_wake(m, now_ms);
    if (st != NULL) {
        st->page = m->page;
        st->overlay = APP_UI_OVERLAY_ALARM;
    }
}

void app_ui_model_clear_alarm(app_ui_model_t *m, app_ui_state_t *st) {
    if (m == NULL) {
        return;
    }
    m->alarm_overlay = false;
    if (st != NULL && st->overlay == APP_UI_OVERLAY_ALARM) {
        st->overlay = APP_UI_OVERLAY_NONE;
    }
}

static void perform(app_ui_action_t a) {
    if (a != APP_UI_ACTION_NONE && s_ops_default != NULL &&
        s_ops_default->perform != NULL) {
        s_ops_default->perform(s_ops_default->ctx, a);
    }
}

void app_ui_model_tick(app_ui_model_t *m, app_ui_state_t *st, bool pressed,
                       uint32_t now_ms, uint16_t timeout_s) {
    if (m == NULL || st == NULL) {
        return;
    }

    /* A press while asleep wakes and is CONSUMED — waking never also
     * changes the page (07 §7.4). */
    if (!m->awake && pressed) {
        app_ui_input_consume_next(&m->input);
        app_ui_model_wake(m, now_ms);
    }

    const app_ui_gesture_t g =
        app_ui_input_sample(&m->input, pressed, now_ms);
    if (g != APP_UI_GESTURE_NONE || pressed) {
        m->last_activity_ms = now_ms;
    }

    /* ── the hold countdown ────────────────────────────────────────────
     * The overlay appears at the 2 s threshold; the ACTION happens on
     * release. Letting go early cancels, and the glass says so. */
    const uint32_t held = app_ui_input_held_ms(&m->input, now_ms);
    if (held >= APP_UI_HOLD_MS && m->alarm_overlay == false) {
        const app_ui_action_t a = held >= APP_UI_FACTORY_MS
                                      ? APP_UI_ACTION_FACTORY_RESET
                                      : action_for_page(m->page);
        m->pending = a;
        st->overlay = APP_UI_OVERLAY_CONFIRM;
        snprintf(st->confirm_text, sizeof st->confirm_text, "%s",
                 app_ui_action_prompt(a, st));
        /* 3 → 2 → 1 across the second second of the hold. */
        const uint32_t into = held - APP_UI_HOLD_MS;
        const uint32_t remaining = into >= 3000u ? 0u : 3u - (into / 1000u);
        st->confirm_count = (uint8_t)remaining;
    } else if (st->overlay == APP_UI_OVERLAY_CONFIRM) {
        st->overlay = APP_UI_OVERLAY_NONE;
        m->pending = APP_UI_ACTION_NONE;
    }

    switch (g) {
    case APP_UI_GESTURE_TAP:
        if (m->alarm_overlay) {
            /* A tap on the alarm overlay ACKNOWLEDGES it and is consumed:
             * it does not also advance the page. */
            m->alarm_overlay = false;
            st->overlay = APP_UI_OVERLAY_NONE;
            perform(APP_UI_ACTION_ACK_ALARM);
        } else {
            m->page = (uint8_t)((m->page + 1) % APP_UI_PAGE_COUNT);
        }
        break;
    case APP_UI_GESTURE_DOUBLE_TAP:
        m->mark_seq++;
        perform(APP_UI_ACTION_ADD_MARK);
        break;
    case APP_UI_GESTURE_HOLD:
        if (!m->alarm_overlay) {
            perform(action_for_page(m->page));
        }
        st->overlay = APP_UI_OVERLAY_NONE;
        m->pending = APP_UI_ACTION_NONE;
        break;
    case APP_UI_GESTURE_FACTORY:
        /* Three separate KEEP HOLDING prompts before it commits
         * (07 §7.4). Each 10 s hold advances one. */
        m->factory_confirms++;
        if (m->factory_confirms >= APP_UI_FACTORY_CONFIRMS) {
            m->factory_confirms = 0;
            perform(APP_UI_ACTION_FACTORY_RESET);
        }
        st->overlay = APP_UI_OVERLAY_NONE;
        m->pending = APP_UI_ACTION_NONE;
        break;
    default:
        break;
    }

    /* ── the alarm overlay's own timeout ──────────────────────────────
     * "Persists until acknowledged (tap) or 60 s, after which the page
     * reverts but the LED keeps signalling and the alarm stays
     * unacknowledged in the API" (07 §7.3). Nothing here touches alarm
     * state; silencing the screen is not the same as dealing with it. */
    if (m->alarm_overlay &&
        now_ms - m->alarm_shown_ms >= APP_UI_ALARM_OVERLAY_MS) {
        m->alarm_overlay = false;
        if (st->overlay == APP_UI_OVERLAY_ALARM) {
            st->overlay = APP_UI_OVERLAY_NONE;
        }
    }
    if (m->alarm_overlay) {
        st->overlay = APP_UI_OVERLAY_ALARM;
    }

    /* ── sleep (07 §7.1, 01 §1.6) ─────────────────────────────────────
     * ~10 mA, the cheapest single item in the power budget, and what lets
     * an AP-mode bridge get anywhere near a 24 h cook. A timeout of 0 is
     * the documented always-on setting, not a bug. */
    if (timeout_s > 0 && m->awake &&
        now_ms - m->last_activity_ms >= (uint32_t)timeout_s * 1000u) {
        set_awake(m, false, now_ms);
    }

    st->page = m->page;
}
