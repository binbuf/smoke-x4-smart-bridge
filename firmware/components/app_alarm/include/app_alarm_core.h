/* app_alarm_core — the device-tier alarm engine as a pure core (F13.1,
 * F13.3–F13.5; design 09 §9.1, §9.2, §9.4).
 *
 * Pure C11: no ESP-IDF headers, no clock of its own, no globals a test
 * cannot reach. Everything that decides whether to wake somebody at 3 a.m.
 * lives here and runs on the host; app_alarm.c only supplies events, a
 * clock, and the four ops the core cannot know.
 *
 * THE CLAIM THIS FILE EXISTS TO MAKE (09 §9.1): the device tier runs with
 * no phone in existence. A phone that ran out of battery is not a reason
 * for a $200 brisket to overcook.
 *
 * Three separable pieces, deliberately:
 *
 *   rules.c        instantaneous conditions — "is this true right now"
 *   alarm_lid.c    the 09 §9.4 lid-open detector, ported from the settled
 *                  Dart original in app/lib/domain/analysis/lid_open.dart
 *   alarm_engine.c latching, sustain, hysteresis, ack, and the id space
 *
 * Splitting "is it true" from "should it fire" is what makes hysteresis
 * testable: the rules are a table test, the lifecycle is a trace test, and
 * neither has to fake the other.
 */
#ifndef APP_ALARM_CORE_H
#define APP_ALARM_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "record_gen.h" /* bridge_alarm_rule_t, TEMP_/SOC_ sentinels */

