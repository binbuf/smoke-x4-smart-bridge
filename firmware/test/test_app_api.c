/* Host tests for app_api (F9.1–F9.10, F8.7, F4.5, F4.6 + the F9.11
 * conformance checks that can run without a live sim): the router over the
 * REAL host-tested modules (config, ctrl, cook_store, ring, time, net),
 * fixture byte-conformance after whitespace normalisation, the streaming
 * bound, and every detached-probe-is-null invariant. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app_api_core.h"
#include "app_api_ws.h"
#include "app_config_store.h"
#include "app_time_core.h"
#include "cook_novelty_log.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"
#include "smoke_x_pktring.h"
#include "test_cook_doubles.h"
#include "test_util.h"

/* ── response capture ─────────────────────────────────────────────────── */

static char g_body[128 * 1024];
static size_t g_body_len;

static int capture_sink(void *ctx, const char *data, size_t len) {
    (void)ctx;
    if (g_body_len + len < sizeof g_body) {
        memcpy(g_body + g_body_len, data, len);
        g_body_len += len;
    }
    return 0;
}

static app_api_out_t g_out;

static void do_req(const char *method, const char *path_and_query,
                   const char *body, const char *bearer) {
    g_body_len = 0;
    app_api_req_t req = {0};
    req.method = method;
    static char path[256];
    snprintf(path, sizeof path, "%s", path_and_query);
    char *q = strchr(path, '?');
    if (q) {
        *q++ = '\0';
        while (q && *q) {
            char *amp = strchr(q, '&');
            if (amp) {
                *amp = '\0';
            }
            char *eq = strchr(q, '=');
            if (eq && req.query_count < APP_API_MAX_QUERY) {
                *eq = '\0';
                snprintf(req.query[req.query_count].key,
                         sizeof req.query[0].key, "%s", q);
                snprintf(req.query[req.query_count].value,
                         sizeof req.query[0].value, "%s", eq + 1);
                req.query_count++;
            }
            q = amp ? amp + 1 : NULL;
        }
    }
    req.path = path;
    req.body = body;
    req.body_len = body ? strlen(body) : 0;
    req.bearer = bearer;
    app_api_out_init(&g_out, capture_sink, NULL);
    CHECK_EQ_INT(app_api_handle(&req, &g_out), 0);
    (void)app_api_out_finish(&g_out);
    g_body[g_body_len] = '\0';
}

/* Whitespace-insensitive JSON equality: both sides normalised by dropping
 * whitespace outside strings. Key ORDER still matters — that is the
 * contract-lock the fixtures provide. */
