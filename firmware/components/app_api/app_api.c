/* app_api — esp_http_server glue over the host-tested core (F9 device
 * half). Adapts requests into app_api_req_t, sinks chunks out through
 * httpd_resp_send_chunk, wires the WebSocket registry to httpd_ws, and
 * supplies the true-device ops (heap, uptime, coredump, www mount). */
#include "app_api.h"

#include <stdlib.h>
#include <string.h>

#include "app_api_core.h"
#include "app_api_ws.h"
#include "app_net.h"
#include "app_time_core.h"
#include "bridge_event.h"
#include "cook_store.h"
#include "esp_core_dump.h"
#include "esp_heap_caps.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

static const char *TAG = "app_api";

static httpd_handle_t s_server;

static uint64_t uptime_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

/* ── ops ───────────────────────────────────────────────────────────────── */

static const char *reset_reason_name(void) {
    switch (esp_reset_reason()) {
        case ESP_RST_POWERON:
            return "poweron";
        case ESP_RST_SW:
            return "sw";
        case ESP_RST_PANIC:
            return "panic";
        case ESP_RST_WDT:
        case ESP_RST_INT_WDT:
        case ESP_RST_TASK_WDT:
            return "wdt";
        case ESP_RST_BROWNOUT:
            return "brownout";
        default:
            return "other";
    }
}

static void ops_sysinfo(app_api_sysinfo_t *out) {
    memset(out, 0, sizeof *out);
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(out->id, sizeof out->id, "%02X%02X", mac[4], mac[5]);
    out->model = "heltec-v3";
    out->fw = "1.0.0";
    out->reset_reason = reset_reason_name();
    out->uptime_s = (uint32_t)(uptime_ms() / 1000u);
    out->free_heap = (uint32_t)esp_get_free_heap_size();
    out->min_free_heap = (uint32_t)esp_get_minimum_free_heap_size();
    size_t cd_addr = 0, cd_size = 0;
    out->coredump_available =
        esp_core_dump_image_get(&cd_addr, &cd_size) == ESP_OK;
    uint32_t total = 0, used = 0;
    if (cook_store_fs_info(&total, &used) == 0 && total > 0) {
        out->storage_total_b = total;
        out->storage_used_b = used;
        out->storage_free_pct =
            (uint8_t)(((uint64_t)(total - used) * 100u) / total);
    }
}

static void ops_net_status(app_api_net_snapshot_t *out) {
    app_net_status_t st;
    app_net_get_status(&st);
    memcpy(out->mode, st.mode, sizeof out->mode);
    memcpy(out->state, st.state, sizeof out->state);
    memcpy(out->ssid, st.ssid, sizeof out->ssid);
    out->rssi = st.rssi;
    memcpy(out->ip, st.ip, sizeof out->ip);
    memcpy(out->host, st.host, sizeof out->host);
    out->ap_clients = st.ap_clients;
}

static size_t ops_coredump_size(void) {
    size_t addr = 0, size = 0;
    return esp_core_dump_image_get(&addr, &size) == ESP_OK ? size : 0;
}

static int ops_coredump_read(size_t off, void *buf, size_t n) {
    size_t addr = 0, size = 0;
    if (esp_core_dump_image_get(&addr, &size) != ESP_OK || off >= size) {
        return -1;
    }
    /* The coredump partition is memory-mapped readable via the flash
     * cache — a spi_flash read keeps it simple. */
    extern esp_err_t esp_flash_read(void *chip, void *buffer,
                                    uint32_t address, uint32_t length);
    if (esp_flash_read(NULL, buf, (uint32_t)(addr + off), (uint32_t)n) !=
        ESP_OK) {
        return -1;
    }
    return (int)n;
}

static bool ops_www_available(void) {
    /* D13: the partition stays unformatted until someone ships content;
     * format-on-fail is disabled by NOT mounting it at all in M2. */
    return false;
}

