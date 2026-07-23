/* Host tests for cook_store's write path and crash safety (F5.1–F5.5,
 * F5.7–F5.9). The load-bearing one is torn-append recovery truncated at
 * EVERY byte offset within the final record — §12.10 says it is not
 * optional, and it is why the core is written against cook_vfs. */
#include <stdio.h>
#include <string.h>

#include "cook_store_core.h"
#include "test_cook_doubles.h"
#include "test_util.h"

static int g_evt_counts[8];
static uint32_t g_last_evt_id;

static void on_evt(cook_store_evt_t evt, uint32_t id, void *ctx) {
    (void)ctx;
    g_evt_counts[evt]++;
    g_last_evt_id = id;
}

static void fresh_store(void) {
    memfs_reset();
    cfg_erase_all(NULL);
    memset(g_evt_counts, 0, sizeof g_evt_counts);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
}

typedef struct {
    int n;
    bridge_sample_rec_t last;
} rec_acc_t;

static int rec_sink(void *ctx, const bridge_sample_rec_t *rec) {
    rec_acc_t *acc = ctx;
    acc->n++;
    acc->last = *rec;
    return 0;
}

static const cook_session_params_t k_params = {
    .num_probes = 4,
    .started_unix_ms = 0,
    .started_uptime_s = 100,
    .name = NULL,
    .device_id = "LMXC[\\",
};

static void append_n(uint32_t first_t, int n) {
    for (int i = 0; i < n; i++) {
        const int16_t temps[4] = {2250, 1503, 1601, BRIDGE_TEMP_DETACHED};
        CHECK_EQ_INT(cook_session_append(first_t + (uint32_t)i * 30, temps,
                                         0x40, -42),
                     COOK_STORE_OK);
    }
}

static void test_open_append_close_reopens_identically(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    CHECK(cook_session_is_open());
    CHECK_EQ_INT((int)cook_session_resume_base_t(), 0); /* fresh session */
    const uint32_t id = cook_session_active_id();
    CHECK_EQ_INT(g_evt_counts[COOK_STORE_EVT_SESSION_STARTED], 1);

    append_n(0, 10);
    CHECK_EQ_INT((int)cook_session_sample_count(), 10);
    CHECK_EQ_INT(cook_session_close(1234567890123ull), COOK_STORE_OK);
    CHECK(!cook_session_is_open());

    /* Remount: the index rebuilds from headers alone (F5.5). */
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
    const cook_index_entry_t *e = cook_store_index_find(id);
    CHECK(e != NULL);
    if (e) {
        CHECK_EQ_INT((int)e->sample_count, 10);
        CHECK_EQ_INT(e->num_probes, 4);
        CHECK(bridge_session_header_closed(e->flags));
        CHECK(e->ended_unix_ms == 1234567890123ull);
    }

    /* And the records read back identically through the read path. */
    rec_acc_t acc = {0};
    CHECK_EQ_INT(cook_store_read(id, 0, UINT32_MAX, 1, 0, COOK_AGG_NONE,
                                 rec_sink, NULL, &acc),
                 COOK_STORE_OK);
    CHECK_EQ_INT(acc.n, 10);
    CHECK_EQ_INT(acc.last.temp[0], 2250);
    CHECK_EQ_INT(acc.last.temp[3], BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT((int)acc.last.t, 270);
}

static void test_fsync_cadence_and_flush(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    const int base = g_fsync_calls;
    append_n(0, 8); /* every 4th append syncs (F5.7) */
    CHECK_EQ_INT(g_fsync_calls, base + 2);
    CHECK_EQ_INT(cook_session_flush(), COOK_STORE_OK); /* alarm/button/... */
    CHECK_EQ_INT(g_fsync_calls, base + 3);
}

/* F5.3: build a valid file, then truncate at every byte offset within the
 * final record; recovery must converge into the same session each time. */
static void test_recovery_truncated_at_every_offset(void) {
    for (size_t cut = 1; cut < BRIDGE_SAMPLE_REC_SIZE; cut++) {
        fresh_store();
        CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
        const uint32_t id = cook_session_active_id();
        append_n(0, 5);
        CHECK_EQ_INT(cook_session_flush(), COOK_STORE_OK);

        /* Power cut: chop `cut` bytes off the final record. */
        char path[48];
        snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
        mem_file_t *f = memfs_find(path);
        CHECK(f != NULL);
        f->len -= cut;

        /* Reboot with active_id still set. */
        memset(g_evt_counts, 0, sizeof g_evt_counts);
        CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL),
                     COOK_STORE_OK);
        CHECK(cook_session_is_open());
        CHECK_EQ_INT((int)cook_session_active_id(), (int)id); /* SAME one */
        CHECK_EQ_INT((int)cook_session_sample_count(), 4);
        CHECK_EQ_INT(g_evt_counts[COOK_STORE_EVT_SESSION_RESUMED], 1);

        /* t resumes one period after the last record — uptime restarted
         * with the reboot, so the caller anchors on this, never on
         * started_uptime (the F5.11 board-found underflow). */
        CHECK_EQ_INT((int)cook_session_resume_base_t(), 90 + 30);

        /* Appending continues where the cook left off. */
        append_n(150, 1);
        CHECK_EQ_INT((int)cook_session_sample_count(), 5);
    }
}

