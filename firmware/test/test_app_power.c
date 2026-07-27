/* test_app_power.c — the battery core on the host (F12.1–F12.4;
 * design 01 §1.3, §1.6, hardware-verified V1.3).
 *
 * Two things this file exists to stop:
 *   1. A 0 mV reading — which is exactly what a divider gated the way
 *      01 §1.3's pseudocode says produces on the real board — rendering
 *      as a FLAT BATTERY rather than as "no data".
 *   2. One bad plateau reading writing a permanently wrong ratio to NVS.
 */
#include "app_power_core.h"
#include "test_util.h"

#include <stdint.h>

/* ── F12.1: the curve and the filter ────────────────────────────────── */

static void test_curve_is_a_lookup_not_a_line(void) {
    /* Both clamps. */
    CHECK_EQ_INT(app_power_soc_from_mv(4300), 100);
    CHECK_EQ_INT(app_power_soc_from_mv(4200), 100);
    CHECK_EQ_INT(app_power_soc_from_mv(3000), 0);
    CHECK_EQ_INT(app_power_soc_from_mv(2500), 0);
    /* 0 mV is not a flat pack — it is no reading at all. */
    CHECK_EQ_INT(app_power_soc_from_mv(0), BRIDGE_SOC_UNKNOWN);
    /* Monotonic across the whole span, with no plateau of "50 %". */
    uint8_t prev = 0;
    for (uint16_t mv = 3000; mv <= 4200; mv += 10) {
        const uint8_t pct = app_power_soc_from_mv(mv);
        CHECK(pct >= prev);
        prev = pct;
    }
    /* The shape that makes it a curve: the top 200 mV is worth far less
     * charge than the middle 200 mV. A linear map gets this wrong in the
     * direction that matters, promising hours that are not there. */
    const int top = app_power_soc_from_mv(4200) - app_power_soc_from_mv(4000);
    const int mid = app_power_soc_from_mv(3900) - app_power_soc_from_mv(3700);
    CHECK(top < mid);
    /* V1.3's measured point: adc 788 mV × 4.9 ≈ 3.86 V — mid-charge, and
     * the arithmetic that ruled ×2.0 out (it would put the pack at
     * 1.58 V, which is impossible). */
    CHECK(app_power_soc_from_mv(3861) > 55);
    CHECK(app_power_soc_from_mv(3861) < 75);
}

static void test_zero_mv_is_unknown_not_flat(void) {
    /* The likeliest wiring mistake on this board, given that V1.3 found
     * the gate INVERTED from the design doc's pseudocode. */
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    CHECK_EQ_INT(p.soc_pct, BRIDGE_SOC_UNKNOWN);
    (void)app_power_core_sample(&p, 0, 0);
    CHECK_EQ_INT(p.soc_pct, BRIDGE_SOC_UNKNOWN);
    CHECK_EQ_INT(p.pack_mv, 0);
    CHECK(!p.charging);
    /* And it does not engage the saver: an unknown battery is not a low
     * one (01 §1.6). */
    CHECK(!app_power_core_saver(&p, false));

    /* A real reading, then the divider disconnected again. */
    (void)app_power_core_sample(&p, 788, 30);
    CHECK(p.soc_pct != BRIDGE_SOC_UNKNOWN);
    (void)app_power_core_sample(&p, 0, 60);
    CHECK_EQ_INT(p.soc_pct, BRIDGE_SOC_UNKNOWN);
}

static void test_default_ratio_is_the_v13_verdict(void) {
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    CHECK_EQ_INT(p.cal_num, 49);
    CHECK_EQ_INT(p.cal_den, 10);
    (void)app_power_core_sample(&p, 788, 0);
    /* 788 × 4.9 = 3861.2 → 3861 mV. V1.3's own arithmetic. */
    CHECK_EQ_INT(p.pack_mv, 3861);
}

static void test_ema_converges_and_never_overshoots(void) {
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    (void)app_power_core_sample(&p, 800, 0);
    CHECK_EQ_INT(p.adc_mv, 800); /* seeded, not averaged from nothing */
    /* A single spike — a Wi-Fi TX burst — moves it by a fraction, not to
     * the spike. */
    (void)app_power_core_sample(&p, 700, 30);
    CHECK(p.adc_mv > 780);
    CHECK(p.adc_mv < 800);
    /* Sustained, it converges. */
    for (int i = 0; i < 200; i++) {
        (void)app_power_core_sample(&p, 700, (uint32_t)(60 + i * 30));
    }
    CHECK(p.adc_mv >= 699 && p.adc_mv <= 701);
}

/* ── F12.2: charging, and the plateau solver ────────────────────────── */

