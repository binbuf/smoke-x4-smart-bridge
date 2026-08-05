/* app_api_core — router, auth, error envelope, and the non-session
 * handlers (F9.1, F9.3, F9.6–F9.8, F9.10, F8.7, F4.5, F4.6). */
#include "app_api_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app_alarm_svc.h"
#include "app_net_core.h"
#include "app_power_svc.h"
#include "app_api_internal.h"
#include "app_config_store.h"
#include "app_time_core.h"
#include "app_ui_cook.h"
#include "cook_novelty_log.h"
#include "cook_power_log.h"
#include "cook_ring.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"
#include "smoke_x_pktring.h"

static const app_api_ops_t *s_ops;

const app_api_ops_t *app_api_ops(void) { return s_ops; }

int app_api_core_init(const app_api_ops_t *ops) {
    if (!ops || !ops->sysinfo || !ops->net_status || !ops->uptime_ms) {
        return -1;
    }
    s_ops = ops;
    return 0;
}

/* ── error envelope (F9.1) ─────────────────────────────────────────────── */

void app_api_error(app_api_out_t *out, int status, const char *code,
                   const char *message) {
    app_api_out_begin(out, status, "application/json");
    app_api_emit_fmt(out, "{\"error\":{\"code\":\"%s\",\"message\":", code);
    app_api_emit_json_str(out, message);
    app_api_emit_str(out, ",\"detail\":null}}");
}

void app_api_error_detail_int(app_api_out_t *out, int status,
                              const char *code, const char *message,
                              const char *detail_key, int detail_value) {
    app_api_out_begin(out, status, "application/json");
    app_api_emit_fmt(out, "{\"error\":{\"code\":\"%s\",\"message\":", code);
    app_api_emit_json_str(out, message);
    app_api_emit_fmt(out, ",\"detail\":{\"%s\":%d}}}", detail_key,
                     detail_value);
}

/* ── query + JSON helpers ──────────────────────────────────────────────── */

const char *app_api_query_get(const app_api_req_t *req, const char *key) {
    for (int i = 0; i < req->query_count; i++) {
        if (strcmp(req->query[i].key, key) == 0) {
            return req->query[i].value;
        }
    }
    return NULL;
}

int app_api_query_int(const app_api_req_t *req, const char *key,
                      long fallback, long *out) {
    const char *v = app_api_query_get(req, key);
    if (!v) {
        *out = fallback;
        return 0;
    }
    char *end;
    const long n = strtol(v, &end, 10);
    if (end == v || *end != '\0') {
        return -1;
    }
    *out = n;
    return 0;
}

/* Finds `"key"` at object level (naive: first occurrence of the quoted
 * key followed by ':'); returns a pointer to its value or NULL. Good
 * enough for the small, flat bodies this API accepts. */
const char *app_api_json_find(const char *body, const char *key) {
    if (!body) {
        return NULL;
    }
    char pat[48];
    snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = body;
    while ((p = strstr(p, pat)) != NULL) {
        const char *q = p + strlen(pat);
        while (*q == ' ' || *q == '\t' || *q == '\n' || *q == '\r') {
            q++;
        }
        if (*q == ':') {
            q++;
            while (*q == ' ' || *q == '\t' || *q == '\n' || *q == '\r') {
                q++;
            }
            return q;
        }
        p = q;
    }
    return NULL;
}

int app_api_json_str(const char *body, const char *key, char *out,
                     size_t cap) {
    const char *v = app_api_json_find(body, key);
    if (!v || *v != '"') {
        return -1;
    }
    v++;
    size_t n = 0;
    while (*v && *v != '"' && n + 1 < cap) {
        if (*v == '\\' && v[1]) {
            v++;
            switch (*v) {
                case 'n':
                    out[n++] = '\n';
                    break;
                case 't':
                    out[n++] = '\t';
                    break;
                default:
                    out[n++] = *v;
            }
            v++;
        } else {
            out[n++] = *v++;
        }
    }
    out[n] = '\0';
    return *v == '"' ? 0 : -1;
}

int app_api_json_int(const char *body, const char *key, long *out) {
    const char *v = app_api_json_find(body, key);
    if (!v) {
        return -1;
    }
    char *end;
    const long n = strtol(v, &end, 10);
    if (end == v) {
        return -1;
    }
    *out = n;
    return 0;
}

/* The 64-bit twin of app_api_json_int, and the one to reach for whenever the
 * field is epoch MILLISECONDS.
 *
 * `long` is 32 bits on the xtensa toolchain and 64 on the Linux host that
 * runs this suite, so an epoch-ms field parsed with strtol saturates at
 * LONG_MAX on the board — 2147483647 ms is the 25th of January 1970 — and
 * passes every host test on the way there. The type has to be explicit. */
int app_api_json_i64(const char *body, const char *key, int64_t *out) {
    const char *v = app_api_json_find(body, key);
    if (!v) {
        return -1;
    }
    char *end;
    const long long n = strtoll(v, &end, 10);
    if (end == v) {
        return -1;
    }
    *out = (int64_t)n;
    return 0;
}

int app_api_json_bool(const char *body, const char *key, bool *out) {
    const char *v = app_api_json_find(body, key);
    if (!v) {
        return -1;
    }
    if (strncmp(v, "true", 4) == 0) {
        *out = true;
        return 0;
    }
    if (strncmp(v, "false", 5) == 0) {
        *out = false;
        return 0;
    }
    return -1;
}

/* ── captive probes (F8.7) — bodies shared verbatim with tools/sim ─────── */

static const char k_apple_success[] =
    "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>";
static const char k_builtin_page[] =
    "<html><body><h1>Smoke Bridge</h1><p>Use the Smoke Bridge app, or GET "
    "/api/v1/status.</p></body></html>";

bool app_api_path_is_open(const char *path) {
    return strncmp(path, "/api/v1", 7) != 0;
}

bool app_api_path_is_ota(const char *path) {
    return path && strcmp(path, "/api/v1/ota") == 0;
}

/* The bearer gate (05 §5.9), factored out so the streamed OTA route runs
 * exactly the same check the router does rather than a second copy. */
static bool auth_ok(const app_api_req_t *req) {
    char token[33] = "";
    (void)app_config_store_get_str(APP_CONFIG_DEV_API_TOKEN, token,
                                   sizeof token);
    if (token[0] == '\0') {
        return true;
    }
    return req->bearer && strcmp(req->bearer, token) == 0;
}

static bool handle_captive(const app_api_req_t *req, app_api_out_t *out) {
    const char *p = req->path;
    if (strcmp(p, "/generate_204") == 0 || strcmp(p, "/gen_204") == 0) {
        app_api_out_begin(out, 204, NULL);
        return true;
    }
    if (strcmp(p, "/hotspot-detect.html") == 0 ||
        strcmp(p, "/library/test/success.html") == 0) {
        app_api_out_begin(out, 200, "text/html");
        app_api_emit_str(out, k_apple_success);
        return true;
    }
    if (strcmp(p, "/ncsi.txt") == 0) {
        app_api_out_begin(out, 200, "text/plain");
        app_api_emit_str(out, "Microsoft NCSI");
        return true;
    }
    if (strcmp(p, "/connecttest.txt") == 0) {
        app_api_out_begin(out, 200, "text/plain");
        app_api_emit_str(out, "Microsoft Connect Test");
        return true;
    }
    return false;
}

/* ── GET /status (F9.3) ────────────────────────────────────────────────── */

static const char *time_source_name(void) {
    switch (app_time_core_source()) {
        case APP_TIME_SNTP:
            return "sntp";
        case APP_TIME_PHONE:
            return "phone";
        case APP_TIME_STALE:
            return "stale";
        default:
            return "none";
    }
}

static void emit_unix_ms_or_null(app_api_out_t *out) {
    uint64_t ms;
    if (app_time_core_now(s_ops->uptime_ms(), &ms)) {
        app_api_emit_fmt(out, "%llu", (unsigned long long)ms);
    } else {
        app_api_emit_str(out, "null");
    }
}

/* Defined with the rest of the cook-clock routes below; /status embeds the
 * same object so a client gets it in the poll it already makes. */
static void emit_cook_clock(app_api_out_t *out);

