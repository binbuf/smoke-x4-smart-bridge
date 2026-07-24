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
} app_api_ops_t;

int app_api_core_init(const app_api_ops_t *ops);

/* Dispatch one request into `out`. Always produces a complete response
 * (status + body); unknown API routes get the 404 envelope, non-API GETs
 * the built-in page or captive answers. Returns 0. */
int app_api_handle(const app_api_req_t *req, app_api_out_t *out);

/* True when the request may skip the bearer gate (captive probes and the
 * built-in page are never gated). Exposed for tests. */
bool app_api_path_is_open(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* APP_API_CORE_H */
