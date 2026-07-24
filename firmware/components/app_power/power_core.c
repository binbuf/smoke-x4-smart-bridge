/* power_core.c — the discharge curve, the filter, the charging inference,
 * the plateau solver, and the saver hysteresis (F12.1–F12.3).
 */
#include "app_power_core.h"

#include <string.h>

/* 01 §1.3: "State-of-charge is a lookup against a Li-ion discharge curve,
 * not a linear map — a linear map reads 50 % for most of the cook and then
 * falls off a cliff."
 *
 * Single-cell resting/light-load points, descending. Interpolated between
 * neighbours and clamped at both ends. */
static const struct {
    uint16_t mv;
    uint8_t pct;
} k_curve[] = {
    {4200, 100}, {4100, 92}, {4000, 85}, {3950, 78}, {3900, 70},
    {3850, 62},  {3800, 55}, {3750, 48}, {3700, 40}, {3650, 33},
    {3600, 26},  {3550, 20}, {3500, 15}, {3450, 11}, {3400, 8},
    {3350, 5},   {3300, 3},  {3200, 1},  {3000, 0},
};
#define CURVE_N ((int)(sizeof k_curve / sizeof k_curve[0]))

uint8_t app_power_soc_from_mv(uint16_t pack_mv) {
    if (pack_mv == 0) {
        return BRIDGE_SOC_UNKNOWN;
    }
    if (pack_mv >= k_curve[0].mv) {
        return 100;
    }
    if (pack_mv <= k_curve[CURVE_N - 1].mv) {
        return 0;
    }
    for (int i = 1; i < CURVE_N; i++) {
        if (pack_mv >= k_curve[i].mv) {
            const int32_t span = k_curve[i - 1].mv - k_curve[i].mv;
            const int32_t up = k_curve[i - 1].pct - k_curve[i].pct;
            const int32_t over = pack_mv - k_curve[i].mv;
            return (uint8_t)(k_curve[i].pct + (over * up + span / 2) / span);
        }
    }
    return 0;
}

void app_power_core_reset(app_power_t *p, uint16_t cal_num,
                          uint16_t cal_den) {
    if (p == NULL) {
        return;
    }
    memset(p, 0, sizeof *p);
    p->cal_num = cal_num != 0 ? cal_num : APP_POWER_CAL_NUM_DEFAULT;
    p->cal_den = cal_den != 0 ? cal_den : APP_POWER_CAL_DEN_DEFAULT;
    p->soc_pct = BRIDGE_SOC_UNKNOWN;
}

/* Within ±20 % of ×4.9. A solution outside it is not a calibration. */
static bool ratio_plausible(uint32_t num, uint32_t den) {
    if (den == 0 || num == 0) {
        return false;
    }
    /* Compare num/den against 49/10 in integer arithmetic:
     *   |num/den − 4.9| ≤ 0.2 × 4.9  ⇔  |10·num − 49·den| ≤ 9.8·den */
    const int64_t lhs = (int64_t)10 * (int64_t)num - (int64_t)49 * den;
    const int64_t bound = ((int64_t)49 * APP_POWER_CAL_TOLERANCE_PCT *
                           (int64_t)den) /
                          100;
    return (lhs < 0 ? -lhs : lhs) <= bound;
}

int app_power_core_calibrate(app_power_t *p, uint16_t actual_mv) {
    if (p == NULL || !p->have || p->adc_mv == 0 || actual_mv == 0) {
        return -1;
    }
    if (!ratio_plausible(actual_mv, p->adc_mv)) {
        return -1;
    }
    p->cal_num = actual_mv;
    p->cal_den = p->adc_mv;
    /* A measured point beats an inferred one, permanently: the plateau
     * solver stands down once a DMM has spoken. */
    p->cal_manual = true;
    p->cal_from_plateau = false;
    return 0;
}

bool app_power_core_saver(const app_power_t *p, bool user_saver) {
    return user_saver || (p != NULL && p->saver_auto);
}

static uint16_t apply_ratio(const app_power_t *p, uint16_t adc_mv) {
    const uint32_t v =
        ((uint32_t)adc_mv * p->cal_num + p->cal_den / 2) / p->cal_den;
    return (uint16_t)(v > 65535u ? 65535u : v);
}

