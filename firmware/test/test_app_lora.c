/* Host tests for app_lora_core (F2.2, F2.3, F2.5): the §1.5 parameter
 * block, the 3.3 s alternating scanner, and the TX guard — including the
 * linked-system assertion that only the sync handler's window reaches TX
 * and a full pairing transmits exactly once. */
#include <string.h>

#include "app_config_store.h"
#include "app_lora_core.h"
#include "smoke_x_ctrl.h"
#include "test_util.h"

static void test_params_match_the_1_5_table(void) {
    const app_lora_params_t *p = app_lora_params();
    CHECK_EQ_INT(p->spreading_factor, 9);
    /* An INDEX, not Hz — the silent misconfiguration §1.5 warns about. */
    CHECK_EQ_INT(p->bandwidth_index, 4);
    CHECK_EQ_INT(p->coding_rate, 1);
    CHECK_EQ_INT(p->preamble_len, 10);
    CHECK_EQ_INT(p->sync_word, 0x12);
    CHECK(p->crc_on);
    CHECK_EQ_INT(p->tx_power_dbm, 22);
    CHECK(p->tcxo_volts > 3.29f && p->tcxo_volts < 3.31f);
    CHECK(p->use_ldo);
}

static void test_scanner_dwell_and_both_channels(void) {
    const uint64_t t0 = 5000;
    /* First dwell: the X4 sync channel. */
    CHECK(app_lora_scan_freq_at(t0, t0) == APP_LORA_SCAN_FREQ_X4);
    CHECK(app_lora_scan_freq_at(t0 + 3299, t0) == APP_LORA_SCAN_FREQ_X4);
    /* Exactly at 3.3 s: flip to the X2 channel. */
    CHECK(app_lora_scan_freq_at(t0 + 3300, t0) == APP_LORA_SCAN_FREQ_X2);
    CHECK(app_lora_scan_freq_at(t0 + 6599, t0) == APP_LORA_SCAN_FREQ_X2);
    /* And back — both channels visited forever, no beat lock. */
    CHECK(app_lora_scan_freq_at(t0 + 6600, t0) == APP_LORA_SCAN_FREQ_X4);
    const uint64_t much_later = t0 + 997u * 3300u;
    CHECK(app_lora_scan_freq_at(much_later, t0) == APP_LORA_SCAN_FREQ_X2);
}

static void test_guard_refuses_outside_window_and_band(void) {
    app_lora_guard_reset();
    CHECK(!app_lora_guard_tx_allowed(918500000u)); /* window closed */
    app_lora_guard_open_sync_window();
    CHECK(app_lora_guard_tx_allowed(918500000u));
    CHECK(!app_lora_guard_tx_allowed(950600000u)); /* out of band */
    CHECK(!app_lora_guard_tx_allowed(0));
    app_lora_guard_close_sync_window();
    CHECK(!app_lora_guard_tx_allowed(918500000u));
}

/* ── Linked-system TX invariant (F2.3's done-when) ─────────────────────── */

typedef struct {
    char ns[16];
    char key[16];
    size_t len;
    uint8_t val[80];
} cfg_entry_t;

static struct {
    cfg_entry_t entries[64];
    int count;
} g_cfg;

static cfg_entry_t *cfg_find(const char *ns, const char *key) {
    for (int i = 0; i < g_cfg.count; i++) {
        if (strcmp(g_cfg.entries[i].ns, ns) == 0 &&
            strcmp(g_cfg.entries[i].key, key) == 0) {
            return &g_cfg.entries[i];
        }
    }
    return NULL;
}

