/* Host tests for the F4 capture layer: the raw packet ring (F4.1) and the
 * novelty seen-set (F4.2). The core F4.2 contract: a synthetic stream with
 * one instance of each reason produces exactly ten entries, and replaying
 * the identical stream produces none. */
#include <stdio.h>
#include <string.h>

#include "smoke_x_novelty.h"
#include "smoke_x_pktring.h"
#include "test_util.h"

#define PAIRED "LMXC[\\"

/* One packet per reason, all for the paired device unless noted. */
static const char *BASELINE = /* -> first (state26 class) */
    "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";
static const char *FIELD1_31 = /* -> field1 */
    "LMXC[\\,31,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";
static const char *HDR3_2 = /* -> trailing (header field 3) */
    "LMXC[\\,30,1,2,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";
static const char *PROBE_STATE_1 = /* -> probe_state */
    "LMXC[\\,30,1,1,1,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";
static const char *NEW_ALARM = /* -> alarm_edge (rising) */
    "LMXC[\\,30,1,1,0,811,1,105,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,1,";
static const char *BILLOWS = /* -> billows */
    "LMXC[\\,30,1,1,0,811,1,105,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,1,0,";
static const char *CELSIUS = /* -> units */
    "LMXC[\\,30,0,1,0,381,1,37,8,0,285,0,71,0,0,288,0,71,0,0,273,0,71,0,0,0,";
static const char *SYNC = /* -> sync */
    "000000,LMXC[\\,160,50,191,54,";
static const char *GARBAGE = /* -> unparsed */
    "not,a,real,payload";
static const char *FOREIGN = /* -> id_mismatch */
    "ZZZZZ,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";

static smoke_x_novelty_entry_t g_entries[32];
static int g_entry_count;

static void sink(const smoke_x_novelty_entry_t *e, void *ctx) {
    (void)ctx;
    if (g_entry_count < (int)(sizeof g_entries / sizeof g_entries[0])) {
        g_entries[g_entry_count] = *e;
    }
    g_entry_count++;
}

static void feed_stream(void) {
    const char *stream[] = {BASELINE, FIELD1_31, HDR3_2,  PROBE_STATE_1,
                            NEW_ALARM, BILLOWS,   CELSIUS, SYNC,
                            GARBAGE,   FOREIGN};
    for (size_t i = 0; i < sizeof stream / sizeof stream[0]; i++) {
        smoke_x_novelty_observe(stream[i], PAIRED, -40, 10,
                                (uint64_t)(i + 1) * 30000u);
    }
}

static int count_reason(smoke_x_novelty_reason_t r) {
    int n = 0;
    for (int i = 0; i < g_entry_count && i < 32; i++) {
        if (g_entries[i].reason == r) {
            n++;
        }
    }
    return n;
}

static void test_one_instance_of_each_reason_is_exactly_ten(void) {
    smoke_x_novelty_init(sink, NULL);
    g_entry_count = 0;
    feed_stream();
    CHECK_EQ_INT(g_entry_count, 10);
    for (int r = 0; r < SMOKE_X_NOVEL_REASON_COUNT; r++) {
        CHECK_EQ_INT(count_reason((smoke_x_novelty_reason_t)r), 1);
    }
}

static void test_replay_produces_nothing(void) {
    smoke_x_novelty_init(sink, NULL);
    g_entry_count = 0;
    feed_stream();
    const int after_first = g_entry_count;
    feed_stream();
    CHECK_EQ_INT(g_entry_count, after_first);
}

static void test_alarm_edge_carries_both_packets(void) {
    smoke_x_novelty_init(sink, NULL);
    g_entry_count = 0;
    feed_stream();
    for (int i = 0; i < g_entry_count; i++) {
        if (g_entries[i].reason == SMOKE_X_NOVEL_ALARM_EDGE) {
            CHECK(strcmp(g_entries[i].payload, NEW_ALARM) == 0);
            /* The packet BEFORE the transition rides along (Q8). */
            CHECK(strcmp(g_entries[i].prev_payload, PROBE_STATE_1) == 0);
        }
    }
}

static void test_steady_state_is_silent(void) {
    smoke_x_novelty_init(sink, NULL);
    g_entry_count = 0;
    smoke_x_novelty_observe(BASELINE, PAIRED, -40, 10, 30000);
    CHECK_EQ_INT(g_entry_count, 1); /* only `first` */
    for (int i = 0; i < 100; i++) {
        smoke_x_novelty_observe(BASELINE, PAIRED, -40, 10,
                                60000u + (uint64_t)i * 30000u);
    }
    CHECK_EQ_INT(g_entry_count, 1); /* a day of normal packets: nothing */
}

static void test_foreign_values_do_not_poison_seen_sets(void) {
    smoke_x_novelty_init(sink, NULL);
    g_entry_count = 0;
    smoke_x_novelty_observe(BASELINE, PAIRED, -40, 10, 30000);
    /* A foreign packet with field1=77 fires id_mismatch only... */
    smoke_x_novelty_observe(
        "ZZZZZ,77,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,"
        "160,32,0,0,",
        PAIRED, -70, 5, 60000);
    CHECK_EQ_INT(count_reason(SMOKE_X_NOVEL_ID_MISMATCH), 1);
    CHECK_EQ_INT(count_reason(SMOKE_X_NOVEL_FIELD1), 0);
    /* ...so field1=77 from OUR device later is still novel. */
    smoke_x_novelty_observe(
        "LMXC[\\,77,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,"
        "160,32,0,0,",
        PAIRED, -40, 10, 90000);
    CHECK_EQ_INT(count_reason(SMOKE_X_NOVEL_FIELD1), 1);
}

static void test_pktring_wraps_and_survives_1000(void) {
    smoke_x_pktring_reset();
    CHECK_EQ_INT((int)smoke_x_pktring_count(), 0);
    CHECK(smoke_x_pktring_get(0) == NULL);

    char buf[64];
    for (int i = 0; i < 1000; i++) {
        snprintf(buf, sizeof buf, "pkt-%d", i);
        smoke_x_pktring_push(buf, (int8_t)-(i % 90), 10, (uint64_t)i * 1000u);
    }
    CHECK_EQ_INT((int)smoke_x_pktring_count(), SMOKE_X_PKTRING_SIZE);

    /* Newest first; the last 64 pushes survive, everything older is gone. */
    const smoke_x_pkt_t *newest = smoke_x_pktring_get(0);
    const smoke_x_pkt_t *oldest =
        smoke_x_pktring_get(SMOKE_X_PKTRING_SIZE - 1);
    CHECK(newest && strcmp(newest->payload, "pkt-999") == 0);
    CHECK(oldest && strcmp(oldest->payload, "pkt-936") == 0);
    CHECK(newest->t_ms == 999000u);
    CHECK(smoke_x_pktring_get(SMOKE_X_PKTRING_SIZE) == NULL);
}

int main(void) {
    test_one_instance_of_each_reason_is_exactly_ten();
    test_replay_produces_nothing();
    test_alarm_edge_carries_both_packets();
    test_steady_state_is_silent();
    test_foreign_values_do_not_poison_seen_sets();
    test_pktring_wraps_and_survives_1000();
    return test_summary("test_smoke_x_novelty");
}
