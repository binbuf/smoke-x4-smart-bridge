/* cook_store_core — session files, recovery, retention, marks, and the
 * streaming read path (design 04; tasks F5.1–F5.5, F5.7–F5.10).
 *
 * Pure C11 over cook_vfs and app_config_store; the whole write/recover/read
 * machinery runs in the host suite. The device binding only mounts LittleFS
 * and supplies the VFS.
 */
#ifndef COOK_STORE_CORE_H
#define COOK_STORE_CORE_H

#include <stdbool.h>
#include <stdint.h>

#include "cook_vfs.h"
#include "record_gen.h"

#ifdef __cplusplus
extern "C" {
#endif

#define COOK_STORE_OK 0
#define COOK_STORE_ERR -1
#define COOK_STORE_ERR_NOT_FOUND -2
#define COOK_STORE_ERR_FULL -3
#define COOK_STORE_ERR_STATE -4 /* e.g. append with no open session */

#define COOK_STORE_MAX_SESSIONS 64
#define COOK_STORE_DIR "/cooks"

/* fsync every Nth append (2 min at the 30 s cadence); everything else
 * rides on the immediate-flush triggers (04 §4.5). */
#define COOK_STORE_FSYNC_INTERVAL 4

typedef enum {
    COOK_STORE_EVT_SESSION_STARTED = 0,
    COOK_STORE_EVT_SESSION_ENDED,
    COOK_STORE_EVT_SESSION_RESUMED, /* power-cut recovery (04 §4.5) */
    COOK_STORE_EVT_STORAGE_FULL,
    COOK_STORE_EVT_SESSION_PURGED, /* retention deleted a session */
} cook_store_evt_t;

typedef void (*cook_store_evt_cb_t)(cook_store_evt_t evt, uint32_t session_id,
                                    void *ctx);

/* One in-RAM index entry per session on disk (04 §4.3: no index file — this
 * is rebuilt from headers at boot). */
typedef struct {
    uint32_t session_id;
    uint64_t started_unix_ms;
    uint64_t ended_unix_ms;
    uint32_t sample_count;
    uint8_t num_probes;
    uint8_t flags; /* header flags: clock_valid/closed/pinned/... */
} cook_index_entry_t;

/* ── Lifecycle of the store ── */

/* Mount-time init: rebuilds the index by reading each .smk header (skipping
 * .bad files), then runs §4.5 recovery if session/active_id is set.
 * app_config_store must already be initialised. */
int cook_store_core_init(const cook_vfs_t *vfs, cook_store_evt_cb_t cb,
                         void *cb_ctx);

/* ── Index (F5.5) ── */

int cook_store_index_count(void);
const cook_index_entry_t *cook_store_index_get(int i); /* ordered by id */
const cook_index_entry_t *cook_store_index_find(uint32_t session_id);

/* ── Sessions (F5.2, F5.4 hooks, F5.7, F5.8) ── */

typedef struct {
    uint8_t num_probes;
    uint64_t started_unix_ms; /* 0 = clock not valid yet */
    uint32_t started_uptime_s;
    const char *name;         /* NULL = auto */
    const char *device_id;
} cook_session_params_t;

/* Allocates the next session id, writes the header, sets active_id. */
int cook_session_open(const cook_session_params_t *p);

bool cook_session_is_open(void);
uint32_t cook_session_active_id(void);
uint32_t cook_session_sample_count(void);

/* Appends one sample (CRC computed here). Applies the fsync cadence. */
int cook_session_append(uint32_t t, const int16_t temp[4], uint8_t flags,
                        int8_t rssi);

/* Immediate flush for the §4.5 triggers (alarm, net change, button, ...). */
int cook_session_flush(void);

/* Appends a mark to the sibling .mrk; text is truncated at 24 bytes on a
 * UTF-8 character boundary (F5.9). probe 0 = whole cook. */
int cook_session_mark(uint32_t t, uint8_t kind, uint8_t probe,
                      const char *text);

/* Finalises sample_count/mark_count, sets closed, clears active_id. */
int cook_session_close(uint64_t ended_unix_ms);

/* Back-patch for F6.2: sets started_unix_ms + clock_valid on the OPEN
 * session's header in place (one 256 B rewrite, no sample rewrite). */
int cook_session_set_clock(uint64_t started_unix_ms);

/* Pin/unpin a closed session (retention never deletes pinned). */
int cook_session_set_pinned(uint32_t session_id, bool pinned);

/* ── Retention (F5.8) — called internally; exposed for tests. ── */
int cook_retention_enforce(void);

/* ── Streaming read (F5.10) ── */

typedef enum {
    COOK_AGG_NONE = 0,
    COOK_AGG_MINMAX,
    COOK_AGG_MEAN,
} cook_agg_t;

typedef struct {
    uint32_t t0;      /* bucket start, seconds since session start */
    uint16_t n;       /* samples aggregated */
    int16_t vmin[4];  /* per probe; BRIDGE_TEMP_DETACHED when none valid */
    int16_t vmax[4];
    int16_t vmean[4];
} cook_bucket_t;

/* Return 0 to continue, non-zero to abort the stream. */
typedef int (*cook_rec_sink_t)(void *ctx, const bridge_sample_rec_t *rec);
typedef int (*cook_bucket_sink_t)(void *ctx, const cook_bucket_t *bucket);

/* Streams [from_t, to_t] (inclusive; 0..UINT32_MAX = whole session).
 * Fixed-width records make the range a binary-searched seek, not a scan.
 * agg == NONE uses rec_sink (with stride ≥ 1); otherwise bucket_sink.
 * Allocation-free; reads one record at a time. */
int cook_store_read(uint32_t session_id, uint32_t from_t, uint32_t to_t,
                    uint16_t stride, uint32_t bucket_s, cook_agg_t agg,
                    cook_rec_sink_t rec_sink, cook_bucket_sink_t bucket_sink,
                    void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* COOK_STORE_CORE_H */