static void handle_status(app_api_out_t *out) {
    app_api_sysinfo_t sys;
    s_ops->sysinfo(&sys);
    app_api_net_snapshot_t net;
    s_ops->net_status(&net);
    const smoke_x_stats_t *st = smoke_x_ctrl_stats();

    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(
        out,
        "{\"device\":{\"id\":\"%s\",\"model\":\"%s\",\"fw\":\"%s\","
        "\"uptime_s\":%u,\"free_heap\":%u,\"min_free_heap\":%u,"
        "\"reset_reason\":\"%s\",\"coredump_available\":%s}",
        sys.id, sys.model, sys.fw, (unsigned)sys.uptime_s,
        (unsigned)sys.free_heap, (unsigned)sys.min_free_heap,
        sys.reset_reason, sys.coredump_available ? "true" : "false");

    int32_t tz = 0;
    (void)app_config_store_get_i32(APP_CONFIG_TIME_TZ_OFFSET_MIN, &tz);
    const app_time_source_t src = app_time_core_source();
    app_api_emit_str(out, ",\"time\":{\"unix_ms\":");
    emit_unix_ms_or_null(out);
    app_api_emit_fmt(out,
                     ",\"source\":\"%s\",\"tz_offset_min\":%d,\"valid\":%s}",
                     time_source_name(), (int)tz,
                     (src == APP_TIME_SNTP || src == APP_TIME_PHONE)
                         ? "true"
                         : "false");

    app_api_emit_fmt(out,
                     ",\"net\":{\"mode\":\"%s\",\"state\":\"%s\",\"ssid\":",
                     net.mode, net.state);
    app_api_emit_json_str(out, net.ssid);
    app_api_emit_fmt(out,
                     ",\"rssi\":%d,\"ip\":\"%s\",\"host\":\"%s\","
                     "\"ap_clients\":%d}",
                     (int)net.rssi, net.ip, net.host, net.ap_clients);

    /* Real since M3. This block was a shape-complete placeholder while BLE
     * did not exist; leaving it hardcoded after F10 landed meant /status
     * reported "bonded":0 on a bridge with a live bond, which reads as a
     * lost pairing rather than as an unimplemented field. */
    app_api_ble_snapshot_t ble = {0};
    if (s_ops->ble_status) {
        s_ops->ble_status(&ble);
    }
    app_api_emit_fmt(out,
                     ",\"ble\":{\"advertising\":%s,\"connections\":%u,"
                     "\"bonded\":%u}",
                     ble.advertising ? "true" : "false",
                     (unsigned)ble.connections, (unsigned)ble.bonded);

    app_config_pairing_t pair;
    const bool paired = app_config_store_get_pairing(&pair) == APP_CONFIG_OK;
    app_api_emit_fmt(out, ",\"pairing\":{\"paired\":%s,\"device_id\":",
                     paired ? "true" : "false");
    if (paired) {
        app_api_emit_json_str(out, pair.device_id);
    } else {
        app_api_emit_str(out, "null");
    }
    if (paired) {
        const uint64_t last = smoke_x_ctrl_last_valid_ms();
        const uint64_t now = s_ops->uptime_ms();
        app_api_emit_fmt(out,
                         ",\"model\":\"%s\",\"num_probes\":%u,"
                         "\"frequency_hz\":%u,\"last_packet_s_ago\":%u,"
                         "\"base_lost\":%s}",
                         pair.num_probes == 2 ? "X2" : "X4",
                         (unsigned)pair.num_probes, (unsigned)pair.frequency,
                         (unsigned)((now - last) / 1000u),
                         smoke_x_ctrl_base_lost() ? "true" : "false");
    } else {
        app_api_emit_str(out,
                         ",\"model\":null,\"num_probes\":0,"
                         "\"frequency_hz\":null,\"last_packet_s_ago\":null,"
                         "\"base_lost\":false}");
    }

    app_api_emit_fmt(out,
                     ",\"radio\":{\"rssi\":%d,\"snr\":%d,\"packets_ok\":%u,"
                     "\"packets_bad\":%u,\"id_mismatch\":%u}",
                     (int)st->last_rssi, (int)st->last_snr,
                     (unsigned)st->valid,
                     (unsigned)(st->parse_fail + st->crc_fail +
                                st->unknown_commas),
                     (unsigned)st->id_mismatch);

    const cook_index_entry_t *oldest = cook_store_index_get(0);
    app_api_emit_fmt(out,
                     ",\"storage\":{\"total_b\":%u,\"used_b\":%u,"
                     "\"free_pct\":%u,\"sessions\":%d,"
                     "\"oldest_session_id\":%u}",
                     (unsigned)sys.storage_total_b,
                     (unsigned)sys.storage_used_b,
                     (unsigned)sys.storage_free_pct, cook_store_index_count(),
                     oldest ? (unsigned)oldest->session_id : 0u);

    /* F12.5 — real, and honest about the absence. This object was a
     * string literal from M2 to M5; SOC_UNKNOWN renders as null rather
     * than as 255 or 0, because a 0 % battery on a bridge that simply
     * cannot measure one is a bug filed against the hardware (P3.2). */
    app_api_emit_str(out, ",\"power\":{\"mv\":");
    if (app_power_svc_available()) {
        app_api_emit_fmt(out, "%u", (unsigned)app_power_svc_mv());
    } else {
        app_api_emit_str(out, "null");
    }
    app_api_emit_str(out, ",\"soc_pct\":");
    const uint8_t soc = app_power_svc_soc();
    if (soc == BRIDGE_SOC_UNKNOWN) {
        app_api_emit_str(out, "null");
    } else {
        app_api_emit_fmt(out, "%u", (unsigned)soc);
    }
    uint16_t batt_mah = 3000;
    (void)app_config_store_get_u16(APP_CONFIG_DEV_BATTERY_MAH, &batt_mah);
    app_api_emit_fmt(out,
                     ",\"charging\":%s,\"saver\":%s,\"battery_mah\":%u}",
                     app_power_svc_charging() ? "true" : "false",
                     app_power_svc_saver() ? "true" : "false",
                     (unsigned)batt_mah);

    const bool active = cook_session_is_open();
    app_api_emit_fmt(out, ",\"session\":{\"active\":%s",
                     active ? "true" : "false");
    if (active) {
        bridge_session_header_t h;
        (void)cook_store_read_header(cook_session_active_id(), &h);
        const cook_ring_sample_t *newest = cook_ring_get(0);
        app_api_emit_fmt(out, ",\"id\":%u,\"name\":",
                         (unsigned)h.session_id);
        app_api_emit_json_str(out, h.name);
        app_api_emit_str(out, ",\"started_unix_ms\":");
        if (bridge_session_header_clock_valid(h.flags)) {
            app_api_emit_fmt(out, "%llu",
                             (unsigned long long)h.started_unix_ms);
        } else {
            app_api_emit_str(out, "null");
        }
        app_api_emit_fmt(out, ",\"elapsed_s\":%u,\"samples\":%u}",
                         newest ? (unsigned)newest->t : 0u,
                         (unsigned)cook_session_sample_count());
    } else {
        app_api_emit_str(out,
                         ",\"id\":null,\"name\":null,"
                         "\"started_unix_ms\":null,\"elapsed_s\":0,"
                         "\"samples\":0}");
    }

    /* Additive (06 §6.5), and NOT the same thing as `session` above. That
     * one is storage: the bridge opened a file because samples arrived.
     * This one is the display clock, which exists only because an app
     * declared a cook. A client reading `session.active` and calling it a
     * cook is reading the wrong field — this is the one the glass shows. */
    app_api_emit_str(out, ",\"cook_clock\":");
    emit_cook_clock(out);

    /* F11b.11 — additive (06 §6.5: clients ignore unknown keys), and the
     * cheapest way to make V3a.1's deferred OLED-error row measurable in
     * the PRODUCT image. An error count with no denominator is not a
     * measurement, so `ok` travels beside it. */
    uint32_t disp_ok = 0;
    uint32_t disp_err = 0;
    if (s_ops->display_counts != NULL) {
        s_ops->display_counts(&disp_ok, &disp_err);
    }
    app_api_emit_fmt(out, ",\"display\":{\"i2c_ok\":%u,\"i2c_err\":%u}",
                     (unsigned)disp_ok, (unsigned)disp_err);

    /* F14.8 — additive, and the only way to read 03 §3.7's verdict
     * without a serial cable. A build with no app_ota reports
     * `not_applicable`, which is true, rather than `passed`, which would
     * be the /status.ble stub all over again. */
    app_api_ota_snapshot_t ota = {0};
    snprintf(ota.gate, sizeof ota.gate, "%s", "not_applicable");
    if (s_ops->ota_status != NULL) {
        s_ops->ota_status(&ota);
    }
    app_api_emit_str(out, ",\"ota\":{\"slot\":");
    app_api_emit_json_str(out, ota.slot);
    app_api_emit_fmt(out, ",\"pending_verify\":%s,\"gate\":",
                     ota.pending_verify ? "true" : "false");
    app_api_emit_json_str(out, ota.gate);
    app_api_emit_str(out, ",\"failed\":");
    if (ota.failed[0] == '\0') {
        app_api_emit_str(out, "null}");
    } else {
        app_api_emit_json_str(out, ota.failed);
        app_api_emit_str(out, "}");
    }

    /* F13.8 — the real list, in 06 §6.2's shape. This field was an empty
     * literal from M2 to M5; the /status.ble stub (found on the board,
     * 2026-07-23) is why it does not stay one a milestone longer than the
     * engine that fills it. */
    app_api_emit_str(out, ",\"alarms\":[");
    const app_alarm_slot_t *alarms[APP_ALARM_MAX_ACTIVE];
    const int an = app_alarm_svc_list(alarms, APP_ALARM_MAX_ACTIVE);
    uint64_t now_unix_ms = 0;
    const bool have_clock =
        app_time_core_now(s_ops->uptime_ms(), &now_unix_ms);
    for (int i = 0; i < an; i++) {
        const app_alarm_slot_t *a = alarms[i];
        app_api_emit_fmt(out,
                         "%s{\"id\":%u,\"rule\":\"%s\","
                         "\"severity\":\"%s\",\"probe\":%u,"
                         "\"since_unix_ms\":",
                         i > 0 ? "," : "", (unsigned)a->id,
                         bridge_alarm_rule_str(a->rule),
                         bridge_alarm_severity_str(a->severity),
                         (unsigned)a->probe);
        /* A bridge with no clock says so rather than emitting an epoch
         * date the app would render as 1970 (04 §4.4). */
        if (have_clock) {
            const uint64_t age_ms =
                ((uint64_t)(uint32_t)(s_ops->uptime_ms() / 1000ull) -
                 (uint64_t)a->since_s) *
                1000ull;
            app_api_emit_fmt(out, "%llu",
                             (unsigned long long)(now_unix_ms > age_ms
                                                      ? now_unix_ms - age_ms
                                                      : 0ull));
        } else {
            app_api_emit_str(out, "null");
        }
        app_api_emit_fmt(out, ",\"acked\":%s}",
                         a->state == APP_ALARM_SLOT_ACKED ? "true" : "false");
    }
    app_api_emit_str(out, "]}");
}