static void normalize_json(const char *in, char *out, size_t cap) {
    size_t n = 0;
    bool in_str = false;
    for (const char *p = in; *p && n + 1 < cap; p++) {
        if (*p == '"' && (p == in || p[-1] != '\\')) {
            in_str = !in_str;
        }
        if (!in_str &&
            (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t')) {
            continue;
        }
        out[n++] = *p;
    }
    out[n] = '\0';
}

static void check_matches_fixture(const char *fixture_name) {
    char path[300];
    snprintf(path, sizeof path, "%s/%s", FIXTURES_HTTP_DIR, fixture_name);
    FILE *f = fopen(path, "rb");
    CHECK(f != NULL);
    if (!f) {
        return;
    }
    static char raw[8192], want[8192], got[8192];
    const size_t n = fread(raw, 1, sizeof raw - 1, f);
    raw[n] = '\0';
    fclose(f);
    normalize_json(raw, want, sizeof want);
    normalize_json(g_body, got, sizeof got);
    if (strcmp(want, got) != 0) {
        fprintf(stderr, "fixture %s mismatch:\nWANT %s\nGOT  %s\n",
                fixture_name, want, got);
    }
    CHECK(strcmp(want, got) == 0);
}

/* ── seeded world ─────────────────────────────────────────────────────── */

static uint64_t g_uptime_ms = 1000000;

static void ops_sysinfo(app_api_sysinfo_t *out) {
    memset(out, 0, sizeof *out);
    snprintf(out->id, sizeof out->id, "A4F2");
    out->model = "heltec-v3";
    out->fw = "1.0.0";
    out->reset_reason = "poweron";
    out->uptime_s = (uint32_t)(g_uptime_ms / 1000u);
    out->free_heap = 168432;
    out->min_free_heap = 141008;
    out->storage_total_b = 2490368;
    out->storage_used_b = 214016;
    out->storage_free_pct = 91;
}

static void ops_net(app_api_net_snapshot_t *out) {
    memset(out, 0, sizeof *out);
    snprintf(out->mode, sizeof out->mode, "sta");
    snprintf(out->state, sizeof out->state, "up");
    snprintf(out->ssid, sizeof out->ssid, "Backyard");
    out->rssi = -54;
    snprintf(out->ip, sizeof out->ip, "192.168.1.42");
    snprintf(out->host, sizeof out->host, "smokebridge.local");
}

static app_net_pending_cfg_t g_last_cfg;
static int g_cfg_requests;

static int ops_request_config(const app_net_pending_cfg_t *cfg) {
    g_last_cfg = *cfg;
    g_cfg_requests++;
    return 0;
}

static uint8_t g_coredump[300];
static size_t g_coredump_size;

static size_t ops_coredump_size(void) { return g_coredump_size; }

static int ops_coredump_read(size_t off, void *buf, size_t n) {
    memcpy(buf, g_coredump + off, n);
    return (int)n;
}

static bool ops_www(void) { return false; }

static uint64_t ops_uptime(void) { return g_uptime_ms; }

static const app_api_ops_t g_api_ops = {
    .sysinfo = ops_sysinfo,
    .net_status = ops_net,
    .net_request_config = ops_request_config,
    .coredump_size = ops_coredump_size,
    .coredump_read = ops_coredump_read,
    .www_available = ops_www,
    .uptime_ms = ops_uptime,
};

/* smoke_x_ctrl radio double (pairing endpoints drive the real ctrl). */
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
    /* The fixture credentials: SmokeBridge-A4F2 / Gk7mR2xQpT. */
    CHECK_EQ_INT(app_config_store_set_str(APP_CONFIG_NET_AP_PSK,
                                          "Gk7mR2xQpT"),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);
    CHECK_EQ_INT(smoke_x_ctrl_init(&g_radio_ops, NULL, false, 0), 0);
    cook_ring_reset();
    smoke_x_pktring_reset();
    CHECK_EQ_INT(app_time_core_init(0, NULL, NULL), 0);
    CHECK_EQ_INT(app_api_core_init(&g_api_ops), 0);
    g_coredump_size = 0;
    g_cfg_requests = 0;
}

/* ── tests ────────────────────────────────────────────────────────────── */

static void test_captive_probes_exact_bytes(void) {
    seed_world();
    do_req("GET", "/generate_204", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 204);
    CHECK_EQ_INT((int)g_body_len, 0);
    do_req("GET", "/gen_204", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 204);
    do_req("GET", "/hotspot-detect.html", NULL, NULL);
    CHECK(strcmp(g_body, "<HTML><HEAD><TITLE>Success</TITLE></HEAD>"
                         "<BODY>Success</BODY></HTML>") == 0);
    do_req("GET", "/ncsi.txt", NULL, NULL);
    CHECK(strcmp(g_body, "Microsoft NCSI") == 0);
    do_req("GET", "/connecttest.txt", NULL, NULL);
    CHECK(strcmp(g_body, "Microsoft Connect Test") == 0);
}

