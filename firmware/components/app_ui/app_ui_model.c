/* app_ui_model.c — view navigation, the power-off hold, and the sleep
 * policy (design 07 §7.1, §7.2, §7.4).
 *
 * The bridge is a passthrough: every control lives in the app, so this owns
 * only which view is on the glass, the power-off confirm, and when the panel
 * sleeps. An alarm is displayed here and never silenced here.
 */
#include "app_ui_model.h"

#include <stdio.h>
#include <string.h>

static const app_ui_model_ops_t *s_ops_default;

const char *app_ui_action_prompt(app_ui_action_t a, const app_ui_state_t *st) {
    (void)st;
    switch (a) {
    case APP_UI_ACTION_POWER_OFF:
        return "Power off?";
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
    /* "It resets to view 1 on boot" (07 §7.2). */
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
    /* "The current view ... resets to view 1 ... whenever an alarm fires"
     * (07 §7.2), and an alarm outranks anything else on the glass. */
    m->page = APP_UI_PAGE_PROBES;
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
     * changes the view (07 §7.4). */
    if (!m->awake && pressed) {
        app_ui_input_consume_next(&m->input);
        app_ui_model_wake(m, now_ms);
    }

    const app_ui_gesture_t g =
        app_ui_input_sample(&m->input, pressed, now_ms);
    if (g != APP_UI_GESTURE_NONE || pressed) {
        m->last_activity_ms = now_ms;
    }

    /* ── the power-off hold ────────────────────────────────────────────
     * The only thing this button commits. The overlay names it once the
     * press is past tap length, counts down to the threshold, and then
     * reads `release to confirm` — holds COMMIT ON RELEASE, so letting go
     * early is the cancel path. */
    const uint32_t held = app_ui_input_held_ms(&m->input, now_ms);
    if (held >= APP_UI_TAP_MAX_MS && !m->alarm_overlay) {
        st->overlay = APP_UI_OVERLAY_CONFIRM;
        snprintf(st->confirm_text, sizeof st->confirm_text, "%s",
                 app_ui_action_prompt(APP_UI_ACTION_POWER_OFF, st));
        /* Whole seconds left before a release would commit; 0 = armed. */
        st->confirm_count =
            held >= APP_UI_HOLD_MS
                ? 0u
                : (uint8_t)((APP_UI_HOLD_MS - held + 999u) / 1000u);
    } else if (st->overlay == APP_UI_OVERLAY_CONFIRM) {
        st->overlay = APP_UI_OVERLAY_NONE;
        st->confirm_count = 0;
    }

    switch (g) {
    case APP_UI_GESTURE_TAP:
        /* The next info view. If the alarm overlay is up it is dismissed —
         * and dismissing is NOT silencing: the alarm stays active and the
         * strip keeps its glyph until the receiver or the app clears it. */
        if (m->alarm_overlay) {
            m->alarm_overlay = false;
            st->overlay = APP_UI_OVERLAY_NONE;
        }
        m->page = (uint8_t)((m->page + 1) % APP_UI_PAGE_COUNT);
        break;
    case APP_UI_GESTURE_HOLD:
        st->overlay = APP_UI_OVERLAY_NONE;
        st->confirm_count = 0;
        /* op_perform enters deep sleep on the device: this never returns. */
        perform(APP_UI_ACTION_POWER_OFF);
        break;
    default:
        break;
    }

    /* ── the alarm overlay's own timeout ──────────────────────────────
     * "Persists until dismissed or 60 s, after which the view reverts but
     * the LED keeps signalling and the alarm stays unsilenced in the API"
     * (07 §7.3). Nothing here touches alarm state; clearing the screen is
     * not the same as dealing with it. */
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