/* ── GET /live (F9.3) ──────────────────────────────────────────────────── */

static const char *role_name(uint8_t role) {
    static const char *const names[] = {"pit", "food", "ambient", "unused"};
    /* app_config roles: 0 pit, 1 food, 2 ambient, 3 unused. */
    return names[role < 4 ? role : 3];
}

static void handle_live(const app_api_req_t *req, app_api_out_t *out) {
    long window = 3600;
    if (app_api_query_int(req, "window", 3600, &window) != 0 || window < 1) {
        return app_api_error(out, 400, "invalid_field", "bad window");
    }
    if (window > 7200) {
        window = 7200;
    }
    const int count = cook_ring_count();
    const cook_ring_sample_t *newest = cook_ring_get(0);
    const uint32_t newest_t = newest ? newest->t : 0;
    const uint32_t from_t =
        newest_t > (uint32_t)window ? newest_t - (uint32_t)window : 0;

    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out, "{\"t\":%u,\"unix_ms\":", (unsigned)newest_t);
    emit_unix_ms_or_null(out);
    const bool celsius =
        newest && (newest->flags & 0x40); /* SOURCE_CELSIUS */
    app_api_emit_fmt(out,
                     ",\"units_source\":\"%s\",\"billows\":{\"attached\":%s,"
                     "\"target_f10\":null},\"probes\":[",
                     celsius ? "C" : "F",
                     newest && (newest->flags & 0x10) ? "true" : "false");

    static const app_config_key_t name_keys[4] = {
        APP_CONFIG_PROBE1_NAME, APP_CONFIG_PROBE2_NAME, APP_CONFIG_PROBE3_NAME,
        APP_CONFIG_PROBE4_NAME};
    static const app_config_key_t role_keys[4] = {
        APP_CONFIG_PROBE1_ROLE, APP_CONFIG_PROBE2_ROLE, APP_CONFIG_PROBE3_ROLE,
        APP_CONFIG_PROBE4_ROLE};
    static const app_config_key_t target_keys[4] = {
        APP_CONFIG_PROBE1_TARGET, APP_CONFIG_PROBE2_TARGET,
        APP_CONFIG_PROBE3_TARGET, APP_CONFIG_PROBE4_TARGET};

    for (int i = 0; i < 4; i++) {
        const bool attached =
            newest && newest->temp[i] != BRIDGE_TEMP_DETACHED &&
            newest->temp[i] != BRIDGE_TEMP_INVALID;
        if (i > 0) {
            app_api_emit_str(out, ",");
        }
        if (!attached) {
            app_api_emit_fmt(out,
                             "{\"n\":%d,\"attached\":false,\"temp_f10\":null}",
                             i + 1);
            continue;
        }
        char name[17] = "";
        uint8_t role = 3;
        int32_t target = 0;
        (void)app_config_store_get_str(name_keys[i], name, sizeof name);
        (void)app_config_store_get_u8(role_keys[i], &role);
        (void)app_config_store_get_i32(target_keys[i], &target);
        app_api_emit_fmt(out, "{\"n\":%d,\"name\":", i + 1);
        app_api_emit_json_str(out, name);
        app_api_emit_fmt(out,
                         ",\"role\":\"%s\",\"attached\":true,\"temp_f10\":%d,"
                         "\"alarm_enabled\":%s,\"target_f10\":",
                         role_name(role), (int)newest->temp[i],
                         (newest->flags & (1u << i)) ? "true" : "false");
        if (target == 0) {
            app_api_emit_str(out, "null");
        } else {
            app_api_emit_fmt(out, "%d", (int)target);
        }
        float rate;
        if (cook_ring_slope_f_per_hr(i, &rate)) {
            app_api_emit_fmt(out, ",\"rate_f_per_hr\":%.1f}", (double)rate);
        } else {
            app_api_emit_str(out, ",\"rate_f_per_hr\":null}");
        }
    }

    /* recent: oldest→newest inside the window, straight from the ring. */
    int first_idx = -1;
    for (int idx = count - 1; idx >= 0; idx--) {
        if (cook_ring_get(idx)->t >= from_t) {
            first_idx = idx;
            break;
        }
    }
    int included = first_idx >= 0 ? first_idx + 1 : 0;
    app_api_emit_fmt(out,
                     "],\"recent\":{\"t0\":%u,\"step_s\":30,\"count\":%d,"
                     "\"series\":[",
                     first_idx >= 0 ? (unsigned)cook_ring_get(first_idx)->t
                                    : 0u,
                     included);
    for (int i = 0; i < 4; i++) {
        bool any = false;
        for (int idx = first_idx; idx >= 0; idx--) {
            const int16_t v = cook_ring_get(idx)->temp[i];
            if (v != BRIDGE_TEMP_DETACHED && v != BRIDGE_TEMP_INVALID) {
                any = true;
                break;
            }
        }
        if (i > 0) {
            app_api_emit_str(out, ",");
        }
        if (!any) {
            app_api_emit_str(out, "null");
            continue;
        }
        app_api_emit_str(out, "[");
        for (int idx = first_idx; idx >= 0; idx--) {
            const int16_t v = cook_ring_get(idx)->temp[i];
            if (idx != first_idx) {
                app_api_emit_str(out, ",");
            }
            if (v == BRIDGE_TEMP_DETACHED || v == BRIDGE_TEMP_INVALID) {
                app_api_emit_str(out, "null");
            } else {
                app_api_emit_fmt(out, "%d", (int)v);
            }
        }
        app_api_emit_str(out, "]");
    }
    app_api_emit_str(out, "]}}");
}

/* ── pairing (F9.6) ────────────────────────────────────────────────────── */

static void handle_pairing_get(app_api_out_t *out) {
    const smoke_x_pair_state_t st = smoke_x_ctrl_state();
    const char *state_name = st == SMOKE_X_CONFIRMED       ? "confirmed"
                             : st == SMOKE_X_SYNC_RECEIVED ? "sync_received"
                                                           : "scanning";
    app_config_pairing_t p;
    const bool paired = st == SMOKE_X_CONFIRMED &&
                        app_config_store_get_pairing(&p) == APP_CONFIG_OK;
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out,
                     "{\"paired\":%s,\"sync_active\":%s,\"state\":\"%s\","
                     "\"device_id\":",
                     paired ? "true" : "false",
                     st == SMOKE_X_UNPAIRED ? "true" : "false", state_name);
    if (paired) {
        app_api_emit_json_str(out, p.device_id);
        app_api_emit_fmt(out,
                         ",\"model\":\"%s\",\"num_probes\":%u,"
                         "\"frequency_hz\":%u}",
                         p.num_probes == 2 ? "X2" : "X4",
                         (unsigned)p.num_probes, (unsigned)p.frequency);
    } else {
        app_api_emit_str(out,
                         "null,\"model\":null,\"num_probes\":0,"
                         "\"frequency_hz\":null}");
    }
}

/* ── config groups + time (F9.7) ───────────────────────────────────────── */

/* newapp §E.3 — "I reached you on the new network; keep it."
 *
 * A 409 for an unarmed commit rather than a cheerful 200: the app uses this to
 * tell "the switch stuck" from "there was never a switch to confirm", and the
 * difference matters when the wizard is deciding whether to keep counting
 * down. */
static void handle_netmode_commit(app_api_out_t *out) {
    if (!app_net_core_commit()) {
        return app_api_error(out, 409, "not_pending",
                             "no mode change is waiting to be confirmed");
    }
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"committed\":true}");
}

static void handle_config_wifi_get(app_api_out_t *out) {
    app_api_net_snapshot_t net;
    s_ops->net_status(&net);
    char sta_ssid[33] = "";
    (void)app_config_store_get_str(APP_CONFIG_NET_STA_SSID, sta_ssid,
                                   sizeof sta_ssid);
    char ap_psk[APP_CONFIG_PSK_LEN + 1] = "";
    (void)app_config_store_get_str(APP_CONFIG_NET_AP_PSK, ap_psk,
                                   sizeof ap_psk);
    app_api_sysinfo_t sys;
    s_ops->sysinfo(&sys);
    uint8_t mode = APP_CONFIG_NET_MODE_AP;
    (void)app_config_store_get_u8(APP_CONFIG_NET_MODE, &mode);

    /* NEVER the stored STA password — only the AP PSK, which anyone on
     * the AP already typed (06 §6.2). */
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out, "{\"mode\":\"%s\",\"sta\":{\"ssid\":",
                     mode == APP_CONFIG_NET_MODE_STA ? "sta" : "ap");
    app_api_emit_json_str(out, sta_ssid);
    app_api_emit_fmt(out,
                     ",\"auth\":\"wpa2_psk\"},\"ap\":{\"ssid\":"
                     "\"SmokeBridge-%s\",\"psk\":\"%s\","
                     "\"ip\":\"192.168.4.1\"}",
                     sys.id, ap_psk);
    /* §E.3 — so an app that has just re-found us can render the countdown it
     * is racing, rather than a spinner with no number on it. */
    app_api_emit_fmt(out, ",\"revert_pending\":%s,\"revert_in_s\":%u}",
                     app_net_core_revert_pending() ? "true" : "false",
                     (unsigned)app_net_core_revert_remaining_s(
                         s_ops->uptime_ms()));
}

