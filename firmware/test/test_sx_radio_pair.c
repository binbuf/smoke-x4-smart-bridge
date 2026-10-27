/*
 * test_sx_radio_pair.c - pairing state machine and the LoRa TX guard (T16).
 *
 * Pure host test: radio, NVS and time are callback fakes. It drives the FSM
 * through UNPAIRED -> SYNC_RECEIVED -> PAIRED -> LOST -> PAIRED, checks the
 * 902-928 MHz gate, the one-shot ACK, probe learning and persistence, and
 * asserts that no public path except the sync-beacon handler can transmit.
 *
 * No board, no ESP-IDF, no radio.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sx_radio_pair.h"
#include "test_util.h"

#define MAX_TUNE_HISTORY 32

typedef struct {
    sx4_pair_record_t stored;
    bool has_stored;

    uint32_t tuned_hz;
    int tune_calls;
    uint32_t tune_history[MAX_TUNE_HISTORY];

    int ack_calls;
    char last_ack[64];
    size_t last_ack_len;

    int save_calls;
    bool fail_save;
    int clear_calls;
    bool fail_clear;
    bool fail_tune;
    bool fail_ack;
} fake_t;

static void fake_init(fake_t *fake) {
    memset(fake, 0, sizeof(*fake));
}

static bool fake_load(void *ctx, sx4_pair_record_t *out) {
    fake_t *fake = ctx;
    if (!fake->has_stored) {
        return false;
    }
    *out = fake->stored;
    return true;
}

static bool fake_save(void *ctx, const sx4_pair_record_t *record) {
    fake_t *fake = ctx;
    fake->save_calls++;
    if (fake->fail_save) {
        return false;
    }
    fake->stored = *record;
    fake->has_stored = true;
    return true;
}

static bool fake_clear(void *ctx) {
    fake_t *fake = ctx;
    fake->clear_calls++;
    if (fake->fail_clear) {
        return false;
    }
    memset(&fake->stored, 0, sizeof fake->stored);
    fake->has_stored = false;
    return true;
}

static bool fake_tune(void *ctx, uint32_t frequency_hz) {
    fake_t *fake = ctx;
    fake->tune_calls++;
    if (fake->fail_tune) {
        return false;
    }
    fake->tuned_hz = frequency_hz;
    if (fake->tune_calls <= MAX_TUNE_HISTORY) {
        fake->tune_history[fake->tune_calls - 1] = frequency_hz;
    }
    return true;
}

static bool fake_ack(void *ctx, const char *ack, size_t length) {
    fake_t *fake = ctx;
    fake->ack_calls++;
    if (fake->fail_ack) {
        return false;
    }
    if (length >= sizeof fake->last_ack) {
        length = sizeof fake->last_ack - 1u;
    }
    memcpy(fake->last_ack, ack, length);
    fake->last_ack[length] = '\0';
    fake->last_ack_len = length;
    return true;
}

static sx4_radio_pair_io_t make_io(fake_t *fake) {
    sx4_radio_pair_io_t io = {
        .ctx = fake,
        .load = fake_load,
        .save = fake_save,
        .clear = fake_clear,
        .tune = fake_tune,
        .send_ack = fake_ack,
    };
    return io;
}

#define SYNC_X4 "000000,LMXC[,160,50,191,54,"
#define SYNC_X2_ID "000000,abCDe,160,50,191,54,"
#define STATE_X4                                                             \
    "LMXC[,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,"     \
    "160,32,0,0,"
#define STATE_X4_FOREIGN                                                     \
    "ZZZZZ[,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,"     \
    "160,32,0,0,"
#define STATE_X2 "abCDe,30,1,1,0,848,1,125,32,0,849,0,260,195,0,0,"

#define FREQ_918_5 918500000u

static bool feed(const char *payload, uint64_t now_ms) {
    return sx4_radio_pair_on_packet((const uint8_t *)payload, strlen(payload),
                                    now_ms);
}

static void check_scan_alternation(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_UNPAIRED);
    CHECK_EQ_UINT(sx4_radio_pair_scan_frequency_hz(), 915000000u);
    CHECK_EQ_UINT(fake.tuned_hz, 915000000u);
    CHECK_EQ_INT(fake.tune_calls, 1);

    sx4_radio_pair_tick(3299);
    CHECK_EQ_UINT(sx4_radio_pair_scan_frequency_hz(), 915000000u);
    CHECK_EQ_INT(fake.tune_calls, 1);

    sx4_radio_pair_tick(3300);
    CHECK_EQ_UINT(sx4_radio_pair_scan_frequency_hz(), 920000000u);
    CHECK_EQ_UINT(fake.tuned_hz, 920000000u);
    CHECK_EQ_INT(fake.tune_calls, 2);

    sx4_radio_pair_tick(6599);
    CHECK_EQ_UINT(sx4_radio_pair_scan_frequency_hz(), 920000000u);

    sx4_radio_pair_tick(6600);
    CHECK_EQ_UINT(sx4_radio_pair_scan_frequency_hz(), 915000000u);
    CHECK_EQ_UINT(fake.tuned_hz, 915000000u);
    CHECK_EQ_INT(fake.tune_calls, 3);
    CHECK_EQ_INT(fake.ack_calls, 0);
}

static void check_pairing_and_lost(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 1000));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_UNPAIRED);

    /* Beacon: retune to the operating channel, ACK once, do not persist yet. */
    CHECK(feed(SYNC_X4, 1500));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_SYNC_RECEIVED);
    CHECK_EQ_UINT(fake.tuned_hz, FREQ_918_5);
    CHECK_EQ_INT(fake.ack_calls, 1);
    CHECK_STR_EQ(fake.last_ack, "LMXC[,SUCCESS,");
    CHECK_EQ_UINT(fake.last_ack_len, strlen("LMXC[,SUCCESS,"));
    CHECK_EQ_INT(fake.save_calls, 0);

    sx4_pair_record_t record;
    CHECK(sx4_radio_pair_record(&record));
    CHECK_STR_EQ(record.device_id, "LMXC[");
    CHECK_EQ_UINT(record.frequency_hz, FREQ_918_5);
    CHECK_EQ_UINT(record.num_probes, 0u); /* learned from the state packet */

    /* Rule 1: further beacons are ignored until an explicit unpair. */
    int tunes_before = fake.tune_calls;
    CHECK(!feed(SYNC_X4, 1600));
    CHECK(!feed(SYNC_X4, 1700));
    CHECK_EQ_INT(fake.ack_calls, 1);
    CHECK_EQ_INT(fake.tune_calls, tunes_before);

    /* A foreign first state packet must not confirm the pairing. */
    CHECK(!feed(STATE_X4_FOREIGN, 1800));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_SYNC_RECEIVED);
    CHECK_EQ_INT(fake.save_calls, 0);

    /* First matching state packet: learn 4 probes and persist. */
    CHECK(feed(STATE_X4, 2000));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    CHECK_EQ_INT(fake.save_calls, 1);
    CHECK(fake.has_stored);
    CHECK_STR_EQ(fake.stored.device_id, "LMXC[");
    CHECK_EQ_UINT(fake.stored.frequency_hz, FREQ_918_5);
    CHECK_EQ_UINT(fake.stored.num_probes, 4u);
    CHECK_EQ_INT(fake.ack_calls, 1);
    CHECK_EQ_UINT(fake.tuned_hz, FREQ_918_5);

    /* 10 minutes of silence -> LOST; radio stays tuned, no scan, no unpair. */
    int tunes_paired = fake.tune_calls;
    sx4_radio_pair_tick(2000 + SX4_PAIR_LOST_TIMEOUT_MS - 1u);
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    sx4_radio_pair_tick(2000 + SX4_PAIR_LOST_TIMEOUT_MS);
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_LOST);
    CHECK_EQ_INT(fake.tune_calls, tunes_paired);
    CHECK_EQ_UINT(fake.tuned_hz, FREQ_918_5);
    CHECK(sx4_radio_pair_record(&record));
    CHECK_EQ_UINT(record.num_probes, 4u);

    /* A returning state packet restores PAIRED without a retune or ACK. */
    uint64_t resumed = 2000 + SX4_PAIR_LOST_TIMEOUT_MS + 30000u;
    CHECK(feed(STATE_X4, resumed));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    CHECK_EQ_INT(fake.tune_calls, tunes_paired);
    CHECK_EQ_INT(fake.ack_calls, 1);

    sx4_radio_pair_counters_t counters;
    sx4_radio_pair_counters_get(&counters);
    CHECK_EQ_UINT(counters.sync_accepted, 1u);
    CHECK_EQ_UINT(counters.acks_sent, 1u);
    CHECK_EQ_UINT(counters.confirmations, 1u);
    CHECK_EQ_UINT(counters.lost_entries, 1u);
    CHECK_EQ_UINT(counters.lost_recoveries, 1u);
}

