/* cook_store_core — session files, recovery, retention, marks, streaming
 * reads (design 04). Pure C11 over cook_vfs + app_config_store. */
#include "cook_store_core.h"

#include <stdio.h>
#include <string.h>

#include "app_config_store.h"

#define MAX_REC_LEN 64u /* future-version records may grow; cap sanity */

static const cook_vfs_t *s_vfs;
static cook_store_evt_cb_t s_cb;
static void *s_cb_ctx;

static cook_index_entry_t s_index[COOK_STORE_MAX_SESSIONS];
static int s_index_count;

static struct {
    bool open;
    int fd;
    bridge_session_header_t hdr;
    uint32_t sample_count;
    uint32_t mark_count;
    uint32_t appends_since_sync;
    bool storage_full;
} s_sess;

static void emit_evt(cook_store_evt_t evt, uint32_t id) {
    if (s_cb) {
        s_cb(evt, id, s_cb_ctx);
    }
}

static void smk_path(char *buf, size_t n, uint32_t id) {
    snprintf(buf, n, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
}

static void mrk_path(char *buf, size_t n, uint32_t id) {
    snprintf(buf, n, COOK_STORE_DIR "/%08X.mrk", (unsigned)id);
}

/* ── Index ─────────────────────────────────────────────────────────────── */

static void index_upsert(const cook_index_entry_t *e) {
    for (int i = 0; i < s_index_count; i++) {
        if (s_index[i].session_id == e->session_id) {
            s_index[i] = *e;
            return;
        }
    }
    if (s_index_count >= COOK_STORE_MAX_SESSIONS) {
        return;
    }
    /* Keep ordered by id (ids are monotonic; lists may not be). */
    int pos = s_index_count;
    while (pos > 0 && s_index[pos - 1].session_id > e->session_id) {
        s_index[pos] = s_index[pos - 1];
        pos--;
    }
    s_index[pos] = *e;
    s_index_count++;
}

static void index_remove(uint32_t id) {
    for (int i = 0; i < s_index_count; i++) {
        if (s_index[i].session_id == id) {
            memmove(&s_index[i], &s_index[i + 1],
                    (size_t)(s_index_count - i - 1) * sizeof s_index[0]);
            s_index_count--;
            return;
        }
    }
}

static void index_entry_from_header(cook_index_entry_t *e,
                                    const bridge_session_header_t *h,
                                    uint32_t derived_count) {
    e->session_id = h->session_id;
    e->started_unix_ms = h->started_unix_ms;
    e->ended_unix_ms = h->ended_unix_ms;
    e->sample_count = bridge_session_header_closed(h->flags)
                          ? h->sample_count
                          : derived_count;
    e->num_probes = h->num_probes;
    e->flags = h->flags;
}

int cook_store_index_count(void) { return s_index_count; }

const cook_index_entry_t *cook_store_index_get(int i) {
    return (i >= 0 && i < s_index_count) ? &s_index[i] : NULL;
}

const cook_index_entry_t *cook_store_index_find(uint32_t session_id) {
    for (int i = 0; i < s_index_count; i++) {
        if (s_index[i].session_id == session_id) {
            return &s_index[i];
        }
    }
    return NULL;
}

/* ── Header I/O ────────────────────────────────────────────────────────── */

static int header_write(int fd, const bridge_session_header_t *h) {
    uint8_t buf[BRIDGE_SESSION_HEADER_SIZE];
    bridge_session_header_encode(h, buf);
    if (s_vfs->seek(s_vfs->ctx, fd, 0, COOK_VFS_SET) != 0) {
        return COOK_STORE_ERR;
    }
    if (s_vfs->write(s_vfs->ctx, fd, buf, sizeof buf) != (long)sizeof buf) {
        return COOK_STORE_ERR;
    }
    return COOK_STORE_OK;
}

/* true = decoded AND crc+magic valid */
static bool header_read(int fd, bridge_session_header_t *h) {
    uint8_t buf[BRIDGE_SESSION_HEADER_SIZE];
    if (s_vfs->seek(s_vfs->ctx, fd, 0, COOK_VFS_SET) != 0) {
        return false;
    }
    if (s_vfs->read(s_vfs->ctx, fd, buf, sizeof buf) != (long)sizeof buf) {
        return false;
    }
    if (!bridge_session_header_decode(buf, h)) {
        return false;
    }
    return bridge_session_header_magic_ok(h);
}

/* ── Record I/O ────────────────────────────────────────────────────────── */

/* Reads record `idx`. Strides by the HEADER's rec_len (04 §4.10) so a
 * longer future record stays readable; only the v1 prefix is decoded, and
 * the CRC is only checkable on v1 layouts. */
static int read_rec_at(int fd, const bridge_session_header_t *h, uint32_t idx,
                       bridge_sample_rec_t *rec, bool *crc_ok) {
    uint8_t buf[MAX_REC_LEN];
    const long off = (long)h->hdr_len + (long)idx * h->rec_len;
    if (s_vfs->seek(s_vfs->ctx, fd, off, COOK_VFS_SET) != off) {
        return COOK_STORE_ERR;
    }
    if (s_vfs->read(s_vfs->ctx, fd, buf, h->rec_len) != (long)h->rec_len) {
        return COOK_STORE_ERR;
    }
    const bool ok = bridge_sample_rec_decode(buf, rec);
    *crc_ok = (h->version == BRIDGE_RECORD_VERSION) ? ok : true;
    return COOK_STORE_OK;
}

/* ── Retention (F5.8) ──────────────────────────────────────────────────── */

static int retention_delete_oldest(void) {
    /* Oldest = smallest id that is closed and unpinned; never the active. */
    for (int i = 0; i < s_index_count; i++) {
        const cook_index_entry_t *e = &s_index[i];
        if (s_sess.open && e->session_id == s_sess.hdr.session_id) {
            continue;
        }
        if (!bridge_session_header_closed(e->flags) ||
            bridge_session_header_pinned(e->flags)) {
            continue;
        }
        char path[48];
        const uint32_t id = e->session_id;
        smk_path(path, sizeof path, id);
        s_vfs->remove(s_vfs->ctx, path);
        mrk_path(path, sizeof path, id);
        s_vfs->remove(s_vfs->ctx, path); /* absent is fine */
        index_remove(id);
        emit_evt(COOK_STORE_EVT_SESSION_PURGED, id);
        return COOK_STORE_OK;
    }
    return COOK_STORE_ERR_NOT_FOUND; /* nothing deletable */
}

int cook_retention_enforce(void) {
    uint8_t max_sessions = 64, min_free = 10;
    (void)app_config_store_get_u8(APP_CONFIG_DEV_RETENTION_MAX_SESSIONS,
                                  &max_sessions);
    (void)app_config_store_get_u8(APP_CONFIG_DEV_RETENTION_MIN_FREE_PCT,
                                  &min_free);
    while (s_index_count > (int)max_sessions ||
           s_vfs->free_pct(s_vfs->ctx) < (int)min_free) {
        if (retention_delete_oldest() != COOK_STORE_OK) {
            break; /* only pinned/active left: stop, don't thrash */
        }
    }
    return COOK_STORE_OK;
}

/* ── Session write path (F5.2, F5.7) ───────────────────────────────────── */

bool cook_session_is_open(void) { return s_sess.open; }

uint32_t cook_session_active_id(void) {
    return s_sess.open ? s_sess.hdr.session_id : 0;
}

uint32_t cook_session_sample_count(void) { return s_sess.sample_count; }

bool cook_session_clock_valid(void) {
    return s_sess.open &&
           bridge_session_header_clock_valid(s_sess.hdr.flags);
}

uint32_t cook_session_started_uptime_s(void) {
    return s_sess.open ? s_sess.hdr.started_uptime_s : 0;
}

int cook_session_open(const cook_session_params_t *p) {
    if (!s_vfs || s_sess.open || !p) {
        return COOK_STORE_ERR_STATE;
    }
    uint32_t id = 1;
    (void)app_config_store_get_u32(APP_CONFIG_SESSION_NEXT_ID, &id);
    if (app_config_store_set_u32(APP_CONFIG_SESSION_NEXT_ID, id + 1) !=
        APP_CONFIG_OK) {
        return COOK_STORE_ERR;
    }

    memset(&s_sess, 0, sizeof s_sess);
    bridge_session_header_t *h = &s_sess.hdr;
    memcpy(h->magic, BRIDGE_SESSION_MAGIC, 4);
    h->version = BRIDGE_RECORD_VERSION;
    h->hdr_len = BRIDGE_SESSION_HEADER_SIZE;
    h->rec_len = BRIDGE_SAMPLE_REC_SIZE;
    h->num_probes = p->num_probes;
    h->session_id = id;
    h->started_unix_ms = p->started_unix_ms;
    h->started_uptime_s = p->started_uptime_s;
    h->sample_period_s = 30;
    if (p->started_unix_ms != 0) {
        h->flags |= BRIDGE_SESSION_HEADER_FLAGS_CLOCK_VALID;
    }
    if (p->device_id) {
        snprintf(h->device_id, sizeof h->device_id, "%s", p->device_id);
    }
    if (p->name) {
        snprintf(h->name, sizeof h->name, "%s", p->name);
    } else {
        snprintf(h->name, sizeof h->name, "Cook #%u", (unsigned)id);
    }

    char path[48];
    smk_path(path, sizeof path, id);
    const int fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_CREATE);
    if (fd < 0) {
        return COOK_STORE_ERR;
    }
    if (header_write(fd, h) != COOK_STORE_OK ||
        s_vfs->fsync(s_vfs->ctx, fd) != 0) {
        s_vfs->close(s_vfs->ctx, fd);
        return COOK_STORE_ERR;
    }
    s_sess.fd = fd;
    s_sess.open = true;

    (void)app_config_store_set_u32(APP_CONFIG_SESSION_ACTIVE_ID, id);
    cook_index_entry_t e;
    index_entry_from_header(&e, h, 0);
    index_upsert(&e);
    emit_evt(COOK_STORE_EVT_SESSION_STARTED, id);
    cook_retention_enforce();
    return COOK_STORE_OK;
}

