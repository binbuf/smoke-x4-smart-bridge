/* rules.c — the nine device-tier rules of design 09 §9.2, evaluated as
 * instantaneous conditions (F13.3).
 *
 * The file 09 §9.2 names by path: "Evaluated in components/app_alarm/
 * rules.c — pure C, no ESP-IDF, host-tested — on every sample plus a 10 s
 * tick."
 *
 * Two functions, and the split is the point:
 *
 *   app_alarm_rules_eval()     what is true RIGHT NOW
 *   app_alarm_rules_cleared()  what is true ENOUGH to let go of
 *
 * The second is not !first. Hysteresis lives in the gap between them, and
 * it is the feature rather than a detail: a probe oscillating ±1 °F across
 * its target must fire once, not once every 30 seconds all night. An alarm
 * that cries wolf gets muted permanently by the user, which is the real
 * failure (09 §9.2, 10 §10.5).
 *
 * Two abstention rules run through everything below:
 *   - A DETACHED probe contributes no temperature-derived condition. It is
 *     BRIDGE_TEMP_DETACHED here and null at every layer above; there is no
 *     path in this file that turns it into a 0.
 *   - A rule needing a slope and lacking one ABSTAINS. cook_ring's slope
 *     already returns "no value" for a short or gappy window, and a
 *     pit_crash inferred from four samples is worse than no pit_crash.
 */
#include "app_alarm_core.h"

#include <string.h>

/* ── the 09 §9.2 property table ─────────────────────────────────────── */

uint8_t app_alarm_rule_severity(uint8_t rule) {
    switch (rule) {
    case BRIDGE_ALARM_RULE_SMOKE_X_ALARM:
    case BRIDGE_ALARM_RULE_TARGET_REACHED:
    case BRIDGE_ALARM_RULE_PIT_CRASH:
        return BRIDGE_ALARM_SEVERITY_CRITICAL;
    default:
        /* battery_low escalates to critical at its second threshold; the
         * evaluated condition carries the actual value. */
        return BRIDGE_ALARM_SEVERITY_WARNING;
    }
}

bool app_alarm_rule_auto_clear(uint8_t rule) {
    switch (rule) {
    /* "Transient alarms that clear themselves are alarms you sleep
     * through" (09 §9.2). Everything critical latches until acknowledged;
     * system_fault latches because a bridge that restarted mid-cook is
     * exactly the thing a user must be told about even after it looks
     * fine again. */
    case BRIDGE_ALARM_RULE_SMOKE_X_ALARM:
    case BRIDGE_ALARM_RULE_TARGET_REACHED:
    case BRIDGE_ALARM_RULE_PIT_CRASH:
    case BRIDGE_ALARM_RULE_SYSTEM_FAULT:
        return false;
    default:
        return true;
    }
}

bool app_alarm_rule_session_scoped(uint8_t rule) {
    switch (rule) {
    /* Properties of the BRIDGE, not of the cook. Ending a session does not
     * charge the battery or free the flash. */
    case BRIDGE_ALARM_RULE_BASE_LOST:
    case BRIDGE_ALARM_RULE_BATTERY_LOW:
    case BRIDGE_ALARM_RULE_STORAGE_LOW:
    case BRIDGE_ALARM_RULE_SYSTEM_FAULT:
        return false;
    default:
        return true;
    }
}

bool app_alarm_rule_lid_suppressed(uint8_t rule) {
    /* 09 §9.2: "While a lid-open is detected, pit_out_of_band and
     * pit_crash are suppressed for 15 minutes." Every spritz and every
     * wrap otherwise fires the pit alarm. */
    return rule == BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND ||
           rule == BRIDGE_ALARM_RULE_PIT_CRASH;
}

/* ── helpers ────────────────────────────────────────────────────────── */

static bool attached(int16_t f10) {
    return f10 != BRIDGE_TEMP_DETACHED && f10 != BRIDGE_TEMP_INVALID;
}

static int pit_index(const app_alarm_input_t *in) {
    for (int i = 0; i < 4; i++) {
        if (in->role[i] == BRIDGE_PROBE_ROLE_PIT) {
            return i;
        }
    }
    return -1;
}