static void handle_config_wifi_post(const app_api_req_t *req,
                                    app_api_out_t *out) {
    char mode[8] = "";
    if (app_api_json_str(req->body, "mode", mode, sizeof mode) != 0 ||
        (strcmp(mode, "ap") != 0 && strcmp(mode, "sta") != 0)) {
        return app_api_error(out, 400, "unsupported_mode",
                             "mode must be ap|sta");
    }
    app_net_pending_cfg_t cfg = {0};
    cfg.mode = strcmp(mode, "sta") == 0 ? APP_CONFIG_NET_MODE_STA
                                        : APP_CONFIG_NET_MODE_AP;
    if (cfg.mode == APP_CONFIG_NET_MODE_STA) {
        if (app_api_json_str(req->body, "ssid", cfg.sta_ssid,
                             sizeof cfg.sta_ssid) != 0 ||
            cfg.sta_ssid[0] == '\0') {
            return app_api_error(out, 400, "invalid_field",
                                 "sta mode needs ssid");
        }
        (void)app_api_json_str(req->body, "psk", cfg.sta_psk,
                               sizeof cfg.sta_psk);
        (void)app_api_json_str(req->body, "username", cfg.sta_user,
                               sizeof cfg.sta_user);
        cfg.sta_auth = 1;
    }

    /* newapp §E.3 — the rollback timer.
     *
     * A mode switch kills the link that carried the command, so the command is
     * a request for a FUTURE state with a deadline: arm the revert BEFORE the
     * apply (while the running config is still the known-good one), and if the
     * phone does not reach us on the new network and commit in time, we put
     * back what worked. Absent or 0 keeps the old fire-and-forget behaviour,
     * which is right for guided setup with a human watching it.
     *
     * A rejected value is a 400 rather than a silent clamp: a caller asking
     * for a 2-second window has misunderstood something, and quietly giving
     * them 10 would hide it. */
    long revert_after_s = 0;
    if (app_api_json_int(req->body, "revert_after_s", &revert_after_s) == 0 &&
        revert_after_s != 0) {
        if (app_net_core_arm_revert((uint32_t)revert_after_s, s_ops->uptime_ms()) !=
            0) {
            return app_api_error(out, 400, "invalid_field",
                                 "revert_after_s must be 0 or 10..600");
        }
    } else {
        (void)app_net_core_arm_revert(0, s_ops->uptime_ms());
    }

    /* Reply FIRST; the deferred apply tears the interface down after the
     * response has flushed (F8.4, 05 §5.4). */
    app_api_out_begin(out, 200, "application/json");
    if (cfg.mode == APP_CONFIG_NET_MODE_AP) {
        app_api_sysinfo_t sys;
        s_ops->sysinfo(&sys);
        char ap_psk[APP_CONFIG_PSK_LEN + 1] = "";
        (void)app_config_store_get_str(APP_CONFIG_NET_AP_PSK, ap_psk,
                                       sizeof ap_psk);
        app_api_emit_fmt(out,
                         "{\"accepted\":true,\"applying_in_ms\":500,"
                         "\"expect\":{\"mode\":\"ap\",\"ssid\":"
                         "\"SmokeBridge-%s\",\"psk\":\"%s\","
                         "\"ip\":\"192.168.4.1\"}}",
                         sys.id, ap_psk);
    } else {
        app_api_emit_str(out,
                         "{\"accepted\":true,\"applying_in_ms\":500,"
                         "\"expect\":{\"mode\":\"sta\",\"host\":"
                         "\"smokebridge.local\"}}");
    }
    if (s_ops->net_request_config) {
        (void)s_ops->net_request_config(&cfg);
    }
}

static void handle_config_mqtt_get(app_api_out_t *out) {
    uint8_t en = 0;
    uint8_t ha = 1;
    (void)app_config_store_get_u8(APP_CONFIG_MQTT_ENABLED, &en);
    (void)app_config_store_get_u8(APP_CONFIG_MQTT_HA_DISCOVERY, &ha);
    uint16_t port = 1883;
    (void)app_config_store_get_u16(APP_CONFIG_MQTT_PORT, &port);
    char host[65] = "";
    char user[65] = "";
    char prefix[33] = "";
    (void)app_config_store_get_str(APP_CONFIG_MQTT_HOST, host, sizeof host);
    (void)app_config_store_get_str(APP_CONFIG_MQTT_USER, user, sizeof user);
    (void)app_config_store_get_str(APP_CONFIG_MQTT_PREFIX, prefix,
                                   sizeof prefix);
    bool connected = s_ops->mqtt_status != NULL && s_ops->mqtt_status();

    /* NEVER the stored password — the sta_psk discipline (06 §6.2). */
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out, "{\"enabled\":%s,\"host\":", en ? "true" : "false");
    app_api_emit_json_str(out, host);
    app_api_emit_fmt(out, ",\"port\":%u,\"user\":", (unsigned)port);
    app_api_emit_json_str(out, user);
    app_api_emit_str(out, ",\"prefix\":");
    app_api_emit_json_str(out, prefix);
    app_api_emit_fmt(out, ",\"ha_discovery\":%s,\"connected\":%s}",
                     ha ? "true" : "false", connected ? "true" : "false");
}

static void handle_config_mqtt_post(const app_api_req_t *req,
                                    app_api_out_t *out) {
    bool enabled = false;
    const bool have_enabled =
        app_api_json_bool(req->body, "enabled", &enabled) == 0;
    char host[65] = "";
    const bool have_host =
        app_api_json_str(req->body, "host", host, sizeof host) == 0;
    long port = 0;
    const bool have_port = app_api_json_int(req->body, "port", &port) == 0;

    if (have_port && (port < 1 || port > 65535)) {
        return app_api_error(out, 400, "invalid_field",
                             "port must be 1..65535");
    }
    /* Enabling needs a broker — from this body or already stored. */
    if (have_enabled && enabled) {
        char cur_host[65] = "";
        (void)app_config_store_get_str(APP_CONFIG_MQTT_HOST, cur_host,
                                       sizeof cur_host);
        const char *effective = have_host ? host : cur_host;
        if (effective[0] == '\0') {
            return app_api_error(out, 400, "invalid_field",
                                 "enabling needs a host");
        }
    }

    char user[65] = "";
    char pass[65] = "";
    char prefix[33] = "";
    bool ha = true;
    if (have_enabled) {
        (void)app_config_store_set_u8(APP_CONFIG_MQTT_ENABLED,
                                      enabled ? 1 : 0);
    }
    if (have_host) {
        (void)app_config_store_set_str(APP_CONFIG_MQTT_HOST, host);
    }
    if (have_port) {
        (void)app_config_store_set_u16(APP_CONFIG_MQTT_PORT, (uint16_t)port);
    }
    if (app_api_json_str(req->body, "user", user, sizeof user) == 0) {
        (void)app_config_store_set_str(APP_CONFIG_MQTT_USER, user);
    }
    if (app_api_json_str(req->body, "pass", pass, sizeof pass) == 0) {
        (void)app_config_store_set_str(APP_CONFIG_MQTT_PASS, pass);
    }
    if (app_api_json_str(req->body, "prefix", prefix, sizeof prefix) == 0) {
        (void)app_config_store_set_str(APP_CONFIG_MQTT_PREFIX, prefix);
    }
    if (app_api_json_bool(req->body, "ha_discovery", &ha) == 0) {
        (void)app_config_store_set_u8(APP_CONFIG_MQTT_HA_DISCOVERY,
                                      ha ? 1 : 0);
    }

    /* Enabling it live restarts the client without a reboot. */
    if (s_ops->mqtt_reconfigure != NULL) {
        s_ops->mqtt_reconfigure();
    }
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"ok\":true}");
}

static void handle_config_device_get(app_api_out_t *out) {
    uint8_t units = 0, timeout_hi = 0, led = 1, saver = 0;
    uint16_t timeout_s = 60, batt_mah = 3000;
    uint8_t max_sessions = 64, min_free = 10;
    (void)app_config_store_get_u8(APP_CONFIG_DEV_UNITS, &units);
    (void)app_config_store_get_u16(APP_CONFIG_DEV_DISPLAY_TIMEOUT_S,
                                   &timeout_s);
    (void)app_config_store_get_u8(APP_CONFIG_DEV_LED_ENABLED, &led);
    (void)app_config_store_get_u8(APP_CONFIG_DEV_BATTERY_SAVER, &saver);
    (void)app_config_store_get_u16(APP_CONFIG_DEV_BATTERY_MAH, &batt_mah);
    (void)app_config_store_get_u8(APP_CONFIG_DEV_RETENTION_MAX_SESSIONS,
                                  &max_sessions);
    (void)app_config_store_get_u8(APP_CONFIG_DEV_RETENTION_MIN_FREE_PCT,
                                  &min_free);
    (void)timeout_hi;
    static const char *const saver_names[] = {"off", "on", "auto"};
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out,
                     "{\"display_units\":\"%s\",\"display_timeout_s\":%u,"
                     "\"led_enabled\":%s,\"battery_saver\":\"%s\","
                     "\"battery_mah\":%u,"
                     "\"retention\":{\"max_sessions\":%u,"
                     "\"min_free_pct\":%u},\"probes\":[",
                     units == 1 ? "C" : "F", (unsigned)timeout_s,
                     led ? "true" : "false",
                     saver_names[saver < 3 ? saver : 2], (unsigned)batt_mah,
                     (unsigned)max_sessions, (unsigned)min_free);
    static const app_config_key_t name_keys[4] = {
        APP_CONFIG_PROBE1_NAME, APP_CONFIG_PROBE2_NAME, APP_CONFIG_PROBE3_NAME,
        APP_CONFIG_PROBE4_NAME};
    static const app_config_key_t role_keys[4] = {
        APP_CONFIG_PROBE1_ROLE, APP_CONFIG_PROBE2_ROLE, APP_CONFIG_PROBE3_ROLE,
        APP_CONFIG_PROBE4_ROLE};
    static const app_config_key_t target_keys[4] = {
        APP_CONFIG_PROBE1_TARGET, APP_CONFIG_PROBE2_TARGET,
        APP_CONFIG_PROBE3_TARGET, APP_CONFIG_PROBE4_TARGET};
    for (int i = 0; i < 4; i++) {
        char name[17] = "";
        uint8_t role = 3;
        int32_t target = 0;
        (void)app_config_store_get_str(name_keys[i], name, sizeof name);
        (void)app_config_store_get_u8(role_keys[i], &role);
        (void)app_config_store_get_i32(target_keys[i], &target);
        app_api_emit_fmt(out, "%s{\"n\":%d,\"name\":", i ? "," : "", i + 1);
        app_api_emit_json_str(out, name);
        app_api_emit_fmt(out, ",\"role\":\"%s\",\"target_f10\":",
                         role_name(role));
        if (target == 0) {
            app_api_emit_str(out, "null}");
        } else {
            app_api_emit_fmt(out, "%d}", (int)target);
        }
    }
    app_api_emit_str(out, "]}");
}