static void test_router_auth_and_errors(void) {
    seed_world();
    do_req("GET", "/api/v1/nope", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 404);
    CHECK(strstr(g_body, "\"not_found\"") != NULL);

    /* POST /ota is deliberately unregistered until F14: honest 404. */
    do_req("POST", "/api/v1/ota", "", NULL);
    CHECK_EQ_INT(g_out.status, 404);

    /* Auth gate: unset → open. */
    do_req("GET", "/api/v1/pairing", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    /* Set → 401 without or with a wrong token, JSON envelope. */
    CHECK_EQ_INT(app_config_store_set_str(APP_CONFIG_DEV_API_TOKEN, "s3cret"),
                 APP_CONFIG_OK);
    do_req("GET", "/api/v1/pairing", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 401);
    check_matches_fixture("error-unauthorized.json");
    do_req("GET", "/api/v1/pairing", NULL, "wrong");
    CHECK_EQ_INT(g_out.status, 401);
    do_req("GET", "/api/v1/pairing", NULL, "s3cret");
    CHECK_EQ_INT(g_out.status, 200);
    /* Captive probes are never gated. */
    do_req("GET", "/generate_204", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 204);
    CHECK_EQ_INT(app_config_store_set_str(APP_CONFIG_DEV_API_TOKEN, ""),
                 APP_CONFIG_OK);
}

static void test_emitter_streams_100kb_through_2kb(void) {
    app_api_out_t out;
    app_api_out_init(&out, capture_sink, NULL);
    g_body_len = 0;
    app_api_out_begin(&out, 200, "text/plain");
    char chunk[100];
    memset(chunk, 'x', sizeof chunk);
    for (int i = 0; i < 1024; i++) {
        app_api_emit_raw(&out, chunk, sizeof chunk);
    }
    const size_t total = app_api_out_finish(&out);
    CHECK_EQ_INT((int)total, 1024 * 100);
    CHECK((int)out.peak <= APP_API_EMIT_BUF); /* the F9.2 bound */
}

static void test_status_shape(void) {
    seed_world();
    do_req("GET", "/api/v1/status", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    /* Section order is the contract's; spot-check the spine. */
    const char *sections[] = {"\"device\":{", "\"time\":{",   "\"net\":{",
                              "\"ble\":{",    "\"pairing\":{", "\"radio\":{",
                              "\"storage\":{", "\"power\":{",  "\"session\":{",
                              "\"alarms\":["};
    const char *prev = g_body;
    for (size_t i = 0; i < sizeof sections / sizeof sections[0]; i++) {
        const char *found = strstr(g_body, sections[i]);
        CHECK(found != NULL);
        CHECK(found >= prev);
        prev = found;
    }
    /* Honest degenerates: BLE off, power null — never invented. */
    CHECK(strstr(g_body, "\"advertising\":false") != NULL);
    CHECK(strstr(g_body, "\"mv\":null") != NULL);
    CHECK(strstr(g_body, "\"id\":\"A4F2\"") != NULL);
}

static void test_live_detached_never_zero(void) {
    seed_world();
    for (int i = 0; i < 20; i++) {
        const cook_ring_sample_t s = {
            .t = (uint32_t)i * 30,
            .temp = {(int16_t)(2250 + i), BRIDGE_TEMP_DETACHED, 950,
                     BRIDGE_TEMP_DETACHED},
            .flags = 0x01, /* p1 alarm armed */
            .rssi = -40,
        };
        cook_ring_push(&s);
    }
    do_req("GET", "/api/v1/live?window=600", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(strstr(g_body, "\"n\":2,\"attached\":false,\"temp_f10\":null") !=
          NULL);
    CHECK(strstr(g_body, "\"temp_f10\":2269") != NULL);
    /* Whole-window-detached series are null; no zero anywhere near p2. */
    CHECK(strstr(g_body, "\"series\":[[") != NULL);
    CHECK(strstr(g_body, "],null,[") != NULL); /* p2 series is null */
    /* p1 rate exists (20 samples, 10-min ramp) and p3 flat. */
    CHECK(strstr(g_body, "\"rate_f_per_hr\":") != NULL);
}

static void seed_session(uint32_t n_samples) {
    const cook_session_params_t params = {
        .num_probes = 4,
        .started_unix_ms = 1774051200000ull,
        .started_uptime_s = 100,
        .name = "Brisket",
        .device_id = "LMXC[\\",
    };
    CHECK_EQ_INT(cook_session_open(&params), COOK_STORE_OK);
    for (uint32_t i = 0; i < n_samples; i++) {
        const int16_t temps[4] = {(int16_t)(2250 + (i % 5)),
                                  (int16_t)(1400 + i / 4),
                                  BRIDGE_TEMP_DETACHED, 950};
        CHECK_EQ_INT(cook_session_append(i * 30, temps, 0x40, -42),
                     COOK_STORE_OK);
    }
}

static void test_sessions_group(void) {
    seed_world();
    seed_session(10);

    do_req("GET", "/api/v1/sessions", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(strstr(g_body, "\"name\":\"Brisket\"") != NULL);
    CHECK(strstr(g_body, "\"closed\":false") != NULL);

    /* POST while active: the fixture envelope, exactly. */
    do_req("POST", "/api/v1/sessions", "{}", NULL);
    CHECK_EQ_INT(g_out.status, 409);
    CHECK(strstr(g_body, "\"session_active\"") != NULL);

    /* Unknown id: the fixture body byte-for-byte (id 42). */
    do_req("GET", "/api/v1/sessions/42", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 404);
    check_matches_fixture("error-session_not_found.json");

    /* PATCH rename + pin on the ACTIVE session. */
    const uint32_t id = cook_session_active_id();
    char path[64];
    snprintf(path, sizeof path, "/api/v1/sessions/%u", (unsigned)id);
    do_req("PATCH", path, "{\"name\":\"Renamed\",\"pinned\":true}", NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(strstr(g_body, "\"name\":\"Renamed\"") != NULL);
    CHECK(strstr(g_body, "\"pinned\":true") != NULL);

    /* DELETE the active session: refused. */
    do_req("DELETE", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 409);

    /* Stop it (host hook closes directly), then DELETE works. */
    snprintf(path, sizeof path, "/api/v1/sessions/%u/stop", (unsigned)id);
    do_req("POST", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(!cook_session_is_open());
    snprintf(path, sizeof path, "/api/v1/sessions/%u", (unsigned)id);
    do_req("DELETE", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(cook_store_index_find(id) == NULL);
}

static void test_samples_formats(void) {
    seed_world();
    seed_session(120);
    const uint32_t id = cook_session_active_id();
    char path[128];

    /* bin: byte-identical to the stored records. */
    snprintf(path, sizeof path, "/api/v1/sessions/%u/samples?format=bin",
             (unsigned)id);
    do_req("GET", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK_EQ_INT((int)g_body_len, 120 * 16);
    bridge_sample_rec_t rec;
    CHECK(bridge_sample_rec_decode((const uint8_t *)g_body, &rec));
    CHECK_EQ_INT((int)rec.t, 0);
    CHECK_EQ_INT(rec.temp[0], 2250);

    /* csv: header + empty fields for the detached probe, never 0. */
    snprintf(path, sizeof path, "/api/v1/sessions/%u/samples?format=csv",
             (unsigned)id);
    do_req("GET", path, NULL, NULL);
    CHECK(strncmp(g_body, "t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi\n",
                  45) == 0);
    /* Row shape: t,iso,p1,p2,,p4,... — p3 is EMPTY. */
    CHECK(strstr(g_body, ",225.0,140.0,,95.0,0,-42") != NULL);

    /* bad params: sim-identical messages. */
    snprintf(path, sizeof path,
             "/api/v1/sessions/%u/samples?format=xml", (unsigned)id);
    do_req("GET", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 400);
    CHECK(strstr(g_body, "bad agg/format") != NULL);
    snprintf(path, sizeof path, "/api/v1/sessions/%u/samples?stride=0",
             (unsigned)id);
    do_req("GET", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 400);
    CHECK(strstr(g_body, "bad range/stride/bucket") != NULL);
}

static void test_samples_bucketed_24h(void) {
    seed_world();
    seed_session(2880); /* a 24 h cook */
    const uint32_t id = cook_session_active_id();
    char path[128];
    snprintf(path, sizeof path,
             "/api/v1/sessions/%u/samples?bucket=90&agg=minmax&probes=1,2",
             (unsigned)id);
    do_req("GET", path, NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(strstr(g_body, "\"count\":960") != NULL); /* 86,370/90 → 960 */
    CHECK(strstr(g_body, "\"agg\":\"minmax\"") != NULL);
    CHECK(strstr(g_body, "\"probes\":[1,2]") != NULL);
    CHECK(strstr(g_body, "\"min\":[") != NULL);
    CHECK(strstr(g_body, "\"max\":[") != NULL);
    CHECK(strstr(g_body, "\"gaps\":[]") != NULL);
    /* Peak buffer bound held through the biggest JSON body we produce. */
    CHECK((int)g_out.peak <= APP_API_EMIT_BUF);
}

static void test_config_wifi_fixture_bytes(void) {
    seed_world();
    do_req("POST", "/api/v1/config/wifi", "{\"mode\":\"ap\"}", NULL);
    CHECK_EQ_INT(g_out.status, 200);
    check_matches_fixture("config-wifi-accept-ap.json");
    CHECK_EQ_INT(g_cfg_requests, 1);

    do_req("POST", "/api/v1/config/wifi",
           "{\"mode\":\"sta\",\"ssid\":\"Backyard\",\"psk\":\"pw\"}", NULL);
    check_matches_fixture("config-wifi-accept-sta.json");
    CHECK_EQ_INT(g_cfg_requests, 2);
    CHECK(strcmp(g_last_cfg.sta_ssid, "Backyard") == 0);

    do_req("POST", "/api/v1/config/wifi", "{\"mode\":\"eth\"}", NULL);
    CHECK_EQ_INT(g_out.status, 400);
    CHECK(strstr(g_body, "unsupported_mode") != NULL);
    CHECK_EQ_INT(g_cfg_requests, 2); /* nothing applied */

    /* GET never leaks the stored STA password. */
    CHECK_EQ_INT(app_config_store_set_str(APP_CONFIG_NET_STA_PSK,
                                          "correct horse"),
                 APP_CONFIG_OK);
    do_req("GET", "/api/v1/config/wifi", NULL, NULL);
    CHECK(strstr(g_body, "correct horse") == NULL);
    CHECK(strstr(g_body, "Gk7mR2xQpT") != NULL); /* AP PSK IS returned */
}

static void test_time_backpatches_open_session(void) {
    seed_world();
    seed_session(80); /* opened with clock... */
    /* Reopen with no clock to exercise the back-patch. */
    (void)cook_store_request_stop();
    const cook_session_params_t params = {.num_probes = 4,
                                          .started_uptime_s = 100,
                                          .device_id = "LMXC[\\"};
    CHECK_EQ_INT(cook_session_open(&params), COOK_STORE_OK);
    CHECK(!cook_session_clock_valid());

    do_req("POST", "/api/v1/time",
           "{\"unix_ms\":1774094400000,\"tz_offset_min\":-300}", NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK_EQ_INT(app_time_core_source(), APP_TIME_PHONE);
    int32_t tz = 0;
    (void)app_config_store_get_i32(APP_CONFIG_TIME_TZ_OFFSET_MIN, &tz);
    CHECK_EQ_INT((int)tz, -300);

    do_req("POST", "/api/v1/time", "{\"unix_ms\":\"soon\"}", NULL);
    CHECK_EQ_INT(g_out.status, 400);
}

static void test_radio_conservative_post(void) {
    seed_world();
    do_req("GET", "/api/v1/radio", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(strstr(g_body, "\"spreading_factor\":9") != NULL);
    CHECK(strstr(g_body, "\"intervals\":[") != NULL);

    /* Any parameter mutation on a paired bridge: refused, radio untouched
     * (the F9.8 conservative reading; out-of-band doubly so). */
    do_req("POST", "/api/v1/radio", "{\"frequency_hz\":950600000}", NULL);
    CHECK_EQ_INT(g_out.status, 400);
    do_req("POST", "/api/v1/radio", "{}", NULL);
    CHECK_EQ_INT(g_out.status, 200);
}

static void test_debug_endpoints(void) {
    seed_world();
    smoke_x_pktring_push("LMXC[\\,30,1,1,0,800,0,160,32,0,0,", -41, 11,
                        5000);
    smoke_x_pktring_push("000000,LMXC[\\,160,50,191,54,", -38, 10, 35000);
    do_req("GET", "/api/v1/debug/packets", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    /* Newest LAST, the sim's order. */
    const char *first = strstr(g_body, "\"uptime_s\":5");
    const char *second = strstr(g_body, "\"uptime_s\":35");
    CHECK(first != NULL && second != NULL && first < second);

    /* Novelty log streams as text/plain through the emitter. */
    CHECK_EQ_INT(cook_novelty_log_init(&g_vfs), COOK_STORE_OK);
    CHECK_EQ_INT(cook_novelty_log_append(1000, "sync", "000000@918500000",
                                         "000000,LMXC[\\,160,50,191,54,"),
                 COOK_STORE_OK);
    do_req("GET", "/api/v1/debug/novelty", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK(strstr(g_body, "1000 sync 000000@918500000") != NULL);

    /* Coredump: 404 without, bytes with. */
    do_req("GET", "/api/v1/debug/coredump", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 404);
    g_coredump_size = sizeof g_coredump;
    for (size_t i = 0; i < sizeof g_coredump; i++) {
        g_coredump[i] = (uint8_t)i;
    }
    do_req("GET", "/api/v1/debug/coredump", NULL, NULL);
    CHECK_EQ_INT(g_out.status, 200);
    CHECK_EQ_INT((int)g_body_len, (int)sizeof g_coredump);
    CHECK(memcmp(g_body, g_coredump, sizeof g_coredump) == 0);
}

static void test_ws_registry_and_frames(void) {
    /* The cap: exactly 2, third refused. */
    const int a = app_api_ws_add(0);
    const int b = app_api_ws_add(0);
    CHECK(a >= 0 && b >= 0 && a != b);
    CHECK_EQ_INT(app_api_ws_add(0), -1);
    app_api_ws_remove(a);
    CHECK(app_api_ws_add(0) >= 0);

    /* subscribe narrows topics; ping answers pong; ack_alarm surfaces. */
    char reply[64];
    int acked;
    CHECK_EQ_INT(app_api_ws_on_message(
                     b, "{\"type\":\"subscribe\",\"topics\":[\"sample\","
                        "\"alarm\"]}",
                     reply, sizeof reply, &acked),
                 0);
    CHECK_EQ_INT((int)app_api_ws_topics(b),
                 WS_TOPIC_SAMPLE | WS_TOPIC_ALARM);
    CHECK_EQ_INT(
        app_api_ws_on_message(b, "{\"type\":\"ping\"}", reply, sizeof reply,
                              &acked),
        0);
    CHECK(strcmp(reply, "{\"type\":\"pong\"}") == 0);
    CHECK_EQ_INT(app_api_ws_on_message(b,
                                       "{\"type\":\"ack_alarm\",\"id\":4}",
                                       reply, sizeof reply, &acked),
                 0);
    CHECK_EQ_INT(acked, 4);

    /* Keepalive: ping every 30 s, drop after two missed. */
    int due[APP_API_WS_MAX_CLIENTS];
    CHECK_EQ_INT(app_api_ws_pings_due(29000, due), 0);
    CHECK(app_api_ws_pings_due(30000, due) >= 1);
    CHECK(app_api_ws_pings_due(60000, due) >= 1);
    CHECK(!app_api_ws_expired(b, 60000)); /* missed 2: at the edge */
    CHECK(app_api_ws_pings_due(90000, due) >= 1);
    CHECK(app_api_ws_expired(b, 90000)); /* missed 3: gone */
    app_api_ws_pong(b);
    CHECK(!app_api_ws_expired(b, 90000));

    /* Frames byte-match the sim's shapes. */
    g_body_len = 0;
    app_api_out_t out;
    app_api_out_init(&out, capture_sink, NULL);
    app_api_ws_hello(&out, "1.0.0", true, 1774094430000ull);
    (void)app_api_out_finish(&out);
    g_body[g_body_len] = '\0';
    CHECK(strcmp(g_body,
                 "{\"type\":\"hello\",\"fw\":\"1.0.0\",\"api\":\"v1\","
                 "\"server_time_ms\":1774094430000}") == 0);

    g_body_len = 0;
    app_api_out_init(&out, capture_sink, NULL);
    const bridge_evt_sample_t s = {.t_rel_s = 43230,
                                   .temp_f10 = {2429, 1634, INT16_MIN,
                                                INT16_MIN},
                                   .flags = 0x10,
                                   .rssi = -70};
    app_api_ws_sample(&out, &s, true, 1774094430000ull);
    (void)app_api_out_finish(&out);
    g_body[g_body_len] = '\0';
    CHECK(strcmp(g_body,
                 "{\"type\":\"sample\",\"t\":43230,"
                 "\"unix_ms\":1774094430000,\"temps_f10\":[2429,1634,null,"
                 "null],\"flags\":{\"billows\":true},\"rssi\":-70}") == 0);

    app_api_ws_remove(b);
    while (app_api_ws_count() > 0) {
        for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
            app_api_ws_remove(i);
        }
    }
}

int main(void) {
    test_captive_probes_exact_bytes();
    test_router_auth_and_errors();
    test_emitter_streams_100kb_through_2kb();
    test_status_shape();
    test_live_detached_never_zero();
    test_sessions_group();
    test_samples_formats();
    test_samples_bucketed_24h();
    test_config_wifi_fixture_bytes();
    test_time_backpatches_open_session();
    test_radio_conservative_post();
    test_debug_endpoints();
    test_ws_registry_and_frames();
    return test_summary("test_app_api");
}
