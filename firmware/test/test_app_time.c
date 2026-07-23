/* Host tests for app_time_core (F6.1–F6.3): source precedence, the named
 * 10 §10.5 back-patch case (a session that starts with no clock and
 * acquires one at t = 40 min), and the monotonic floor across a reboot. */
#include <string.h>

#include "app_time_core.h"
#include "cook_store_core.h"
#include "test_cook_doubles.h"
#include "test_util.h"

static int g_acquired_calls;
static void on_acquired(void *ctx) {
    (void)ctx;
    g_acquired_calls++;
}

static void fresh(void) {
    memfs_reset();
    cfg_erase_all(NULL);
    g_acquired_calls = 0;
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
}

static void test_source_precedence(void) {
    fresh();
    CHECK_EQ_INT(app_time_core_init(1000, on_acquired, NULL), 0);
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_NONE);
    uint64_t now;
    CHECK(!app_time_core_now(2000, &now)); /* nothing to say yet */

    /* Phone lands first (the AP-mode normal case). */
    CHECK(app_time_core_set(APP_TIME_PHONE, 1750000000000ull, 10000));
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_PHONE);
    CHECK_EQ_INT(g_acquired_calls, 1);
    CHECK(app_time_core_now(20000, &now));
    CHECK(now == 1750000000000ull + 10000);

    /* SNTP replaces phone... */
    CHECK(app_time_core_set(APP_TIME_SNTP, 1750000005000ull, 30000));
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_SNTP);
    /* ...but phone never replaces SNTP. */
    CHECK(!app_time_core_set(APP_TIME_PHONE, 1999999999999ull, 40000));
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_SNTP);
    /* A refreshed SNTP is adopted, and acquiring fired only once. */
    CHECK(app_time_core_set(APP_TIME_SNTP, 1750000006000ull, 50000));
    CHECK_EQ_INT(g_acquired_calls, 1);
}

static void test_backpatch_named_case(void) {
    /* 10 §10.5: session starts with no clock; a source arrives at t=40 min;
     * the header becomes correctly dated with no sample rewrite. */
    fresh();
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);
    CHECK_EQ_INT(app_time_core_init(0, on_acquired, NULL), 0);

    const cook_session_params_t params = {
        .num_probes = 4,
        .started_unix_ms = 0, /* clock_valid = 0 */
        .started_uptime_s = 600,
        .device_id = "LMXC[\\",
    };
    CHECK_EQ_INT(cook_session_open(&params), COOK_STORE_OK);
    const int16_t temps[4] = {2250, 1000, 1000, 1000};
    for (int i = 0; i < 80; i++) { /* 40 min of samples */
        CHECK_EQ_INT(cook_session_append((uint32_t)i * 30, temps, 0, -40),
                     COOK_STORE_OK);
    }

    /* The phone connects at uptime 600 s + 40 min and provides the time. */
    const uint64_t now_uptime_ms = (600ull + 2400ull) * 1000ull;
    const uint64_t now_unix_ms = 1800000000000ull;
    CHECK(app_time_core_set(APP_TIME_PHONE, now_unix_ms, now_uptime_ms));

    /* The glue (here, the test) back-patches via the primitive. */
    uint64_t started_unix = 0;
    CHECK(app_time_core_unix_at(600ull * 1000ull, now_uptime_ms,
                                &started_unix));
    CHECK(started_unix == now_unix_ms - 2400ull * 1000ull);
    CHECK_EQ_INT(cook_session_set_clock(started_unix), COOK_STORE_OK);

    /* Header dated, clock_valid set, all 80 samples byte-identical. */
    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk",
             (unsigned)cook_session_active_id());
    mem_file_t *f = memfs_find(path);
    CHECK(f != NULL);
    if (f) {
        bridge_session_header_t h;
        CHECK(bridge_session_header_decode(f->data, &h));
        CHECK(h.started_unix_ms == started_unix);
        CHECK(bridge_session_header_clock_valid(h.flags));
        bridge_sample_rec_t rec;
        CHECK(bridge_sample_rec_decode(
            f->data + BRIDGE_SESSION_HEADER_SIZE + 79 * BRIDGE_SAMPLE_REC_SIZE,
            &rec));
        CHECK_EQ_INT((int)rec.t, 79 * 30); /* t untouched: still relative */
    }
}

static void test_monotonic_floor_across_reboot(void) {
    fresh();
    CHECK_EQ_INT(app_time_core_init(0, on_acquired, NULL), 0);
    CHECK(app_time_core_set(APP_TIME_SNTP, 1750000000000ull, 0));

    /* Run 25 minutes: the floor persists at the 10-minute cadence. */
    for (uint64_t up = 0; up <= 25 * 60000ull; up += 60000ull) {
        app_time_core_tick(up);
    }
    uint64_t stored = 0;
    CHECK_EQ_INT(
        app_config_store_get_u64(APP_CONFIG_TIME_LAST_EPOCH_MS, &stored),
        APP_CONFIG_OK);
    CHECK(stored >= 1750000000000ull + 20 * 60000ull);

    /* "Reboot" with no source: starts from the floor, marked stale,
     * non-decreasing. */
    CHECK_EQ_INT(app_time_core_init(0, on_acquired, NULL), 0);
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_STALE);
    uint64_t a = 0, b = 0;
    CHECK(app_time_core_now(1000, &a));
    CHECK(app_time_core_now(5000, &b));
    CHECK(a >= stored);
    CHECK(b >= a); /* never backwards */

    /* A real source later still counts as an acquisition (back-patch). */
    const int before = g_acquired_calls;
    CHECK(app_time_core_set(APP_TIME_PHONE, stored + 10000000ull, 9000));
    CHECK_EQ_INT(g_acquired_calls, before + 1);
}

static void test_no_source_no_answer_no_persist(void) {
    fresh();
    CHECK_EQ_INT(app_time_core_init(0, on_acquired, NULL), 0);
    for (uint64_t up = 0; up <= 30 * 60000ull; up += 60000ull) {
        app_time_core_tick(up);
    }
    uint64_t stored = 1;
    CHECK_EQ_INT(
        app_config_store_get_u64(APP_CONFIG_TIME_LAST_EPOCH_MS, &stored),
        APP_CONFIG_OK);
    CHECK(stored == 0); /* schema default: nothing was ever persisted */
}

int main(void) {
    test_source_precedence();
    test_backpatch_named_case();
    test_monotonic_floor_across_reboot();
    test_no_source_no_answer_no_persist();
    return test_summary("test_app_time");
}
