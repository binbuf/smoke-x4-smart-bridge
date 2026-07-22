/* Host tests for smoke_x_ctrl (F3.4, F3.6, F3.7): the full pairing
 * transition sequence on real fixtures, X2 vs X4 probe-count learning,
 * the TX and frequency invariants, the watchdog, and packet accounting. */
#include <stdint.h>
#include <string.h>

#include "app_config_store.h"
#include "smoke_x_ctrl.h"
#include "test_util.h"

/* Real vectors from x4-events-10min (2026-07-21). */
static const char *SYNC = "000000,LMXC[\\,160,50,191,54,"; /* 918.5 MHz */
static const char *X4_STATE =
    "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";
static const char *X2_STATE_SAME_ID =
    "LMXC[\\,30,1,1,0,848,1,125,32,0,849,0,260,195,0,0,";
static const char *X4_FOREIGN =
    "ZZZZZ,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";

/* ── In-memory config backend (same double as test_app_config) ─────────── */

typedef struct {
    char ns[16];
    char key[16];
    size_t len;
    uint8_t val[80];
} mem_entry_t;

static struct {
    mem_entry_t entries[64];
    int count;
} g_mem;

static mem_entry_t *mem_find(const char *ns, const char *key) {
    for (int i = 0; i < g_mem.count; i++) {
        if (strcmp(g_mem.entries[i].ns, ns) == 0 &&
            strcmp(g_mem.entries[i].key, key) == 0) {
            return &g_mem.entries[i];
        }
    }
    return NULL;
}

static int mem_get(void *ctx, const char *ns, const char *key, void *out,
                   size_t *len) {
    (void)ctx;
    mem_entry_t *e = mem_find(ns, key);
    if (!e) {
        return APP_CONFIG_ERR_NOT_FOUND;
    }
    if (!out) {
        *len = e->len;
        return APP_CONFIG_OK;
    }
    if (*len < e->len) {
        return APP_CONFIG_ERR;
    }
    memcpy(out, e->val, e->len);
    *len = e->len;
    return APP_CONFIG_OK;
}

static int mem_set(void *ctx, const char *ns, const char *key, const void *val,
                   size_t len) {
    (void)ctx;
    mem_entry_t *e = mem_find(ns, key);
    if (!e) {
        e = &g_mem.entries[g_mem.count++];
        snprintf(e->ns, sizeof e->ns, "%s", ns);
        snprintf(e->key, sizeof e->key, "%s", key);
    }
    memcpy(e->val, val, len);
    e->len = len;
    return APP_CONFIG_OK;
}

static int mem_erase_all(void *ctx) {
    (void)ctx;
    g_mem.count = 0;
    return APP_CONFIG_OK;
}

static const app_config_backend_t g_backend = {
    .get = mem_get, .set = mem_set, .erase_all = mem_erase_all, .ctx = NULL};

static uint32_t fake_rng(void) { return 42u; }

/* ── Radio/event doubles ───────────────────────────────────────────────── */

static uint32_t g_freq_set;
static int g_freq_calls;
static char g_txed[64];
static int g_tx_calls;
static int g_scan_calls;

static int g_evt_counts[8];
static smoke_x_sample_t g_last_sample;

static int op_set_frequency(void *ctx, uint32_t hz) {
    (void)ctx;
    g_freq_set = hz;
    g_freq_calls++;
    return 0;
}

static int op_transmit(void *ctx, const char *payload) {
    (void)ctx;
    /* The frequency must already be the operating one when the ACK goes
     * out — never the sync channel (§2.5 invariant 3). */
    CHECK(g_freq_set == 918500000u);
    snprintf(g_txed, sizeof g_txed, "%s", payload);
    g_tx_calls++;
    return 0;
}

static void op_start_scan(void *ctx) {
    (void)ctx;
    g_scan_calls++;
}

static void op_publish(void *ctx, smoke_x_evt_t evt, const void *payload) {
    (void)ctx;
    g_evt_counts[evt]++;
    if (evt == SMOKE_X_EVT_SAMPLE) {
        memcpy(&g_last_sample, payload, sizeof g_last_sample);
    }
}

static const smoke_x_ops_t g_ops = {
    .set_frequency = op_set_frequency,
    .transmit = op_transmit,
    .start_scan = op_start_scan,
    .publish = op_publish,
};