static const app_api_ops_t k_ops = {
    .sysinfo = ops_sysinfo,
    .net_status = ops_net_status,
    .net_request_config = app_net_request_config,
    .coredump_size = ops_coredump_size,
    .coredump_read = ops_coredump_read,
    .www_available = ops_www_available,
    .uptime_ms = uptime_ms,
};

/* ── request adaptation ────────────────────────────────────────────────── */

typedef struct {
    httpd_req_t *req;
    const app_api_out_t *out; /* status/ctype read at FIRST flush � they
                                 are set by out_begin before any emit */
    bool headers_sent;
} sink_ctx_t;

static int http_sink(void *ctx, const char *data, size_t len) {
    sink_ctx_t *c = ctx;
    if (!c->headers_sent) {
        char status_line[16];
        snprintf(status_line, sizeof status_line, "%d", c->out->status);
        (void)httpd_resp_set_status(c->req, status_line);
        if (c->out->content_type) {
            (void)httpd_resp_set_type(c->req, c->out->content_type);
        }
        (void)httpd_resp_set_hdr(c->req, "Access-Control-Allow-Origin", "*");
        c->headers_sent = true;
    }
    return httpd_resp_send_chunk(c->req, data, (ssize_t)len) == ESP_OK ? 0
                                                                       : -1;
}

static esp_err_t common_handler(httpd_req_t *req) {
    app_net_note_activity(); /* feeds the F8.2 switch-back guard */

    app_api_req_t creq = {0};
    switch (req->method) {
        case HTTP_GET:
            creq.method = "GET";
            break;
        case HTTP_POST:
            creq.method = "POST";
            break;
        case HTTP_PATCH:
            creq.method = "PATCH";
            break;
        case HTTP_DELETE:
            creq.method = "DELETE";
            break;
        default:
            creq.method = "GET";
    }

    static char path[256];
    /* Truncation of an oversized URI is fine: it 404s. */
    memset(path, 0, sizeof path);
    strncat(path, req->uri, sizeof path - 1);
    char *q = strchr(path, '?');
    if (q) {
        *q++ = '\0';
        while (q && *q && creq.query_count < APP_API_MAX_QUERY) {
            char *amp = strchr(q, '&');
            if (amp) {
                *amp = '\0';
            }
            char *eq = strchr(q, '=');
            if (eq) {
                *eq = '\0';
                snprintf(creq.query[creq.query_count].key,
                         sizeof creq.query[0].key, "%s", q);
                snprintf(creq.query[creq.query_count].value,
                         sizeof creq.query[0].value, "%s", eq + 1);
                creq.query_count++;
            }
            q = amp ? amp + 1 : NULL;
        }
    }
    creq.path = path;

    static char body[APP_API_MAX_BODY + 1];
    if (req->content_len > 0) {
        if (req->content_len > APP_API_MAX_BODY) {
            httpd_resp_set_status(req, "413");
            httpd_resp_set_type(req, "application/json");
            httpd_resp_sendstr(
                req, "{\"error\":{\"code\":\"body_too_large\",\"message\":"
                     "\"8 KB request cap\",\"detail\":null}}");
            return ESP_OK;
        }
        size_t got = 0;
        while (got < (size_t)req->content_len) {
            const int n = httpd_req_recv(req, body + got,
                                         (size_t)req->content_len - got);
            if (n <= 0) {
                return ESP_FAIL;
            }
            got += (size_t)n;
        }
        body[got] = '\0';
        creq.body = body;
        creq.body_len = got;
    }

    static char auth[64];
    if (httpd_req_get_hdr_value_str(req, "Authorization", auth,
                                    sizeof auth) == ESP_OK &&
        strncmp(auth, "Bearer ", 7) == 0) {
        creq.bearer = auth + 7;
    }

    app_api_out_t out;
    sink_ctx_t sc = {.req = req};
    app_api_out_init(&out, http_sink, &sc);
    sc.out = &out;
    (void)app_api_handle(&creq, &out);
    (void)app_api_out_finish(&out);
    if (!sc.headers_sent) { /* empty body (204): still send headers */
        (void)http_sink(&sc, "", 0);
    }
    return httpd_resp_send_chunk(req, NULL, 0);
}