static void check_out_of_band_never_tunes_or_transmits(void) {
    static const char *const beacons[] = {
        /* 900 MHz and 930 MHz, encoded little-endian. */
        "000000,LMXC[,0,233,164,53,",
        "000000,LMXC[,128,172,110,53,",
    };

    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    int tunes_before = fake.tune_calls;

    for (size_t i = 0; i < sizeof beacons / sizeof beacons[0]; i++) {
        CHECK(!feed(beacons[i], 100));
        CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_UNPAIRED);
        CHECK_EQ_UINT(fake.tuned_hz, 915000000u);
        CHECK_EQ_INT(fake.tune_calls, tunes_before);
        CHECK_EQ_INT(fake.ack_calls, 0);
    }

    sx4_radio_pair_counters_t counters;
    sx4_radio_pair_counters_get(&counters);
    CHECK_EQ_UINT(counters.rejected_syncs, 2u);

    /* A later valid beacon still pairs: rejection did not wedge the FSM. */
    CHECK(feed(SYNC_X4, 200));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_SYNC_RECEIVED);
    CHECK_EQ_UINT(fake.tuned_hz, FREQ_918_5);
    CHECK_EQ_INT(fake.ack_calls, 1);
}

static void check_malformed_beacon_keeps_state(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    int tunes_before = fake.tune_calls;

    CHECK(!feed("000000,LMXC[,160,50,191,", 10)); /* 5 commas */
    CHECK(!feed("000000,LMXC[,160,50,191,XX,", 20));
    CHECK(!feed("", 30));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_UNPAIRED);
    CHECK_EQ_INT(fake.tune_calls, tunes_before);
    CHECK_EQ_INT(fake.ack_calls, 0);
}

