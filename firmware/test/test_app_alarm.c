/* test_app_alarm.c — the device-tier alarm engine on the host (F13.1,
 * F13.3–F13.5; design 09 §9.2, §9.4, 10 §10.5).
 *
 * The named regression from 10 §10.5 is here and it is the reason the
 * whole epic exists: A PROBE OSCILLATING ±1 °F ACROSS ITS TARGET FIRES
 * ONCE. Everything else in this file is either the rule table, the
 * lifecycle, or the lid-open branch that keeps a spritz from being an
 * alarm.
 *
 * Every rule gets three tests and not one: it fires, it does not re-fire,
 * and it abstains on bad input. A rule with only the first is not done.
 */
#include "app_alarm_core.h"
#include "test_util.h"

#include <string.h>

/* ── fixtures ───────────────────────────────────────────────────────── */

/* A plausible mid-cook: probe 1 is the pit at 243.0 °F targeting 250.0,
 * probe 2 is a brisket at 163.2 targeting 203.0, 3 and 4 unplugged. */
static void base_input(app_alarm_input_t *in) {
    memset(in, 0, sizeof *in);
    in->temp_f10[0] = 2430;
    in->temp_f10[1] = 1632;
    in->temp_f10[2] = BRIDGE_TEMP_DETACHED;
    in->temp_f10[3] = BRIDGE_TEMP_DETACHED;
    in->role[0] = BRIDGE_PROBE_ROLE_PIT;
    in->role[1] = BRIDGE_PROBE_ROLE_FOOD;
    in->role[2] = BRIDGE_PROBE_ROLE_FOOD;
    in->role[3] = BRIDGE_PROBE_ROLE_FOOD;
    in->target_f10[0] = 2500;
    in->target_f10[1] = 2030;
    in->soc_pct = 71;
    in->storage_valid = true;
    in->storage_free_pct = 91;
    in->session_active = true;
    in->sample_fresh = true;
    in->now_s = 1000;
}

static int count_rule(const app_alarm_cond_t *c, int n, uint8_t rule) {
    int k = 0;
    for (int i = 0; i < n; i++) {
        if (c[i].rule == rule) {
            k++;
        }
    }
    return k;
}

static int count_evt(const app_alarm_evt_t *e, int n, uint8_t kind,
                     uint8_t rule) {
    int k = 0;
    for (int i = 0; i < n; i++) {
        if (e[i].kind == kind && e[i].rule == rule) {
            k++;
        }
    }
    return k;
}

/* ── F13.1 — the configuration codec ────────────────────────────────── */

static void test_cfg_defaults_are_the_design_table(void) {
    app_alarm_cfg_t c;
    app_alarm_cfg_defaults(&c);
    /* 09 §9.2's table, transcribed once here so a silent edit to the
     * defaults is a red test rather than a quieter night. */
    CHECK_EQ_INT(c.pit_band_f10, 250);
    CHECK_EQ_INT(c.pit_band_sustain_s, 600);
    CHECK_EQ_INT(c.pit_crash_below_f10, 500);
    CHECK_EQ_INT(c.pit_crash_slope_f10_per_hr, -100);
    CHECK_EQ_INT(c.pit_crash_sustain_s, 600);
    CHECK_EQ_INT(c.base_lost_s, 600);
    CHECK_EQ_INT(c.batt_warn_pct, 15);
    CHECK_EQ_INT(c.batt_crit_pct, 5);
    CHECK_EQ_INT(c.storage_free_pct, 2);
    CHECK_EQ_INT(c.target_rearm_f10, 30);
    CHECK_EQ_INT(c.band_rearm_s, 300);
    CHECK_EQ_INT(c.lid_grace_s, 900);
    for (uint8_t r = 0; r < APP_ALARM_RULE_COUNT; r++) {
        CHECK(app_alarm_cfg_rule_enabled(&c, r));
    }
    CHECK(!app_alarm_cfg_rule_enabled(&c, APP_ALARM_RULE_COUNT));
}