int cook_session_append(uint32_t t, const int16_t temp[4], uint8_t flags,
                        int8_t rssi) {
    if (!s_sess.open) {
        return COOK_STORE_ERR_STATE;
    }
    if (s_sess.storage_full) {
        return COOK_STORE_ERR_FULL;
    }
    uint8_t min_free = 10;
    (void)app_config_store_get_u8(APP_CONFIG_DEV_RETENTION_MIN_FREE_PCT,
                                  &min_free);
    if (s_vfs->free_pct(s_vfs->ctx) < (int)min_free) {
        cook_retention_enforce();
        if (s_vfs->free_pct(s_vfs->ctx) <= 1) {
            /* Only the active session (and pinned) left, partition full:
             * stop loudly rather than corrupting (04 §4.7). */
            s_sess.storage_full = true;
            emit_evt(COOK_STORE_EVT_STORAGE_FULL, s_sess.hdr.session_id);
            return COOK_STORE_ERR_FULL;
        }
    }

    bridge_sample_rec_t rec = {.t = t, .flags = flags, .rssi = rssi};
    memcpy(rec.temp, temp, sizeof rec.temp);
    uint8_t buf[BRIDGE_SAMPLE_REC_SIZE];
    bridge_sample_rec_encode(&rec, buf);

    if (s_vfs->seek(s_vfs->ctx, s_sess.fd, 0, COOK_VFS_END) < 0) {
        return COOK_STORE_ERR;
    }
    if (s_vfs->write(s_vfs->ctx, s_sess.fd, buf, sizeof buf) !=
        (long)sizeof buf) {
        return COOK_STORE_ERR;
    }
    s_sess.sample_count++;
    s_sess.appends_since_sync++;
    if (s_sess.appends_since_sync >= COOK_STORE_FSYNC_INTERVAL) {
        s_sess.appends_since_sync = 0;
        if (s_vfs->fsync(s_vfs->ctx, s_sess.fd) != 0) {
            return COOK_STORE_ERR;
        }
    }
    return COOK_STORE_OK;
}

