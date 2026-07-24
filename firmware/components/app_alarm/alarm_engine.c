/* alarm_engine.c — latching, sustain, hysteresis, ack, and the id space
 * (F13.4; design 09 §9.2's lifecycle diagram).
 *
 *      condition true                ack (button / app / BLE)
 *   ────────────────────►  RAISED  ─────────────────────────►  ACKED
 *                           │  │                                 │
 *       condition false     │  └──── auto_clear && cond false ───┤
 *       + hysteresis        │                                    │
 *                           ▼                                    ▼
 *                        CLEARED ◄─────────────────────────── CLEARED
 *
 * With one state the diagram leaves implicit and this file makes explicit:
 * PENDING, between "the condition went true" and "it has held long enough".
 * pit_out_of_band's 10 minutes and pit_crash's 10 minutes live there, and
 * putting them in the lifecycle rather than in the rules is what keeps
 * rules.c a table test.
 *
 * Three properties worth stating because they are the ones a rewrite
 * breaks:
 *
 *   LATCHED. A target_reached that fires at 02:00 is still raised at
 *   07:00. Only an acknowledgement, a re-arm after acknowledgement, or the
 *   end of the session moves it.
 *
 *   ACKNOWLEDGING SILENCES, IT DOES NOT RESOLVE. The alarm stays in the
 *   list and in /status with acked: true; only the LED and the buzzer
 *   stop.
 *
 *   HYSTERESIS ON RE-ARM. The clear condition is rules.c's hysteresed
 *   inverse and not !raise, so a probe oscillating ±1 °F across its target
 *   fires exactly once.
 */
#include "app_alarm_core.h"

#include <string.h>

static bool attached(int16_t f10) {
    return f10 != BRIDGE_TEMP_DETACHED && f10 != BRIDGE_TEMP_INVALID;
}

void app_alarm_engine_reset(app_alarm_engine_t *e) {
    if (e == NULL) {
        return;
    }
    memset(e, 0, sizeof *e);
    e->next_id = 1;
}

static uint8_t alloc_id(app_alarm_engine_t *e) {
    /* u8, monotonic from 1, wrapping to 1 — never 0, which already reads
     * as "no alarm" at three call sites. */
    for (int attempt = 0; attempt < 256; attempt++) {
        if (e->next_id == 0) {
            e->next_id = 1;
        }
        const uint8_t id = e->next_id++;
        bool taken = false;
        for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
            if (e->slots[i].state != APP_ALARM_SLOT_FREE &&
                e->slots[i].id == id) {
                taken = true;
                break;
            }
        }
        if (!taken) {
            return id;
        }
    }
    return 1;
}

static app_alarm_slot_t *find_slot(app_alarm_engine_t *e, uint8_t rule,
                                   uint8_t probe) {
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        app_alarm_slot_t *s = &e->slots[i];
        if (s->state != APP_ALARM_SLOT_FREE && s->rule == rule &&
            s->probe == probe) {
            return s;
        }
    }
    return NULL;
}

static bool push_evt(app_alarm_evt_t *out, int cap, int *n, uint8_t kind,
                     const app_alarm_slot_t *s) {
    if (out == NULL || *n >= cap) {
        return false;
    }
    out[*n].kind = kind;
    out[*n].rule = s->rule;
    out[*n].probe = s->probe;
    out[*n].id = s->id;
    out[*n].severity = s->severity;
    out[*n].value_f10 = s->value_f10;
    (*n)++;
    return true;
}