static void test_cfg_roundtrip_and_degradation(void) {
    app_alarm_cfg_t a;
    app_alarm_cfg_defaults(&a);
    a.enabled_mask = 0x015Au;
    a.pit_band_f10 = 400;
    a.pit_crash_slope_f10_per_hr = -250;
    a.batt_warn_pct = 22;
    a.lid_grace_s = 1200;

    uint8_t buf[APP_ALARM_CFG_MAX_BYTES];
    const int n = app_alarm_cfg_encode(&a, buf, sizeof buf);
    CHECK(n > 0);
    /* The 64 B NVS cap is a test, not a comment. */
    CHECK(n <= APP_ALARM_CFG_MAX_BYTES);

    app_alarm_cfg_t b;
    CHECK_EQ_INT(app_alarm_cfg_decode(buf, (size_t)n, &b), n);
    CHECK_EQ_INT(b.enabled_mask, a.enabled_mask);
    CHECK_EQ_INT(b.pit_band_f10, 400);
    CHECK_EQ_INT(b.pit_crash_slope_f10_per_hr, -250);
    CHECK_EQ_INT(b.batt_warn_pct, 22);
    CHECK_EQ_INT(b.lid_grace_s, 1200);

    /* Never written: the whole table defaults rather than zeroing, because
     * an all-zero config is every alarm disabled. */
    app_alarm_cfg_t z;
    memset(&z, 0xAA, sizeof z);
    CHECK_EQ_INT(app_alarm_cfg_decode(NULL, 0, &z), 0);
    CHECK_EQ_INT(z.pit_band_f10, 250);
    for (uint8_t r = 0; r < APP_ALARM_RULE_COUNT; r++) {
        CHECK(app_alarm_cfg_rule_enabled(&z, r));
    }

    /* Truncated at every offset: no read past the end, no zero fields,
     * and everything before the cut survives. */
    for (size_t cut = 0; cut <= (size_t)n; cut++) {
        app_alarm_cfg_t t;
        (void)app_alarm_cfg_decode(buf, cut, &t);
        CHECK(t.pit_band_f10 == 400 || t.pit_band_f10 == 250);
        CHECK(t.lid_grace_s == 1200 || t.lid_grace_s == 900);
        CHECK(t.batt_warn_pct != 0);
    }

    /* A FUTURE version keeps the prefix it understands. Rejecting it would
     * silently disable every alarm on a downgraded bridge. */
    uint8_t future[APP_ALARM_CFG_MAX_BYTES];
    memcpy(future, buf, (size_t)n);
    future[0] = 99;
    app_alarm_cfg_t f;
    (void)app_alarm_cfg_decode(future, (size_t)n, &f);
    CHECK_EQ_INT(f.pit_band_f10, 400);
    CHECK_EQ_INT(f.enabled_mask, a.enabled_mask);
}

/* ── F13.3 — the rule table ─────────────────────────────────────────── */

static void test_rule_properties(void) {
    /* 09 §9.2's severity column. */
    CHECK_EQ_INT(app_alarm_rule_severity(BRIDGE_ALARM_RULE_TARGET_REACHED),
                 BRIDGE_ALARM_SEVERITY_CRITICAL);
    CHECK_EQ_INT(app_alarm_rule_severity(BRIDGE_ALARM_RULE_PIT_CRASH),
                 BRIDGE_ALARM_SEVERITY_CRITICAL);
    CHECK_EQ_INT(app_alarm_rule_severity(BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND),
                 BRIDGE_ALARM_SEVERITY_WARNING);
    /* Latched vs. self-clearing. */
    CHECK(!app_alarm_rule_auto_clear(BRIDGE_ALARM_RULE_TARGET_REACHED));
    CHECK(app_alarm_rule_auto_clear(BRIDGE_ALARM_RULE_BASE_LOST));
    /* Properties of the bridge survive the cook. */
    CHECK(!app_alarm_rule_session_scoped(BRIDGE_ALARM_RULE_BATTERY_LOW));
    CHECK(app_alarm_rule_session_scoped(BRIDGE_ALARM_RULE_TARGET_REACHED));
    /* Only the two pit rules are suppressed by a lid open. */
    CHECK(app_alarm_rule_lid_suppressed(BRIDGE_ALARM_RULE_PIT_CRASH));
    CHECK(app_alarm_rule_lid_suppressed(BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND));
    CHECK(!app_alarm_rule_lid_suppressed(BRIDGE_ALARM_RULE_TARGET_REACHED));
    /* The generated names are the JSON spellings (06 §6.2). */
    CHECK(strcmp(bridge_alarm_rule_str(BRIDGE_ALARM_RULE_TARGET_REACHED),
                 "target_reached") == 0);
    CHECK(strcmp(bridge_alarm_rule_str(BRIDGE_ALARM_RULE_SYSTEM_FAULT),
                 "system_fault") == 0);
    CHECK(strcmp(bridge_alarm_rule_str(99), "") == 0);
    CHECK(strcmp(bridge_alarm_severity_str(BRIDGE_ALARM_SEVERITY_CRITICAL),
                 "critical") == 0);
}