/* ── WebSocket (F9.9 glue) ─────────────────────────────────────────────── */

typedef struct {
    int slot;
    int fd;
    bool used;
} ws_conn_t;

static ws_conn_t s_ws_conns[APP_API_WS_MAX_CLIENTS];

static void ws_send_text(int fd, const char *text, size_t len) {
    httpd_ws_frame_t frame = {
        .final = true,
        .type = HTTPD_WS_TYPE_TEXT,
        .payload = (uint8_t *)text,
        .len = len,
    };
    const esp_err_t err = httpd_ws_send_frame_async(s_server, fd, &frame);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "ws async send to fd %d failed: %s", fd,
                 esp_err_to_name(err));
    }
}

/* In-handler send: the documented path while `req` exists. */
static void ws_send_text_req(httpd_req_t *req, const char *text,
                             size_t len) {
    httpd_ws_frame_t frame = {
        .final = true,
        .type = HTTPD_WS_TYPE_TEXT,
        .payload = (uint8_t *)text,
        .len = len,
    };
    const esp_err_t err = httpd_ws_send_frame(req, &frame);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "ws send failed: %s", esp_err_to_name(err));
    }
}

typedef struct {
    char buf[512];
    size_t len;
} frame_buf_t;

static int frame_sink(void *ctx, const char *data, size_t len) {
    frame_buf_t *f = ctx;
    if (f->len + len < sizeof f->buf) {
        memcpy(f->buf + f->len, data, len);
        f->len += len;
    }
    return 0;
}

static void ws_broadcast(uint32_t topic_bit_mask,
                         void (*build)(app_api_out_t *out, void *arg),
                         void *arg) {
    /* Runs ONLY on the ws_push task (single consumer): the frame buffer
     * lives in static storage, not on anyone's stack. */
    static frame_buf_t fb;
    fb.len = 0;
    app_api_out_t out;
    app_api_out_init(&out, frame_sink, &fb);
    build(&out, arg);
    (void)app_api_out_finish(&out);
    for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
        if (s_ws_conns[i].used &&
            (app_api_ws_topics(s_ws_conns[i].slot) & topic_bit_mask)) {
            ws_send_text(s_ws_conns[i].fd, fb.buf, fb.len);
        }
    }
}

/* ── The ws_push task (03 §3.2 rule 2, tasks.h) ─────────────────────────
 * Event handlers run on the shared event-loop task and may not build
 * frames there — the first board sitting proved it the hard way (sys_evt
 * stack overflow, then TLS corruption crashing inside lwip). Handlers
 * copy the POD payload onto this queue and return; serialization and
 * fan-out happen HERE. */

typedef struct {
    uint8_t kind; /* 0 sample, 1 session */
    union {
        bridge_evt_sample_t sample;
        bridge_evt_session_t session;
    } u;
} push_msg_t;

static QueueHandle_t s_push_queue;

static void build_sample_frame(app_api_out_t *out, void *arg) {
    const bridge_evt_sample_t *s = arg;
    uint64_t unix_ms = 0;
    const bool have = app_time_core_now(uptime_ms(), &unix_ms);
    app_api_ws_sample(out, s, have, unix_ms);
}

static void build_session_frame(app_api_out_t *out, void *arg) {
    const bridge_evt_session_t *e = arg;
    app_api_ws_session(out,
                       e->action == BRIDGE_SESSION_STARTED ? "started"
                                                           : "ended",
                       e->session_id, NULL);
}