int cook_session_flush(void) {
    if (!s_sess.open) {
        return COOK_STORE_ERR_STATE;
    }
    s_sess.appends_since_sync = 0;
    return s_vfs->fsync(s_vfs->ctx, s_sess.fd) == 0 ? COOK_STORE_OK
                                                    : COOK_STORE_ERR;
}

/* Truncate to a UTF-8 boundary: never leave a dangling lead/continuation
 * byte inside the 24-byte field (F5.9). */
static void utf8_copy_truncate(char *dst, size_t cap, const char *src) {
    size_t n = strlen(src);
    if (n > cap) {
        n = cap;
        while (n > 0 && ((unsigned char)src[n] & 0xC0u) == 0x80u) {
            n--; /* don't split a multibyte sequence */
        }
    }
    memset(dst, 0, cap);
    memcpy(dst, src, n);
}

int cook_session_mark(uint32_t t, uint8_t kind, uint8_t probe,
                      const char *text) {
    if (!s_sess.open) {
        return COOK_STORE_ERR_STATE;
    }
    bridge_mark_rec_t m = {.t = t, .kind = kind, .probe = probe};
    utf8_copy_truncate(m.text, sizeof m.text, text ? text : "");
    uint8_t buf[BRIDGE_MARK_REC_SIZE];
    bridge_mark_rec_encode(&m, buf);

    char path[48];
    mrk_path(path, sizeof path, s_sess.hdr.session_id);
    int fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_RDWR);
    if (fd < 0) {
        fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_CREATE);
    }
    if (fd < 0) {
        return COOK_STORE_ERR;
    }
    int rc = COOK_STORE_ERR;
    if (s_vfs->seek(s_vfs->ctx, fd, 0, COOK_VFS_END) >= 0 &&
        s_vfs->write(s_vfs->ctx, fd, buf, sizeof buf) == (long)sizeof buf &&
        s_vfs->fsync(s_vfs->ctx, fd) == 0) {
        rc = COOK_STORE_OK;
        s_sess.mark_count++;
    }
    s_vfs->close(s_vfs->ctx, fd);
    return rc;
}