static void test_eval_quiet_when_nothing_is_wrong(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_input_t in;
    base_input(&in);
    app_alarm_cond_t c[APP_ALARM_MAX_ACTIVE];
    CHECK_EQ_INT(app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE), 0);
}

static void test_eval_target_reached(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_cond_t c[APP_ALARM_MAX_ACTIVE];

    app_alarm_input_t in;
    base_input(&in);
    in.temp_f10[1] = 2031; /* 203.1 °F against a 203.0 target */
    int n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_TARGET_REACHED), 1);

    /* The PIT crossing its own target is normal operation, not an alarm. */
    base_input(&in);
    in.temp_f10[0] = 2600;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_TARGET_REACHED), 0);

    /* An UNSET target is silent — never treated as a target of 0. */
    base_input(&in);
    in.target_f10[1] = 0;
    in.temp_f10[1] = 2031;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_TARGET_REACHED), 0);

    /* A DETACHED probe contributes no temperature-derived condition. */
    base_input(&in);
    in.temp_f10[1] = BRIDGE_TEMP_DETACHED;
    in.session_active = false; /* isolate from probe_detached */
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(n, 0);

    /* Disabled by configuration. */
    base_input(&in);
    in.temp_f10[1] = 2031;
    cfg.enabled_mask &= (uint16_t) ~(1u << BRIDGE_ALARM_RULE_TARGET_REACHED);
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_TARGET_REACHED), 0);
}

static void test_eval_pit_rules(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_cond_t c[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;

    /* Out of band: 250.0 target, ±25 °F, so 224.9 is out and 225.0 is in. */
    base_input(&in);
    in.temp_f10[0] = 2249;
    int n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND), 1);
    for (int i = 0; i < n; i++) {
        if (c[i].rule == BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND) {
            CHECK_EQ_INT(c[i].sustain_s, 600);
            CHECK_EQ_INT(c[i].clear_sustain_s, 300);
            CHECK_EQ_INT(c[i].probe, 1);
        }
    }
    in.temp_f10[0] = 2250;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND), 0);

    /* Crash: > 50 °F below target AND falling faster than −10 °F/hr. */
    base_input(&in);
    in.temp_f10[0] = 1900;
    in.slope_valid[0] = true;
    in.slope_f_per_hr[0] = -40.0f;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_CRASH), 1);

    /* WITHOUT a slope it ABSTAINS — a pit_crash inferred from a short or
     * gappy window is worse than none (cook_ring already says so). */
    in.slope_valid[0] = false;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_CRASH), 0);

    /* Cold but steady is a low fire, not a dying one. */
    in.slope_valid[0] = true;
    in.slope_f_per_hr[0] = -1.0f;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_CRASH), 0);

    /* pit_crash never applies to a food probe. */
    base_input(&in);
    in.role[0] = BRIDGE_PROBE_ROLE_FOOD;
    in.temp_f10[0] = 1900;
    in.slope_valid[0] = true;
    in.slope_f_per_hr[0] = -40.0f;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_CRASH), 0);
}