bool app_power_core_sample(app_power_t *p, uint16_t adc_mv, uint32_t now_s) {
    if (p == NULL) {
        return false;
    }
    const uint8_t prev_soc = p->soc_pct;
    const bool prev_charging = p->charging;
    const bool prev_saver = p->saver_auto;
    const uint16_t prev_mv = p->pack_mv;

    if (adc_mv == 0) {
        /* The divider is disconnected — on this board, the most likely
         * cause is driving GPIO37 the way 01 §1.3's pseudocode says
         * (LOW) rather than the way the board wants (HIGH, V1.3). That is
         * a wiring fault, and it must read as "no battery data", never as
         * a flat pack. */
        p->have = false;
        p->adc_mv = 0;
        p->pack_mv = 0;
        p->soc_pct = BRIDGE_SOC_UNKNOWN;
        p->charging = false;
        p->plateau_n = 0;
        p->saver_auto = false; /* an unknown battery is not a low one */
        return prev_soc != BRIDGE_SOC_UNKNOWN || prev_charging ||
               prev_saver;
    }

    if (!p->have) {
        p->adc_mv = adc_mv;
        p->have = true;
    } else {
        /* EMA, alpha = 1/8, in integers. */
        const int32_t diff = (int32_t)adc_mv - (int32_t)p->adc_mv;
        p->adc_mv = (uint16_t)((int32_t)p->adc_mv +
                               (diff >> APP_POWER_EMA_SHIFT) +
                               (diff > 0 && (diff & 7) != 0 ? 1 : 0));
    }
    p->pack_mv = apply_ratio(p, p->adc_mv);
    p->soc_pct = app_power_soc_from_mv(p->pack_mv);

    /* ── charging, inferred ──────────────────────────────────────────── */
    if (!p->have_ref || now_s < p->ref_t_s) {
        p->ref_mv = p->pack_mv;
        p->ref_t_s = now_s;
        p->have_ref = true;
    }
    bool rising = false;
    if (now_s - p->ref_t_s >= APP_POWER_RISE_S) {
        rising = (int32_t)p->pack_mv - (int32_t)p->ref_mv >=
                 APP_POWER_RISE_MV;
        p->ref_mv = p->pack_mv;
        p->ref_t_s = now_s;
        p->charging = rising || p->pack_mv >= APP_POWER_CHARGE_MV;
    } else {
        p->charging = p->charging || p->pack_mv >= APP_POWER_CHARGE_MV;
        if (p->pack_mv < APP_POWER_CHARGE_MV && !rising &&
            p->pack_mv + APP_POWER_RISE_MV < p->ref_mv) {
            /* Falling well below the reference: whatever we thought, it
             * is discharging now. */
            p->charging = false;
        }
    }

    /* ── plateau self-calibration (F12.2) ───────────────────────────────
     * The answer to V1.3's missing second DMM point. Only while charging,
     * only on a genuinely flat reading, and only when the solution is
     * plausible — one bad write is permanent and silent. */
    if (p->cal_manual || !p->charging) {
        p->plateau_n = 0;
    } else {
        const int32_t d = (int32_t)p->pack_mv - (int32_t)p->plateau_mv;
        /* The RAW reading has to be steady too, not just the filtered one.
         * An EMA turns noise into a flat line by construction, so testing
         * only the filtered value would let a wandering pack look like a
         * plateau and write a ratio solved from an average. */
        const int32_t raw = (int32_t)apply_ratio(p, adc_mv);
        const int32_t dr = raw - (int32_t)p->pack_mv;
        const bool steady = (d < 0 ? -d : d) <= APP_POWER_PLATEAU_TOL_MV &&
                            (dr < 0 ? -dr : dr) <= APP_POWER_PLATEAU_TOL_MV;
        if (p->plateau_n > 0 && steady) {
            p->plateau_n++;
        } else {
            p->plateau_mv = p->pack_mv;
            p->plateau_n = 1;
        }
        if (p->plateau_n >= APP_POWER_PLATEAU_SAMPLES &&
            !p->cal_from_plateau &&
            p->pack_mv >= APP_POWER_PLATEAU_MIN_MV &&
            ratio_plausible(APP_POWER_FULL_MV, p->adc_mv)) {
            p->cal_num = APP_POWER_FULL_MV;
            p->cal_den = p->adc_mv;
            p->cal_from_plateau = true;
            p->pack_mv = apply_ratio(p, p->adc_mv);
            p->soc_pct = app_power_soc_from_mv(p->pack_mv);
        }
    }

    /* ── the saver's automatic half (F12.3) ─────────────────────────── */
    if (p->soc_pct == BRIDGE_SOC_UNKNOWN) {
        p->saver_auto = false;
    } else if (!p->saver_auto) {
        if (p->soc_pct < APP_POWER_SAVER_ON_PCT) {
            p->saver_auto = true;
        }
    } else if (p->soc_pct > APP_POWER_SAVER_OFF_PCT) {
        p->saver_auto = false;
    }

    return p->soc_pct != prev_soc || p->charging != prev_charging ||
           p->saver_auto != prev_saver || p->pack_mv != prev_mv;
}

int app_power_read_once(const app_power_adc_ops_t *ops, uint16_t *adc_mv) {
    if (ops == NULL || ops->gate == NULL || ops->read_mv == NULL ||
        adc_mv == NULL) {
        return -1;
    }
    *adc_mv = 0;
    /* HIGH connects the divider (V1.3 — inverted from 01 §1.3's own
     * pseudocode). This is the only place in the firmware that knows. */
    if (ops->gate(ops->ctx, true) != 0) {
        return -1;
    }
    if (ops->delay_us != NULL) {
        ops->delay_us(ops->ctx, APP_POWER_SETTLE_US);
    }
    uint16_t mv = 0;
    const int rc = ops->read_mv(ops->ctx, &mv);
    /* Released even on failure: leaving the divider connected costs
     * quiescent current for the rest of the cook. */
    (void)ops->gate(ops->ctx, false);
    if (rc != 0) {
        return -1;
    }
    *adc_mv = mv;
    return 0;
}