static bool emit(app_alarm_cond_t *out, int cap, int *n,
                 const app_alarm_cond_t *c) {
    if (*n >= cap) {
        return false;
    }
    out[*n] = *c;
    (*n)++;
    return true;
}

/* ── the evaluator ──────────────────────────────────────────────────── */

int app_alarm_rules_eval(const app_alarm_cfg_t *cfg,
                         const app_alarm_input_t *in, app_alarm_cond_t *out,
                         int cap) {
    int n = 0;
    if (cfg == NULL || in == NULL || out == NULL || cap <= 0) {
        return 0;
    }
    const int pit = pit_index(in);

    /* ── smoke_x_alarm — the BASE STATION's own decision, mirrored ─────
     * Distinct from pit_out_of_band on purpose: this reports the X4's
     * settings, that one reports the user's. They can disagree and both
     * be right (09 §9.2). */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_SMOKE_X_ALARM)) {
        bool any = false;
        for (int i = 0; i < 4; i++) {
            if (!in->base_alarm_armed[i] || !attached(in->temp_f10[i])) {
                continue;
            }
            const int16_t t = in->temp_f10[i];
            if (t > in->base_alarm_high_f10[i] ||
                t < in->base_alarm_low_f10[i]) {
                const app_alarm_cond_t c = {
                    .rule = BRIDGE_ALARM_RULE_SMOKE_X_ALARM,
                    .probe = (uint8_t)(i + 1),
                    .severity = BRIDGE_ALARM_SEVERITY_CRITICAL,
                    .value_f10 = t,
                    .sustain_s = 0,
                    .clear_sustain_s = 0,
                };
                (void)emit(out, cap, &n, &c);
                any = true;
            }
        }
        /* The trailing new_alarm flag is EDGE-triggered — one packet per
         * alarm event (02 Q8, answered by capture). A bare edge with no
         * probe outside its band still means the base beeped, so it is
         * reported against the whole cook rather than swallowed. */
        if (in->new_alarm && !any) {
            const app_alarm_cond_t c = {
                .rule = BRIDGE_ALARM_RULE_SMOKE_X_ALARM,
                .probe = 0,
                .severity = BRIDGE_ALARM_SEVERITY_CRITICAL,
                .value_f10 = 0,
                .sustain_s = 0,
                .clear_sustain_s = 0,
            };
            (void)emit(out, cap, &n, &c);
        }
    }

    /* ── target_reached — a FOOD probe crosses its target upward ─────── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_TARGET_REACHED)) {
        for (int i = 0; i < 4; i++) {
            if (in->role[i] != BRIDGE_PROBE_ROLE_FOOD) {
                continue; /* a pit probe "reaching target" is normal */
            }
            if (!attached(in->temp_f10[i]) || in->target_f10[i] <= 0) {
                continue; /* an unset target is silent, never target 0 */
            }
            if ((int32_t)in->temp_f10[i] >= in->target_f10[i]) {
                const app_alarm_cond_t c = {
                    .rule = BRIDGE_ALARM_RULE_TARGET_REACHED,
                    .probe = (uint8_t)(i + 1),
                    .severity = BRIDGE_ALARM_SEVERITY_CRITICAL,
                    .value_f10 = in->temp_f10[i],
                    .sustain_s = 0,
                    .clear_sustain_s = 0,
                };
                (void)emit(out, cap, &n, &c);
            }
        }
    }

    /* ── pit_out_of_band — OUR band, around the CONFIGURED target ────── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND) &&
        pit >= 0 && attached(in->temp_f10[pit]) && in->target_f10[pit] > 0) {
        const int32_t t = in->temp_f10[pit];
        const int32_t lo = in->target_f10[pit] - cfg->pit_band_f10;
        const int32_t hi = in->target_f10[pit] + cfg->pit_band_f10;
        if (t < lo || t > hi) {
            const app_alarm_cond_t c = {
                .rule = BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND,
                .probe = (uint8_t)(pit + 1),
                .severity = BRIDGE_ALARM_SEVERITY_WARNING,
                .value_f10 = in->temp_f10[pit],
                .sustain_s = cfg->pit_band_sustain_s,
                .clear_sustain_s = cfg->band_rearm_s,
            };
            (void)emit(out, cap, &n, &c);
        }
    }

    /* ── pit_crash — far below target AND falling: the fire is dying ─── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_PIT_CRASH) &&
        pit >= 0 && attached(in->temp_f10[pit]) && in->target_f10[pit] > 0 &&
        in->slope_valid[pit]) {
        const int32_t below = in->target_f10[pit] - (int32_t)in->temp_f10[pit];
        const float slope_f10 = in->slope_f_per_hr[pit] * 10.0f;
        if (below > cfg->pit_crash_below_f10 &&
            slope_f10 < (float)cfg->pit_crash_slope_f10_per_hr) {
            const app_alarm_cond_t c = {
                .rule = BRIDGE_ALARM_RULE_PIT_CRASH,
                .probe = (uint8_t)(pit + 1),
                .severity = BRIDGE_ALARM_SEVERITY_CRITICAL,
                .value_f10 = in->temp_f10[pit],
                .sustain_s = cfg->pit_crash_sustain_s,
                .clear_sustain_s = 0,
            };
            (void)emit(out, cap, &n, &c);
        }
    }

    /* ── probe_detached — attached → detached DURING a session ───────── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_PROBE_DETACHED) &&
        in->session_active) {
        for (int i = 0; i < 4; i++) {
            if (in->probe_seen_attached[i] && !attached(in->temp_f10[i])) {
                const app_alarm_cond_t c = {
                    .rule = BRIDGE_ALARM_RULE_PROBE_DETACHED,
                    .probe = (uint8_t)(i + 1),
                    .severity = BRIDGE_ALARM_SEVERITY_WARNING,
                    .value_f10 = BRIDGE_TEMP_DETACHED,
                    .sustain_s = 0,
                    .clear_sustain_s = 0,
                };
                (void)emit(out, cap, &n, &c);
            }
        }
    }

    /* ── base_lost — the rule that proves the 10 s tick is necessary ───
     * It fires on the ABSENCE of a packet, so it can never be driven by
     * one arriving. */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_BASE_LOST) &&
        in->since_last_packet_s >= cfg->base_lost_s) {
        const app_alarm_cond_t c = {
            .rule = BRIDGE_ALARM_RULE_BASE_LOST,
            .probe = 0,
            .severity = BRIDGE_ALARM_SEVERITY_WARNING,
            .value_f10 = (int16_t)(in->since_last_packet_s > 32767u
                                       ? 32767
                                       : (int)in->since_last_packet_s),
            .sustain_s = 0,
            .clear_sustain_s = 0,
        };
        (void)emit(out, cap, &n, &c);
    }

    /* ── battery_low — two thresholds, one rule ──────────────────────── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_BATTERY_LOW) &&
        in->soc_pct != BRIDGE_SOC_UNKNOWN && in->soc_pct <= 100) {
        if (in->soc_pct <= cfg->batt_warn_pct) {
            const app_alarm_cond_t c = {
                .rule = BRIDGE_ALARM_RULE_BATTERY_LOW,
                .probe = 0,
                .severity = in->soc_pct <= cfg->batt_crit_pct
                                ? BRIDGE_ALARM_SEVERITY_CRITICAL
                                : BRIDGE_ALARM_SEVERITY_WARNING,
                .value_f10 = (int16_t)in->soc_pct,
                .sustain_s = 0,
                .clear_sustain_s = 0,
            };
            (void)emit(out, cap, &n, &c);
        }
    }

    /* ── storage_low ─────────────────────────────────────────────────── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_STORAGE_LOW) &&
        in->storage_valid && in->storage_free_pct <= cfg->storage_free_pct) {
        const app_alarm_cond_t c = {
            .rule = BRIDGE_ALARM_RULE_STORAGE_LOW,
            .probe = 0,
            .severity = BRIDGE_ALARM_SEVERITY_WARNING,
            .value_f10 = (int16_t)in->storage_free_pct,
            .sustain_s = 0,
            .clear_sustain_s = 0,
        };
        (void)emit(out, cap, &n, &c);
    }

    /* ── system_fault — a coredump was found at boot ─────────────────── */
    if (app_alarm_cfg_rule_enabled(cfg, BRIDGE_ALARM_RULE_SYSTEM_FAULT) &&
        in->coredump_present) {
        const app_alarm_cond_t c = {
            .rule = BRIDGE_ALARM_RULE_SYSTEM_FAULT,
            .probe = 0,
            .severity = BRIDGE_ALARM_SEVERITY_WARNING,
            .value_f10 = 0,
            .sustain_s = 0,
            .clear_sustain_s = 0,
        };
        (void)emit(out, cap, &n, &c);
    }

    return n;
}