static void test_eval_device_rules(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_cond_t c[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;

    /* base_lost fires on the ABSENCE of a packet. */
    base_input(&in);
    in.since_last_packet_s = 599;
    CHECK_EQ_INT(count_rule(c,
                            app_alarm_rules_eval(&cfg, &in, c,
                                                 APP_ALARM_MAX_ACTIVE),
                            BRIDGE_ALARM_RULE_BASE_LOST),
                 0);
    in.since_last_packet_s = 600;
    CHECK_EQ_INT(count_rule(c,
                            app_alarm_rules_eval(&cfg, &in, c,
                                                 APP_ALARM_MAX_ACTIVE),
                            BRIDGE_ALARM_RULE_BASE_LOST),
                 1);

    /* battery_low, two thresholds, one rule. */
    base_input(&in);
    in.soc_pct = 15;
    int n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_BATTERY_LOW), 1);
    for (int i = 0; i < n; i++) {
        if (c[i].rule == BRIDGE_ALARM_RULE_BATTERY_LOW) {
            CHECK_EQ_INT(c[i].severity, BRIDGE_ALARM_SEVERITY_WARNING);
        }
    }
    in.soc_pct = 4;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    for (int i = 0; i < n; i++) {
        if (c[i].rule == BRIDGE_ALARM_RULE_BATTERY_LOW) {
            CHECK_EQ_INT(c[i].severity, BRIDGE_ALARM_SEVERITY_CRITICAL);
        }
    }
    /* SOC_UNKNOWN is not a flat battery — the P3.2 sentinel, honoured. */
    in.soc_pct = BRIDGE_SOC_UNKNOWN;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_BATTERY_LOW), 0);

    /* storage_low needs a valid reading, not a zeroed struct. */
    base_input(&in);
    in.storage_valid = false;
    in.storage_free_pct = 0;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_STORAGE_LOW), 0);
    in.storage_valid = true;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_STORAGE_LOW), 1);

    /* system_fault: a coredump was found at boot. */
    base_input(&in);
    in.coredump_present = true;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_SYSTEM_FAULT), 1);

    /* smoke_x_alarm mirrors the BASE's own band, not ours. */
    base_input(&in);
    in.base_alarm_armed[0] = true;
    in.base_alarm_low_f10[0] = 2000;
    in.base_alarm_high_f10[0] = 2400;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_SMOKE_X_ALARM), 1);
    /* Our band says 243.0 against a 250.0 ±25 target is fine. Both are
     * correct; they are answering different questions. */
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND), 0);

    /* The bare edge-triggered flag still reports, against the whole cook. */
    base_input(&in);
    in.new_alarm = true;
    n = app_alarm_rules_eval(&cfg, &in, c, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(count_rule(c, n, BRIDGE_ALARM_RULE_SMOKE_X_ALARM), 1);
    for (int i = 0; i < n; i++) {
        if (c[i].rule == BRIDGE_ALARM_RULE_SMOKE_X_ALARM) {
            CHECK_EQ_INT(c[i].probe, 0);
        }
    }
}

static void test_eval_probe_detached(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;

    base_input(&in);
    CHECK_EQ_INT(
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL),
        0);

    /* A jack that was NEVER used does not alarm when it stays empty. */
    in.now_s += 30;
    CHECK_EQ_INT(
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL),
        0);

    /* Unplugging one that was in use does. */
    in.now_s += 30;
    in.temp_f10[1] = BRIDGE_TEMP_DETACHED;
    int n =
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL);
    CHECK_EQ_INT(count_evt(ev, n, APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_PROBE_DETACHED),
                 1);

    /* And it does not re-fire every 30 seconds while it stays unplugged. */
    for (int i = 0; i < 10; i++) {
        in.now_s += 30;
        CHECK_EQ_INT(app_alarm_engine_step(&e, &cfg, &in, ev,
                                           APP_ALARM_MAX_ACTIVE, NULL),
                     0);
    }

    /* Plugging it back in resolves it — this one auto-clears. */
    in.now_s += 30;
    in.temp_f10[1] = 1640;
    n = app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL);
    CHECK_EQ_INT(count_evt(ev, n, APP_ALARM_EVT_CLEARED,
                           BRIDGE_ALARM_RULE_PROBE_DETACHED),
                 1);
    CHECK(!app_alarm_engine_unacked(&e));
}