static int session_finalize(uint64_t ended_unix_ms) {
    bridge_session_header_t *h = &s_sess.hdr;
    h->ended_unix_ms = ended_unix_ms;
    h->sample_count = s_sess.sample_count;
    h->mark_count = s_sess.mark_count;
    h->flags |= BRIDGE_SESSION_HEADER_FLAGS_CLOSED;
    if (header_write(s_sess.fd, h) != COOK_STORE_OK ||
        s_vfs->fsync(s_vfs->ctx, s_sess.fd) != 0) {
        return COOK_STORE_ERR;
    }
    s_vfs->close(s_vfs->ctx, s_sess.fd);

    cook_index_entry_t e;
    index_entry_from_header(&e, h, s_sess.sample_count);
    index_upsert(&e);

    const uint32_t id = h->session_id;
    memset(&s_sess, 0, sizeof s_sess);
    (void)app_config_store_set_u32(APP_CONFIG_SESSION_ACTIVE_ID, 0);
    emit_evt(COOK_STORE_EVT_SESSION_ENDED, id);
    return COOK_STORE_OK;
}

int cook_session_close(uint64_t ended_unix_ms) {
    if (!s_sess.open) {
        return COOK_STORE_ERR_STATE;
    }
    return session_finalize(ended_unix_ms);
}

int cook_session_set_clock(uint64_t started_unix_ms) {
    if (!s_sess.open) {
        return COOK_STORE_ERR_STATE;
    }
    bridge_session_header_t *h = &s_sess.hdr;
    h->started_unix_ms = started_unix_ms;
    h->flags |= BRIDGE_SESSION_HEADER_FLAGS_CLOCK_VALID;
    /* One 256 B in-place block rewrite; sample data untouched (04 §4.4). */
    if (header_write(s_sess.fd, h) != COOK_STORE_OK) {
        return COOK_STORE_ERR;
    }
    cook_index_entry_t e;
    index_entry_from_header(&e, h, s_sess.sample_count);
    index_upsert(&e);
    return cook_session_flush();
}