static void reset_doubles(void) {
    g_freq_set = 0;
    g_freq_calls = 0;
    g_txed[0] = '\0';
    g_tx_calls = 0;
    g_scan_calls = 0;
    memset(g_evt_counts, 0, sizeof g_evt_counts);
}

static void fresh_ctrl(bool rescan) {
    mem_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);
    reset_doubles();
    CHECK_EQ_INT(smoke_x_ctrl_init(&g_ops, NULL, rescan, 0), 0);
}

/* ── Tests ─────────────────────────────────────────────────────────────── */

static void test_full_pairing_flow_x4(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_UNPAIRED);
    CHECK_EQ_INT(g_scan_calls, 1); /* unpaired boot starts the scan */

    /* Sync: retune, ACK, no persistence yet. */
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_SYNC_RECEIVED);
    CHECK(g_freq_set == 918500000u);
    CHECK_EQ_INT(g_tx_calls, 1);
    CHECK(strcmp(g_txed, "LMXC[\\,SUCCESS,") == 0);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_SYNCED], 1);
    app_config_pairing_t p;
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_ERR_NOT_FOUND);

    /* First state message: probe count learned HERE, pairing persisted. */
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_CONFIRMED);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_PAIRED], 1);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_SAMPLE], 1);
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_OK);
    CHECK_EQ_INT(p.num_probes, 4);
    CHECK(p.frequency == 918500000u);
    CHECK(strcmp(p.device_id, "LMXC[\\") == 0);

    /* The sample carries link quality (F2.4). */
    CHECK_EQ_INT(g_last_sample.rssi, -39);
    CHECK_EQ_INT(g_last_sample.snr, 10);
    CHECK_EQ_INT(g_last_sample.state.num_probes, 4);

    /* Exactly one transmission per pairing (§2.5 invariant 1). */
    CHECK_EQ_INT(g_tx_calls, 1);
}

static void test_x2_confirms_two_probes_from_same_sync(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X2_STATE_SAME_ID, -50, 8, 4000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_CONFIRMED);
    app_config_pairing_t p;
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_OK);
    CHECK_EQ_INT(p.num_probes, 2);
}

static void test_syncs_ignored_after_sync_received(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 2000), -1);
    CHECK_EQ_INT(g_tx_calls, 1); /* no second ACK */
    CHECK_EQ_INT((int)smoke_x_ctrl_stats()->sync_ignored, 1);

    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 32000), -1);
    CHECK_EQ_INT((int)smoke_x_ctrl_stats()->sync_ignored, 2);
}

static void test_out_of_band_sync_rejected_before_retune(void) {
    fresh_ctrl(false);
    /* 128,113,169,56 LE → 950,628,736 Hz ≈ 950.6 MHz. Outside 902–928. */
    CHECK_EQ_INT(
        smoke_x_ctrl_on_payload("000000,LMXC[\\,128,113,169,56,", -41, 11,
                                1000),
        -1);
    CHECK_EQ_INT(g_freq_calls, 0); /* never retuned (§2.5 invariant 4) */
    CHECK_EQ_INT(g_tx_calls, 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_UNPAIRED);
}

static void test_foreign_device_dropped_and_counted(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);

    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_FOREIGN, -70, 5, 61000), -1);
    CHECK_EQ_INT((int)smoke_x_ctrl_stats()->id_mismatch, 1);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_SAMPLE], 1); /* not published */
}

static void test_unpair_clears_and_rescans(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);

    const int scans_before = g_scan_calls;
    CHECK_EQ_INT(smoke_x_ctrl_unpair(), 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_UNPAIRED);
    CHECK_EQ_INT(g_scan_calls, scans_before + 1);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_UNPAIRED], 1);
    app_config_pairing_t p;
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_ERR_NOT_FOUND);
    /* Unpairing transmits nothing — other receivers are untouched. */
    CHECK_EQ_INT(g_tx_calls, 1);

    /* A fresh sync is accepted again. */
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 90000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_SYNC_RECEIVED);
}

static void test_boot_with_persisted_pairing(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);

    /* "Reboot": re-init against the same backing store. */
    reset_doubles();
    CHECK_EQ_INT(smoke_x_ctrl_init(&g_ops, NULL, false, 0), 0);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_CONFIRMED);
    CHECK(g_freq_set == 918500000u); /* tuned straight to the stored freq */
    CHECK_EQ_INT(g_scan_calls, 0);
    CHECK_EQ_INT(g_tx_calls, 0); /* a reboot never re-ACKs */
}