/* ── F13.4 — the lifecycle, and THE regression ──────────────────────── */

static void test_oscillating_probe_fires_exactly_once(void) {
    /* 10 §10.5's named case. A probe hovering at threshold otherwise
     * generates an alarm every 30 seconds all night, and an alarm that
     * cries wolf gets muted permanently — which is the real failure. */
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);

    int raised = 0;
    int cleared = 0;
    /* Two hours at the 30 s cadence, wobbling ±1 °F across a 203.0 target. */
    for (int i = 0; i < 240; i++) {
        in.now_s = 1000 + (uint32_t)i * 30u;
        in.temp_f10[1] = (int16_t)(i % 2 == 0 ? 2040 : 2020);
        const int n = app_alarm_engine_step(&e, &cfg, &in, ev,
                                            APP_ALARM_MAX_ACTIVE, NULL);
        raised += count_evt(ev, n, APP_ALARM_EVT_RAISED,
                            BRIDGE_ALARM_RULE_TARGET_REACHED);
        cleared += count_evt(ev, n, APP_ALARM_EVT_CLEARED,
                             BRIDGE_ALARM_RULE_TARGET_REACHED);
    }
    CHECK_EQ_INT(raised, 1);
    CHECK_EQ_INT(cleared, 0);
    CHECK(app_alarm_engine_unacked(&e));

    /* Acknowledging silences but does not resolve: still listed. */
    const app_alarm_slot_t *list[APP_ALARM_MAX_ACTIVE];
    CHECK_EQ_INT(app_alarm_engine_list(&e, list, APP_ALARM_MAX_ACTIVE), 1);
    const uint8_t id = list[0]->id;
    CHECK(id != 0);
    CHECK_EQ_INT(app_alarm_engine_ack(&e, id, ev, APP_ALARM_MAX_ACTIVE), 1);
    CHECK(!app_alarm_engine_unacked(&e));
    CHECK_EQ_INT(app_alarm_engine_list(&e, list, APP_ALARM_MAX_ACTIVE), 1);
    CHECK_EQ_INT(list[0]->state, APP_ALARM_SLOT_ACKED);
    /* Acking twice, or acking an unknown id, is a no-op rather than an
     * error — three transports can send the same ack. */
    CHECK_EQ_INT(app_alarm_engine_ack(&e, id, ev, APP_ALARM_MAX_ACTIVE), 0);
    CHECK_EQ_INT(app_alarm_engine_ack(&e, 200, ev, APP_ALARM_MAX_ACTIVE), 0);

    /* Still wobbling: an ACKED alarm must not clear on a 1 °F dip either. */
    for (int i = 0; i < 40; i++) {
        in.now_s += 30;
        in.temp_f10[1] = (int16_t)(i % 2 == 0 ? 2040 : 2020);
        CHECK_EQ_INT(app_alarm_engine_step(&e, &cfg, &in, ev,
                                           APP_ALARM_MAX_ACTIVE, NULL),
                     0);
    }

    /* 3 °F below target re-arms it: THEN it clears, and only then can it
     * fire again. */
    in.now_s += 30;
    in.temp_f10[1] = 1990;
    int n =
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL);
    CHECK_EQ_INT(count_evt(ev, n, APP_ALARM_EVT_CLEARED,
                           BRIDGE_ALARM_RULE_TARGET_REACHED),
                 1);
    in.now_s += 30;
    in.temp_f10[1] = 2040;
    n = app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL);
    CHECK_EQ_INT(count_evt(ev, n, APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_TARGET_REACHED),
                 1);
    /* A fresh id, because it is a fresh alarm. */
    CHECK_EQ_INT(app_alarm_engine_list(&e, list, APP_ALARM_MAX_ACTIVE), 1);
    CHECK(list[0]->id != id);
}

