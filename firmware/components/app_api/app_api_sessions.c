/* app_api_sessions — the sessions group and the streamed samples
 * workhorse (F9.4, F9.5). Every body flows through the F9.2 emitter;
 * bucketed aggregation uses a bounded static working set so memory use is
 * independent of session length. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app_api_internal.h"
#include "cook_store_core.h"

#define MAX_BUCKETS 1024

int app_api_maxt_sink(void *ctx, const bridge_sample_rec_t *rec);

/* ── session JSON ──────────────────────────────────────────────────────── */

static void emit_session_json(app_api_out_t *out,
                              const bridge_session_header_t *h,
                              uint32_t derived_count, uint32_t mark_count) {
    const bool clock = bridge_session_header_clock_valid(h->flags);
    const bool closed = bridge_session_header_closed(h->flags);
    app_api_emit_fmt(out, "{\"id\":%u,\"name\":", (unsigned)h->session_id);
    app_api_emit_json_str(out, h->name);
    app_api_emit_str(out, ",\"started_unix_ms\":");
    if (clock && h->started_unix_ms != 0) {
        app_api_emit_fmt(out, "%llu", (unsigned long long)h->started_unix_ms);
    } else {
        app_api_emit_str(out, "null");
    }
    app_api_emit_str(out, ",\"ended_unix_ms\":");
    if (closed && clock && h->ended_unix_ms != 0) {
        app_api_emit_fmt(out, "%llu", (unsigned long long)h->ended_unix_ms);
    } else {
        app_api_emit_str(out, "null");
    }
    app_api_emit_fmt(out,
                     ",\"sample_period_s\":%u,\"sample_count\":%u,"
                     "\"num_probes\":%u,\"probes\":[",
                     (unsigned)h->sample_period_s,
                     (unsigned)(closed ? h->sample_count : derived_count),
                     (unsigned)h->num_probes);
    static const char *const roles[] = {"unused", "pit", "food", "ambient"};
    for (int i = 0; i < 4; i++) {
        app_api_emit_fmt(out, "%s{\"n\":%d,\"name\":", i ? "," : "", i + 1);
        char name[13];
        memcpy(name, h->probe_name[i], 12);
        name[12] = '\0';
        app_api_emit_json_str(out, name);
        app_api_emit_fmt(out, ",\"role\":\"%s\",\"target_f10\":",
                         roles[h->probe_role[i] < 4 ? h->probe_role[i] : 0]);
        if (h->probe_target[i] == 0) {
            app_api_emit_str(out, "null}");
        } else {
            app_api_emit_fmt(out, "%d}", (int)h->probe_target[i]);
        }
    }
    app_api_emit_fmt(out, "],\"closed\":%s,\"pinned\":%s,\"mark_count\":%u}",
                     closed ? "true" : "false",
                     bridge_session_header_pinned(h->flags) ? "true"
                                                            : "false",
                     (unsigned)mark_count);
}

void app_api_handle_sessions_list(const app_api_req_t *req,
                                  app_api_out_t *out) {
    (void)req;
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"sessions\":[");
    const int n = cook_store_index_count();
    for (int i = 0; i < n; i++) {
        const cook_index_entry_t *e = cook_store_index_get(i);
        bridge_session_header_t h;
        if (cook_store_read_header(e->session_id, &h) != COOK_STORE_OK) {
            continue;
        }
        if (i > 0) {
            app_api_emit_str(out, ",");
        }
        emit_session_json(out, &h, e->sample_count, h.mark_count);
    }
    app_api_emit_str(out, "]}");
}

void app_api_handle_sessions_post(const app_api_req_t *req,
                                  app_api_out_t *out) {
    (void)req;
    if (cook_session_is_open()) {
        return app_api_error(out, 409, "session_active",
                             "a session is already running");
    }
    /* The explicit-start path into F5.4's lifecycle: the session opens on
     * the next received sample; the WebSocket announces it. */
    (void)cook_store_request_start();
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_str(out, "{\"ok\":true,\"pending\":true}");
}

/* ── marks ─────────────────────────────────────────────────────────────── */

typedef struct {
    app_api_out_t *out;
    int n;
} marks_ctx_t;