static void test_watchdog_base_lost_and_found(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);

    /* Just under the threshold: quiet. */
    smoke_x_ctrl_tick(31000 + SMOKE_X_BASE_LOST_TIMEOUT_MS - 1);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_BASE_LOST], 0);

    /* At the threshold: fires exactly once, not on every tick. */
    smoke_x_ctrl_tick(31000 + SMOKE_X_BASE_LOST_TIMEOUT_MS);
    smoke_x_ctrl_tick(31000 + SMOKE_X_BASE_LOST_TIMEOUT_MS + 5000);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_BASE_LOST], 1);

    /* A valid packet recovers. */
    const uint64_t later = 31000 + SMOKE_X_BASE_LOST_TIMEOUT_MS + 60000;
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -60, 6, later), 0);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_BASE_FOUND], 1);
    smoke_x_ctrl_tick(later + 1000);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_BASE_LOST], 1); /* re-armed, quiet */
}

static void test_rescan_stays_off_by_default(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);
    const int scans_before = g_scan_calls;

    smoke_x_ctrl_tick(31000 + SMOKE_X_RESCAN_TIMEOUT_MS + 1000);
    CHECK_EQ_INT(g_scan_calls, scans_before); /* does not engage */
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_CONFIRMED);
}

static void test_rescan_when_enabled_and_no_active_cook(void) {
    fresh_ctrl(true);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);

    /* An active cook blocks it. */
    CHECK_EQ_INT(app_config_store_set_u32(APP_CONFIG_SESSION_ACTIVE_ID, 7),
                 APP_CONFIG_OK);
    smoke_x_ctrl_tick(31000 + SMOKE_X_RESCAN_TIMEOUT_MS + 1000);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_CONFIRMED);

    /* Cook over: the scan resumes, pairing stays persisted. */
    CHECK_EQ_INT(app_config_store_set_u32(APP_CONFIG_SESSION_ACTIVE_ID, 0),
                 APP_CONFIG_OK);
    smoke_x_ctrl_tick(31000 + SMOKE_X_RESCAN_TIMEOUT_MS + 2000);
    CHECK_EQ_INT(smoke_x_ctrl_state(), SMOKE_X_UNPAIRED);
    CHECK_EQ_INT(g_evt_counts[SMOKE_X_EVT_RESCAN], 1);
    app_config_pairing_t p;
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_OK);
}

static void test_accounting(void) {
    fresh_ctrl(false);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(SYNC, -41, 11, 1000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 31000), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 61300), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(X4_STATE, -39, 10, 137000), 0);

    CHECK_EQ_INT(smoke_x_ctrl_on_payload("junk,with,commas", 0, 0, 140000),
                 -1);
    CHECK_EQ_INT(
        smoke_x_ctrl_on_payload(
            "LMXC[\\,30,1,1,0,8x8,0,160,32,0,801,0,160,32,0,807,0,160,32,0,"
            "807,0,160,32,0,0,",
            0, 0, 141000),
        -1);
    smoke_x_ctrl_note_crc_error();

    const smoke_x_stats_t *st = smoke_x_ctrl_stats();
    CHECK_EQ_INT((int)st->valid, 3);
    CHECK_EQ_INT((int)st->unknown_commas, 1);
    CHECK_EQ_INT((int)st->parse_fail, 1);
    CHECK_EQ_INT((int)st->crc_fail, 1);
    /* Intervals: 30.3 s and 75.7 s → buckets 1 and 2. */
    CHECK_EQ_INT((int)st->interval_hist[1], 1);
    CHECK_EQ_INT((int)st->interval_hist[2], 1);
}

int main(void) {
    test_full_pairing_flow_x4();
    test_x2_confirms_two_probes_from_same_sync();
    test_syncs_ignored_after_sync_received();
    test_out_of_band_sync_rejected_before_retune();
    test_foreign_device_dropped_and_counted();
    test_unpair_clears_and_rescans();
    test_boot_with_persisted_pairing();
    test_watchdog_base_lost_and_found();
    test_rescan_stays_off_by_default();
    test_rescan_when_enabled_and_no_active_cook();
    test_accounting();
    return test_summary("test_smoke_x_ctrl");
}