static void test_unacked_target_never_clears_itself(void) {
    /* "A target_reached that fires at 02:00 stays raised until someone
     * acknowledges it, even if the probe later cools." */
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);

    in.temp_f10[1] = 2040;
    CHECK_EQ_INT(
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL),
        1);
    /* Five hours of cooling with nobody in the room. */
    for (int i = 0; i < 600; i++) {
        in.now_s += 30;
        in.temp_f10[1] = 1500;
        CHECK_EQ_INT(app_alarm_engine_step(&e, &cfg, &in, ev,
                                           APP_ALARM_MAX_ACTIVE, NULL),
                     0);
    }
    CHECK(app_alarm_engine_unacked(&e));
}

static void test_sustain_and_pending(void) {
    /* pit_out_of_band needs 10 minutes. A momentary excursion — opening
     * the vent, a gust — must not raise anything at all. */
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);

    /* 222.0 °F: out of the 250 ±25 band, but only 21 °F below the 243.0
     * starting point, so the LID DETECTOR does not fire and this test
     * measures the sustain rather than the grace window. (Writing it with
     * a 33 °F step first was instructive: the drop read as a lid open and
     * suppressed the pit alarm for 15 minutes — which is the feature
     * working, in the wrong test.) */
    for (int i = 0; i < 10; i++) { /* 5 minutes out of band */
        in.now_s += 30;
        in.temp_f10[0] = 2220;
        CHECK_EQ_INT(app_alarm_engine_step(&e, &cfg, &in, ev,
                                           APP_ALARM_MAX_ACTIVE, NULL),
                     0);
    }
    in.now_s += 30;
    in.temp_f10[0] = 2440; /* back in band before the sustain elapsed */
    CHECK_EQ_INT(
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL),
        0);
    CHECK(!app_alarm_engine_unacked(&e));

    /* Now hold it out of band past 10 minutes: exactly one raise. */
    int raised = 0;
    for (int i = 0; i < 40; i++) {
        in.now_s += 30;
        in.temp_f10[0] = 2220;
        const int n = app_alarm_engine_step(&e, &cfg, &in, ev,
                                            APP_ALARM_MAX_ACTIVE, NULL);
        raised += count_evt(ev, n, APP_ALARM_EVT_RAISED,
                            BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND);
    }
    CHECK_EQ_INT(raised, 1);

    /* Back in band clears only after the 5-minute re-arm window. */
    in.now_s += 30;
    in.temp_f10[0] = 2440;
    CHECK_EQ_INT(
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL),
        0);
    int cleared = 0;
    for (int i = 0; i < 12; i++) {
        in.now_s += 30;
        const int n = app_alarm_engine_step(&e, &cfg, &in, ev,
                                            APP_ALARM_MAX_ACTIVE, NULL);
        cleared += count_evt(ev, n, APP_ALARM_EVT_CLEARED,
                             BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND);
    }
    CHECK_EQ_INT(cleared, 1);
}

static void test_session_end_scoping(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);

    in.temp_f10[1] = 2040; /* target_reached — session-scoped */
    in.soc_pct = 4;        /* battery_low    — a property of the BRIDGE */
    const int n =
        app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL);
    CHECK_EQ_INT(n, 2);

    const int c =
        app_alarm_engine_session_end(&e, ev, APP_ALARM_MAX_ACTIVE);
    CHECK_EQ_INT(c, 1);
    CHECK_EQ_INT(ev[0].rule, BRIDGE_ALARM_RULE_TARGET_REACHED);
    const app_alarm_slot_t *list[APP_ALARM_MAX_ACTIVE];
    CHECK_EQ_INT(app_alarm_engine_list(&e, list, APP_ALARM_MAX_ACTIVE), 1);
    CHECK_EQ_INT(list[0]->rule, BRIDGE_ALARM_RULE_BATTERY_LOW);
}

