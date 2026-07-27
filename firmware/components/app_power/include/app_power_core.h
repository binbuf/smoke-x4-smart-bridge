/* app_power_core — battery measurement as a pure core (F12.1–F12.3;
 * design 01 §1.3, §1.6, hardware-verified V1.3).
 *
 * Pure C11: no ESP-IDF, no ADC, no clock. app_power.c supplies raw
 * millivolts and a timestamp; everything that turns those into a number a
 * user acts on is here and runs on the host.
 *
 * WHAT V1.3 SETTLED, AND WHERE IT CONTRADICTS THE DESIGN DOC.
 * 01 §1.3's pseudocode drives GPIO37 LOW to enable the divider. On the
 * real board it is INVERTED: GPIO37 **HIGH** enables it, LOW disconnects
 * and reads 0 mV. F12 follows the board. The polarity lives in exactly one
 * place — app_power_read_once()'s `gate` op — the same way app_ui's Vext
 * polarity lives only in op_vext_power.
 *
 * WHAT V1.3 DID NOT SETTLE. The ratio is ×4.9 on one inferred point and no
 * DMM reading; a second charge state was never measured. So this core
 * self-calibrates against the 4.2 V full-charge plateau, and REFUSES any
 * solution outside ±20 % of ×4.9 — one bad write to NVS is permanent and
 * silent, and a pack that would need ×2.0 is a different board, not a
 * calibration.
 *
 * AND THE SENTINEL THAT MAKES ALL OF IT SAFE. soc_pct is
 * BRIDGE_SOC_UNKNOWN (255, P3.2) whenever there is no honest reading —
 * including the 0 mV a disconnected divider produces, which is the most
 * likely wiring mistake given the inverted gate. A wrong percentage is
 * worse than no percentage; every consumer has rendered its absence
 * correctly since M4.
 */
#ifndef APP_POWER_CORE_H
#define APP_POWER_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "record_gen.h" /* BRIDGE_SOC_UNKNOWN */