static int role_from_name(const char *s) {
    if (strcmp(s, "pit") == 0) {
        return APP_CONFIG_ROLE_PIT;
    }
    if (strcmp(s, "food") == 0) {
        return APP_CONFIG_ROLE_FOOD;
    }
    if (strcmp(s, "ambient") == 0) {
        return APP_CONFIG_ROLE_AMBIENT;
    }
    if (strcmp(s, "unused") == 0) {
        return APP_CONFIG_ROLE_UNUSED;
    }
    return -1;
}

static void handle_config_device_post(const app_api_req_t *req,
                                      app_api_out_t *out) {
    const char *body = req->body;
    char sval[17];
    long ival;
    bool bval;
    if (app_api_json_str(body, "display_units", sval, sizeof sval) == 0) {
        (void)app_config_store_set_u8(APP_CONFIG_DEV_UNITS,
                                      strcmp(sval, "C") == 0 ? 1 : 0);
    }
    if (app_api_json_int(body, "display_timeout_s", &ival) == 0) {
        /* Clamp to {0} ∪ [15,600]. 0 means never sleep; any positive value is
         * held at >= 15 s so a passkey or OTA screen cannot be made unreadable.
         * A value of 1 left the board unprovisionable (13 §13.2.1), because the
         * handler validated nothing. */
        uint16_t to;
        if (ival <= 0) {
            to = 0;
        } else if (ival < 15) {
            to = 15;
        } else if (ival > 600) {
            to = 600;
        } else {
            to = (uint16_t)ival;
        }
        (void)app_config_store_set_u16(APP_CONFIG_DEV_DISPLAY_TIMEOUT_S, to);
    }
    if (app_api_json_bool(body, "led_enabled", &bval) == 0) {
        (void)app_config_store_set_u8(APP_CONFIG_DEV_LED_ENABLED,
                                      bval ? 1 : 0);
    }
    if (app_api_json_str(body, "battery_saver", sval, sizeof sval) == 0) {
        const uint8_t v = strcmp(sval, "on") == 0    ? 1
                          : strcmp(sval, "auto") == 0 ? 2
                                                      : 0;
        (void)app_config_store_set_u8(APP_CONFIG_DEV_BATTERY_SAVER, v);
    }
    if (app_api_json_int(body, "battery_mah", &ival) == 0) {
        /* Rated pack capacity — label + future mA-draw diagnostic only; it
         * does NOT feed the SoC curve (that is a voltage lookup). Refused
         * out of the u16 range, mirroring vbat_actual_mv: one bad write to
         * NVS is silent and permanent. */
        if (ival <= 0 || ival > 65535) {
            return app_api_error(out, 400, "invalid_field",
                                 "battery_mah out of range (1..65535)");
        }
        (void)app_config_store_set_u16(APP_CONFIG_DEV_BATTERY_MAH,
                                       (uint16_t)ival);
    }
    if (app_api_json_int(body, "max_sessions", &ival) == 0) {
        (void)app_config_store_set_u8(APP_CONFIG_DEV_RETENTION_MAX_SESSIONS,
                                      (uint8_t)ival);
    }
    if (app_api_json_int(body, "min_free_pct", &ival) == 0) {
        (void)app_config_store_set_u8(APP_CONFIG_DEV_RETENTION_MIN_FREE_PCT,
                                      (uint8_t)ival);
    }
    if (app_api_json_int(body, "vbat_actual_mv", &ival) == 0) {
        /* F12.5 — 01 §1.3's one-point calibration, solved rather than
         * merely recorded (M2 stored the number and left den 0). A DMM
         * reading beats the plateau solver's inference and stands the
         * solver down; an implied ratio outside ±20 % of ×4.9 is refused,
         * because one bad write to NVS is permanent and silent. */
        if (ival <= 0 || ival > 65535 ||
            app_power_svc_calibrate((uint16_t)ival) != 0) {
            return app_api_error(out, 400, "invalid_field",
                                 "vbat_actual_mv implies an implausible "
                                 "divider ratio");
        }
    }
    /* probes: [{"n":1,"name":...,"role":...,"target_f10":...}, ...] */
    const char *probes = app_api_json_find(body, "probes");
    if (probes && *probes == '[') {
        /* One tolerant forward scan. The old loop searched the compact form
         * from `p` OR the spaced form from `probes` (the start of the array),
         * so a single pretty-printed body (curl, Postman, Home Assistant)
         * re-found the first object every iteration and spun the httpd task
         * forever — an unauthenticated remote DoS on the default config. This
         * advances `p` strictly and accepts any whitespace between objects. */
        const char *p = probes + 1; /* past '[' */
        for (;;) {
            while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' ||
                   *p == ',') {
                p++;
            }
            if (*p != '{') {
                break; /* ']' or end of body — never restart from the top */
            }
            const char *obj_end = strchr(p, '}');
            if (!obj_end) {
                break;
            }
            char obj[192];
            const size_t n = (size_t)(obj_end - p + 1) < sizeof obj
                                 ? (size_t)(obj_end - p + 1)
                                 : sizeof obj - 1;
            memcpy(obj, p, n);
            obj[n] = '\0';
            long pn;
            if (app_api_json_int(obj, "n", &pn) == 0 && pn >= 1 && pn <= 4) {
                static const app_config_key_t nk[4] = {
                    APP_CONFIG_PROBE1_NAME, APP_CONFIG_PROBE2_NAME,
                    APP_CONFIG_PROBE3_NAME, APP_CONFIG_PROBE4_NAME};
                static const app_config_key_t rk[4] = {
                    APP_CONFIG_PROBE1_ROLE, APP_CONFIG_PROBE2_ROLE,
                    APP_CONFIG_PROBE3_ROLE, APP_CONFIG_PROBE4_ROLE};
                static const app_config_key_t tk[4] = {
                    APP_CONFIG_PROBE1_TARGET, APP_CONFIG_PROBE2_TARGET,
                    APP_CONFIG_PROBE3_TARGET, APP_CONFIG_PROBE4_TARGET};
                char pname[17];
                if (app_api_json_str(obj, "name", pname, sizeof pname) == 0) {
                    (void)app_config_store_set_str(nk[pn - 1], pname);
                }
                char prole[12];
                if (app_api_json_str(obj, "role", prole, sizeof prole) == 0) {
                    const int r = role_from_name(prole);
                    if (r >= 0) {
                        (void)app_config_store_set_u8(rk[pn - 1],
                                                      (uint8_t)r);
                    }
                }
                long pt;
                if (app_api_json_int(obj, "target_f10", &pt) == 0) {
                    (void)app_config_store_set_i32(tk[pn - 1], (int32_t)pt);
                }
            }
            p = obj_end + 1; /* strictly advances — termination guaranteed */
        }
    }
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"ok\":true}");
}

/* F13.8 — /config/alarms speaks JSON in both directions. Until M5 this
 * handler stored the POSTed bytes verbatim and echoed them back, which was
 * honest as a placeholder (the M2 plan recorded it as provisional) and is
 * a lie the moment an engine reads them. The NVS byte layout is
 * device-private; the contract is 06 §6.2's JSON. */
static bool alarm_rule_from_name(const char *name, size_t len, uint8_t *out) {
    for (uint8_t r = 0; r < APP_ALARM_RULE_COUNT; r++) {
        const char *s = bridge_alarm_rule_str(r);
        if (strlen(s) == len && strncmp(s, name, len) == 0) {
            *out = r;
            return true;
        }
    }
    return false;
}

