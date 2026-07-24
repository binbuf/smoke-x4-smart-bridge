/* app_api_core — the HTTP contract as a pure core (F9.1, F9.3–F9.8,
 * F9.10, F8.7, F4.5, F4.6; design 06).
 *
 * Routing, parameter parsing, auth, and every handler run on the host:
 * the handlers read the same host-testable modules the firmware runs
 * (app_config_store, smoke_x_ctrl, cook_store, cook_ring, app_time_core,
 * app_net_core), and the few true-device facts arrive through ops. The
 * esp_http_server glue only adapts requests and sinks chunks.
 */
#ifndef APP_API_CORE_H
#define APP_API_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_api_emit.h"
#include "app_net_core.h"
#include "app_ota_core.h"

#ifdef __cplusplus
extern "C" {
#endif

#define APP_API_MAX_QUERY 8
#define APP_API_MAX_BODY 8192 /* 413 body_too_large beyond this */

typedef struct {
    char key[16];
    char value[80];
} app_api_query_t;

typedef struct {
    const char *method; /* "GET" | "POST" | "PATCH" | "DELETE" */
    const char *path;   /* no query string */
    app_api_query_t query[APP_API_MAX_QUERY];
    int query_count;
    const char *body; /* NUL-terminated JSON or NULL */
    size_t body_len;
    const char *bearer; /* Authorization bearer token or NULL */
} app_api_req_t;

/* Device facts the pure modules cannot know. */
typedef struct {
    char id[8];       /* "A4F2" */
    const char *model;
    const char *fw;
    const char *reset_reason;
    uint32_t uptime_s;
    uint32_t free_heap;
    uint32_t min_free_heap;
    bool coredump_available;
    uint32_t storage_total_b;
    uint32_t storage_used_b;
    uint8_t storage_free_pct;
} app_api_sysinfo_t;

typedef struct {
    char mode[4];
    char state[12];
    char ssid[33];
    int8_t rssi;
    char ip[16];
    char host[24];
    int ap_clients;
} app_api_net_snapshot_t;

typedef struct {
    bool advertising;
    uint8_t connections;
    uint8_t bonded;
} app_api_ble_snapshot_t;

/* V3.1 — one row of GET /api/v1/debug/tasks.
 *
 * 01 §1.4 asks for stack watermarks "logged once a minute at debug
 * level"; that is right for a bench session and useless for a 24 h
 * unattended soak, which cannot hold a serial cable. The soak reads them
 * over HTTP, so the evidence becomes a committed artifact instead of a
 * log line nobody captured. */
#define APP_API_MAX_TASKS 24

typedef struct {
    char name[16];
    uint32_t stack_b;      /* declared, 0 when the IDF created the task */
    uint32_t high_water_b; /* the deepest it has ever been */
    uint32_t margin_b;     /* computed HERE: it is what the threshold is
                              stated against, and a reader should not
                              have to subtract */
    uint8_t priority;
    int8_t core; /* -1 = unpinned */
} app_api_task_row_t;

typedef struct {
    app_api_task_row_t rows[APP_API_MAX_TASKS];
    int count;
    uint32_t free_heap;
    uint32_t min_free_heap;
    /* R2's actual failure mode. Total free heap CANNOT see fragmentation:
     * 80 KB free in 2 KB pieces cannot allocate a TLS buffer, and every
     * heap number still looks fine. */
    uint32_t largest_free_block;
} app_api_tasks_snapshot_t;

/* F14.8 — what /status.ota reports. Filled by the glue from app_ota. */
typedef struct {
    char slot[12];    /* "ota_0" */
    bool pending_verify;
    char gate[16];    /* not_applicable | waiting | passed | failed */
    char failed[48];  /* "" or "storage,net" */
} app_api_ota_snapshot_t;

typedef struct {
    void (*sysinfo)(app_api_sysinfo_t *out);
    void (*net_status)(app_api_net_snapshot_t *out);
    /* F10: null on a build without BLE, which /status reports as zeros
     * rather than pretending. */
    void (*ble_status)(app_api_ble_snapshot_t *out);
    /* F8.4 deferred apply — reply first, this fires after. */
    int (*net_request_config)(const app_net_pending_cfg_t *cfg);
    /* Coredump partition access (F4.6): size 0 = none stored. */
    size_t (*coredump_size)(void);
    int (*coredump_read)(size_t off, void *buf, size_t n);
    /* F9.10: true only if www mounted AND index.html.gz exists. */
    bool (*www_available)(void);
    /* Current uptime for /live windows and watchdog-ish fields. */
    uint64_t (*uptime_ms)(void);
    /* F11b.11 — the OLED's own I²C traffic. NULL on a build with no
     * panel, which /status reports as zeros rather than pretending.
     * This is V3a.1's deferred OLED-error row made readable without a
     * serial cable: M3 could not measure it because the panel was dark
     * except while a passkey was showing. */
    void (*display_counts)(uint32_t *ok, uint32_t *err);
    /* F14.8 — the running slot and the 03 §3.7 gate. NULL on a build
     * without app_ota, which /status reports as `not_applicable` rather
     * than as a cheerful `passed`: the /status.ble lesson, applied before
     * the board can teach it again. */
    void (*ota_status)(app_api_ota_snapshot_t *out);
    /* V3.1 — FreeRTOS task watermarks + heap fragmentation. NULL on a
     * build without them, which reports an empty list. */
    void (*tasks_snapshot)(app_api_tasks_snapshot_t *out);
} app_api_ops_t;

int app_api_core_init(const app_api_ops_t *ops);

/* Dispatch one request into `out`. Always produces a complete response
 * (status + body); unknown API routes get the 404 envelope, non-API GETs
 * the built-in page or captive answers. Returns 0. */
int app_api_handle(const app_api_req_t *req, app_api_out_t *out);

/* True when the request may skip the bearer gate (captive probes and the
 * built-in page are never gated). Exposed for tests. */
bool app_api_path_is_open(const char *path);

/* ── F14.5: POST /api/v1/ota ───────────────────────────────────────────
 *
 * THE ONE ROUTE EXEMPT FROM THE 8 KB BODY CAP. Every other request is
 * buffered whole by the glue and dispatched through app_api_handle(); a
 * 1.3 MB image must be intercepted before that and streamed in ≤ 4 KB
 * reads straight into flash. Nothing is ever materialised — the same
 * structural rule F9 gave responses, now on the request side.
 *
 * The decisions still live here rather than in the glue: auth, admission
 * (06 §6.2's 409/503/400), the read loop, progress throttling, and both
 * reply shapes. The glue supplies two functions.
 */
bool app_api_path_is_ota(const char *path);

/* >0 = bytes read, 0 = end of body, <0 = transport error. */
typedef int (*app_api_body_read_fn)(void *ctx, void *buf, size_t cap);
/* One WebSocket `ota` frame's worth. Called from the request task, so the
 * glue must ENQUEUE rather than fan out (03 §3.2). */
typedef void (*app_api_ota_progress_fn)(void *ctx, app_ota_phase_t phase,
                                        int pct);

typedef struct {
    app_api_body_read_fn read;
    void *read_ctx;
    size_t content_len;
    bool session_active;
    const app_ota_ops_t *flash;
    app_ota_session_t *session;
    app_api_ota_progress_fn progress;
    void *progress_ctx;
} app_api_ota_ctx_t;

/* Always produces a complete response. Returns 0. */
int app_api_handle_ota(const app_api_req_t *req, app_api_out_t *out,
                       const app_api_ota_ctx_t *ota);

#ifdef __cplusplus
}
#endif

#endif /* APP_API_CORE_H */