#ifdef __cplusplus
extern "C" {
#endif

/* V1.3: ×4.9 (Heltec forum, 390k/100k), as a rational so NVS holds two
 * u16s and the arithmetic stays integer. */
#define APP_POWER_CAL_NUM_DEFAULT 49
#define APP_POWER_CAL_DEN_DEFAULT 10

/* Li-ion full-charge plateau — the reference the solver calibrates on. */
#define APP_POWER_FULL_MV 4200
/* Charging is INFERRED (no charge-status line on this board): either the
 * filtered pack is at/above this, or it rose by RISE_MV over RISE_S. */
#define APP_POWER_CHARGE_MV 4150
#define APP_POWER_RISE_MV 30
#define APP_POWER_RISE_S 600
/* Plateau: this many consecutive samples within this many mV. */
#define APP_POWER_PLATEAU_SAMPLES 8
#define APP_POWER_PLATEAU_TOL_MV 10
/* And the reading must ALREADY look like a nearly-full pack under the
 * stored ratio. The solver's job is REFINEMENT — V1.3 established ×4.9
 * with real arithmetic — not discovery. Without this, any sustained flat
 * reading while the charging inference happens to be true would be solved
 * as though it were 4.2 V; a pack held at 3.6 V would calibrate itself to
 * "100 %", which is the exact class of confidently-wrong number the
 * SOC_UNKNOWN sentinel exists to avoid. A ratio wrong enough to miss this
 * gate is a bench row, not something to fix silently. */
#define APP_POWER_PLATEAU_MIN_MV 4000
/* The clamp that makes one bad reading survivable. */
#define APP_POWER_CAL_TOLERANCE_PCT 20

/* 01 §1.6's saver profile, with hysteresis so a pack sitting at 20 %
 * does not toggle CPU frequency all night. */
#define APP_POWER_SAVER_ON_PCT 20
#define APP_POWER_SAVER_OFF_PCT 30

/* EMA shift: alpha = 1/8. Sized so a Wi-Fi TX burst does not move the
 * displayed percentage, and a real discharge still shows within minutes
 * at the 30 s cadence. */
#define APP_POWER_EMA_SHIFT 3

typedef struct {
    bool have;              /* a valid reading has been seen */
    uint16_t adc_mv;        /* filtered ADC millivolts, BEFORE the ratio */
    uint16_t pack_mv;       /* after the ratio; 0 when unknown */
    uint8_t soc_pct;        /* 0..100, or BRIDGE_SOC_UNKNOWN */
    bool charging;          /* inferred — see the header comment */
    uint16_t cal_num;
    uint16_t cal_den;
    bool cal_manual;        /* a DMM point was given; the solver defers */
    bool cal_from_plateau;  /* the solver has converged at least once */
    bool saver_auto;        /* the AUTOMATIC half of the saver decision */
    /* rise detection */
    uint16_t ref_mv;
    uint32_t ref_t_s;
    bool have_ref;
    /* plateau tracking */
    uint16_t plateau_mv;
    int plateau_n;
} app_power_t;

void app_power_core_reset(app_power_t *p, uint16_t cal_num, uint16_t cal_den);

/* Feed one raw ADC reading (millivolts at the pin) at `now_s`.
 * adc_mv == 0 means the divider is disconnected — SOC_UNKNOWN, never 0 %.
 * Returns true when a field an observer publishes actually changed. */
bool app_power_core_sample(app_power_t *p, uint16_t adc_mv, uint32_t now_s);

/* The 01 §1.3 discharge-curve lookup. A LOOKUP, not a linear map: a linear
 * map reads "50 %" for most of the cook and then falls off a cliff. */
uint8_t app_power_soc_from_mv(uint16_t pack_mv);

/* 01 §1.3's one-point command (POST /config/device vbat_actual_mv).
 * Takes precedence over anything the plateau solver decided, and disables
 * it: a measured point beats an inferred one. Returns 0 on success, -1
 * when the implied ratio is outside the ±20 % clamp. */
int app_power_core_calibrate(app_power_t *p, uint16_t actual_mv);

/* The effective saver state: the user's sticky setting OR the automatic
 * one. Only the automatic half ever releases, so charging back to 30 %
 * cannot silently undo a deliberate choice. */
bool app_power_core_saver(const app_power_t *p, bool user_saver);

/* ── the ADC seam (F12.4) ────────────────────────────────────────────
 * Host-testable so the V1.3 gate ORDER is a test rather than a comment. */

typedef struct {
    /* GPIO37. `enable` true = divider connected = the line driven HIGH.
     * The glue owns knowing that; the core states intent (V1.3). */
    int (*gate)(void *ctx, bool enable);
    /* One oversampled conversion on ADC1_CH0, in millivolts at the pin. */
    int (*read_mv)(void *ctx, uint16_t *mv);
    void (*delay_us)(void *ctx, uint32_t us);
    void *ctx;
} app_power_adc_ops_t;

#define APP_POWER_SETTLE_US 200

/* Gate on → settle → read → gate off (which saves the divider's quiescent
 * draw). The gate is ALWAYS released, including on a failed read. */
int app_power_read_once(const app_power_adc_ops_t *ops, uint16_t *adc_mv);

/* ── soft-power wake confirm (07 §7.4) ────────────────────────────────
 * A deep-sleep GPIO0 wake reaches our firmware only AFTER the ROM has run;
 * we then require the button held continuously for APP_POWER_WAKE_HOLD_MS
 * before finishing boot. Released early → straight back to deep sleep, so a
 * pocket-press cannot power the bridge on 12 hours from a socket. Pure, so
 * "how long, and does an early release abort?" is a host test rather than a
 * comment — the same discipline as the app_ui gesture machine.
 *
 * The first sample must be pressed=true (the wake press itself); a wake with
 * nothing actually held is an abort, not a wake. */
#define APP_POWER_WAKE_HOLD_MS 5000

typedef enum {
    APP_POWER_WAKE_PENDING = 0, /* still holding, not yet the full window */
    APP_POWER_WAKE_CONFIRMED,   /* held long enough — finish booting */
    APP_POWER_WAKE_ABORTED,     /* released early — re-arm and sleep again */
} app_power_wake_t;

typedef struct {
    bool started;
    uint32_t press_ms;
} app_power_wake_hold_t;

void app_power_wake_hold_reset(app_power_wake_hold_t *w);

/* Feed the button level (true = down) at now_ms; call every ~20 ms from the
 * wake gate. Returns the running decision. */
app_power_wake_t app_power_wake_hold_sample(app_power_wake_hold_t *w,
                                            bool pressed, uint32_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* APP_POWER_CORE_H */