static void check_ack_failure_is_not_accepted(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);
    fake.fail_ack = true;

    CHECK(sx4_radio_pair_init(&io, 0));
    CHECK(!feed(SYNC_X4, 100));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_UNPAIRED);
    /* Tuning was restored to the scan channel after the failed ACK. */
    CHECK_EQ_UINT(fake.tuned_hz, 915000000u);

    fake.fail_ack = false;
    CHECK(feed(SYNC_X4, 200));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_SYNC_RECEIVED);
    CHECK_EQ_INT(fake.ack_calls, 2);
}

static void check_save_failure_retries(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    CHECK(feed(SYNC_X4, 100));

    fake.fail_save = true;
    CHECK(!feed(STATE_X4, 200));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_SYNC_RECEIVED);
    CHECK(!fake.has_stored);

    fake.fail_save = false;
    CHECK(feed(STATE_X4, 300));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    CHECK(fake.has_stored);

    sx4_radio_pair_counters_t counters;
    sx4_radio_pair_counters_get(&counters);
    CHECK_EQ_UINT(counters.save_failures, 1u);
}

static void check_num_probes_comes_from_first_state(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    CHECK(feed(SYNC_X2_ID, 100));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_SYNC_RECEIVED);
    CHECK_EQ_INT(fake.save_calls, 0);

    CHECK(feed(STATE_X2, 200));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    CHECK_EQ_INT(fake.save_calls, 1);
    CHECK_EQ_UINT(fake.stored.num_probes, 2u);
    CHECK_STR_EQ(fake.stored.device_id, "abCDe");
}

static void check_reboot_restores_pairing(void) {
    fake_t first;
    fake_init(&first);
    sx4_radio_pair_io_t io = make_io(&first);

    CHECK(sx4_radio_pair_init(&io, 0));
    CHECK(feed(SYNC_X4, 100));
    CHECK(feed(STATE_X4, 200));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);

    /* Reboot: a fresh FSM instance loads the saved record and tunes to it. */
    fake_t second;
    fake_init(&second);
    second.stored = first.stored;
    second.has_stored = true;
    sx4_radio_pair_io_t io2 = make_io(&second);

    CHECK(sx4_radio_pair_init(&io2, 5000));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    CHECK_EQ_UINT(second.tuned_hz, FREQ_918_5);
    CHECK_EQ_INT(second.save_calls, 0);

    sx4_pair_record_t record;
    CHECK(sx4_radio_pair_record(&record));
    CHECK_STR_EQ(record.device_id, "LMXC[");
    CHECK_EQ_UINT(record.frequency_hz, FREQ_918_5);
    CHECK_EQ_UINT(record.num_probes, 4u);

    /* A rebooted paired bridge does not scan for another unit. */
    int tunes = second.tune_calls;
    sx4_radio_pair_tick(5000 + 4u * SX4_PAIR_SCAN_INTERVAL_MS);
    CHECK_EQ_INT(second.tune_calls, tunes);
    CHECK_EQ_UINT(second.tuned_hz, FREQ_918_5);
}