static void test_charging_is_inferred_at_both_boundaries(void) {
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    /* Level branch: 4.15 V and above. 4150/4.9 = 847 adc mV. */
    for (int i = 0; i < 40; i++) {
        (void)app_power_core_sample(&p, 860, (uint32_t)(i * 30));
    }
    CHECK(p.pack_mv >= APP_POWER_CHARGE_MV);
    CHECK(p.charging);

    /* Discharging, well below the level threshold and falling. */
    app_power_core_reset(&p, 0, 0);
    uint16_t adc = 800;
    for (int i = 0; i < 60; i++) {
        (void)app_power_core_sample(&p, adc, (uint32_t)(i * 30));
        if (adc > 740) {
            adc = (uint16_t)(adc - 1);
        }
    }
    CHECK(!p.charging);

    /* Rise branch: a slow climb of more than 30 mV over 10 minutes with
     * the pack nowhere near 4.15 V. */
    app_power_core_reset(&p, 0, 0);
    adc = 760;
    for (int i = 0; i < 40; i++) {
        (void)app_power_core_sample(&p, adc, (uint32_t)(i * 30));
        adc = (uint16_t)(adc + 2);
    }
    CHECK(p.pack_mv < APP_POWER_CHARGE_MV);
    CHECK(p.charging);
}

static void charge_up_to(app_power_t *p, uint16_t from_adc, uint16_t to_adc,
                         uint32_t *t) {
    /* A real charge: the pack CLIMBS, which is what the ratio-independent
     * half of the charging inference reads. The level branch (≥ 4.15 V)
     * cannot be relied on here, because a mis-calibrated ratio is exactly
     * the situation the solver exists to fix — if detecting a charge
     * needed a correct ratio first, the solver could never start. */
    for (uint16_t a = from_adc; a <= to_adc; a++) {
        (void)app_power_core_sample(p, a, *t);
        *t += 30;
    }
    for (int i = 0; i < 8; i++) {
        (void)app_power_core_sample(p, to_adc, *t);
        *t += 30;
    }
}

static void test_plateau_solver_converges_and_then_stops(void) {
    app_power_t p;
    /* Start mis-calibrated at ×4.7 so convergence is visible: the pack
     * really is on its 4.2 V plateau and the stored ratio calls it
     * 4.03 V. A REFINEMENT, which is all this solver claims to be — a
     * ratio wrong enough to read a full pack below 4.0 V does not get
     * fixed here (see APP_POWER_PLATEAU_MIN_MV). */
    app_power_core_reset(&p, 47, 10);
    const uint16_t plateau_adc = 857; /* 857 × 4.9 ≈ 4199 mV */
    uint32_t t = 0;
    charge_up_to(&p, 800, plateau_adc, &t);
    CHECK(p.charging);
    CHECK(p.cal_from_plateau);
    /* It solved for the ratio that puts this reading at 4.2 V exactly. */
    CHECK(p.pack_mv >= 4190 && p.pack_mv <= 4210);
    CHECK_EQ_INT(p.soc_pct, 100);
    const uint16_t num = p.cal_num;
    const uint16_t den = p.cal_den;
    /* And it stops: a converged solver does not keep rewriting NVS. */
    for (int i = 0; i < 60; i++) {
        (void)app_power_core_sample(&p, plateau_adc, t);
        t += 30;
    }
    CHECK_EQ_INT(p.cal_num, num);
    CHECK_EQ_INT(p.cal_den, den);
}

static void test_noisy_plateau_does_not_trigger(void) {
    app_power_t p;
    app_power_core_reset(&p, 47, 10);
    uint32_t t = 0;
    /* Charging — but then wandering by far more than the tolerance every
     * sample. The EMA would smooth this into a flat line, which is
     * exactly why the raw reading is checked too. */
    for (uint16_t a = 800; a <= 857; a++) {
        (void)app_power_core_sample(&p, a, t);
        t += 30;
    }
    CHECK(p.charging);
    for (int i = 0; i < 60; i++) {
        const uint16_t adc = (uint16_t)(857 + (i % 2 ? 12 : -12));
        (void)app_power_core_sample(&p, adc, t);
        t += 30;
    }
    CHECK(!p.cal_from_plateau);
    CHECK_EQ_INT(p.cal_num, 47);
}