static void emit_alarm_cfg(app_api_out_t *out) {
    const app_alarm_cfg_t *c = app_alarm_svc_cfg();
    app_api_emit_str(out, "{\"rules\":[");
    for (uint8_t r = 0; r < APP_ALARM_RULE_COUNT; r++) {
        app_api_emit_fmt(out,
                         "%s{\"rule\":\"%s\",\"enabled\":%s,"
                         "\"severity\":\"%s\"}",
                         r > 0 ? "," : "", bridge_alarm_rule_str(r),
                         app_alarm_cfg_rule_enabled(c, r) ? "true" : "false",
                         bridge_alarm_severity_str(
                             app_alarm_rule_severity(r)));
    }
    /* Split into three calls on purpose: app_api_emit_fmt formats into a
     * 256 B stack `piece` and TRUNCATES silently past it. Writing the
     * twelve tunables as one format string fits in the source and not in
     * that buffer — the first draft did exactly that and lost the last
     * two fields, which the host test caught because it asserts a field
     * at the END of the object rather than only at the start. */
    app_api_emit_fmt(out,
                     "],\"pit_band_f10\":%d,\"pit_band_sustain_s\":%u,"
                     "\"pit_crash_below_f10\":%d",
                     (int)c->pit_band_f10, (unsigned)c->pit_band_sustain_s,
                     (int)c->pit_crash_below_f10);
    app_api_emit_fmt(out,
                     ",\"pit_crash_slope_f10_per_hr\":%d,"
                     "\"pit_crash_sustain_s\":%u,\"base_lost_s\":%u",
                     (int)c->pit_crash_slope_f10_per_hr,
                     (unsigned)c->pit_crash_sustain_s,
                     (unsigned)c->base_lost_s);
    app_api_emit_fmt(out,
                     ",\"battery_warn_pct\":%u,\"battery_crit_pct\":%u,"
                     "\"storage_free_pct\":%u,\"target_rearm_f10\":%d,"
                     "\"band_rearm_s\":%u,\"lid_grace_s\":%u}",
                     (unsigned)c->batt_warn_pct, (unsigned)c->batt_crit_pct,
                     (unsigned)c->storage_free_pct,
                     (int)c->target_rearm_f10, (unsigned)c->band_rearm_s,
                     (unsigned)c->lid_grace_s);
}

/* Applies one integer field if present, REFUSING an out-of-range value
 * rather than clamping it. A band of 30000 tenths is a typo, and quietly
 * storing 2000 instead would leave the user with a setting they never
 * chose and no way to tell. */
static bool take_int(const char *body, const char *key, long lo, long hi,
                     long *dst) {
    long v;
    if (app_api_json_int(body, key, &v) != 0) {
        return true; /* absent: merge-patch leaves it alone */
    }
    if (v < lo || v > hi) {
        return false;
    }
    *dst = v;
    return true;
}

#define TAKE_OR_400(key, lo, hi, field, cast)                              \
    do {                                                                   \
        long v_ = (long)(cfg.field);                                       \
        if (!take_int(body, key, (lo), (hi), &v_)) {                       \
            return app_api_error(out, 400, "invalid_field", key);          \
        }                                                                  \
        cfg.field = (cast)v_;                                              \
    } while (0)

static void handle_config_alarms(const app_api_req_t *req,
                                 app_api_out_t *out, bool post) {
    if (!post) {
        app_api_out_begin(out, 200, "application/json");
        emit_alarm_cfg(out);
        return;
    }

    app_alarm_cfg_t cfg = *app_alarm_svc_cfg();
    const char *body = req->body;
    if (body == NULL) {
        return app_api_error(out, 400, "invalid_body", "expected JSON");
    }

    /* rules: [{"rule":"target_reached","enabled":false}, ...] */
    const char *p = strstr(body, "\"rules\"");
    if (p != NULL && (p = strchr(p, '[')) != NULL) {
        p++;
        while (*p != '\0' && *p != ']') {
            const char *name = strstr(p, "\"rule\"");
            const char *obj_end = strchr(p, '}');
            if (name == NULL || obj_end == NULL || name > obj_end) {
                break;
            }
            name = strchr(name + 6, '"');
            if (name == NULL) {
                break;
            }
            name++;
            const char *name_end = strchr(name, '"');
            if (name_end == NULL) {
                break;
            }
            uint8_t rule;
            if (!alarm_rule_from_name(name, (size_t)(name_end - name),
                                      &rule)) {
                return app_api_error(out, 400, "invalid_field",
                                     "unknown rule");
            }
            const char *en = strstr(name_end, "\"enabled\"");
            const char *yes = en != NULL ? strstr(en, "true") : NULL;
            if (en != NULL && en < obj_end) {
                if (yes != NULL && yes < obj_end) {
                    cfg.enabled_mask |= (uint16_t)(1u << rule);
                } else {
                    cfg.enabled_mask &= (uint16_t) ~(1u << rule);
                }
            }
            p = obj_end + 1;
            if (*p == ',') {
                p++;
            }
        }
    }

    TAKE_OR_400("pit_band_f10", 10, 2000, pit_band_f10, int16_t);
    TAKE_OR_400("pit_band_sustain_s", 0, 7200, pit_band_sustain_s, uint16_t);
    TAKE_OR_400("pit_crash_below_f10", 10, 4000, pit_crash_below_f10,
                int16_t);
    TAKE_OR_400("pit_crash_slope_f10_per_hr", -30000, 0,
                pit_crash_slope_f10_per_hr, int16_t);
    TAKE_OR_400("pit_crash_sustain_s", 0, 7200, pit_crash_sustain_s,
                uint16_t);
    TAKE_OR_400("base_lost_s", 60, 65535, base_lost_s, uint16_t);
    TAKE_OR_400("battery_warn_pct", 1, 100, batt_warn_pct, uint8_t);
    TAKE_OR_400("battery_crit_pct", 1, 100, batt_crit_pct, uint8_t);
    TAKE_OR_400("storage_free_pct", 1, 50, storage_free_pct, uint8_t);
    TAKE_OR_400("target_rearm_f10", 0, 1000, target_rearm_f10, int16_t);
    TAKE_OR_400("band_rearm_s", 0, 7200, band_rearm_s, uint16_t);
    TAKE_OR_400("lid_grace_s", 0, 7200, lid_grace_s, uint16_t);

    if (app_alarm_svc_set_cfg(&cfg) != 0) {
        return app_api_error(out, 500, "internal", "could not store rules");
    }
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"ok\":true}");
}

static void handle_time_post(const app_api_req_t *req, app_api_out_t *out) {
    /* int64, NOT long: a 2026 epoch in milliseconds is 1.77e12, which
     * strtol saturates to LONG_MAX on the 32-bit-long device toolchain
     * while parsing perfectly on the 64-bit host that runs the tests. The
     * board's clock landed in January 1970 and the suite stayed green. */
    int64_t unix_ms;
    if (app_api_json_i64(req->body, "unix_ms", &unix_ms) != 0 ||
        unix_ms <= 0) {
        return app_api_error(out, 400, "invalid_field",
                             "unix_ms must be int");
    }
    long tz;
    if (app_api_json_int(req->body, "tz_offset_min", &tz) == 0) {
        (void)app_config_store_set_i32(APP_CONFIG_TIME_TZ_OFFSET_MIN,
                                       (int32_t)tz);
    }
    /* The phone source: F6.1 arbitration decides; F6.2's back-patch rides
     * the acquisition event, already built and tested. */
    (void)app_time_core_set(APP_TIME_PHONE, (uint64_t)unix_ms,
                            s_ops->uptime_ms());
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"ok\":true}");
}

/* ── the app-confirmed cook clock ──────────────────────────────────────
 *
 * The device shows an elapsed time only because an app told it to. This is
 * the whole contract for that: the app says how old the cook is, the strip
 * renders it, and nothing else on the bridge reads it. Recording, retention,
 * and /sessions are untouched — the bridge keeps logging whether or not a
 * cook is ever declared.
 *
 * Setting is IDEMPOTENT AND RE-CALLABLE. Confirming a cook that is already
 * five minutes old is the normal case, not a correction: you light the fire,
 * then you open the app.
 */

static void emit_cook_clock(app_api_out_t *out) {
    uint32_t elapsed = 0;
    const uint32_t up_s = (uint32_t)(s_ops->uptime_ms() / 1000ull);
    if (app_ui_cook_get(up_s, &elapsed)) {
        app_api_emit_fmt(out, "{\"set\":true,\"elapsed_s\":%u}",
                         (unsigned)elapsed);
    } else {
        /* null, not 0. Zero is a cook that started this instant. */
        app_api_emit_str(out, "{\"set\":false,\"elapsed_s\":null}");
    }
}

static void handle_cook_clock_get(app_api_out_t *out) {
    app_api_out_begin(out, 200, "application/json");
    emit_cook_clock(out);
}