int cook_session_set_pinned(uint32_t session_id, bool pinned) {
    if (s_sess.open && session_id == s_sess.hdr.session_id) {
        return COOK_STORE_ERR_STATE; /* the active session needs no pin */
    }
    char path[48];
    smk_path(path, sizeof path, session_id);
    const int fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_RDWR);
    if (fd < 0) {
        return COOK_STORE_ERR_NOT_FOUND;
    }
    bridge_session_header_t h;
    int rc = COOK_STORE_ERR;
    if (header_read(fd, &h)) {
        if (pinned) {
            h.flags |= BRIDGE_SESSION_HEADER_FLAGS_PINNED;
        } else {
            h.flags &= (uint8_t)~BRIDGE_SESSION_HEADER_FLAGS_PINNED;
        }
        if (header_write(fd, &h) == COOK_STORE_OK &&
            s_vfs->fsync(s_vfs->ctx, fd) == 0) {
            cook_index_entry_t e;
            index_entry_from_header(&e, &h, h.sample_count);
            index_upsert(&e);
            rc = COOK_STORE_OK;
        }
    }
    s_vfs->close(s_vfs->ctx, fd);
    return rc;
}

/* ── Recovery (F5.3, 04 §4.5) ──────────────────────────────────────────── */

static void recover_active(uint32_t id) {
    char path[48];
    smk_path(path, sizeof path, id);
    const int fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_RDWR);
    if (fd < 0) {
        (void)app_config_store_set_u32(APP_CONFIG_SESSION_ACTIVE_ID, 0);
        return;
    }

    bridge_session_header_t h;
    if (!header_read(fd, &h) || h.rec_len == 0 || h.rec_len > MAX_REC_LEN ||
        h.hdr_len < BRIDGE_SESSION_HEADER_SIZE) {
        /* Corrupt header: keep the bytes for post-mortem, start fresh —
         * never silently discard (04 §4.5 step 2). */
        s_vfs->close(s_vfs->ctx, fd);
        char bad[56];
        snprintf(bad, sizeof bad, "%s.bad", path);
        s_vfs->rename(s_vfs->ctx, path, bad);
        index_remove(id);
        (void)app_config_store_set_u32(APP_CONFIG_SESSION_ACTIVE_ID, 0);
        return;
    }

    /* Step 4: align the body to whole records (torn append). */
    long size = s_vfs->size(s_vfs->ctx, fd);
    long body = size - h.hdr_len;
    if (body < 0) {
        body = 0;
    }
    uint32_t count = (uint32_t)(body / h.rec_len);
    if (body % h.rec_len != 0) {
        s_vfs->truncate(s_vfs->ctx, fd,
                        (long)h.hdr_len + (long)count * h.rec_len);
    }

    /* Steps 5–6: walk back over CRC-bad tails, at most 3 records. */
    int truncations = 0;
    while (count > 0 && truncations < 3) {
        bridge_sample_rec_t rec;
        bool crc_ok = false;
        if (read_rec_at(fd, &h, count - 1, &rec, &crc_ok) != COOK_STORE_OK) {
            break;
        }
        if (crc_ok) {
            break;
        }
        count--;
        truncations++;
        s_vfs->truncate(s_vfs->ctx, fd,
                        (long)h.hdr_len + (long)count * h.rec_len);
    }

    if (truncations >= 3 && count > 0) {
        /* Step 6 fallout: give up and close the session as-is. */
        bridge_sample_rec_t rec;
        bool crc_ok = false;
        if (read_rec_at(fd, &h, count - 1, &rec, &crc_ok) == COOK_STORE_OK &&
            !crc_ok) {
            s_sess.open = true;
            s_sess.fd = fd;
            s_sess.hdr = h;
            s_sess.sample_count = count;
            s_sess.mark_count = h.mark_count;
            session_finalize(h.ended_unix_ms);
            return;
        }
    }

    /* Step 7: resume into the SAME session. */
    s_sess.open = true;
    s_sess.fd = fd;
    s_sess.hdr = h;
    s_sess.sample_count = count;
    s_sess.mark_count = h.mark_count;
    s_sess.appends_since_sync = 0;
    s_sess.storage_full = false;

    uint32_t last_t = 0;
    if (count > 0) {
        bridge_sample_rec_t rec;
        bool crc_ok;
        if (read_rec_at(fd, &h, count - 1, &rec, &crc_ok) == COOK_STORE_OK) {
            last_t = rec.t;
        }
    }
    (void)cook_session_mark(last_t, BRIDGE_MARK_KIND_AUTO_DETECTED, 0,
                            "power restored");
    cook_index_entry_t e;
    index_entry_from_header(&e, &h, count);
    index_upsert(&e);
    emit_evt(COOK_STORE_EVT_SESSION_RESUMED, id);
}