int app_alarm_engine_step(app_alarm_engine_t *e, const app_alarm_cfg_t *cfg,
                          const app_alarm_input_t *in, app_alarm_evt_t *out,
                          int cap, app_alarm_lid_evt_t *lid_evt) {
    int n = 0;
    if (lid_evt != NULL) {
        *lid_evt = APP_ALARM_LID_NONE;
    }
    if (e == NULL || cfg == NULL || in == NULL) {
        return 0;
    }

    /* The engine owns "has this jack ever been used this session", so no
     * caller has to remember to fill it in. */
    app_alarm_input_t input = *in;
    int pit = -1;
    for (int i = 0; i < 4; i++) {
        if (attached(input.temp_f10[i])) {
            e->seen_attached[i] = true;
        }
        input.probe_seen_attached[i] = e->seen_attached[i];
        if (input.role[i] == BRIDGE_PROBE_ROLE_PIT && pit < 0) {
            pit = i;
        }
    }

    /* ── lid open (09 §9.4) ───────────────────────────────────────────
     * Detection starts the grace window immediately; a second lid open
     * inside an active window EXTENDS it rather than stacking a second
     * one. Escalation ends the grace at once, because the whole point of
     * escalating is to let pit_crash through. */
    if (pit >= 0 && input.sample_fresh) {
        const app_alarm_lid_evt_t ev =
            app_alarm_lid_add(&e->lid, input.now_s, input.temp_f10[pit]);
        if (lid_evt != NULL) {
            *lid_evt = ev;
        }
        if (ev == APP_ALARM_LID_DETECTED) {
            e->lid_grace = true;
            e->lid_grace_until_s = input.now_s + cfg->lid_grace_s;
        } else if (ev == APP_ALARM_LID_ESCALATED) {
            e->lid_grace = false;
            e->lid_grace_until_s = 0;
        }
    }
    if (e->lid_grace && input.now_s >= e->lid_grace_until_s) {
        e->lid_grace = false;
    }

    app_alarm_cond_t conds[APP_ALARM_MAX_ACTIVE];
    const int cn =
        app_alarm_rules_eval(cfg, &input, conds, APP_ALARM_MAX_ACTIVE);

    bool matched[APP_ALARM_MAX_ACTIVE];
    memset(matched, 0, sizeof matched);

    for (int c = 0; c < cn; c++) {
        const app_alarm_cond_t *cond = &conds[c];
        if (e->lid_grace && app_alarm_rule_lid_suppressed(cond->rule)) {
            continue; /* every spritz otherwise fires the pit alarm */
        }
        app_alarm_slot_t *s = find_slot(e, cond->rule, cond->probe);
        if (s == NULL) {
            for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
                if (e->slots[i].state == APP_ALARM_SLOT_FREE) {
                    s = &e->slots[i];
                    break;
                }
            }
            if (s == NULL) {
                /* Saturated. Refuse and count — never overwrite a raised
                 * alarm to make room for a new one. */
                e->dropped++;
                continue;
            }
            memset(s, 0, sizeof *s);
            s->state = APP_ALARM_SLOT_PENDING;
            s->rule = cond->rule;
            s->probe = cond->probe;
            s->held_since_s = input.now_s;
        }
        matched[(int)(s - e->slots)] = true;
        s->severity = cond->severity;
        s->value_f10 = cond->value_f10;
        s->clear_sustain_s = cond->clear_sustain_s;
        s->clearing = false;
        s->clear_since_s = 0;

        if (s->state == APP_ALARM_SLOT_PENDING &&
            input.now_s - s->held_since_s >= cond->sustain_s) {
            s->state = APP_ALARM_SLOT_RAISED;
            s->id = alloc_id(e);
            s->since_s = input.now_s;
            (void)push_evt(out, cap, &n, APP_ALARM_EVT_RAISED, s);
        }
    }

    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        app_alarm_slot_t *s = &e->slots[i];
        if (s->state == APP_ALARM_SLOT_FREE || matched[i]) {
            continue;
        }
        if (s->state == APP_ALARM_SLOT_PENDING) {
            /* The condition went away before it sustained. Nothing was
             * ever raised, so nothing is reported. */
            s->state = APP_ALARM_SLOT_FREE;
            continue;
        }
        /* RAISED or ACKED. A latched rule in RAISED never clears itself —
         * that is what latched MEANS — but once acknowledged it may, so a
         * re-armed target_reached can fire again on the next cut. */
        const bool may_clear =
            app_alarm_rule_auto_clear(s->rule) ||
            s->state == APP_ALARM_SLOT_ACKED;
        if (!may_clear) {
            continue;
        }
        if (!app_alarm_rules_cleared(cfg, &input, s->rule, s->probe)) {
            s->clearing = false;
            s->clear_since_s = 0;
            continue;
        }
        if (!s->clearing) {
            s->clearing = true;
            s->clear_since_s = input.now_s;
        }
        if (input.now_s - s->clear_since_s >= s->clear_sustain_s) {
            (void)push_evt(out, cap, &n, APP_ALARM_EVT_CLEARED, s);
            s->state = APP_ALARM_SLOT_FREE;
        }
    }

    return n;
}

