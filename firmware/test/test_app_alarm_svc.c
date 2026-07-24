/* test_app_alarm_svc.c — the alarm engine wired to the rest of the
 * firmware (F13.6, F13.7; design 09 §9.2, 04 §4.2).
 *
 * Not a double of the world: this drives app_alarm_svc against the REAL
 * app_config_store, smoke_x_ctrl, cook_ring and cook_store, over the
 * in-memory backends the cook_store suites already use. The only fakes
 * are the four device facts a pure module cannot know.
 */
#include "app_alarm_svc.h"
#include "app_config_store.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"
#include "test_cook_doubles.h"
#include "test_util.h"

/* ── the four device facts ──────────────────────────────────────────── */

static bool g_coredump;
static bool g_storage_known = true;
static uint8_t g_storage_free = 91;
static uint8_t g_soc = BRIDGE_SOC_UNKNOWN;

static app_alarm_evt_t g_pub[64];
static int g_pub_n;

static bool op_coredump(void *c) {
    (void)c;
    return g_coredump;
}
static bool op_storage(void *c, uint8_t *pct) {
    (void)c;
    if (!g_storage_known) {
        return false;
    }
    *pct = g_storage_free;
    return true;
}
static uint8_t op_soc(void *c) {
    (void)c;
    return g_soc;
}
static void op_publish(void *c, const app_alarm_evt_t *e) {
    (void)c;
    if (g_pub_n < (int)(sizeof g_pub / sizeof g_pub[0])) {
        g_pub[g_pub_n++] = *e;
    }
}
static const app_alarm_ops_t g_ops = {.coredump_present = op_coredump,
                                      .storage_free_pct = op_storage,
                                      .soc_pct = op_soc,
                                      .publish = op_publish};

/* ── smoke_x_ctrl radio double ──────────────────────────────────────── */

static int rop_set_freq(void *c, uint32_t hz) {
    (void)c;
    (void)hz;
    return 0;
}
static int rop_tx(void *c, const char *p) {
    (void)c;
    (void)p;
    return 0;
}
static void rop_scan(void *c) { (void)c; }
static void rop_pub(void *c, smoke_x_evt_t e, const void *p) {
    (void)c;
    (void)e;
    (void)p;
}
static const smoke_x_ops_t g_radio_ops = {.set_frequency = rop_set_freq,
                                          .transmit = rop_tx,
                                          .start_scan = rop_scan,
                                          .publish = rop_pub};

static void seed_world(void) {
    memfs_reset();
    cfg_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);
    CHECK_EQ_INT(smoke_x_ctrl_init(&g_radio_ops, NULL, false, 0), 0);
    cook_ring_reset();
    g_coredump = false;
    g_storage_known = true;
    g_storage_free = 91;
    g_soc = BRIDGE_SOC_UNKNOWN;
    g_pub_n = 0;
    /* Probe 1 is the pit at 250.0 °F, probe 2 a brisket at 203.0. The
     * app_config role ordering (PIT 0, FOOD 1) is deliberately NOT the
     * wire's, which is what the service's wire_role() exists to bridge. */
    CHECK_EQ_INT(app_config_store_set_u8(APP_CONFIG_PROBE1_ROLE,
                                         APP_CONFIG_ROLE_PIT),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_set_i32(APP_CONFIG_PROBE1_TARGET, 2500),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_set_u8(APP_CONFIG_PROBE2_ROLE,
                                         APP_CONFIG_ROLE_FOOD),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_set_i32(APP_CONFIG_PROBE2_TARGET, 2030),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(app_alarm_svc_init(&g_ops), 0);
}

static void push_sample(uint32_t t, int16_t pit, int16_t food) {
    cook_ring_sample_t s = {.t = t, .rssi = -70};
    s.temp[0] = pit;
    s.temp[1] = food;
    s.temp[2] = BRIDGE_TEMP_DETACHED;
    s.temp[3] = BRIDGE_TEMP_DETACHED;
    cook_ring_push(&s);
}

static int g_mark_kinds[32];
static int g_mark_n;
static int mark_cb(void *ctx, const bridge_mark_rec_t *m) {
    (void)ctx;
    if (g_mark_n < 32) {
        g_mark_kinds[g_mark_n++] = m->kind;
    }
    return 0;
}
/* Marks are counted by reading them back off the (in-memory) .mrk, not by
 * trusting a counter — the file is the artifact the app and the CSV
 * export both read. */