/* ── the hysteresed inverse ─────────────────────────────────────────── */

bool app_alarm_rules_cleared(const app_alarm_cfg_t *cfg,
                             const app_alarm_input_t *in, uint8_t rule,
                             uint8_t probe) {
    if (cfg == NULL || in == NULL) {
        return false;
    }
    const int i = probe >= 1 && probe <= 4 ? probe - 1 : -1;

    switch (rule) {
    case BRIDGE_ALARM_RULE_TARGET_REACHED: {
        /* THE hysteresis case (09 §9.2): "target_reached cannot re-raise
         * until the probe drops 3 °F below target." A ±1 °F wobble across
         * the threshold never satisfies this, which is why it fires once. */
        if (i < 0 || !attached(in->temp_f10[i]) || in->target_f10[i] <= 0) {
            return false;
        }
        return (int32_t)in->temp_f10[i] <
               in->target_f10[i] - cfg->target_rearm_f10;
    }
    case BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND: {
        /* Back INSIDE the band; the engine additionally requires it to
         * hold for band_rearm_s. */
        if (i < 0 || !attached(in->temp_f10[i]) || in->target_f10[i] <= 0) {
            return false;
        }
        const int32_t t = in->temp_f10[i];
        return t >= in->target_f10[i] - cfg->pit_band_f10 &&
               t <= in->target_f10[i] + cfg->pit_band_f10;
    }
    case BRIDGE_ALARM_RULE_PIT_CRASH: {
        if (i < 0 || !attached(in->temp_f10[i]) || in->target_f10[i] <= 0) {
            return false;
        }
        /* Recovered to within the crash margin, or climbing again. */
        const int32_t below = in->target_f10[i] - (int32_t)in->temp_f10[i];
        if (below <= cfg->pit_crash_below_f10) {
            return true;
        }
        return in->slope_valid[i] && in->slope_f_per_hr[i] > 0.0f;
    }
    case BRIDGE_ALARM_RULE_SMOKE_X_ALARM: {
        if (i < 0) {
            return !in->new_alarm;
        }
        if (!attached(in->temp_f10[i]) || !in->base_alarm_armed[i]) {
            return true;
        }
        const int16_t t = in->temp_f10[i];
        return t <= in->base_alarm_high_f10[i] &&
               t >= in->base_alarm_low_f10[i];
    }
    case BRIDGE_ALARM_RULE_PROBE_DETACHED:
        return i >= 0 && attached(in->temp_f10[i]);
    case BRIDGE_ALARM_RULE_BASE_LOST:
        return in->since_last_packet_s < cfg->base_lost_s;
    case BRIDGE_ALARM_RULE_BATTERY_LOW:
        /* Charged back above the warning threshold plus a 5-point margin,
         * so a pack sitting at exactly 15 % does not chatter. */
        return in->soc_pct != BRIDGE_SOC_UNKNOWN &&
               in->soc_pct > (uint8_t)(cfg->batt_warn_pct + 5u);
    case BRIDGE_ALARM_RULE_STORAGE_LOW:
        return in->storage_valid &&
               in->storage_free_pct > (uint8_t)(cfg->storage_free_pct + 2u);
    case BRIDGE_ALARM_RULE_SYSTEM_FAULT:
        /* Only an acknowledgement and the end of the boot clears it. */
        return !in->coredump_present;
    default:
        return false;
    }
}