int app_alarm_engine_ack(app_alarm_engine_t *e, uint8_t id,
                         app_alarm_evt_t *out, int cap) {
    int n = 0;
    if (e == NULL || id == 0) {
        return 0;
    }
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        app_alarm_slot_t *s = &e->slots[i];
        if (s->state == APP_ALARM_SLOT_RAISED && s->id == id) {
            s->state = APP_ALARM_SLOT_ACKED;
            (void)push_evt(out, cap, &n, APP_ALARM_EVT_ACKED, s);
        }
    }
    return n;
}

int app_alarm_engine_ack_all(app_alarm_engine_t *e, app_alarm_evt_t *out,
                             int cap) {
    int n = 0;
    if (e == NULL) {
        return 0;
    }
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        app_alarm_slot_t *s = &e->slots[i];
        if (s->state == APP_ALARM_SLOT_RAISED) {
            s->state = APP_ALARM_SLOT_ACKED;
            (void)push_evt(out, cap, &n, APP_ALARM_EVT_ACKED, s);
        }
    }
    return n;
}

int app_alarm_engine_session_end(app_alarm_engine_t *e, app_alarm_evt_t *out,
                                 int cap) {
    int n = 0;
    if (e == NULL) {
        return 0;
    }
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        app_alarm_slot_t *s = &e->slots[i];
        if (s->state == APP_ALARM_SLOT_FREE ||
            !app_alarm_rule_session_scoped(s->rule)) {
            continue;
        }
        if (s->state != APP_ALARM_SLOT_PENDING) {
            (void)push_evt(out, cap, &n, APP_ALARM_EVT_CLEARED, s);
        }
        s->state = APP_ALARM_SLOT_FREE;
    }
    memset(e->seen_attached, 0, sizeof e->seen_attached);
    app_alarm_lid_reset(&e->lid);
    e->lid_grace = false;
    e->lid_grace_until_s = 0;
    return n;
}

int app_alarm_engine_list(const app_alarm_engine_t *e,
                          const app_alarm_slot_t **out, int cap) {
    int n = 0;
    if (e == NULL || out == NULL) {
        return 0;
    }
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE && n < cap; i++) {
        const app_alarm_slot_t *s = &e->slots[i];
        if (s->state != APP_ALARM_SLOT_RAISED &&
            s->state != APP_ALARM_SLOT_ACKED) {
            continue;
        }
        /* Oldest first: the alarm that has been waiting longest is the one
         * a user scanning a list should see at the top. */
        int j = n++;
        while (j > 0 && out[j - 1]->since_s > s->since_s) {
            out[j] = out[j - 1];
            j--;
        }
        out[j] = s;
    }
    return n;
}

bool app_alarm_engine_unacked(const app_alarm_engine_t *e) {
    if (e == NULL) {
        return false;
    }
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        if (e->slots[i].state == APP_ALARM_SLOT_RAISED) {
            return true;
        }
    }
    return false;
}

const app_alarm_slot_t *app_alarm_engine_find(const app_alarm_engine_t *e,
                                              uint8_t id) {
    if (e == NULL || id == 0) {
        return NULL;
    }
    for (int i = 0; i < APP_ALARM_MAX_ACTIVE; i++) {
        const app_alarm_slot_t *s = &e->slots[i];
        if (s->state != APP_ALARM_SLOT_FREE && s->id == id) {
            return s;
        }
    }
    return NULL;
}