static void ws_push_task(void *arg) {
    (void)arg;
    push_msg_t msg;
    while (true) {
        if (xQueueReceive(s_push_queue, &msg, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        if (msg.kind == 0) {
            ws_broadcast(WS_TOPIC_SAMPLE, build_sample_frame, &msg.u.sample);
        } else {
            ws_broadcast(WS_TOPIC_SESSION, build_session_frame,
                         &msg.u.session);
        }
    }
}

static void on_sample_evt(void *arg, esp_event_base_t base, int32_t id,
                          void *data) {
    (void)arg;
    (void)base;
    (void)id;
    if (app_api_ws_count() == 0) {
        return; /* nobody listening: zero cost on the event loop */
    }
    push_msg_t msg = {.kind = 0};
    memcpy(&msg.u.sample, data, sizeof msg.u.sample);
    (void)xQueueSend(s_push_queue, &msg, 0);
}

static void on_session_evt(void *arg, esp_event_base_t base, int32_t id,
                           void *data) {
    (void)arg;
    (void)base;
    (void)id;
    if (app_api_ws_count() == 0) {
        return;
    }
    push_msg_t msg = {.kind = 1};
    memcpy(&msg.u.session, data, sizeof msg.u.session);
    (void)xQueueSend(s_push_queue, &msg, 0);
}

/* The open path. Board-found (M2 sitting): IDF v6 NEVER invokes the ws
 * URI handler on the handshake GET — it completes the handshake and
 * returns ("do not call the uri->handler", httpd_uri.c). This runs as
 * the post-handshake callback instead, where `req` is live and the 101
 * is already on the wire. */
static esp_err_t ws_open_cb(httpd_req_t *req) {
    {
        /* Enforce the cap by closing 1013 if the registry is full (the
         * F9.9 spike resolution). */
        const int slot = app_api_ws_add(uptime_ms());
        const int fd = httpd_req_to_sockfd(req);
        if (slot < 0) {
            httpd_ws_frame_t close_frame = {
                .final = true,
                .type = HTTPD_WS_TYPE_CLOSE,
                .payload = (uint8_t[]){0x03, 0xF5}, /* 1013 */
                .len = 2,
            };
            (void)httpd_ws_send_frame(req, &close_frame);
            return ESP_FAIL;
        }
        for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
            if (!s_ws_conns[i].used) {
                s_ws_conns[i] = (ws_conn_t){.slot = slot, .fd = fd,
                                            .used = true};
                break;
            }
        }
        app_net_set_low_latency(true);

        /* hello, then the current sample, so the client has state. */
        frame_buf_t fb = {0};
        app_api_out_t out;
        app_api_out_init(&out, frame_sink, &fb);
        uint64_t now_unix = 0;
        const bool have = app_time_core_now(uptime_ms(), &now_unix);
        app_api_ws_hello(&out, "1.0.0", have, now_unix);
        (void)app_api_out_finish(&out);
        ws_send_text_req(req, fb.buf, fb.len);

        const cook_ring_sample_t *newest = cook_ring_get(0);
        if (newest) {
            bridge_evt_sample_t s = {0};
            s.t_rel_s = newest->t;
            memcpy(s.temp_f10, newest->temp, sizeof s.temp_f10);
            s.flags = newest->flags;
            s.rssi = newest->rssi;
            fb.len = 0;
            app_api_out_init(&out, frame_sink, &fb);
            build_sample_frame(&out, &s);
            (void)app_api_out_finish(&out);
            ws_send_text_req(req, fb.buf, fb.len);
        }
        return ESP_OK;
    }
}

/* Data frames only — the open path lives in ws_open_cb (IDF v6 never
 * calls this for the handshake GET). */
static esp_err_t ws_handler(httpd_req_t *req) {
    /* Incoming frame. */
    httpd_ws_frame_t frame = {0};
    if (httpd_ws_recv_frame(req, &frame, 0) != ESP_OK) {
        return ESP_FAIL;
    }
    static uint8_t payload[256];
    if (frame.len >= sizeof payload) {
        return ESP_OK;
    }
    frame.payload = payload;
    if (httpd_ws_recv_frame(req, &frame, frame.len) != ESP_OK) {
        return ESP_FAIL;
    }
    payload[frame.len] = '\0';

    const int fd = httpd_req_to_sockfd(req);
    int slot = -1;
    for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
        if (s_ws_conns[i].used && s_ws_conns[i].fd == fd) {
            slot = s_ws_conns[i].slot;
            break;
        }
    }
    if (frame.type == HTTPD_WS_TYPE_CLOSE) {
        for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
            if (s_ws_conns[i].used && s_ws_conns[i].fd == fd) {
                app_api_ws_remove(s_ws_conns[i].slot);
                s_ws_conns[i].used = false;
            }
        }
        if (app_api_ws_count() == 0) {
            app_net_set_low_latency(false);
        }
        return ESP_OK;
    }
    if (frame.type == HTTPD_WS_TYPE_TEXT && slot >= 0) {
        char reply[64];
        int acked = -1;
        (void)app_api_ws_on_message(slot, (const char *)payload, reply,
                                    sizeof reply, &acked);
        app_api_ws_pong(slot);
        if (reply[0] != '\0') {
            ws_send_text(fd, reply, strlen(reply));
        }
        /* ack_alarm routing lands with the alarm engine (M5 F13). */
    }
    return ESP_OK;
}