static void test_recovery_walks_back_crc_bad_tail(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    const uint32_t id = cook_session_active_id();
    append_n(0, 6);
    CHECK_EQ_INT(cook_session_flush(), COOK_STORE_OK);

    /* Corrupt the LAST TWO records in place (half-programmed writes). */
    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
    mem_file_t *f = memfs_find(path);
    f->data[f->len - 3] ^= 0xFF;
    f->data[f->len - 20] ^= 0xFF;

    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
    CHECK(cook_session_is_open());
    CHECK_EQ_INT((int)cook_session_sample_count(), 4);

    /* The auto-mark landed in the sibling .mrk (04 §4.5 step 7). */
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.mrk", (unsigned)id);
    mem_file_t *m = memfs_find(path);
    CHECK(m != NULL);
    if (m) {
        bridge_mark_rec_t mark;
        CHECK(bridge_mark_rec_decode(m->data + m->len - BRIDGE_MARK_REC_SIZE,
                                     &mark));
        CHECK_EQ_INT(mark.kind, BRIDGE_MARK_KIND_AUTO_DETECTED);
        CHECK(strcmp(mark.text, "power restored") == 0);
    }
}

static void test_recovery_gives_up_after_three_and_closes(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    const uint32_t id = cook_session_active_id();
    append_n(0, 8);
    CHECK_EQ_INT(cook_session_flush(), COOK_STORE_OK);

    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
    mem_file_t *f = memfs_find(path);
    /* Corrupt the last FOUR records: recovery truncates 3, then gives up
     * and closes the session as-is — bounded, no unbounded truncation. */
    for (int i = 1; i <= 4; i++) {
        f->data[f->len - (size_t)i * BRIDGE_SAMPLE_REC_SIZE + 5] ^= 0xFF;
    }

    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
    CHECK(!cook_session_is_open()); /* closed as-is, not resumed */
    const cook_index_entry_t *e = cook_store_index_find(id);
    CHECK(e && bridge_session_header_closed(e->flags));
    uint32_t active = 99;
    CHECK_EQ_INT(app_config_store_get_u32(APP_CONFIG_SESSION_ACTIVE_ID,
                                          &active),
                 APP_CONFIG_OK);
    CHECK_EQ_INT((int)active, 0);
}

static void test_bad_header_renames_to_bad_and_starts_fresh(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    const uint32_t id = cook_session_active_id();
    append_n(0, 3);
    CHECK_EQ_INT(cook_session_flush(), COOK_STORE_OK);

    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
    memfs_find(path)->data[1] ^= 0xFF; /* magic dies, and so does the CRC */

    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
    CHECK(!cook_session_is_open());
    char bad[56];
    snprintf(bad, sizeof bad, "%s.bad", path);
    CHECK(memfs_find(bad) != NULL); /* kept for post-mortem, not discarded */
    CHECK(memfs_find(path) == NULL);

    /* And the .bad file is skipped, not fatal, on the next rebuild. */
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
    CHECK_EQ_INT(cook_store_index_count(), 0);
}

static void test_future_version_header_is_read_not_rejected(void) {
    fresh_store();
    /* A v2 file with rec_len 20: a v1 reader strides by the header's
     * rec_len and reads the v1 prefix (04 §4.10). */
    uint8_t file[BRIDGE_SESSION_HEADER_SIZE + 3 * 20];
    bridge_session_header_t h = {0};
    memcpy(h.magic, BRIDGE_SESSION_MAGIC, 4);
    h.version = 2;
    h.hdr_len = BRIDGE_SESSION_HEADER_SIZE;
    h.rec_len = 20;
    h.num_probes = 4;
    h.session_id = 42;
    h.sample_count = 3;
    h.flags = BRIDGE_SESSION_HEADER_FLAGS_CLOSED;
    bridge_session_header_encode(&h, file);
    for (int i = 0; i < 3; i++) {
        bridge_sample_rec_t r = {.t = (uint32_t)i * 30,
                                 .temp = {100 + i, 200, 300, 400},
                                 .flags = 0,
                                 .rssi = -40};
        uint8_t rec[20] = {0};
        bridge_sample_rec_encode(&r, rec);
        rec[16] = 0xEE; /* future fields a v1 reader must skip */
        memcpy(file + BRIDGE_SESSION_HEADER_SIZE + i * 20, rec, 20);
    }
    memfs_put(COOK_STORE_DIR "/0000002A.smk", file, sizeof file);

    CHECK_EQ_INT(cook_store_core_init(&g_vfs, on_evt, NULL), COOK_STORE_OK);
    const cook_index_entry_t *e = cook_store_index_find(42);
    CHECK(e != NULL);
    if (e) {
        CHECK_EQ_INT((int)e->sample_count, 3);
    }
    rec_acc_t acc = {0};
    CHECK_EQ_INT(cook_store_read(42, 0, UINT32_MAX, 1, 0, COOK_AGG_NONE,
                                 rec_sink, NULL, &acc),
                 COOK_STORE_OK);
    CHECK_EQ_INT(acc.n, 3);
    CHECK_EQ_INT(acc.last.temp[0], 102);
}

