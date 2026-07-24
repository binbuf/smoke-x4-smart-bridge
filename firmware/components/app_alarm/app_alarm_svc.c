/* app_alarm_svc.c — F13.6 (the wiring) and F13.7 (the marks).
 *
 * Still ESP-IDF-free. Everything here runs in the host suite against the
 * real app_config_store, smoke_x_ctrl, cook_ring and cook_store — the
 * same modules the firmware runs, not doubles of them.
 */
#include "app_alarm_svc.h"

#include <stdio.h>
#include <string.h>

#include "app_config_store.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"

static app_alarm_ops_t s_ops;
static app_alarm_cfg_t s_cfg;
static app_alarm_engine_t s_engine;
static bool s_inited;

/* app_config's role values and the wire's are NOT the same ordering, and
 * conflating them would silently make every probe a pit. app_config:
 * PIT 0, FOOD 1, AMBIENT 2, UNUSED 3. The wire (records.yaml): UNUSED 0,
 * PIT 1, FOOD 2, AMBIENT 3. */
static uint8_t wire_role(uint8_t cfg_role) {
    switch (cfg_role) {
    case APP_CONFIG_ROLE_PIT:
        return BRIDGE_PROBE_ROLE_PIT;
    case APP_CONFIG_ROLE_FOOD:
        return BRIDGE_PROBE_ROLE_FOOD;
    case APP_CONFIG_ROLE_AMBIENT:
        return BRIDGE_PROBE_ROLE_AMBIENT;
    default:
        return BRIDGE_PROBE_ROLE_UNUSED;
    }
}

static void load_cfg(void) {
    uint8_t blob[APP_ALARM_CFG_MAX_BYTES];
    size_t len = sizeof blob;
    if (app_config_store_get_blob(APP_CONFIG_ALARM_RULES, blob, &len) !=
        APP_CONFIG_OK) {
        len = 0;
    }
    (void)app_alarm_cfg_decode(len > 0 ? blob : NULL, len, &s_cfg);
}

int app_alarm_svc_init(const app_alarm_ops_t *ops) {
    memset(&s_ops, 0, sizeof s_ops);
    if (ops != NULL) {
        s_ops = *ops;
    }
    app_alarm_engine_reset(&s_engine);
    load_cfg();
    s_inited = true;
    return 0;
}

const app_alarm_cfg_t *app_alarm_svc_cfg(void) { return &s_cfg; }

int app_alarm_svc_set_cfg(const app_alarm_cfg_t *cfg) {
    if (cfg == NULL) {
        return -1;
    }
    uint8_t blob[APP_ALARM_CFG_MAX_BYTES];
    const int n = app_alarm_cfg_encode(cfg, blob, sizeof blob);
    if (n < 0) {
        return -1;
    }
    if (app_config_store_set_blob(APP_CONFIG_ALARM_RULES, blob, (size_t)n) !=
        APP_CONFIG_OK) {
        return -1;
    }
    s_cfg = *cfg;
    return 0;
}

/* ── marks (F13.7; 04 §4.2) ─────────────────────────────────────────── */

static uint32_t session_t(void) {
    const cook_ring_sample_t *newest = cook_ring_get(0);
    return newest != NULL ? newest->t : 0u;
}

static void write_alarm_mark(const app_alarm_evt_t *e) {
    /* A session that is not open drops the mark rather than opening one:
     * an alarm is not a reason to start a cook. */
    if (!cook_session_is_open()) {
        return;
    }
    char text[25];
    const char *rule = bridge_alarm_rule_str(e->rule);
    if (e->value_f10 == BRIDGE_TEMP_DETACHED || e->value_f10 == 0) {
        snprintf(text, sizeof text, "%s", rule);
    } else {
        snprintf(text, sizeof text, "%s %d.%d", rule, e->value_f10 / 10,
                 (e->value_f10 < 0 ? -e->value_f10 : e->value_f10) % 10);
    }
    (void)cook_session_mark(session_t(), BRIDGE_MARK_KIND_ALARM, e->probe,
                            text);
}

static void write_lid_mark(void) {
    if (!cook_session_is_open()) {
        return;
    }
    (void)cook_session_mark(session_t(), BRIDGE_MARK_KIND_LID_OPEN, 0,
                            "lid open");
}

/* ── the evaluation pass ────────────────────────────────────────────── */

static void publish_all(const app_alarm_evt_t *ev, int n) {
    for (int i = 0; i < n; i++) {
        if (ev[i].kind == APP_ALARM_EVT_RAISED) {
            write_alarm_mark(&ev[i]);
        }
        if (s_ops.publish != NULL) {
            s_ops.publish(s_ops.ctx, &ev[i]);
        }
    }
}