static int marks_of_kind(uint8_t kind) {
    g_mark_n = 0;
    (void)cook_store_read_marks(cook_session_active_id(), mark_cb, NULL);
    int n = 0;
    for (int i = 0; i < g_mark_n; i++) {
        if (g_mark_kinds[i] == kind) {
            n++;
        }
    }
    return n;
}

static uint32_t open_session(void) {
    const cook_session_params_t p = {.num_probes = 4, .name = "Brisket"};
    CHECK_EQ_INT(cook_session_open(&p), COOK_STORE_OK);
    return cook_session_active_id();
}

static int count_pub(uint8_t kind, uint8_t rule) {
    int n = 0;
    for (int i = 0; i < g_pub_n; i++) {
        if (g_pub[i].kind == kind && g_pub[i].rule == rule) {
            n++;
        }
    }
    return n;
}

/* ── tests ──────────────────────────────────────────────────────────── */

static void test_defaults_load_when_nothing_was_ever_written(void) {
    seed_world();
    const app_alarm_cfg_t *c = app_alarm_svc_cfg();
    CHECK_EQ_INT(c->pit_band_f10, 250);
    CHECK(app_alarm_cfg_rule_enabled(c, BRIDGE_ALARM_RULE_TARGET_REACHED));
}

static void test_config_round_trips_through_nvs(void) {
    seed_world();
    app_alarm_cfg_t c = *app_alarm_svc_cfg();
    c.pit_band_f10 = 400;
    c.enabled_mask &= (uint16_t) ~(1u << BRIDGE_ALARM_RULE_BASE_LOST);
    CHECK_EQ_INT(app_alarm_svc_set_cfg(&c), 0);
    /* A reboot: re-init reads it back out of the store. */
    CHECK_EQ_INT(app_alarm_svc_init(&g_ops), 0);
    CHECK_EQ_INT(app_alarm_svc_cfg()->pit_band_f10, 400);
    CHECK(!app_alarm_cfg_rule_enabled(app_alarm_svc_cfg(),
                                      BRIDGE_ALARM_RULE_BASE_LOST));
    /* And the blob really is inside the 64 B NVS key. */
    uint8_t blob[128];
    size_t len = sizeof blob;
    CHECK_EQ_INT(app_config_store_get_blob(APP_CONFIG_ALARM_RULES, blob,
                                           &len),
                 APP_CONFIG_OK);
    CHECK(len <= 64);
}

static void test_sample_driven_raise_writes_a_mark(void) {
    seed_world();
    (void)open_session();

    push_sample(0, 2500, 1600);
    app_alarm_svc_on_sample(0);
    CHECK_EQ_INT(g_pub_n, 0);

    push_sample(30, 2500, 2040); /* over the 203.0 target */
    app_alarm_svc_on_sample(30);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_TARGET_REACHED),
                 1);
    CHECK(app_alarm_svc_unacked());

    /* F13.7: the raise is annotated on the session's timeline as a
     * kind-5 mark, so the graph shows where it happened. */
    CHECK_EQ_INT(marks_of_kind(BRIDGE_MARK_KIND_ALARM), 1);

    /* It does not write a second mark every 30 s while it stays raised —
     * the same latching that keeps the alarm quiet keeps the timeline
     * readable. */
    for (int i = 0; i < 10; i++) {
        push_sample(60u + (uint32_t)i * 30u, 2500, 2040);
        app_alarm_svc_on_sample(60u + (uint32_t)i * 30u);
    }
    CHECK_EQ_INT(marks_of_kind(BRIDGE_MARK_KIND_ALARM), 1);
}

static void test_tick_raises_base_lost_with_no_samples_at_all(void) {
    /* The rule that proves the 10 s tick is load-bearing: it fires on the
     * ABSENCE of a packet and can never be driven by one arriving. */
    seed_world();
    app_alarm_svc_tick(600, 599);
    CHECK_EQ_INT(g_pub_n, 0);
    app_alarm_svc_tick(610, 600);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_BASE_LOST),
                 1);
    /* And it clears itself when the base comes back. */
    g_pub_n = 0;
    app_alarm_svc_tick(620, 0);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_CLEARED,
                           BRIDGE_ALARM_RULE_BASE_LOST),
                 1);
}