static int marks_cb(void *ctx, const bridge_mark_rec_t *m) {
    marks_ctx_t *c = ctx;
    if (c->n > 0) {
        app_api_emit_str(c->out, ",");
    }
    char text[25];
    memcpy(text, m->text, 24);
    text[24] = '\0';
    app_api_emit_fmt(c->out, "{\"t\":%u,\"kind\":%u,\"probe\":%u,\"text\":",
                     (unsigned)m->t, (unsigned)m->kind, (unsigned)m->probe);
    app_api_emit_json_str(c->out, text);
    app_api_emit_str(c->out, "}");
    c->n++;
    return 0;
}

/* ── samples (F9.5) ────────────────────────────────────────────────────── */

typedef struct {
    app_api_out_t *out;
    uint32_t emitted;
    uint32_t stride;
    uint32_t seen;
    /* gap tracking */
    uint32_t prev_t;
    bool have_prev;
    /* csv */
    bool clock_valid;
    uint64_t started_unix_ms;
} sample_ctx_t;

static int count_sink(void *ctx, const bridge_sample_rec_t *rec) {
    (void)rec;
    (*(uint32_t *)ctx)++;
    return 0;
}

static int bin_sink(void *ctx, const bridge_sample_rec_t *rec) {
    sample_ctx_t *c = ctx;
    if ((c->seen++ % c->stride) == 0) {
        uint8_t buf[BRIDGE_SAMPLE_REC_SIZE];
        bridge_sample_rec_encode(rec, buf);
        app_api_emit_raw(c->out, buf, sizeof buf);
    }
    return 0;
}

static void emit_temp_or_null(app_api_out_t *out, int16_t v) {
    if (v == BRIDGE_TEMP_DETACHED || v == BRIDGE_TEMP_INVALID) {
        app_api_emit_str(out, "null");
    } else {
        app_api_emit_fmt(out, "%d", (int)v);
    }
}

static int ndjson_sink(void *ctx, const bridge_sample_rec_t *rec) {
    sample_ctx_t *c = ctx;
    if ((c->seen++ % c->stride) != 0) {
        return 0;
    }
    app_api_emit_fmt(c->out, "{\"t\":%u,\"temps_f10\":[", (unsigned)rec->t);
    for (int i = 0; i < 4; i++) {
        if (i) {
            app_api_emit_str(c->out, ",");
        }
        emit_temp_or_null(c->out, rec->temp[i]);
    }
    app_api_emit_fmt(c->out, "],\"billows\":%s,\"rssi\":%d}\n",
                     bridge_sample_rec_billows(rec->flags) ? "true" : "false",
                     (int)rec->rssi);
    return 0;
}