#ifdef __cplusplus
extern "C" {
#endif

/* Nine rules (09 §9.2), generated as bridge_alarm_rule_t. */
#define APP_ALARM_RULE_COUNT 9

/* One slot per live (rule, probe) pair. Worst case is target_reached and
 * probe_detached and smoke_x_alarm on four probes each, plus the four
 * device-scoped rules = 16. Sized to hold it rather than to hope. */
#define APP_ALARM_MAX_ACTIVE 16

/* ── Configuration (F13.1) ────────────────────────────────────────────
 * Persisted as the APP_CONFIG_ALARM_RULES blob. Device-private: 06 §6.2
 * specifies /config/alarms as JSON and no BLE characteristic carries it,
 * so the byte layout is deliberately NOT in protocol/records.yaml.
 *
 * The layout is append-only and version-tagged. Decoding keeps the fields
 * it understands and defaults the rest — a firmware downgrade that meets a
 * newer blob must not silently disable every alarm. */

#define APP_ALARM_CFG_VERSION 1
#define APP_ALARM_CFG_MAX_BYTES 64 /* the NVS blob's capacity */

typedef struct {
    /* Bit per bridge_alarm_rule_t; all nine on by default (09 §9.2). */
    uint16_t enabled_mask;
    /* pit_out_of_band: ±band around the CONFIGURED target, and how long it
     * must hold. The base station's own band drives smoke_x_alarm instead —
     * the two can disagree and both be right. */
    int16_t pit_band_f10;       /* 250 = ±25 °F */
    uint16_t pit_band_sustain_s; /* 600 = 10 min */
    /* pit_crash: more than this far below target AND falling faster than
     * this, for this long. "The fire is dying." */
    int16_t pit_crash_below_f10;          /* 500 = 50 °F */
    int16_t pit_crash_slope_f10_per_hr;   /* -100 = -10 °F/hr */
    uint16_t pit_crash_sustain_s;         /* 600 */
    uint16_t base_lost_s;                 /* 600 */
    uint8_t batt_warn_pct;                /* 15 */
    uint8_t batt_crit_pct;                /* 5 */
    uint8_t storage_free_pct;             /* 2 */
    /* Hysteresis. THE FEATURE, not a detail: a probe oscillating ±1 °F
     * across its target fires once (09 §9.2, 10 §10.5). */
    int16_t target_rearm_f10; /* 30 = 3 °F below target before re-arming */
    uint16_t band_rearm_s;    /* 300 = back inside the band for 5 min */
    uint16_t lid_grace_s;     /* 900 = pit alarms suppressed for 15 min */
} app_alarm_cfg_t;

void app_alarm_cfg_defaults(app_alarm_cfg_t *out);

/* Returns bytes written, or -1 when cap is too small. */
int app_alarm_cfg_encode(const app_alarm_cfg_t *cfg, uint8_t *buf, size_t cap);

/* Never fails: a NULL, empty, truncated, or future-version buffer yields
 * defaults for everything it cannot read. Returns the number of bytes it
 * actually consumed. */
int app_alarm_cfg_decode(const void *buf, size_t len, app_alarm_cfg_t *out);

bool app_alarm_cfg_rule_enabled(const app_alarm_cfg_t *cfg, uint8_t rule);

/* ── Rule properties (09 §9.2's table) ──────────────────────────────── */

/* Default severity. battery_low escalates to critical at its second
 * threshold, so the evaluated condition carries the actual value. */
uint8_t app_alarm_rule_severity(uint8_t rule);
/* Whether the alarm resolves itself once its condition goes away.
 * false = latched until acknowledged; "transient alarms that clear
 * themselves are alarms you sleep through" (09 §9.2). */
bool app_alarm_rule_auto_clear(uint8_t rule);
/* Whether ending the session clears it. base_lost, battery_low,
 * storage_low and system_fault are properties of the BRIDGE, not of the
 * cook, and survive. */
bool app_alarm_rule_session_scoped(uint8_t rule);
/* Whether the lid-open grace window suppresses it (09 §9.2). */
bool app_alarm_rule_lid_suppressed(uint8_t rule);

/* ── Evaluator input (F13.3) ───────────────────────────────────────── */

typedef struct {
    /* Canonical tenths °F; BRIDGE_TEMP_DETACHED / _INVALID survive here.
     * There is no code path in this file that can produce a 0 for a
     * detached probe — the invariant the whole project has held since M0. */
    int16_t temp_f10[4];
    uint8_t role[4];      /* bridge_probe_role_t */
    int32_t target_f10[4]; /* 0 = unset; an unset target is silent */
    /* The base station's own alarm configuration, straight off the wire. */
    bool base_alarm_armed[4];
    int16_t base_alarm_low_f10[4];
    int16_t base_alarm_high_f10[4];
    /* The packet's edge-triggered new_alarm flag (02 Q8). */
    bool new_alarm;
    /* From cook_ring_slope_f_per_hr(): a rule with no slope ABSTAINS. */
    bool slope_valid[4];
    float slope_f_per_hr[4];
    /* Set by the engine: this probe has been attached at some point in
     * this session, so unplugging it now is an event rather than a
     * never-used jack. */
    bool probe_seen_attached[4];

    uint32_t since_last_packet_s;
    uint8_t soc_pct;          /* BRIDGE_SOC_UNKNOWN = no battery data */
    uint8_t storage_free_pct;
    bool storage_valid;
    bool coredump_present;
    bool session_active;
    /* True when this call carries a NEWLY decoded state message. The
     * §9.4 lid window is defined over samples, and the 10 s tick is the
     * absence of one — advancing the detector on a tick would feed it the
     * same temperature at a new timestamp and quietly widen the window. */
    bool sample_fresh;
    uint32_t now_s; /* monotonic seconds; the core never reads a clock */
} app_alarm_input_t;

typedef struct {
    uint8_t rule;     /* bridge_alarm_rule_t */
    uint8_t probe;    /* 0 = whole cook, 1..4 */
    uint8_t severity; /* bridge_alarm_severity_t */
    int16_t value_f10;
    uint16_t sustain_s;       /* must hold this long before it RAISES */
    uint16_t clear_sustain_s; /* and this long before it CLEARS */
} app_alarm_cond_t;

/* Every raise condition true at this instant. Returns the count written
 * (capped at `cap`). Order is stable: rule ascending, then probe. */
int app_alarm_rules_eval(const app_alarm_cfg_t *cfg,
                         const app_alarm_input_t *in, app_alarm_cond_t *out,
                         int cap);

/* Whether an existing (rule, probe) alarm's CLEAR condition holds — the
 * hysteresed inverse, not simply !raise. target_reached needs the probe
 * 3 °F below target; pit_out_of_band needs it back inside the band. */
bool app_alarm_rules_cleared(const app_alarm_cfg_t *cfg,
                             const app_alarm_input_t *in, uint8_t rule,
                             uint8_t probe);

/* ── Lid-open detector (F13.5; 09 §9.4) ─────────────────────────────
 * A direct port of app/lib/domain/analysis/lid_open.dart. Any constant
 * that differs between the two is a defect in one of them. */

#define APP_ALARM_LID_DROP_F10 250      /* ≥ 25 °F */
#define APP_ALARM_LID_WINDOW_S 180      /* within any 3-minute window */
#define APP_ALARM_LID_CONFIRM_S 1200    /* recovery deadline: 20 min */
#define APP_ALARM_LID_RECOVER_NUM 1     /* ≥ 50 % of the drop */
#define APP_ALARM_LID_RECOVER_DEN 2
#define APP_ALARM_LID_RING 16

typedef enum {
    APP_ALARM_LID_NONE = 0,
    APP_ALARM_LID_DETECTED,  /* start the grace window NOW */
    APP_ALARM_LID_CONFIRMED, /* it recovered — it was a lid open */
    APP_ALARM_LID_ESCALATED, /* it did not — the fire is dying */
} app_alarm_lid_evt_t;

typedef struct {
    struct {
        uint32_t t;
        int16_t f10;
    } recent[APP_ALARM_LID_RING];
    int n;
    bool active;
    int16_t reference_f10;
    int16_t low_f10;
    uint32_t detect_t;
} app_alarm_lid_t;

void app_alarm_lid_reset(app_alarm_lid_t *l);
/* Feed pit samples in order. A detached pit is skipped, not treated as a
 * 32768-degree drop. */
app_alarm_lid_evt_t app_alarm_lid_add(app_alarm_lid_t *l, uint32_t t,
                                      int16_t pit_f10);
bool app_alarm_lid_pending(const app_alarm_lid_t *l);

/* ── The latching engine (F13.4) ──────────────────────────────────── */

typedef enum {
    APP_ALARM_SLOT_FREE = 0,
    APP_ALARM_SLOT_PENDING, /* condition true, sustain not yet met */
    APP_ALARM_SLOT_RAISED,
    APP_ALARM_SLOT_ACKED,
} app_alarm_slot_state_t;

typedef struct {
    uint8_t state; /* app_alarm_slot_state_t */
    uint8_t rule;
    uint8_t probe;
    uint8_t id; /* 1..255, never 0 */
    uint8_t severity;
    int16_t value_f10;
    uint32_t held_since_s;  /* PENDING: first instant the condition held */
    uint32_t since_s;       /* RAISED: when it fired */
    uint32_t clear_since_s; /* first instant the clear condition held */
    uint16_t clear_sustain_s; /* carried from the condition that raised it */
    bool clearing;
} app_alarm_slot_t;

typedef enum {
    APP_ALARM_EVT_RAISED = 0,
    APP_ALARM_EVT_CLEARED,
    APP_ALARM_EVT_ACKED,
} app_alarm_evt_kind_t;

typedef struct {
    uint8_t kind; /* app_alarm_evt_kind_t */
    uint8_t rule;
    uint8_t probe;
    uint8_t id;
    uint8_t severity;
    int16_t value_f10;
} app_alarm_evt_t;

typedef struct {
    app_alarm_slot_t slots[APP_ALARM_MAX_ACTIVE];
    app_alarm_lid_t lid;
    uint8_t next_id;
    bool seen_attached[4];
    /* Lid-open grace: pit alarms suppressed until this instant. */
    bool lid_grace;
    uint32_t lid_grace_until_s;
    /* Diagnostics — a saturated table must be visible, never silent. */
    uint32_t dropped;
} app_alarm_engine_t;

void app_alarm_engine_reset(app_alarm_engine_t *e);

/* One evaluation pass. `in` is taken by value in spirit: the engine fills
 * in probe_seen_attached itself, so callers never have to remember to.
 * Returns the number of transitions written to `out`.
 *
 * Also returns, through `lid_evt` when non-NULL, the lid-open detector's
 * event for this sample — the caller writes the §9.4 auto-mark. */
int app_alarm_engine_step(app_alarm_engine_t *e, const app_alarm_cfg_t *cfg,
                          const app_alarm_input_t *in, app_alarm_evt_t *out,
                          int cap, app_alarm_lid_evt_t *lid_evt);

/* Acknowledge by id. Silences; does not resolve (09 §9.2) — the alarm
 * stays in the list with acked = true. Returns the number of transitions
 * (0 when the id is unknown or already acked). */
int app_alarm_engine_ack(app_alarm_engine_t *e, uint8_t id,
                         app_alarm_evt_t *out, int cap);
/* Every raised alarm at once — the OLED's "tap PRG to silence". */
int app_alarm_engine_ack_all(app_alarm_engine_t *e, app_alarm_evt_t *out,
                             int cap);

/* Clears the session-scoped rules; leaves the bridge-scoped ones. */
int app_alarm_engine_session_end(app_alarm_engine_t *e, app_alarm_evt_t *out,
                                 int cap);

/* Read-only view for /status, the OLED, and live_state. Slots in
 * RAISED or ACKED only, oldest first. Returns the count. */
int app_alarm_engine_list(const app_alarm_engine_t *e,
                          const app_alarm_slot_t **out, int cap);
/* True while any alarm is raised and NOT acknowledged — what drives the
 * LED, the buzzer, live_state.alarm_active, and the ⚠ glyph. */
bool app_alarm_engine_unacked(const app_alarm_engine_t *e);
const app_alarm_slot_t *app_alarm_engine_find(const app_alarm_engine_t *e,
                                              uint8_t id);

#ifdef __cplusplus
}
#endif

#endif /* APP_ALARM_CORE_H */