static void test_ack_from_three_sources_reaches_one_state(void) {
    seed_world();
    push_sample(0, 2500, 2040);
    app_alarm_svc_on_sample(0);
    const app_alarm_slot_t *list[APP_ALARM_MAX_ACTIVE];
    CHECK_EQ_INT(app_alarm_svc_list(list, APP_ALARM_MAX_ACTIVE), 1);
    const uint8_t id = list[0]->id;

    /* The button's "silence everything" path. */
    CHECK_EQ_INT(app_alarm_svc_ack_all(), 1);
    CHECK(!app_alarm_svc_unacked());
    /* HTTP's {"type":"ack_alarm","id":N} and BLE's device_control op 11
     * are the same call, and both are idempotent — three transports can
     * send the same ack for the same alarm. */
    CHECK_EQ_INT(app_alarm_svc_ack(id), 0);
    CHECK_EQ_INT(app_alarm_svc_ack(id), 0);
    /* Acknowledging SILENCES; it does not resolve. */
    CHECK_EQ_INT(app_alarm_svc_list(list, APP_ALARM_MAX_ACTIVE), 1);
    CHECK_EQ_INT(list[0]->state, APP_ALARM_SLOT_ACKED);
    CHECK(app_alarm_svc_find(id) != NULL);
    CHECK(app_alarm_svc_find(0) == NULL);
}

static void test_session_end_keeps_the_bridge_scoped_alarms(void) {
    seed_world();
    g_soc = 4;
    push_sample(0, 2500, 2040);
    app_alarm_svc_on_sample(0);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_TARGET_REACHED),
                 1);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_BATTERY_LOW),
                 1);

    g_pub_n = 0;
    app_alarm_svc_session_ended();
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_CLEARED,
                           BRIDGE_ALARM_RULE_TARGET_REACHED),
                 1);
    const app_alarm_slot_t *list[APP_ALARM_MAX_ACTIVE];
    CHECK_EQ_INT(app_alarm_svc_list(list, APP_ALARM_MAX_ACTIVE), 1);
    CHECK_EQ_INT(list[0]->rule, BRIDGE_ALARM_RULE_BATTERY_LOW);
}

static void test_unknown_facts_abstain_rather_than_guess(void) {
    seed_world();
    /* No app_power yet: SOC_UNKNOWN is not a flat battery (P3.2). */
    g_soc = BRIDGE_SOC_UNKNOWN;
    /* Storage not known yet either. */
    g_storage_known = false;
    push_sample(0, 2500, 1600);
    app_alarm_svc_on_sample(0);
    CHECK_EQ_INT(g_pub_n, 0);

    /* A build with no ops at all must not crash and must not invent. */
    CHECK_EQ_INT(app_alarm_svc_init(NULL), 0);
    push_sample(30, 2500, 1600);
    app_alarm_svc_on_sample(30);
    CHECK(!app_alarm_svc_unacked());
}

static void test_lid_open_writes_an_auto_mark_and_no_pit_alarm(void) {
    seed_world();
    (void)open_session();

    uint32_t t = 0;
    for (int i = 0; i < 20; i++, t += 30) {
        push_sample(t, 2500, 1600);
        app_alarm_svc_on_sample(t);
    }
    CHECK_EQ_INT(marks_of_kind(BRIDGE_MARK_KIND_LID_OPEN), 0);

    static const int16_t spritz[] = {2400, 2200, 1900, 2050, 2200,
                                     2350, 2450, 2500};
    for (size_t i = 0; i < sizeof spritz / sizeof spritz[0]; i++, t += 30) {
        push_sample(t, spritz[i], 1600);
        app_alarm_svc_on_sample(t);
    }
    /* One kind-2 auto-mark (09 §9.4), and no pit alarm at all. */
    CHECK_EQ_INT(marks_of_kind(BRIDGE_MARK_KIND_LID_OPEN), 1);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_PIT_OUT_OF_BAND),
                 0);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED, BRIDGE_ALARM_RULE_PIT_CRASH),
                 0);
}

static void test_marks_are_dropped_when_no_session_is_open(void) {
    /* An alarm is not a reason to start a cook. */
    seed_world();
    CHECK(!cook_session_is_open());
    push_sample(0, 2500, 2040);
    app_alarm_svc_on_sample(0);
    CHECK_EQ_INT(count_pub(APP_ALARM_EVT_RAISED,
                           BRIDGE_ALARM_RULE_TARGET_REACHED),
                 1);
    CHECK(!cook_session_is_open());
}

int main(void) {
    test_defaults_load_when_nothing_was_ever_written();
    test_config_round_trips_through_nvs();
    test_sample_driven_raise_writes_a_mark();
    test_tick_raises_base_lost_with_no_samples_at_all();
    test_ack_from_three_sources_reaches_one_state();
    test_session_end_keeps_the_bridge_scoped_alarms();
    test_unknown_facts_abstain_rather_than_guess();
    test_lid_open_writes_an_auto_mark_and_no_pit_alarm();
    test_marks_are_dropped_when_no_session_is_open();
    return test_summary("test_app_alarm_svc");
}