static int csv_sink(void *ctx, const bridge_sample_rec_t *rec) {
    sample_ctx_t *c = ctx;
    if ((c->seen++ % c->stride) != 0) {
        return 0;
    }
    app_api_emit_fmt(c->out, "%u,", (unsigned)rec->t);
    if (c->clock_valid) {
        const uint64_t ms = c->started_unix_ms + (uint64_t)rec->t * 1000u;
        /* Civil-from-days (Hinnant) � no platform gmtime variants. */
        const int64_t secs = (int64_t)(ms / 1000u);
        int64_t days = secs / 86400;
        int rem = (int)(secs % 86400);
        int64_t z = days + 719468;
        const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
        const unsigned doe = (unsigned)(z - era * 146097);
        const unsigned yoe =
            (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        const int64_t y = (int64_t)yoe + era * 400;
        const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        const unsigned mp = (5 * doy + 2) / 153;
        const unsigned d = doy - (153 * mp + 2) / 5 + 1;
        const unsigned m = mp < 10 ? mp + 3 : mp - 9;
        app_api_emit_fmt(c->out, "%04d-%02u-%02uT%02d:%02d:%02d.%03uZ",
                         (int)(y + (m <= 2)), m, d, rem / 3600,
                         (rem % 3600) / 60, rem % 60,
                         (unsigned)(ms % 1000u));
    }
    for (int i = 0; i < 4; i++) {
        app_api_emit_str(c->out, ",");
        const int16_t v = rec->temp[i];
        if (v != BRIDGE_TEMP_DETACHED && v != BRIDGE_TEMP_INVALID) {
            /* Detached probes are EMPTY fields, never 0 (04 §4.10). */
            app_api_emit_fmt(c->out, "%.1f", v / 10.0);
        }
    }
    app_api_emit_fmt(c->out, ",%d,%d\n",
                     bridge_sample_rec_billows(rec->flags) ? 1 : 0,
                     (int)rec->rssi);
    return 0;
}

static int gaps_sink(void *ctx, const bridge_sample_rec_t *rec) {
    sample_ctx_t *c = ctx;
    if (c->have_prev && rec->t - c->prev_t > 45) {
        if (c->emitted > 0) {
            app_api_emit_str(c->out, ",");
        }
        app_api_emit_fmt(c->out, "{\"from\":%u,\"to\":%u}",
                         (unsigned)c->prev_t, (unsigned)rec->t);
        c->emitted++;
    }
    c->prev_t = rec->t;
    c->have_prev = true;
    return 0;
}

static int plain_json_sink(void *ctx, const bridge_sample_rec_t *rec) {
    sample_ctx_t *c = ctx;
    if ((c->seen++ % c->stride) != 0) {
        return 0;
    }
    if (c->emitted++ > 0) {
        app_api_emit_str(c->out, ",");
    }
    app_api_emit_fmt(c->out, "{\"t\":%u,\"temps_f10\":[", (unsigned)rec->t);
    for (int i = 0; i < 4; i++) {
        if (i) {
            app_api_emit_str(c->out, ",");
        }
        emit_temp_or_null(c->out, rec->temp[i]);
    }
    app_api_emit_fmt(c->out, "],\"billows\":%s,\"rssi\":%d}",
                     bridge_sample_rec_billows(rec->flags) ? "true" : "false",
                     (int)rec->rssi);
    return 0;
}

/* Bounded bucket accumulation: one probe at a time (memory independent of
 * session length — the F9.2 spirit applied to aggregation). */
static int16_t s_bmin[MAX_BUCKETS];
static int16_t s_bmax[MAX_BUCKETS];
static int32_t s_bsum[MAX_BUCKETS];
static uint16_t s_bn[MAX_BUCKETS];

typedef struct {
    uint32_t from;
    uint32_t bucket_s;
    uint32_t count;
    int probe; /* 0-based */
} bucket_ctx_t;

static int bucket_sink(void *ctx, const bridge_sample_rec_t *rec) {
    bucket_ctx_t *c = ctx;
    const int16_t v = rec->temp[c->probe];
    if (v == BRIDGE_TEMP_DETACHED || v == BRIDGE_TEMP_INVALID) {
        return 0;
    }
    uint32_t b = (rec->t - c->from) / c->bucket_s;
    if (b >= c->count) {
        b = c->count - 1; /* t == to lands in the last bucket (sim rule) */
    }
    if (s_bn[b] == 0 || v < s_bmin[b]) {
        s_bmin[b] = v;
    }
    if (s_bn[b] == 0 || v > s_bmax[b]) {
        s_bmax[b] = v;
    }
    s_bsum[b] += v;
    s_bn[b]++;
    return 0;
}

static void emit_bucket_array(app_api_out_t *out, uint32_t count,
                              const int16_t *vals, bool mean) {
    app_api_emit_str(out, "[");
    for (uint32_t b = 0; b < count; b++) {
        if (b) {
            app_api_emit_str(out, ",");
        }
        if (s_bn[b] == 0) {
            app_api_emit_str(out, "null");
        } else if (mean) {
            app_api_emit_fmt(out, "%ld",
                             lround((double)s_bsum[b] / s_bn[b]));
        } else {
            app_api_emit_fmt(out, "%d", (int)vals[b]);
        }
    }
    app_api_emit_str(out, "]");
}

static void handle_samples(const app_api_req_t *req, app_api_out_t *out,
                           uint32_t id) {
    bridge_session_header_t h;
    if (cook_store_read_header(id, &h) != COOK_STORE_OK) {
        char msg[32];
        snprintf(msg, sizeof msg, "no session %u", (unsigned)id);
        return app_api_error_detail_int(out, 404, "session_not_found", msg,
                                        "id", (int)id);
    }

    long from = 0, to = -1, stride = 1, bucket = 0;
    if (app_api_query_int(req, "from", 0, &from) != 0 ||
        app_api_query_int(req, "to", -1, &to) != 0 ||
        app_api_query_int(req, "stride", 1, &stride) != 0 ||
        app_api_query_int(req, "bucket", 0, &bucket) != 0) {
        return app_api_error(out, 400, "invalid_field", "bad numeric param");
    }
    const char *agg = app_api_query_get(req, "agg");
    if (!agg) {
        agg = bucket > 0 ? "mean" : "none";
    }
    const char *format = app_api_query_get(req, "format");
    if (!format) {
        format = "bin";
    }
    if (stride < 1 || bucket < 0 || from < 0 || (to >= 0 && to < from)) {
        return app_api_error(out, 400, "invalid_field",
                             "bad range/stride/bucket");
    }
    if ((strcmp(agg, "none") != 0 && strcmp(agg, "mean") != 0 &&
         strcmp(agg, "minmax") != 0) ||
        (strcmp(format, "bin") != 0 && strcmp(format, "json") != 0 &&
         strcmp(format, "ndjson") != 0 && strcmp(format, "csv") != 0)) {
        return app_api_error(out, 400, "invalid_field", "bad agg/format");
    }

    int probes[4];
    int probe_count = 0;
    const char *pq = app_api_query_get(req, "probes");
    if (pq) {
        char tmp[32];
        snprintf(tmp, sizeof tmp, "%s", pq);
        char *save = NULL;
        for (char *tok = strtok_r(tmp, ",", &save); tok;
             tok = strtok_r(NULL, ",", &save)) {
            const int p = atoi(tok);
            if (p >= 1 && p <= 4 && probe_count < 4) {
                probes[probe_count++] = p;
            }
        }
    } else {
        for (int i = 0; i < 4; i++) {
            probes[probe_count++] = i + 1;
        }
    }

    /* Record count for the plain-JSON `count` field: one cheap pass. */
    uint32_t range_count = 0;
    (void)cook_store_read(id, (uint32_t)from,
                          to >= 0 ? (uint32_t)to : UINT32_MAX, 1, 0,
                          COOK_AGG_NONE, count_sink, NULL, &range_count);

    /* Bucketed JSON (bucket>0 && agg!=none). */
    if (bucket > 0 && strcmp(agg, "none") != 0) {
        uint32_t to_u;
        if (to >= 0) {
            to_u = (uint32_t)to;
        } else {
            /* The sim defaults `to` to the last sample's t. */
            uint32_t maxt = (uint32_t)from;
            (void)cook_store_read(id, (uint32_t)from, UINT32_MAX, 1, 0,
                                  COOK_AGG_NONE, app_api_maxt_sink, NULL,
                                  &maxt);
            to_u = maxt;
        }
        const uint32_t count =
            ((to_u - (uint32_t)from) + (uint32_t)bucket - 1) /
            (uint32_t)bucket;
        if (count == 0 || count > MAX_BUCKETS) {
            return app_api_error(out, 400, "invalid_field",
                                 "bucket count out of range (max 1024)");
        }
        const bool minmax = strcmp(agg, "minmax") == 0;
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_fmt(out,
                         "{\"session_id\":%u,\"from\":%ld,\"to\":%u,"
                         "\"bucket_s\":%ld,\"agg\":\"%s\",\"count\":%u,"
                         "\"probes\":[",
                         (unsigned)id, from, (unsigned)to_u, bucket, agg,
                         (unsigned)count);
        for (int i = 0; i < probe_count; i++) {
            app_api_emit_fmt(out, "%s%d", i ? "," : "", probes[i]);
        }
        app_api_emit_str(out, "],\"series\":[");
        for (int i = 0; i < probe_count; i++) {
            memset(s_bn, 0, sizeof(uint16_t) * count);
            memset(s_bsum, 0, sizeof(int32_t) * count);
            bucket_ctx_t bc = {.from = (uint32_t)from,
                               .bucket_s = (uint32_t)bucket,
                               .count = count,
                               .probe = probes[i] - 1};
            (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0,
                                  COOK_AGG_NONE, bucket_sink, NULL, &bc);
            app_api_emit_fmt(out, "%s{\"probe\":%d,", i ? "," : "",
                             probes[i]);
            if (minmax) {
                app_api_emit_str(out, "\"min\":");
                emit_bucket_array(out, count, s_bmin, false);
                app_api_emit_str(out, ",");
            }
            app_api_emit_str(out, "\"mean\":");
            emit_bucket_array(out, count, NULL, true);
            if (minmax) {
                app_api_emit_str(out, ",\"max\":");
                emit_bucket_array(out, count, s_bmax, false);
            }
            app_api_emit_str(out, "}");
        }
        app_api_emit_str(out, "],\"gaps\":[");
        sample_ctx_t gc = {.out = out, .stride = 1};
        (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0, COOK_AGG_NONE,
                              gaps_sink, NULL, &gc);
        app_api_emit_str(out, "]}");
        return;
    }

    const uint32_t to_u = to >= 0 ? (uint32_t)to : UINT32_MAX;
    sample_ctx_t ctx = {.out = out, .stride = (uint32_t)stride};
    ctx.clock_valid = bridge_session_header_clock_valid(h.flags) &&
                      h.started_unix_ms != 0;
    ctx.started_unix_ms = h.started_unix_ms;

    if (strcmp(format, "bin") == 0) {
        app_api_out_begin(out, 200, "application/octet-stream");
        (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0, COOK_AGG_NONE,
                              bin_sink, NULL, &ctx);
        return;
    }
    if (strcmp(format, "ndjson") == 0) {
        app_api_out_begin(out, 200, "application/x-ndjson");
        (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0, COOK_AGG_NONE,
                              ndjson_sink, NULL, &ctx);
        return;
    }
    if (strcmp(format, "csv") == 0) {
        app_api_out_begin(out, 200, "text/csv");
        app_api_emit_str(out,
                         "t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi\n");
        (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0, COOK_AGG_NONE,
                              csv_sink, NULL, &ctx);
        return;
    }

    /* Plain JSON: count first (already have range_count), then samples,
     * then gaps — the sim's key order. */
    const uint32_t emitted_count =
        stride > 1 ? (range_count + (uint32_t)stride - 1) / (uint32_t)stride
                   : range_count;
    app_api_out_begin(out, 200, "application/json");
    app_api_emit_fmt(out, "{\"session_id\":%u,\"from\":%ld,\"to\":",
                     (unsigned)id, from);
    if (to >= 0) {
        app_api_emit_fmt(out, "%ld", to);
    } else {
        uint32_t maxt = (uint32_t)from;
        (void)cook_store_read(id, (uint32_t)from, UINT32_MAX, 1, 0,
                              COOK_AGG_NONE, app_api_maxt_sink, NULL, &maxt);
        app_api_emit_fmt(out, "%u", (unsigned)maxt);
    }
    app_api_emit_fmt(out, ",\"count\":%u,\"probes\":[",
                     (unsigned)emitted_count);
    for (int i = 0; i < probe_count; i++) {
        app_api_emit_fmt(out, "%s%d", i ? "," : "", probes[i]);
    }
    app_api_emit_str(out, "],\"samples\":[");
    ctx.emitted = 0;
    ctx.seen = 0;
    (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0, COOK_AGG_NONE,
                          plain_json_sink, NULL, &ctx);
    app_api_emit_str(out, "],\"gaps\":[");
    sample_ctx_t gc = {.out = out, .stride = 1};
    (void)cook_store_read(id, (uint32_t)from, to_u, 1, 0, COOK_AGG_NONE,
                          gaps_sink, NULL, &gc);
    app_api_emit_str(out, "]}");
}

int app_api_maxt_sink(void *ctx, const bridge_sample_rec_t *rec) {
    uint32_t *maxt = ctx;
    if (rec->t > *maxt) {
        *maxt = rec->t;
    }
    return 0;
}

/* ── per-session dispatch ──────────────────────────────────────────────── */

void app_api_handle_session(const app_api_req_t *req, app_api_out_t *out,
                            uint32_t id, const char *sub) {
    bridge_session_header_t h;
    if (cook_store_read_header(id, &h) != COOK_STORE_OK) {
        char msg[32];
        snprintf(msg, sizeof msg, "no session %u", (unsigned)id);
        return app_api_error_detail_int(out, 404, "session_not_found", msg,
                                        "id", (int)id);
    }
    const cook_index_entry_t *e = cook_store_index_find(id);
    const uint32_t derived = e ? e->sample_count : h.sample_count;
    const bool is_get = strcmp(req->method, "GET") == 0;

    if (sub[0] == '\0') {
        if (is_get) {
            app_api_out_begin(out, 200, "application/json");
            emit_session_json(out, &h, derived, h.mark_count);
            return;
        }
        if (strcmp(req->method, "PATCH") == 0) {
            cook_session_patch_t p = {.pinned = -1};
            char name[40];
            if (app_api_json_str(req->body, "name", name, sizeof name) ==
                0) {
                p.name = name;
            }
            bool pinned;
            if (app_api_json_bool(req->body, "pinned", &pinned) == 0) {
                p.pinned = pinned ? 1 : 0;
            }
            if (cook_session_patch(id, &p) != COOK_STORE_OK) {
                return app_api_error(out, 500, "storage_error",
                                     "header rewrite failed");
            }
            (void)cook_store_read_header(id, &h);
            app_api_out_begin(out, 200, "application/json");
            emit_session_json(out, &h, derived, h.mark_count);
            return;
        }
        if (strcmp(req->method, "DELETE") == 0) {
            const int rc = cook_store_delete(id);
            if (rc == COOK_STORE_ERR_STATE) {
                return app_api_error(
                    out, 409, "session_active",
                    "refusing to delete the active session");
            }
            if (rc != COOK_STORE_OK) {
                return app_api_error(out, 500, "storage_error",
                                     "delete failed");
            }
            app_api_out_begin(out, 200, "application/json");
            app_api_emit_str(out, "{\"ok\":true}");
            return;
        }
    }
    if (strcmp(sub, "/stop") == 0 && strcmp(req->method, "POST") == 0) {
        if (!cook_session_is_open() || cook_session_active_id() != id) {
            return app_api_error(out, 409, "session_active",
                                 "no active session with this id");
        }
        (void)cook_store_request_stop();
        app_api_out_begin(out, 200, "application/json");
        app_api_emit_str(out, "{\"ok\":true}");
        return;
    }
    if (strcmp(sub, "/samples") == 0 && is_get) {
        return handle_samples(req, out, id);
    }
    if (strcmp(sub, "/marks") == 0) {
        if (is_get) {
            app_api_out_begin(out, 200, "application/json");
            app_api_emit_str(out, "{\"marks\":[");
            marks_ctx_t mc = {.out = out};
            (void)cook_store_read_marks(id, marks_cb, &mc);
            app_api_emit_str(out, "]}");
            return;
        }
        if (strcmp(req->method, "POST") == 0) {
            if (!cook_session_is_open() || cook_session_active_id() != id) {
                return app_api_error(out, 409, "session_active",
                                     "marks land on the active session");
            }
            long t = 0, kind = 0, probe = 0;
            (void)app_api_json_int(req->body, "t", &t);
            (void)app_api_json_int(req->body, "kind", &kind);
            (void)app_api_json_int(req->body, "probe", &probe);
            char text[64] = "";
            (void)app_api_json_str(req->body, "text", text, sizeof text);
            if (cook_session_mark((uint32_t)t, (uint8_t)kind,
                                  (uint8_t)probe, text) != COOK_STORE_OK) {
                return app_api_error(out, 500, "storage_error",
                                     "mark append failed");
            }
            app_api_out_begin(out, 200, "application/json");
            app_api_emit_fmt(out,
                             "{\"t\":%ld,\"kind\":%ld,\"probe\":%ld,"
                             "\"text\":",
                             t, kind, probe);
            app_api_emit_json_str(out, text);
            app_api_emit_str(out, "}");
            return;
        }
    }
    app_api_error(out, 404, "not_found", "no such route");
}