static int cfg_get(void *ctx, const char *ns, const char *key, void *out,
                   size_t *len) {
    (void)ctx;
    cfg_entry_t *e = cfg_find(ns, key);
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

static int cfg_set(void *ctx, const char *ns, const char *key,
                   const void *val, size_t len) {
    (void)ctx;
    cfg_entry_t *e = cfg_find(ns, key);
    if (!e) {
        e = &g_cfg.entries[g_cfg.count++];
        snprintf(e->ns, sizeof e->ns, "%s", ns);
        snprintf(e->key, sizeof e->key, "%s", key);
    }
    memcpy(e->val, val, len);
    e->len = len;
    return APP_CONFIG_OK;
}

static int cfg_erase(void *ctx) {
    (void)ctx;
    g_cfg.count = 0;
    return APP_CONFIG_OK;
}

static const app_config_backend_t g_backend = {
    .get = cfg_get, .set = cfg_set, .erase_all = cfg_erase, .ctx = NULL};

static uint32_t rng(void) { return 3u; }

static uint32_t g_radio_freq;
static int g_tx_attempts;
static int g_tx_accepted;

/* The device glue's TX path, faithfully: guard first, then the radio. */
static int glue_start_tx(const char *payload) {
    (void)payload;
    g_tx_attempts++;
    if (!app_lora_guard_tx_allowed(g_radio_freq)) {
        return -1;
    }
    g_tx_accepted++;
    return 0;
}

static int op_set_frequency(void *ctx, uint32_t hz) {
    (void)ctx;
    g_radio_freq = hz;
    return 0;
}

/* The ONLY caller that opens the window is the sync handler's transmit
 * op — exactly how smoke_x.c wires it on the device. */
static int op_transmit(void *ctx, const char *payload) {
    (void)ctx;
    app_lora_guard_open_sync_window();
    const int rc = glue_start_tx(payload);
    app_lora_guard_close_sync_window();
    return rc;
}

static void op_start_scan(void *ctx) { (void)ctx; }
static void op_publish(void *ctx, smoke_x_evt_t evt, const void *payload) {
    (void)ctx;
    (void)evt;
    (void)payload;
}

static const smoke_x_ops_t g_ops = {
    .set_frequency = op_set_frequency,
    .transmit = op_transmit,
    .start_scan = op_start_scan,
    .publish = op_publish,
};

static void test_only_the_sync_handler_reaches_tx(void) {
    cfg_erase(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_backend, rng), APP_CONFIG_OK);
    app_lora_guard_reset();
    g_radio_freq = 0;
    g_tx_attempts = 0;
    g_tx_accepted = 0;
    CHECK_EQ_INT(smoke_x_ctrl_init(&g_ops, NULL, false, 0), 0);

    /* A full pairing: sync + first state = exactly ONE transmission. */
    CHECK_EQ_INT(smoke_x_ctrl_on_payload("000000,LMXC[\\,160,50,191,54,",
                                         -41, 11, 1000),
                 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload(
                     "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,"
                     "160,32,0,807,0,160,32,0,0,",
                     -39, 10, 31000),
                 0);
    CHECK_EQ_INT(g_tx_accepted, 1);

    /* Any OTHER call path (debug endpoint, stray code) is refused: the
     * window only exists inside the transmit op above. */
    CHECK_EQ_INT(glue_start_tx("LMXC[\\,SUCCESS,"), -1);
    CHECK_EQ_INT(g_tx_accepted, 1);

    /* An out-of-band sync never retunes NOR transmits (invariant 4). */
    const uint32_t freq_before = g_radio_freq;
    const int attempts_before = g_tx_attempts;
    CHECK_EQ_INT(smoke_x_ctrl_unpair(), 0);
    CHECK_EQ_INT(smoke_x_ctrl_on_payload("000000,LMXC[\\,128,113,169,56,",
                                         -41, 11, 60000),
                 -1);
    CHECK(g_radio_freq == freq_before);
    CHECK_EQ_INT(g_tx_attempts, attempts_before);
}

int main(void) {
    test_params_match_the_1_5_table();
    test_scanner_dwell_and_both_channels();
    test_guard_refuses_outside_window_and_band();
    test_only_the_sync_handler_reaches_tx();
    return test_summary("test_app_lora");
}