static void test_marks_utf8_safe_truncation(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    /* 22 ASCII bytes + '€' (3 bytes) crosses the 24-byte cap at byte 25;
     * a naive cut at 24 would leave 2 dangling UTF-8 bytes. */
    CHECK_EQ_INT(cook_session_mark(60, BRIDGE_MARK_KIND_NOTE, 1,
                                   "abcdefghijklmnopqrstuv€"),
                 COOK_STORE_OK);
    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.mrk",
             (unsigned)cook_session_active_id());
    mem_file_t *m = memfs_find(path);
    CHECK(m != NULL);
    if (m) {
        bridge_mark_rec_t mark;
        CHECK(bridge_mark_rec_decode(m->data, &mark));
        CHECK_EQ_INT((int)strlen(mark.text), 22); /* '€' dropped whole */
        CHECK_EQ_INT(mark.probe, 1);
    }
}

static void test_retention_pinned_and_active_survive(void) {
    fresh_store();
    /* Three closed sessions; pin the oldest. */
    uint32_t ids[3];
    for (int i = 0; i < 3; i++) {
        CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
        ids[i] = cook_session_active_id();
        append_n(0, 2);
        CHECK_EQ_INT(cook_session_close(1000), COOK_STORE_OK);
    }
    CHECK_EQ_INT(cook_session_set_pinned(ids[0], true), COOK_STORE_OK);

    /* Squeeze retention: max 2 sessions. */
    CHECK_EQ_INT(app_config_store_set_u8(
                     APP_CONFIG_DEV_RETENTION_MAX_SESSIONS, 2),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(cook_retention_enforce(), COOK_STORE_OK);
    /* The PINNED oldest survives; the unpinned oldest (ids[1]) went. */
    CHECK_EQ_INT(cook_store_index_count(), 2);
    CHECK(cook_store_index_find(ids[0]) != NULL);
    CHECK(cook_store_index_find(ids[1]) == NULL);
    CHECK(cook_store_index_find(ids[2]) != NULL);
    CHECK_EQ_INT(g_evt_counts[COOK_STORE_EVT_SESSION_PURGED], 1);
}

static void test_partition_full_stops_loudly(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    append_n(0, 2);
    /* Only the active session exists and the disk is "full": nothing is
     * deletable, appending stops with an explicit event (04 §4.7). */
    g_free_pct = 0;
    const int16_t temps[4] = {1000, 1000, 1000, 1000};
    CHECK_EQ_INT(cook_session_append(90, temps, 0, -40),
                 COOK_STORE_ERR_FULL);
    CHECK_EQ_INT(g_evt_counts[COOK_STORE_EVT_STORAGE_FULL], 1);
    CHECK(cook_session_is_open()); /* the session is not destroyed */
    CHECK_EQ_INT(cook_store_index_count(), 1);
}

static void test_clock_backpatch_rewrites_header_only(void) {
    fresh_store();
    CHECK_EQ_INT(cook_session_open(&k_params), COOK_STORE_OK);
    const uint32_t id = cook_session_active_id();
    append_n(0, 4);
    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
    mem_file_t *f = memfs_find(path);
    uint8_t before[3 * BRIDGE_SAMPLE_REC_SIZE];
    memcpy(before, f->data + BRIDGE_SESSION_HEADER_SIZE, sizeof before);

    CHECK_EQ_INT(cook_session_set_clock(1750000000000ull), COOK_STORE_OK);

    /* Samples untouched; header carries the clock (F6.2's contract). */
    CHECK(memcmp(before, f->data + BRIDGE_SESSION_HEADER_SIZE,
                 sizeof before) == 0);
    bridge_session_header_t h;
    CHECK(bridge_session_header_decode(f->data, &h));
    CHECK(h.started_unix_ms == 1750000000000ull);
    CHECK(bridge_session_header_clock_valid(h.flags));
}

int main(void) {
    test_open_append_close_reopens_identically();
    test_fsync_cadence_and_flush();
    test_recovery_truncated_at_every_offset();
    test_recovery_walks_back_crc_bad_tail();
    test_recovery_gives_up_after_three_and_closes();
    test_bad_header_renames_to_bad_and_starts_fresh();
    test_future_version_header_is_read_not_rejected();
    test_marks_utf8_safe_truncation();
    test_retention_pinned_and_active_survive();
    test_partition_full_stops_loudly();
    test_clock_backpatch_rewrites_header_only();
    return test_summary("test_cook_store");
}