/* ── Init / index rebuild (F5.5) ───────────────────────────────────────── */

static void scan_cb(const char *name, void *u) {
    (void)u;
    const size_t n = strlen(name);
    if (n < 5 || strcmp(name + n - 4, ".smk") != 0) {
        return; /* .mrk, .bad, novelty.log: not sessions */
    }
    char path[64];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%s", name);
    const int fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_RDONLY);
    if (fd < 0) {
        return;
    }
    bridge_session_header_t h;
    if (header_read(fd, &h) && h.rec_len != 0) {
        const long size = s_vfs->size(s_vfs->ctx, fd);
        long body = size - h.hdr_len;
        if (body < 0) {
            body = 0;
        }
        cook_index_entry_t e;
        index_entry_from_header(&e, &h, (uint32_t)(body / h.rec_len));
        index_upsert(&e);
    }
    s_vfs->close(s_vfs->ctx, fd); /* invalid header: skip, don't abort */
}

int cook_store_core_init(const cook_vfs_t *vfs, cook_store_evt_cb_t cb,
                         void *cb_ctx) {
    if (!vfs) {
        return COOK_STORE_ERR;
    }
    s_vfs = vfs;
    s_cb = cb;
    s_cb_ctx = cb_ctx;
    s_index_count = 0;
    memset(&s_sess, 0, sizeof s_sess);

    s_vfs->list(s_vfs->ctx, COOK_STORE_DIR, scan_cb, NULL);

    uint32_t active_id = 0;
    (void)app_config_store_get_u32(APP_CONFIG_SESSION_ACTIVE_ID, &active_id);
    if (active_id != 0) {
        recover_active(active_id);
    }
    return COOK_STORE_OK;
}

/* ── Streaming read (F5.10) ────────────────────────────────────────────── */

static void bucket_reset(cook_bucket_t *b, uint32_t t0, int32_t sums[4],
                         uint16_t counts[4]) {
    memset(b, 0, sizeof *b);
    b->t0 = t0;
    for (int i = 0; i < 4; i++) {
        b->vmin[i] = INT16_MAX;
        b->vmax[i] = INT16_MIN;
        sums[i] = 0;
        counts[i] = 0;
    }
}

static void bucket_finish(cook_bucket_t *b, const int32_t sums[4],
                          const uint16_t counts[4]) {
    for (int i = 0; i < 4; i++) {
        if (counts[i] == 0) {
            b->vmin[i] = BRIDGE_TEMP_DETACHED;
            b->vmax[i] = BRIDGE_TEMP_DETACHED;
            b->vmean[i] = BRIDGE_TEMP_DETACHED;
        } else {
            b->vmean[i] = (int16_t)(sums[i] / (int32_t)counts[i]);
        }
    }
}