static void build_input(app_alarm_input_t *in, uint32_t now_s,
                        uint32_t since_last_packet_s, bool sample_fresh) {
    static const app_config_key_t role_keys[4] = {
        APP_CONFIG_PROBE1_ROLE, APP_CONFIG_PROBE2_ROLE,
        APP_CONFIG_PROBE3_ROLE, APP_CONFIG_PROBE4_ROLE};
    static const app_config_key_t target_keys[4] = {
        APP_CONFIG_PROBE1_TARGET, APP_CONFIG_PROBE2_TARGET,
        APP_CONFIG_PROBE3_TARGET, APP_CONFIG_PROBE4_TARGET};

    memset(in, 0, sizeof *in);
    in->now_s = now_s;
    in->since_last_packet_s = since_last_packet_s;
    in->sample_fresh = sample_fresh;
    in->session_active = cook_session_is_open();

    const cook_ring_sample_t *newest = cook_ring_get(0);
    for (int i = 0; i < 4; i++) {
        in->temp_f10[i] = newest != NULL ? newest->temp[i]
                                         : (int16_t)BRIDGE_TEMP_DETACHED;
        uint8_t role = APP_CONFIG_ROLE_UNUSED;
        (void)app_config_store_get_u8(role_keys[i], &role);
        in->role[i] = wire_role(role);
        int32_t target = 0;
        (void)app_config_store_get_i32(target_keys[i], &target);
        in->target_f10[i] = target;
        in->slope_valid[i] = cook_ring_slope_f_per_hr(i, &in->slope_f_per_hr[i]);
    }

    /* The base station's own settings, straight off the newest accepted
     * state message. Its bands are whole degrees of the ACTIVE unit and
     * our canonical scale is tenths °F, so they are scaled here — the one
     * place the two representations meet. */
    const smoke_x_state_t *st = smoke_x_ctrl_last_state();
    if (st != NULL) {
        in->new_alarm = st->new_alarm;
        const bool celsius = st->units == SMOKE_X_UNITS_C;
        for (int i = 0; i < 4 && i < st->num_probes; i++) {
            if (!st->probes[i].alarm_armed) {
                continue;
            }
            in->base_alarm_armed[i] = true;
            const int32_t lo = st->probes[i].alarm_low;
            const int32_t hi = st->probes[i].alarm_high;
            in->base_alarm_low_f10[i] =
                (int16_t)(celsius ? (lo * 90 + 5) / 5 + 320 : lo * 10);
            in->base_alarm_high_f10[i] =
                (int16_t)(celsius ? (hi * 90 + 5) / 5 + 320 : hi * 10);
        }
    }

    uint8_t pct = 0;
    if (s_ops.storage_free_pct != NULL &&
        s_ops.storage_free_pct(s_ops.ctx, &pct)) {
        in->storage_valid = true;
        in->storage_free_pct = pct;
    }
    in->soc_pct = s_ops.soc_pct != NULL ? s_ops.soc_pct(s_ops.ctx)
                                        : (uint8_t)BRIDGE_SOC_UNKNOWN;
    in->coredump_present =
        s_ops.coredump_present != NULL && s_ops.coredump_present(s_ops.ctx);
}

static void step(uint32_t now_s, uint32_t since_last_packet_s, bool feed_lid) {
    if (!s_inited) {
        return;
    }
    app_alarm_input_t in;
    build_input(&in, now_s, since_last_packet_s, feed_lid);

    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    app_alarm_lid_evt_t lid = APP_ALARM_LID_NONE;
    const int n = app_alarm_engine_step(&s_engine, &s_cfg, &in, ev,
                                        APP_ALARM_MAX_ACTIVE, &lid);

    if (lid == APP_ALARM_LID_DETECTED) {
        write_lid_mark();
    }
    publish_all(ev, n);
}

void app_alarm_svc_on_sample(uint32_t now_s) { step(now_s, 0, true); }

void app_alarm_svc_tick(uint32_t now_s, uint32_t since_last_packet_s) {
    step(now_s, since_last_packet_s, false);
}

int app_alarm_svc_ack(uint8_t id) {
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    const int n = app_alarm_engine_ack(&s_engine, id, ev,
                                       APP_ALARM_MAX_ACTIVE);
    for (int i = 0; i < n; i++) {
        if (s_ops.publish != NULL) {
            s_ops.publish(s_ops.ctx, &ev[i]);
        }
    }
    return n;
}

int app_alarm_svc_ack_all(void) {
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    const int n = app_alarm_engine_ack_all(&s_engine, ev,
                                           APP_ALARM_MAX_ACTIVE);
    for (int i = 0; i < n; i++) {
        if (s_ops.publish != NULL) {
            s_ops.publish(s_ops.ctx, &ev[i]);
        }
    }
    return n;
}

void app_alarm_svc_session_started(void) {
    /* A new cook starts with a clean lid detector and no "this jack was in
     * use" memory; the bridge-scoped alarms carry over untouched. */
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    const int n = app_alarm_engine_session_end(&s_engine, ev,
                                               APP_ALARM_MAX_ACTIVE);
    for (int i = 0; i < n; i++) {
        if (s_ops.publish != NULL) {
            s_ops.publish(s_ops.ctx, &ev[i]);
        }
    }
}

void app_alarm_svc_session_ended(void) {
    app_alarm_evt_t ev[APP_ALARM_MAX_ACTIVE];
    const int n = app_alarm_engine_session_end(&s_engine, ev,
                                               APP_ALARM_MAX_ACTIVE);
    for (int i = 0; i < n; i++) {
        if (s_ops.publish != NULL) {
            s_ops.publish(s_ops.ctx, &ev[i]);
        }
    }
}

int app_alarm_svc_list(const app_alarm_slot_t **out, int cap) {
    return app_alarm_engine_list(&s_engine, out, cap);
}

bool app_alarm_svc_unacked(void) {
    return app_alarm_engine_unacked(&s_engine);
}

const app_alarm_slot_t *app_alarm_svc_find(uint8_t id) {
    return app_alarm_engine_find(&s_engine, id);
}