static void check_unpair_restarts_scan(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    CHECK(feed(SYNC_X4, 100));
    CHECK(feed(STATE_X4, 200));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);

    /* A failed clear keeps the pairing and the PAIRED state. */
    fake.fail_clear = true;
    CHECK(!sx4_radio_pair_unpair(300));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
    CHECK(fake.has_stored);

    fake.fail_clear = false;
    CHECK(sx4_radio_pair_unpair(400));
    CHECK_EQ_INT(fake.clear_calls, 2);
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_UNPAIRED);
    CHECK(!fake.has_stored);
    CHECK_EQ_UINT(fake.tuned_hz, 915000000u);

    sx4_radio_pair_tick(400 + SX4_PAIR_SCAN_INTERVAL_MS);
    CHECK_EQ_UINT(sx4_radio_pair_scan_frequency_hz(), 920000000u);

    /* Re-pair works after unpair. */
    CHECK(feed(SYNC_X4, 5000));
    CHECK_EQ_INT(fake.ack_calls, 2);
    CHECK(feed(STATE_X4, 5100));
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_PAIRED);
}

/*
 * Runtime proof for the TX guard: exercise every non-sync path and require
 * zero transmissions. Only feed(SYNC_X4) may increment ack_calls.
 */
static void check_no_other_path_transmits(void) {
    fake_t fake;
    fake_init(&fake);
    sx4_radio_pair_io_t io = make_io(&fake);

    CHECK(sx4_radio_pair_init(&io, 0));
    sx4_radio_pair_tick(3300);
    sx4_radio_pair_tick(6600);
    CHECK(!feed(STATE_X4, 100));          /* no pairing yet */
    CHECK(!feed("LMXC[,SUCCESS,", 200));  /* ACK-shaped payload, 2 commas */
    CHECK(!feed(STATE_X4_FOREIGN, 300));
    CHECK(!feed("garbage", 400));
    CHECK(!feed("", 500));
    CHECK_EQ_INT(fake.ack_calls, 0);

    CHECK(feed(SYNC_X4, 600));
    CHECK_EQ_INT(fake.ack_calls, 1);
    CHECK(feed(STATE_X4, 700));
    CHECK(!feed(SYNC_X4, 800)); /* ignored while paired */
    sx4_radio_pair_tick(700 + SX4_PAIR_LOST_TIMEOUT_MS);
    CHECK_EQ_INT(sx4_radio_pair_state(), SX4_PAIR_LOST);
    CHECK(feed(STATE_X4, 700 + SX4_PAIR_LOST_TIMEOUT_MS + 1u));
    CHECK(!feed(STATE_X4_FOREIGN, 700 + SX4_PAIR_LOST_TIMEOUT_MS + 2u));
    CHECK_EQ_INT(fake.ack_calls, 1);

    sx4_radio_pair_unpair(700 + SX4_PAIR_LOST_TIMEOUT_MS + 3u);
    CHECK(!feed(STATE_X4, 700 + SX4_PAIR_LOST_TIMEOUT_MS + 4u));
    sx4_radio_pair_tick(700 + 2u * SX4_PAIR_LOST_TIMEOUT_MS);
    CHECK_EQ_INT(fake.ack_calls, 1);
}

static size_t count_substring(const char *text, const char *needle) {
    size_t count = 0;
    size_t needle_len = strlen(needle);
    const char *cursor = text;
    while ((cursor = strstr(cursor, needle)) != NULL) {
        count++;
        cursor += needle_len;
    }
    return count;
}

static char *read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    char *buffer = malloc((size_t)size + 1u);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }
    size_t got = fread(buffer, 1, (size_t)size, file);
    fclose(file);
    buffer[got] = '\0';
    return buffer;
}

/*
 * Static proof: the LoRaSend primitive appears once, in sx_radio.c's private
 * ACK adapter, and the FSM's send_ack callback is called once, in the
 * sync-beacon handler.
 */
static void check_single_tx_call_site(void) {
    char path[512];
    snprintf(path, sizeof path, "%s/sx_radio.c", SX4_RADIO_SRC_DIR);
    char *radio = read_file(path);
    snprintf(path, sizeof path, "%s/sx_radio_pair.c", SX4_RADIO_SRC_DIR);
    char *pair = read_file(path);

    CHECK(radio != NULL);
    CHECK(pair != NULL);
    if (radio == NULL || pair == NULL) {
        free(radio);
        free(pair);
        return;
    }

    CHECK_EQ_UINT(count_substring(radio, "LoRaSend("), 1u);
    CHECK_EQ_UINT(count_substring(pair, "LoRaSend("), 0u);
    CHECK_EQ_UINT(count_substring(pair, "s_pair.io.send_ack("), 1u);

    free(radio);
    free(pair);
}

int main(void) {
    check_scan_alternation();
    check_pairing_and_lost();
    check_out_of_band_never_tunes_or_transmits();
    check_malformed_beacon_keeps_state();
    check_ack_failure_is_not_accepted();
    check_save_failure_retries();
    check_num_probes_comes_from_first_state();
    check_reboot_restores_pairing();
    check_unpair_restarts_scan();
    check_no_other_path_transmits();
    check_single_tx_call_site();
    return sx4_test_summary("sx-radio-pair");
}