int cook_store_read(uint32_t session_id, uint32_t from_t, uint32_t to_t,
                    uint16_t stride, uint32_t bucket_s, cook_agg_t agg,
                    cook_rec_sink_t rec_sink, cook_bucket_sink_t bucket_sink,
                    void *ctx) {
    if (!s_vfs || (agg == COOK_AGG_NONE && !rec_sink) ||
        (agg != COOK_AGG_NONE && (!bucket_sink || bucket_s == 0))) {
        return COOK_STORE_ERR;
    }
    if (stride == 0) {
        stride = 1;
    }
    /* Reading the open session: land the tail first. */
    if (s_sess.open && session_id == s_sess.hdr.session_id) {
        (void)cook_session_flush();
    }

    char path[48];
    smk_path(path, sizeof path, session_id);
    const int fd = s_vfs->open(s_vfs->ctx, path, COOK_VFS_RDONLY);
    if (fd < 0) {
        return COOK_STORE_ERR_NOT_FOUND;
    }
    bridge_session_header_t h;
    if (!header_read(fd, &h) || h.rec_len == 0 || h.rec_len > MAX_REC_LEN) {
        s_vfs->close(s_vfs->ctx, fd);
        return COOK_STORE_ERR;
    }
    const long size = s_vfs->size(s_vfs->ctx, fd);
    long body = size - h.hdr_len;
    if (body < 0) {
        body = 0;
    }
    const uint32_t count = (uint32_t)(body / h.rec_len);
    if (count == 0) {
        s_vfs->close(s_vfs->ctx, fd);
        return COOK_STORE_OK;
    }

    /* Fixed-width records: the range is a binary-searched SEEK, ≤ 18 reads
     * even for a 54-day file (04 §4.8). Find first index with t >= from_t. */
    uint32_t lo = 0, hi = count;
    while (lo < hi) {
        const uint32_t mid = lo + (hi - lo) / 2;
        bridge_sample_rec_t rec;
        bool crc_ok;
        if (read_rec_at(fd, &h, mid, &rec, &crc_ok) != COOK_STORE_OK) {
            s_vfs->close(s_vfs->ctx, fd);
            return COOK_STORE_ERR;
        }
        if (rec.t < from_t) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }

    int rc = COOK_STORE_OK;
    cook_bucket_t bucket;
    int32_t sums[4];
    uint16_t counts[4];
    bool bucket_live = false;
    uint32_t emitted = 0;

    for (uint32_t idx = lo; idx < count; idx++) {
        bridge_sample_rec_t rec;
        bool crc_ok;
        if (read_rec_at(fd, &h, idx, &rec, &crc_ok) != COOK_STORE_OK) {
            rc = COOK_STORE_ERR;
            break;
        }
        if (!crc_ok) {
            continue; /* a torn mid-file record is skipped, not plotted */
        }
        if (rec.t > to_t) {
            break;
        }

        if (agg == COOK_AGG_NONE) {
            if ((emitted++ % stride) == 0) {
                if (rec_sink(ctx, &rec) != 0) {
                    break;
                }
            }
            continue;
        }

        const uint32_t t0 = rec.t - (rec.t % bucket_s);
        if (!bucket_live || t0 != bucket.t0) {
            if (bucket_live) {
                bucket_finish(&bucket, sums, counts);
                if (bucket_sink(ctx, &bucket) != 0) {
                    bucket_live = false;
                    break;
                }
            }
            bucket_reset(&bucket, t0, sums, counts);
            bucket_live = true;
        }
        bucket.n++;
        for (int i = 0; i < 4; i++) {
            const int16_t v = rec.temp[i];
            if (v == BRIDGE_TEMP_DETACHED || v == BRIDGE_TEMP_INVALID) {
                continue; /* sentinels never aggregate */
            }
            if (v < bucket.vmin[i]) {
                bucket.vmin[i] = v;
            }
            if (v > bucket.vmax[i]) {
                bucket.vmax[i] = v;
            }
            sums[i] += v;
            counts[i]++;
        }
    }
    if (rc == COOK_STORE_OK && bucket_live) {
        bucket_finish(&bucket, sums, counts);
        (void)bucket_sink(ctx, &bucket);
    }
    s_vfs->close(s_vfs->ctx, fd);
    return rc;
}