static void handle_cook_clock_post(const app_api_req_t *req,
                                   app_api_out_t *out) {
    long elapsed = 0;
    int64_t started_ms = 0;
    const bool have_elapsed =
        app_api_json_int(req->body, "elapsed_s", &elapsed) == 0;
    const bool have_started =
        app_api_json_i64(req->body, "started_unix_ms", &started_ms) == 0;

    /* Exactly one. Accepting both and picking a winner means a client with a
     * disagreeing pair never finds out which one the bridge used. */
    if (have_elapsed == have_started) {
        return app_api_error(
            out, 400, "invalid_field",
            "send exactly one of elapsed_s or started_unix_ms");
    }

    if (have_started) {
        /* Shape before state: a malformed field is a 400 whether or not the
         * device happens to have a clock, and answering 409 for it would
         * send the client off to POST /time over a typo. */
        if (started_ms <= 0) {
            return app_api_error(out, 400, "invalid_field",
                                 "started_unix_ms must be a positive epoch "
                                 "in milliseconds");
        }
        uint64_t now_ms = 0;
        if (!app_time_core_now(s_ops->uptime_ms(), &now_ms)) {
            /* An absolute start time is unusable without a clock to measure
             * it against, and guessing one would put an invented elapsed on
             * the glass — the exact failure this feature removes. The client
             * can POST /time first, or send elapsed_s, which needs no clock
             * at all. */
            return app_api_error(out, 409, "clock_unknown",
                                 "no wall clock yet — set /time first or "
                                 "send elapsed_s instead");
        }
        const int64_t delta_ms = (int64_t)now_ms - started_ms;
        /* A start a little in the future is clock skew between a phone and a
         * bridge, not an error; clamp it. A start hours ahead still fails
         * below, on the range check. */
        elapsed = (long)(delta_ms > 0 ? delta_ms / 1000 : 0);
    }

    if (elapsed < 0 || (uint32_t)elapsed > APP_UI_COOK_MAX_ELAPSED_S) {
        return app_api_error_detail_int(
            out, 400, "invalid_field",
            "elapsed must be 0..359940 s (99:59, the width of the strip's "
            "clock)",
            "max_elapsed_s", (int)APP_UI_COOK_MAX_ELAPSED_S);
    }
    const uint32_t up_s = (uint32_t)(s_ops->uptime_ms() / 1000ull);
    if (app_ui_cook_set((uint32_t)elapsed, up_s) != 0) {
        return app_api_error(out, 400, "invalid_field",
                             "elapsed out of range");
    }
    app_api_out_begin(out, 200, "application/json");
    emit_cook_clock(out);
}

static void handle_cook_clock_delete(app_api_out_t *out) {
    app_ui_cook_clear();
    app_api_out_begin(out, 200, "application/json");
    emit_cook_clock(out);
}

/* ── radio (F9.8) ──────────────────────────────────────────────────────── */

static void handle_radio_get(app_api_out_t *out) {
    const smoke_x_stats_t *st = smoke_x_ctrl_stats();
    const uint32_t freq = smoke_x_ctrl_frequency_hz();
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"frequency_hz\":");
    if (freq != 0) {
        app_api_emit_fmt(out, "%u", (unsigned)freq);
    } else {
        app_api_emit_str(out, "null");
    }
    app_api_emit_fmt(out,
                     ",\"spreading_factor\":9,\"bandwidth_khz\":125,"
                     "\"rssi\":%d,\"snr\":%d,\"packets_ok\":%u,"
                     "\"packets_bad\":%u,\"id_mismatch\":%u,"
                     "\"intervals\":[%u,%u,%u,%u,%u]}",
                     (int)st->last_rssi, (int)st->last_snr,
                     (unsigned)st->valid,
                     (unsigned)(st->parse_fail + st->crc_fail +
                                st->unknown_commas),
                     (unsigned)st->id_mismatch, (unsigned)st->interval_hist[0],
                     (unsigned)st->interval_hist[1],
                     (unsigned)st->interval_hist[2],
                     (unsigned)st->interval_hist[3],
                     (unsigned)st->interval_hist[4]);
}

static void handle_radio_post(const app_api_req_t *req, app_api_out_t *out) {
    /* The conservative reading (the F9.8 flag): the protocol fixes
     * SF/BW/CR and frequency is pairing state — every mutation attempt is
     * refused WITHOUT touching the radio seam. An empty body is a no-op. */
    long v;
    if (app_api_json_int(req->body, "frequency_hz", &v) == 0 ||
        app_api_json_int(req->body, "spreading_factor", &v) == 0 ||
        app_api_json_int(req->body, "bandwidth_khz", &v) == 0 ||
        app_api_json_int(req->body, "coding_rate", &v) == 0) {
        return app_api_error(out, 400, "invalid_field",
                             "radio parameters are pairing state on this "
                             "bridge; see design 06");
    }
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"ok\":true}");
}

/* ── debug (F4.5, F4.6) ────────────────────────────────────────────────── */

static void handle_debug_packets(app_api_out_t *out) {
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"packets\":[");
    const int count = (int)smoke_x_pktring_count();
    /* Newest LAST, capped at 64 — the sim's order. */
    for (int i = count - 1; i >= 0; i--) {
        const smoke_x_pkt_t *p = smoke_x_pktring_get((size_t)i);
        if (i != count - 1) {
            app_api_emit_str(out, ",");
        }
        app_api_emit_fmt(out, "{\"uptime_s\":%u,\"rssi\":%d,\"snr\":%d,"
                              "\"payload\":",
                         (unsigned)(p->t_ms / 1000u), (int)p->rssi,
                         (int)p->snr);
        app_api_emit_json_str(out, p->payload);
        app_api_emit_str(out, "}");
    }
    app_api_emit_str(out, "]}");
}

/* Passthrough: streams a text log straight to the response emitter. Shared
 * by /debug/novelty and /debug/power — both are plain-text ring dumps. */
static int log_text_sink(void *ctx, const char *data, size_t len) {
    app_api_emit_raw(ctx, data, len);
    return 0;
}

static void handle_debug_novelty(app_api_out_t *out) {
    app_api_out_begin(out, 200, "text/plain");
    (void)cook_novelty_log_stream(log_text_sink, out);
}

/* The persisted battery power log — the discharge curve and, after an
 * offline brownout, the last reading before death followed by the BOOT
 * marker. This is what the human reads after the offline battery test. */
static void handle_debug_power(app_api_out_t *out) {
    app_api_out_begin(out, 200, "text/plain");
    (void)cook_power_log_stream(log_text_sink, out);
}

/* V3.1 — the soak's evidence, over HTTP rather than over a serial cable
 * (design 01 §1.4, 10 §10.5). Streamed like every other response. */
static void handle_debug_tasks(app_api_out_t *out) {
    static app_api_tasks_snapshot_t snap;
    memset(&snap, 0, sizeof snap);
    if (s_ops->tasks_snapshot != NULL) {
        s_ops->tasks_snapshot(&snap);
    }
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out,
                     "{\"heap\":{\"free_b\":%u,\"min_free_b\":%u,"
                     "\"largest_free_block_b\":%u},\"tasks\":[",
                     (unsigned)snap.free_heap,
                     (unsigned)snap.min_free_heap,
                     (unsigned)snap.largest_free_block);
    for (int i = 0; i < snap.count && i < APP_API_MAX_TASKS; i++) {
        const app_api_task_row_t *r = &snap.rows[i];
        app_api_emit_str(out, i > 0 ? ",{\"name\":" : "{\"name\":");
        app_api_emit_json_str(out, r->name);
        app_api_emit_fmt(out,
                         ",\"stack_b\":%u,\"high_water_b\":%u,"
                         "\"margin_b\":%u,\"priority\":%u,\"core\":%d}",
                         (unsigned)r->stack_b, (unsigned)r->high_water_b,
                         (unsigned)r->margin_b, (unsigned)r->priority,
                         (int)r->core);
    }
    app_api_emit_str(out, "]}");
}

static void handle_debug_coredump(app_api_out_t *out) {
    const size_t size = s_ops->coredump_size ? s_ops->coredump_size() : 0;
    if (size == 0) {
        return app_api_error(out, 404, "not_found", "no coredump stored");
    }
    app_api_out_begin(out, 200, "application/octet-stream");
    uint8_t buf[512];
    size_t off = 0;
    while (off < size) {
        const size_t n = size - off < sizeof buf ? size - off : sizeof buf;
        if (s_ops->coredump_read(off, buf, n) < 0) {
            break;
        }
        app_api_emit_raw(out, buf, n);
        off += n;
    }
}

/* ── router (F9.1) ─────────────────────────────────────────────────────── */