static void test_table_saturation_never_overwrites(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);

    /* Everything at once: four probes over target, four over the base's
     * band, plus every device-scoped rule. */
    for (int i = 0; i < 4; i++) {
        in.role[i] = BRIDGE_PROBE_ROLE_FOOD;
        in.temp_f10[i] = 2500;
        in.target_f10[i] = 2030;
        in.base_alarm_armed[i] = true;
        in.base_alarm_low_f10[i] = 0;
        in.base_alarm_high_f10[i] = 2100;
    }
    in.since_last_packet_s = 900;
    in.soc_pct = 2;
    in.storage_free_pct = 1;
    in.coredump_present = true;
    (void)app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE, NULL);

    const app_alarm_slot_t *list[APP_ALARM_MAX_ACTIVE];
    const int live = app_alarm_engine_list(&e, list, APP_ALARM_MAX_ACTIVE);
    CHECK(live <= APP_ALARM_MAX_ACTIVE);
    /* Whatever fit is still there; nothing was silently replaced, and
     * anything refused is counted rather than lost. */
    for (int i = 0; i < live; i++) {
        CHECK(list[i]->id != 0);
    }
    for (int i = 0; i < live; i++) {
        for (int j = i + 1; j < live; j++) {
            CHECK(list[i]->id != list[j]->id);
        }
    }
}

/* ── F13.5 — lid open, and the third exit-gate clause ───────────────── */

static void test_lid_open_does_not_fire_a_false_pit_alarm(void) {
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);
    in.target_f10[0] = 2500;

    int pit_alarms = 0;
    int lid_detected = 0;
    int lid_confirmed = 0;
    app_alarm_lid_evt_t lid;

    /* 10 minutes steady at 250 °F. */
    for (int i = 0; i < 20; i++) {
        in.now_s += 30;
        in.temp_f10[0] = 2500;
        const int n = app_alarm_engine_step(&e, &cfg, &in, ev,
                                            APP_ALARM_MAX_ACTIVE, &lid);
        pit_alarms += count_evt(ev, n, APP_ALARM_EVT_RAISED,
                                BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND);
    }

    /* A spritz: down 60 °F, back inside 10 minutes. */
    static const int16_t spritz[] = {2400, 2200, 1900, 2000, 2150,
                                     2300, 2400, 2470, 2500, 2500};
    for (size_t i = 0; i < sizeof spritz / sizeof spritz[0]; i++) {
        in.now_s += 30;
        in.temp_f10[0] = spritz[i];
        in.slope_valid[0] = true;
        in.slope_f_per_hr[0] = -60.0f;
        const int n = app_alarm_engine_step(&e, &cfg, &in, ev,
                                            APP_ALARM_MAX_ACTIVE, &lid);
        if (lid == APP_ALARM_LID_DETECTED) {
            lid_detected++;
        }
        if (lid == APP_ALARM_LID_CONFIRMED) {
            lid_confirmed++;
        }
        pit_alarms += count_evt(ev, n, APP_ALARM_EVT_RAISED,
                                BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND);
        pit_alarms += count_evt(ev, n, APP_ALARM_EVT_RAISED,
                                BRIDGE_ALARM_RULE_PIT_CRASH);
    }
    CHECK_EQ_INT(lid_detected, 1);
    CHECK_EQ_INT(lid_confirmed, 1);
    /* THE EXIT-GATE CLAUSE: a lid open fires no pit alarm. */
    CHECK_EQ_INT(pit_alarms, 0);
}

