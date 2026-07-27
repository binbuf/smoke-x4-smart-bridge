/* T4.2: replay a captured .loralog through the full host stack — radio
 * payloads → pairing controller → lifecycle → cook_store appends — and
 * prove the resulting .smk is byte-identical on repeat runs. One captured
 * cook becomes an unlimited, deterministic test fixture. */
#include <string.h>

#include "cook_lifecycle.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"
#include "test_cook_doubles.h"
#include "test_loralog_reader.h"
#include "test_util.h"

#define MAX_LINES 512

static loralog_line_t g_log[MAX_LINES];
static int g_log_count;

static cook_lifecycle_t g_lc;

/* The same canonicalisation the device glue applies (04 §4.2). */
static int16_t to_f10(int16_t v, smoke_x_units_t units) {
    if (v == SMOKE_X_TEMP_DETACHED || v == SMOKE_X_TEMP_INVALID) {
        return v;
    }
    return units == SMOKE_X_UNITS_F ? v
                                    : (int16_t)(((int32_t)v * 9) / 5 + 320);
}

static void on_sample(const smoke_x_sample_t *s) {
    int16_t temps[4];
    uint8_t flags = 0;
    bool any_attached = false;
    for (int i = 0; i < 4; i++) {
        temps[i] = i < s->state.num_probes
                       ? to_f10(s->state.probes[i].temp_x10, s->state.units)
                       : BRIDGE_TEMP_DETACHED;
        if (i < s->state.num_probes && s->state.probes[i].alarm_armed) {
            flags |= (uint8_t)(1u << i);
        }
        if (temps[i] != BRIDGE_TEMP_DETACHED &&
            temps[i] != BRIDGE_TEMP_INVALID) {
            any_attached = true;
        }
    }
    if (s->state.billows_attached) {
        flags |= BRIDGE_SAMPLE_REC_FLAGS_BILLOWS;
    }
    if (s->state.new_alarm) {
        flags |= BRIDGE_SAMPLE_REC_FLAGS_NEW_ALARM;
    }
    if (s->state.units == SMOKE_X_UNITS_C) {
        flags |= BRIDGE_SAMPLE_REC_FLAGS_SOURCE_CELSIUS;
    }

    const uint32_t now_s = (uint32_t)(s->t_ms / 1000u);
    const cook_lc_input_t in = {
        .now_s = now_s,
        .paired = true,
        .sample = true,
        .any_attached = any_attached,
    };
    if (cook_lifecycle_step(&g_lc, &in) == COOK_LC_START) {
        app_config_pairing_t p;
        const char *dev = app_config_store_get_pairing(&p) == APP_CONFIG_OK
                              ? p.device_id
                              : "";
        const cook_session_params_t params = {
            .num_probes = s->state.num_probes,
            .started_unix_ms = 0,
            .started_uptime_s = now_s,
            .device_id = dev,
        };
        CHECK_EQ_INT(cook_session_open(&params), COOK_STORE_OK);
        cook_lifecycle_note_started(&g_lc, now_s);
    }
    if (cook_session_is_open()) {
        const uint32_t t = now_s - cook_session_started_uptime_s();
        CHECK_EQ_INT(cook_session_append(t, temps, flags, s->rssi),
                     COOK_STORE_OK);
    }
}

static int op_set_frequency(void *ctx, uint32_t hz) {
    (void)ctx;
    (void)hz;
    return 0;
}
static int op_transmit(void *ctx, const char *payload) {
    (void)ctx;
    (void)payload;
    return 0;
}
static void op_start_scan(void *ctx) { (void)ctx; }
static void op_publish(void *ctx, smoke_x_evt_t evt, const void *payload) {
    (void)ctx;
    if (evt == SMOKE_X_EVT_SAMPLE) {
        on_sample(payload);
    }
}

static const smoke_x_ops_t g_ops = {
    .set_frequency = op_set_frequency,
    .transmit = op_transmit,
    .start_scan = op_start_scan,
    .publish = op_publish,
};

/* Runs the whole replay; returns the session's .smk contents. */
static size_t run_replay(uint8_t *out, size_t cap, uint32_t *session_id) {
    memfs_reset();
    cfg_erase_all(NULL);
    if (app_config_store_init(&g_cfg_backend, cfg_rng) != APP_CONFIG_OK ||
        cook_store_core_init(&g_vfs, NULL, NULL) != COOK_STORE_OK ||
        smoke_x_ctrl_init(&g_ops, NULL, false, 0) != 0) {
        return 0;
    }
    cook_lifecycle_reset(&g_lc);

    for (int i = 0; i < g_log_count; i++) {
        const loralog_line_t *e = &g_log[i];
        if (e->is_tx) {
            continue;
        }
        (void)smoke_x_ctrl_on_payload(e->payload, (int8_t)e->rssi,
                                      (int8_t)e->snr, e->t_ms);
    }
    if (!cook_session_is_open()) {
        return 0;
    }
    *session_id = cook_session_active_id();
    CHECK_EQ_INT(cook_session_close(0), COOK_STORE_OK);

    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk",
             (unsigned)*session_id);
    mem_file_t *f = memfs_find(path);
    if (!f || f->len > cap) {
        return 0;
    }
    memcpy(out, f->data, f->len);
    return f->len;
}

static uint8_t g_run1[64 * 1024];
static uint8_t g_run2[64 * 1024];

static void test_replay_is_deterministic(void) {
    char path[256];
    snprintf(path, sizeof path, "%s/x4-events-10min.loralog",
             FIXTURES_LORA_DIR);
    g_log_count = loralog_read(path, g_log, MAX_LINES);
    CHECK(g_log_count > 30);

    uint32_t id1 = 0, id2 = 0;
    const size_t len1 = run_replay(g_run1, sizeof g_run1, &id1);
    const size_t len2 = run_replay(g_run2, sizeof g_run2, &id2);

    /* The hot-water probe crossed 90 °F mid-capture, so the lifecycle
     * auto-started a session; the file must replay byte-identically. */
    CHECK(len1 > BRIDGE_SESSION_HEADER_SIZE);
    CHECK_EQ_INT((int)len1, (int)len2);
    CHECK_EQ_INT((int)id1, (int)id2);
    CHECK(memcmp(g_run1, g_run2, len1) == 0);

    /* And the session is real: header + a plausible number of samples. */
    bridge_session_header_t h;
    CHECK(bridge_session_header_decode(g_run1, &h));
    CHECK(bridge_session_header_closed(h.flags));
    CHECK(h.sample_count >= 20);
    CHECK_EQ_INT(h.num_probes, 4);
    CHECK_EQ_INT((int)(len1 - BRIDGE_SESSION_HEADER_SIZE),
                 (int)(h.sample_count * BRIDGE_SAMPLE_REC_SIZE));

    /* The capture's dropouts survive as t-gaps, not compressed time. */
    bool found_gap = false;
    for (uint32_t i = 1; i < h.sample_count; i++) {
        bridge_sample_rec_t a, b;
        CHECK(bridge_sample_rec_decode(
            g_run1 + BRIDGE_SESSION_HEADER_SIZE +
                (i - 1) * BRIDGE_SAMPLE_REC_SIZE,
            &a));
        CHECK(bridge_sample_rec_decode(
            g_run1 + BRIDGE_SESSION_HEADER_SIZE + i * BRIDGE_SAMPLE_REC_SIZE,
            &b));
        if (b.t - a.t > 45) {
            found_gap = true;
        }
    }
    CHECK(found_gap);
}

int main(void) {
    test_replay_is_deterministic();
    return test_summary("test_replay");
}