static void test_a_flat_reading_far_below_full_is_not_a_plateau(void) {
    /* Found by a failing test rather than by reading the code: a pack
     * held at ~3.6 V while the charging inference was true satisfied
     * "flat + charging" and was solved AS IF it were 4.2 V, calibrating
     * itself to a confident 100 %. APP_POWER_PLATEAU_MIN_MV is the fix,
     * and this is the case that found it. */
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    uint32_t t = 0;
    charge_up_to(&p, 700, 739, &t); /* 739 × 4.9 ≈ 3621 mV */
    CHECK(p.charging);
    for (int i = 0; i < 60; i++) {
        (void)app_power_core_sample(&p, 739, t);
        t += 30;
    }
    CHECK(!p.cal_from_plateau);
    CHECK_EQ_INT(p.cal_num, 49);
    CHECK(p.soc_pct > 20 && p.soc_pct < 40);
}

static void test_an_implausible_solution_is_refused(void) {
    /* The failure this clamp exists for: a solution implying ×2.0 (the
     * ESPHome number) is not a calibration, it is a different board. One
     * bad write is permanent and silent. */
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    /* 4200/2100 = ×2.0, far outside ±20 % of ×4.9. */
    uint32_t t = 0;
    charge_up_to(&p, 2050, 2100, &t);
    for (int i = 0; i < 60; i++) {
        (void)app_power_core_sample(&p, 2100, t);
        t += 30;
    }
    CHECK(!p.cal_from_plateau);
    CHECK_EQ_INT(p.cal_num, 49);
    CHECK_EQ_INT(p.cal_den, 10);

    /* The manual command is clamped by the same rule. */
    app_power_core_reset(&p, 0, 0);
    (void)app_power_core_sample(&p, 800, 0);
    CHECK_EQ_INT(app_power_core_calibrate(&p, 1600), -1); /* ×2.0 */
    CHECK_EQ_INT(p.cal_num, 49);
    CHECK_EQ_INT(app_power_core_calibrate(&p, 0), -1);
}

static void test_manual_calibration_wins_over_the_solver(void) {
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    (void)app_power_core_sample(&p, 800, 0);
    /* A DMM says 4020 mV against 800 mV of ADC → ×5.025, inside the
     * clamp. */
    CHECK_EQ_INT(app_power_core_calibrate(&p, 4020), 0);
    CHECK(p.cal_manual);
    (void)app_power_core_sample(&p, 800, 30);
    CHECK(p.pack_mv >= 4015 && p.pack_mv <= 4025);
    /* Now charge to a plateau: the solver must stand down, because a
     * measured point beats an inferred one. */
    uint32_t t = 60;
    charge_up_to(&p, 800, 857, &t);
    for (int i = 0; i < 60; i++) {
        (void)app_power_core_sample(&p, 857, t);
        t += 30;
    }
    CHECK(!p.cal_from_plateau);
    CHECK_EQ_INT(p.cal_num, 4020);
}

/* ── F12.3: the saver ───────────────────────────────────────────────── */

static void test_saver_hysteresis_and_the_users_setting(void) {
    app_power_t p;
    app_power_core_reset(&p, 0, 0);
    uint32_t t = 0;
    int engaged = 0;
    bool last = false;

/* pack mV → the ADC reading that produces it at the default ×4.9. */
#define ADC_FOR(pack_mv) ((uint16_t)(((pack_mv) * 10 + 24) / 49))
#define FEED(pack_mv, n)                                                   \
    do {                                                                   \
        for (int i_ = 0; i_ < (n); i_++) {                                 \
            (void)app_power_core_sample(&p, ADC_FOR(pack_mv), t);          \
            t += 30;                                                       \
            if (p.saver_auto && !last) {                                   \
                engaged++;                                                 \
            }                                                              \
            last = p.saver_auto;                                           \
        }                                                                  \
    } while (0)

    FEED(3800, 40); /* ~55 % — nowhere near the saver */
    CHECK(!p.saver_auto);
    CHECK_EQ_INT(engaged, 0);

    FEED(3500, 80); /* ~15 % — engages */
    CHECK(p.saver_auto);
    CHECK_EQ_INT(engaged, 1);

    /* Now oscillate across the 20 % line for an hour. Engaging is a CPU
     * frequency change and an advertising-interval change; doing it twice
     * a minute all night is the failure this hysteresis prevents, and it
     * is the same argument F13 makes about alarms. */
    for (int i = 0; i < 120; i++) {
        FEED(i % 2 ? 3560 : 3520, 1);
    }
    CHECK_EQ_INT(engaged, 1);
    CHECK(p.saver_auto);

    /* Charging back to 27 % does NOT release it: the release threshold is
     * 30 %, and that gap is the whole point. */
    FEED(3620, 200);
    CHECK(p.soc_pct > APP_POWER_SAVER_ON_PCT);
    CHECK(p.soc_pct <= APP_POWER_SAVER_OFF_PCT);
    CHECK(p.saver_auto);
    CHECK_EQ_INT(engaged, 1);

    /* Above 30 %, it releases. */
    FEED(3800, 200);
    CHECK(!p.saver_auto);

    /* And the user's sticky setting is untouched by the whole cycle: an
     * automatic release must never undo a deliberate choice. */
    CHECK(app_power_core_saver(&p, true));
    CHECK(!app_power_core_saver(&p, false));
#undef FEED
#undef ADC_FOR
}