static void test_dying_fire_still_escalates(void) {
    /* The other branch, and the expensive one to get wrong: suppressing a
     * REAL pit_crash. Same drop, no recovery. */
    app_alarm_cfg_t cfg;
    app_alarm_cfg_defaults(&cfg);
    app_alarm_engine_t e;
    app_alarm_engine_reset(&e);
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_input_t in;
    base_input(&in);
    in.target_f10[0] = 2500;

    for (int i = 0; i < 20; i++) {
        in.now_s += 30;
        in.temp_f10[0] = 2500;
        (void)app_alarm_engine_step(&e, &cfg, &in, ev, APP_ALARM_MAX_ACTIVE,
                                    NULL);
    }

    app_alarm_lid_evt_t lid;
    int escalated = 0;
    int detected = 0;
    int crash = 0;
    /* The same 30 °F step a lid open produces — so detection fires and the
     * grace window starts — and then no recovery at all. */
    int16_t t = 2200;
    for (int i = 0; i < 100; i++) {
        in.now_s += 30;
        in.temp_f10[0] = t;
        t = (int16_t)(t > 700 ? t - 10 : 700);
        in.slope_valid[0] = true;
        in.slope_f_per_hr[0] = -30.0f;
        const int n = app_alarm_engine_step(&e, &cfg, &in, ev,
                                            APP_ALARM_MAX_ACTIVE, &lid);
        if (lid == APP_ALARM_LID_DETECTED) {
            detected++;
        }
        if (lid == APP_ALARM_LID_ESCALATED) {
            escalated++;
            /* Escalation ends the grace immediately: the whole point of
             * escalating is to let pit_crash through. */
            CHECK(crash == 0);
        }
        crash += count_evt(ev, n, APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_PIT_CRASH);
    }
    CHECK_EQ_INT(detected, 1);
    CHECK_EQ_INT(escalated, 1);
    CHECK_EQ_INT(crash, 1);
}

static void test_lid_detector_matches_the_dart_original(void) {
    /* app/lib/domain/analysis/lid_open.dart's constants, asserted here so
     * the two implementations cannot drift apart quietly. */
    CHECK_EQ_INT(APP_ALARM_LID_DROP_F10, 250);   /* lidDetectDropF 25 */
    CHECK_EQ_INT(APP_ALARM_LID_WINDOW_S, 180);   /* lidDetectWindowS */
    CHECK_EQ_INT(APP_ALARM_LID_CONFIRM_S, 1200); /* lidConfirmWindowS */
    /* lidConfirmRecoveryFraction 0.5 */
    CHECK_EQ_INT(APP_ALARM_LID_RECOVER_NUM, 1);
    CHECK_EQ_INT(APP_ALARM_LID_RECOVER_DEN, 2);

    app_alarm_lid_t l;
    app_alarm_lid_reset(&l);
    /* A detached pit is skipped, not read as a 3276.8 °F drop. */
    CHECK_EQ_INT(app_alarm_lid_add(&l, 0, BRIDGE_TEMP_DETACHED),
                 APP_ALARM_LID_NONE);
    CHECK(!app_alarm_lid_pending(&l));
    /* A single sample can never be its own reference. */
    CHECK_EQ_INT(app_alarm_lid_add(&l, 30, 2500), APP_ALARM_LID_NONE);
    /* 24.9 °F is not a lid open; 25.0 is. */
    CHECK_EQ_INT(app_alarm_lid_add(&l, 60, 2251), APP_ALARM_LID_NONE);
    app_alarm_lid_reset(&l);
    CHECK_EQ_INT(app_alarm_lid_add(&l, 30, 2500), APP_ALARM_LID_NONE);
    CHECK_EQ_INT(app_alarm_lid_add(&l, 60, 2250), APP_ALARM_LID_DETECTED);
    CHECK(app_alarm_lid_pending(&l));
    /* A drop OUTSIDE the 3-minute window is a slow cool, not a lid. */
    app_alarm_lid_reset(&l);
    CHECK_EQ_INT(app_alarm_lid_add(&l, 0, 2500), APP_ALARM_LID_NONE);
    CHECK_EQ_INT(app_alarm_lid_add(&l, 400, 2000), APP_ALARM_LID_NONE);
}

int main(void) {
    test_cfg_defaults_are_the_design_table();
    test_cfg_roundtrip_and_degradation();
    test_rule_properties();
    test_eval_quiet_when_nothing_is_wrong();
    test_eval_target_reached();
    test_eval_pit_rules();
    test_eval_device_rules();
    test_eval_probe_detached();
    test_oscillating_probe_fires_exactly_once();
    test_unacked_target_never_clears_itself();
    test_sustain_and_pending();
    test_session_end_scoping();
    test_table_saturation_never_overwrites();
    test_lid_open_does_not_fire_a_false_pit_alarm();
    test_dying_fire_still_escalates();
    test_lid_detector_matches_the_dart_original();
    return test_summary("test_app_alarm");
}
