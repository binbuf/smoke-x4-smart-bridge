/* Host tests for the streaming read path (F5.10): bucketed min/mean/max
 * aggregation that keeps a lid-open spike visible, stride decimation, and
 * the binary-search bound that makes a range query on a 54-day file a
 * seek, not a scan. */
#include <stdio.h>
#include <string.h>

#include "cook_store_core.h"
#include "test_cook_doubles.h"
#include "test_util.h"

typedef struct {
    int n;
} rec_count_acc_t;

static int count_sink(void *ctx, const bridge_sample_rec_t *rec) {
    (void)rec;
    ((rec_count_acc_t *)ctx)->n++;
    return 0;
}

static void put_session_file(uint32_t id, uint32_t n_samples,
                             uint32_t period_s,
                             int16_t (*temp_fn)(uint32_t idx, int probe)) {
    const size_t len =
        BRIDGE_SESSION_HEADER_SIZE + (size_t)n_samples * BRIDGE_SAMPLE_REC_SIZE;
    uint8_t *file = malloc(len);
    bridge_session_header_t h = {0};
    memcpy(h.magic, BRIDGE_SESSION_MAGIC, 4);
    h.version = BRIDGE_RECORD_VERSION;
    h.hdr_len = BRIDGE_SESSION_HEADER_SIZE;
    h.rec_len = BRIDGE_SAMPLE_REC_SIZE;
    h.num_probes = 4;
    h.session_id = id;
    h.sample_period_s = period_s;
    h.sample_count = n_samples;
    h.flags = BRIDGE_SESSION_HEADER_FLAGS_CLOSED;
    bridge_session_header_encode(&h, file);
    for (uint32_t i = 0; i < n_samples; i++) {
        bridge_sample_rec_t r = {.t = i * period_s, .flags = 0, .rssi = -40};
        for (int p = 0; p < 4; p++) {
            r.temp[p] = temp_fn(i, p);
        }
        bridge_sample_rec_encode(
            &r, file + BRIDGE_SESSION_HEADER_SIZE +
                    (size_t)i * BRIDGE_SAMPLE_REC_SIZE);
    }
    char path[48];
    snprintf(path, sizeof path, COOK_STORE_DIR "/%08X.smk", (unsigned)id);
    memfs_put(path, file, len);
    free(file);
}

/* 24 h cook: pit steady at 225.0, probe 2 ramps, probe 3 detached, and a
 * single lid-open spike down 60° at sample 1000. */
static int16_t cook24_temp(uint32_t idx, int probe) {
    switch (probe) {
        case 0:
            return idx == 1000 ? 1650 : 2250;
        case 1:
            return (int16_t)(400 + (idx < 2400 ? idx : 2400));
        case 2:
            return BRIDGE_TEMP_DETACHED;
        default:
            return 950;
    }
}

typedef struct {
    int n;
    cook_bucket_t spike; /* the bucket containing t=30000 */
    cook_bucket_t first;
} bucket_acc_t;

static int bucket_sink(void *ctx, const cook_bucket_t *b) {
    bucket_acc_t *acc = ctx;
    if (acc->n == 0) {
        acc->first = *b;
    }
    acc->n++;
    if (30000 >= b->t0 && 30000 < b->t0 + 90) {
        acc->spike = *b;
    }
    return 0;
}

static void test_24h_bucket_90_minmax_is_960_and_spike_survives(void) {
    memfs_reset();
    cfg_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    put_session_file(7, 2880, 30, cook24_temp);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);

    bucket_acc_t acc = {0};
    CHECK_EQ_INT(cook_store_read(7, 0, UINT32_MAX, 1, 90, COOK_AGG_MINMAX,
                                 NULL, bucket_sink, &acc),
                 COOK_STORE_OK);
    CHECK_EQ_INT(acc.n, 960); /* 86,400 s / 90 s */

    /* The spike sample (t=30000, 165.0°) is inside its bucket's min while
     * the mean stays near 225 — the excursion survives aggregation. */
    CHECK_EQ_INT(acc.spike.vmin[0], 1650);
    CHECK_EQ_INT(acc.spike.vmax[0], 2250);
    CHECK(acc.spike.vmean[0] > 1650 && acc.spike.vmean[0] < 2250);

    /* A detached probe aggregates to the sentinel, never a number. */
    CHECK_EQ_INT(acc.first.vmin[2], BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT(acc.first.vmean[2], BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT(acc.first.n, 3); /* 90 s bucket at 30 s cadence */
}

static int16_t flat_temp(uint32_t idx, int probe) {
    (void)idx;
    (void)probe;
    return 1000;
}

static void test_stride_decimation(void) {
    memfs_reset();
    cfg_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    put_session_file(8, 600, 30, flat_temp);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);

    rec_count_acc_t acc = {0};
    CHECK_EQ_INT(cook_store_read(8, 0, UINT32_MAX, 6, 0, COOK_AGG_NONE,
                                 count_sink, NULL, &acc),
                 COOK_STORE_OK);
    CHECK_EQ_INT(acc.n, 100); /* every 6th of 600 */
}

static void test_54_day_range_query_is_a_seek(void) {
    memfs_reset();
    cfg_erase_all(NULL);
    CHECK_EQ_INT(app_config_store_init(&g_cfg_backend, cfg_rng),
                 APP_CONFIG_OK);
    /* 54 days at 30 s = 155,520 records ≈ 2.5 MB. */
    put_session_file(9, 155520, 30, flat_temp);
    CHECK_EQ_INT(cook_store_core_init(&g_vfs, NULL, NULL), COOK_STORE_OK);

    g_read_calls = 0;
    rec_count_acc_t acc = {0};
    /* A 5-minute window from the middle of day 40. */
    const uint32_t from = 40u * 86400u;
    CHECK_EQ_INT(cook_store_read(9, from, from + 300, 1, 0, COOK_AGG_NONE,
                                 count_sink, NULL, &acc),
                 COOK_STORE_OK);
    CHECK_EQ_INT(acc.n, 11);
    /* header + ≤18 binary-search probes + 12 emit/terminate reads. The
     * bound is what makes a 54-day file as cheap as a 1-hour one. */
    CHECK(g_read_calls <= 34);
}

int main(void) {
    test_24h_bucket_90_minmax_is_960_and_spike_survives();
    test_stride_decimation();
    test_54_day_range_query_is_a_seek();
    return test_summary("test_cook_read");
}