/* ── F12.4: the ADC seam and the V1.3 gate order ────────────────────── */

static int g_trace[8];
static int g_trace_n;
static int g_read_rc;
static uint16_t g_read_mv;

static int op_gate(void *ctx, bool enable) {
    (void)ctx;
    if (g_trace_n < 8) {
        g_trace[g_trace_n++] = enable ? 1 : 0;
    }
    return 0;
}
static int op_read(void *ctx, uint16_t *mv) {
    (void)ctx;
    if (g_trace_n < 8) {
        g_trace[g_trace_n++] = 2;
    }
    *mv = g_read_mv;
    return g_read_rc;
}
static int g_delays;
static void op_delay(void *ctx, uint32_t us) {
    (void)ctx;
    CHECK_EQ_INT(us, APP_POWER_SETTLE_US);
    g_delays++;
}

static void test_the_gate_is_driven_high_and_always_released(void) {
    const app_power_adc_ops_t ops = {
        .gate = op_gate, .read_mv = op_read, .delay_us = op_delay};
    g_trace_n = 0;
    g_delays = 0;
    g_read_rc = 0;
    g_read_mv = 788;
    uint16_t mv = 0;
    CHECK_EQ_INT(app_power_read_once(&ops, &mv), 0);
    CHECK_EQ_INT(mv, 788);
    /* V1.3, as an assertion: enable(HIGH) → settle → read → release. */
    CHECK_EQ_INT(g_trace_n, 3);
    CHECK_EQ_INT(g_trace[0], 1);
    CHECK_EQ_INT(g_trace[1], 2);
    CHECK_EQ_INT(g_trace[2], 0);
    CHECK_EQ_INT(g_delays, 1);

    /* A failed conversion still releases the gate: leaving the divider
     * connected costs quiescent current for the rest of the cook. */
    g_trace_n = 0;
    g_read_rc = -1;
    CHECK_EQ_INT(app_power_read_once(&ops, &mv), -1);
    CHECK_EQ_INT(mv, 0);
    CHECK_EQ_INT(g_trace[g_trace_n - 1], 0);

    CHECK_EQ_INT(app_power_read_once(NULL, &mv), -1);
    CHECK_EQ_INT(app_power_read_once(&ops, NULL), -1);
}

static void test_wake_hold_confirms_only_a_sustained_press(void) {
    app_power_wake_hold_t w;

    /* A full 5 s hold confirms — and not one tick sooner. */
    app_power_wake_hold_reset(&w);
    uint32_t t = 0;
    for (; t < APP_POWER_WAKE_HOLD_MS; t += 20) {
        CHECK_EQ_INT(app_power_wake_hold_sample(&w, true, t),
                     APP_POWER_WAKE_PENDING);
    }
    CHECK_EQ_INT(app_power_wake_hold_sample(&w, true, t),
                 APP_POWER_WAKE_CONFIRMED);

    /* Released early → aborted (re-sleep): a pocket-press cannot power the
     * bridge on. */
    app_power_wake_hold_reset(&w);
    (void)app_power_wake_hold_sample(&w, true, 0);
    (void)app_power_wake_hold_sample(&w, true, 2000);
    CHECK_EQ_INT(app_power_wake_hold_sample(&w, false, 2020),
                 APP_POWER_WAKE_ABORTED);

    /* A wake with nothing actually held is not honoured. */
    app_power_wake_hold_reset(&w);
    CHECK_EQ_INT(app_power_wake_hold_sample(&w, false, 0),
                 APP_POWER_WAKE_ABORTED);
}

int main(void) {
    test_curve_is_a_lookup_not_a_line();
    test_zero_mv_is_unknown_not_flat();
    test_default_ratio_is_the_v13_verdict();
    test_ema_converges_and_never_overshoots();
    test_charging_is_inferred_at_both_boundaries();
    test_plateau_solver_converges_and_then_stops();
    test_noisy_plateau_does_not_trigger();
    test_a_flat_reading_far_below_full_is_not_a_plateau();
    test_an_implausible_solution_is_refused();
    test_manual_calibration_wins_over_the_solver();
    test_saver_hysteresis_and_the_users_setting();
    test_the_gate_is_driven_high_and_always_released();
    test_wake_hold_confirms_only_a_sustained_press();
    return test_summary("test_app_power");
}