/* ── registration ──────────────────────────────────────────────────────── */

int app_api_init(void) {
    if (app_api_core_init(&k_ops) != 0) {
        return -1;
    }
    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.server_port = 80;
    cfg.max_open_sockets = 7; /* the 06 §6.1 cap, stated and enforced */
    cfg.uri_match_fn = httpd_uri_match_wildcard;
    cfg.lru_purge_enable = true;
    /* Board-found (M2 sitting): the default 4 KB drowns under the ≤2 KB
     * streaming chunk plus JSON scratch — the overflow trampled pthread
     * TLS and crashed inside lwip send. Watermarks land in F9.13. */
    cfg.stack_size = 8192;
    if (httpd_start(&s_server, &cfg) != ESP_OK) {
        return -1;
    }

    static const httpd_uri_t ws_uri = {
        .uri = "/api/v1/stream",
        .method = HTTP_GET,
        .handler = ws_handler, /* data frames only on IDF v6 */
        .is_websocket = true,
        .ws_post_handshake_cb = ws_open_cb, /* the real open path */
    };
    (void)httpd_register_uri_handler(s_server, &ws_uri);

    static const httpd_uri_t get_uri = {.uri = "/*",
                                        .method = HTTP_GET,
                                        .handler = common_handler};
    static const httpd_uri_t post_uri = {.uri = "/*",
                                         .method = HTTP_POST,
                                         .handler = common_handler};
    static const httpd_uri_t patch_uri = {.uri = "/*",
                                          .method = HTTP_PATCH,
                                          .handler = common_handler};
    static const httpd_uri_t delete_uri = {.uri = "/*",
                                           .method = HTTP_DELETE,
                                           .handler = common_handler};
    (void)httpd_register_uri_handler(s_server, &get_uri);
    (void)httpd_register_uri_handler(s_server, &post_uri);
    (void)httpd_register_uri_handler(s_server, &patch_uri);
    (void)httpd_register_uri_handler(s_server, &delete_uri);

    /* The fan-out task (tasks.h ws_push row) MUST exist before the
     * handlers that feed it are registered. */
    s_push_queue = xQueueCreate(8, sizeof(push_msg_t));
    /* 4096 per tasks.h: the lwip send path runs on this stack. */
    if (!s_push_queue ||
        xTaskCreatePinnedToCore(ws_push_task, "ws_push", 4096, NULL, 4,
                                NULL, 0) != pdPASS) {
        return -1;
    }

    (void)bridge_event_handler_register(BRIDGE_EVT_SAMPLE, on_sample_evt,
                                        NULL, "api_ws_sample");
    (void)bridge_event_handler_register(BRIDGE_EVT_SESSION, on_session_evt,
                                        NULL, "api_ws_session");

    ESP_LOGI(TAG, "httpd up on :80 (max_open_sockets=7, ws cap=%d)",
             APP_API_WS_MAX_CLIENTS);
    return 0;
}