int app_api_handle(const app_api_req_t *req, app_api_out_t *out) {
    const char *path = req->path;
    const bool is_get = strcmp(req->method, "GET") == 0;

    if (handle_captive(req, out)) {
        return 0; /* probes answer regardless of anything else (F8.7) */
    }

    if (strncmp(path, "/api/v1", 7) != 0) {
        /* F9.10: the glue serves static only when the www mount rule
         * passes; everything else gets the built-in page. */
        if (is_get) {
            app_api_out_begin(out, 200, "text/html");
            app_api_emit_str(out, k_builtin_page);
        } else {
            app_api_error(out, 404, "not_found", "no such route");
        }
        return 0;
    }

    /* The optional bearer gate (05 §5.9): set → required on all of
     * API routes, JSON like every other response. */
    if (!auth_ok(req)) {
        app_api_error(out, 401, "unauthorized",
                      "missing or invalid bearer token");
        return 0;
    }

    const char *api = path + 7;

    if (is_get && strcmp(api, "/status") == 0) {
        handle_status(out);
        return 0;
    }
    if (is_get && strcmp(api, "/live") == 0) {
        handle_live(req, out);
        return 0;
    }
    if (is_get && strcmp(api, "/sessions") == 0) {
        app_api_handle_sessions_list(req, out);
        return 0;
    }
    if (!is_get && strcmp(api, "/sessions") == 0 &&
        strcmp(req->method, "POST") == 0) {
        app_api_handle_sessions_post(req, out);
        return 0;
    }
    if (strncmp(api, "/sessions/", 10) == 0) {
        const char *idp = api + 10;
        char *end;
        const unsigned long id = strtoul(idp, &end, 10);
        if (end == idp) {
            app_api_error(out, 404, "not_found", "bad session id");
            return 0;
        }
        app_api_handle_session(req, out, (uint32_t)id, end);
        return 0;
    }
    if (is_get && strcmp(api, "/pairing") == 0) {
        handle_pairing_get(out);
        return 0;
    }
    if (strcmp(req->method, "POST") == 0 &&
        strcmp(api, "/pairing/sync") == 0) {
        (void)smoke_x_ctrl_unpair(); /* restarts the scan; M1 proved it
                                        touches nothing external */
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_str(out, "{\"ok\":true,\"sync_active\":true}");
        return 0;
    }
    if (strcmp(req->method, "POST") == 0 &&
        strcmp(api, "/pairing/unpair") == 0) {
        (void)smoke_x_ctrl_unpair();
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_str(out, "{\"ok\":true}");
        return 0;
    }
    /* ── the destructive verbs (v1.1) ──────────────────────────────────
     * The PRG button is display + power only, so factory reset and restart
     * have to be reachable from the app. Each answers FIRST and acts after
     * the deferral in the glue, exactly like the OTA reboot: a client that
     * never sees its 200 cannot tell success from a dropped connection. */
    /* newapp §E.3 — the confirmation half of a mode switch. */
    if (strcmp(req->method, "POST") == 0 &&
        strcmp(api, "/config/wifi/commit") == 0) {
        handle_netmode_commit(out);
        return 0;
    }
    if (strcmp(req->method, "POST") == 0 && strcmp(api, "/restart") == 0) {
        if (s_ops->reboot == NULL) {
            app_api_error(out, 501, "unsupported",
                          "no restart on this build");
            return 0;
        }
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_str(out, "{\"ok\":true,\"rebooting_in_ms\":500}");
        s_ops->reboot();
        return 0;
    }
    if (strcmp(req->method, "POST") == 0 &&
        strcmp(api, "/factory-reset") == 0) {
        if (s_ops->factory_reset == NULL) {
            app_api_error(out, 501, "unsupported",
                          "no factory reset on this build");
            return 0;
        }
        if (s_ops->factory_reset() != 0) {
            app_api_error(out, 500, "failed", "factory reset failed");
            return 0;
        }
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_str(out, "{\"ok\":true,\"rebooting_in_ms\":500}");
        return 0;
    }
    if (strcmp(req->method, "POST") == 0 && strcmp(api, "/power-off") == 0) {
        if (s_ops->power_off == NULL) {
            app_api_error(out, 501, "unsupported",
                          "no power off on this build");
            return 0;
        }
        /* wake_requires_button is not decoration: nothing remote can bring
         * the bridge back, so the app must be able to warn before asking. */
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_str(out,
                         "{\"ok\":true,\"sleeping_in_ms\":500,"
                         "\"wake_requires_button\":true}");
        s_ops->power_off();
        return 0;
    }
    if (strcmp(api, "/config/wifi") == 0) {
        if (is_get) {
            handle_config_wifi_get(out);
        } else {
            handle_config_wifi_post(req, out);
        }
        return 0;
    }
    if (strcmp(api, "/config/device") == 0) {
        if (is_get) {
            handle_config_device_get(out);
        } else {
            handle_config_device_post(req, out);
        }
        return 0;
    }
    if (strcmp(api, "/config/mqtt") == 0) {
        if (is_get) {
            handle_config_mqtt_get(out);
        } else {
            handle_config_mqtt_post(req, out);
        }
        return 0;
    }
    if (strcmp(api, "/config/alarms") == 0) {
        handle_config_alarms(req, out, !is_get);
        return 0;
    }
    if (strcmp(req->method, "POST") == 0 && strcmp(api, "/time") == 0) {
        handle_time_post(req, out);
        return 0;
    }
    if (strcmp(api, "/cook-clock") == 0) {
        if (is_get) {
            handle_cook_clock_get(out);
        } else if (strcmp(req->method, "POST") == 0) {
            handle_cook_clock_post(req, out);
        } else if (strcmp(req->method, "DELETE") == 0) {
            handle_cook_clock_delete(out);
        } else {
            app_api_error(out, 404, "not_found", "no such route");
        }
        return 0;
    }
    if (strcmp(api, "/radio") == 0) {
        if (is_get) {
            handle_radio_get(out);
        } else {
            handle_radio_post(req, out);
        }
        return 0;
    }
    if (is_get && strcmp(api, "/debug/packets") == 0) {
        handle_debug_packets(out);
        return 0;
    }
    if (is_get && strcmp(api, "/debug/novelty") == 0) {
        handle_debug_novelty(out);
        return 0;
    }
    if (is_get && strcmp(api, "/debug/power") == 0) {
        handle_debug_power(out);
        return 0;
    }
    if (is_get && strcmp(api, "/debug/coredump") == 0) {
        handle_debug_coredump(out);
        return 0;
    }
    if (is_get && strcmp(api, "/debug/tasks") == 0) {
        handle_debug_tasks(out);
        return 0;
    }
    /* F14.5 — /ota is real now, but it never comes through here: the
     * glue intercepts it BEFORE the 8 KB body buffer and calls
     * app_api_handle_ota() with a streaming reader. Reaching this line
     * with a POST means the glue forgot, and saying so beats a 404 that
     * looks like the M2..M5 stub. */
    if (strcmp(api, "/ota") == 0 && strcmp(req->method, "POST") == 0) {
        app_api_error(out, 500, "internal",
                      "ota must be streamed; the glue did not intercept it");
        return 0;
    }
    app_api_error(out, 404, "not_found", "no such route");
    return 0;
}

/* ── F14.5: the streamed OTA upload ───────────────────────────────────── */

static void ota_emit_progress(const app_api_ota_ctx_t *ota) {
    if (!ota->progress) {
        return;
    }
    app_ota_phase_t phase;
    int pct = 0;
    while (app_ota_session_take_progress(ota->session, &phase, &pct)) {
        ota->progress(ota->progress_ctx, phase, pct);
    }
}

int app_api_handle_ota(const app_api_req_t *req, app_api_out_t *out,
                       const app_api_ota_ctx_t *ota) {
    if (!req || !out || !ota || !ota->session || !ota->flash || !ota->read) {
        app_api_error(out, 500, "internal", "ota context incomplete");
        return 0;
    }
    /* Auth first: a wrong token must not even be told whether a cook is
     * running. */
    if (!auth_ok(req)) {
        app_api_error(out, 401, "unauthorized",
                      "missing or invalid bearer token");
        return 0;
    }
    if (strcmp(req->method, "POST") != 0) {
        app_api_error(out, 404, "not_found", "no such route");
        return 0;
    }

    const char *force = app_api_query_get(req, "force");
    const bool forced = force && strcmp(force, "1") == 0;

    const app_ota_admit_t admit = app_ota_session_admit(
        ota->session, ota->session_active, forced, ota->content_len);
    switch (admit) {
    case APP_OTA_ADMIT_OK:
        break;
    case APP_OTA_ADMIT_SESSION_ACTIVE:
        app_api_error(out, 409, "session_active",
                      "a cook is running — retry with ?force=1. Nobody "
                      "should discover a bad flash 14 hours into a brisket");
        return 0;
    case APP_OTA_ADMIT_IN_PROGRESS:
        app_api_error(out, 503, "ota_in_progress",
                      "an update is already being written");
        return 0;
    case APP_OTA_ADMIT_EMPTY:
        app_api_error(out, 400, "invalid_body", "empty image");
        return 0;
    }

    app_ota_session_begin(ota->session, ota->flash, ota->content_len);

    static uint8_t chunk[2048];
    size_t got = 0;
    while (got < ota->content_len) {
        const size_t want = (ota->content_len - got) < sizeof chunk
                                ? (ota->content_len - got)
                                : sizeof chunk;
        const int n = ota->read(ota->read_ctx, chunk, want);
        if (n < 0) {
            app_ota_session_fail(ota->session, "upload_aborted");
            ota_emit_progress(ota);
            app_api_error(out, 400, "invalid_body",
                          "the upload stopped before the image ended");
            app_ota_session_reset(ota->session);
            return 0;
        }
        if (n == 0) {
            break;
        }
        if (app_ota_session_feed(ota->session, chunk, (size_t)n) != 0) {
            const char *reason = ota->session->fail_reason
                                     ? ota->session->fail_reason
                                     : "invalid_image";
            ota_emit_progress(ota);
            app_api_error(out, 400, "invalid_body", reason);
            app_ota_session_reset(ota->session);
            return 0;
        }
        got += (size_t)n;
        ota_emit_progress(ota);
    }

    if (app_ota_session_finish(ota->session) != 0) {
        const char *reason = ota->session->fail_reason
                                 ? ota->session->fail_reason
                                 : "image_validation_failed";
        ota_emit_progress(ota);
        /* 400 rather than 500: the image the client sent is the problem,
         * and it is the client that must send a different one. */
        app_api_error(out, 400, "invalid_body", reason);
        app_ota_session_reset(ota->session);
        return 0;
    }
    ota_emit_progress(ota);

    /* 06 §6.2's OtaAccepted, sent BEFORE the deferred reboot fires. */
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out, "{\"accepted\":true,\"image_size_b\":%u,\"slot\":",
                     (unsigned)ota->session->received);
    app_api_emit_json_str(out, ota->flash->slot_name
                                   ? ota->flash->slot_name(ota->flash->ctx)
                                   : "");
    app_api_emit_str(out, ",\"version\":");
    app_api_emit_json_str(out, ota->session->info.version);
    app_api_emit_str(out, ",\"project\":");
    /* Reported, never enforced — a fork that renames its CMake project
     * should not be locked out of its own hardware. */
    app_api_emit_json_str(out, ota->session->info.project);
    app_api_emit_str(out, ",\"rebooting_in_ms\":500}");
    return 0;
}
