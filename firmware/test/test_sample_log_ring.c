/*
 * Host tests for the sample-log ring core (T18).
 *
 * The ring runs over the RAM log_io fake: no ESP-IDF, no flash. Scenarios cover
 * geometry/capacity, empty format, fill, wrap and oldest-sector erase, torn
 * tails, dual-header recovery, generation mismatch/reclaim and a full default
 * partition.
 */
#include <string.h>

#include "log_core.h"
#include "ram_log_io.h"
#include "test_util.h"

#define TEST_GENERATION_A 0x1234ABCDu
#define TEST_GENERATION_B 0x99887766u

static uint8_t g_storage[SAMPLE_LOG_DEFAULT_PARTITION_BYTES];

typedef struct {
    ram_log_io_t ram;
    log_io_t io;
} fixture_t;

static void fixture_init(fixture_t *f, uint32_t sectors) {
    CHECK_EQ_INT(ram_log_io_init(&f->ram, g_storage,
                                 sectors * SAMPLE_LOG_SECTOR_SIZE,
                                 SAMPLE_LOG_SECTOR_SIZE),
                 0);
    ram_log_io_as_io(&f->ram, &f->io);
}

static sx4_sample_rec_t make_record(uint32_t unix_s) {
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof rec);
    for (unsigned i = 0; i < 4u; i++) {
        rec.temp[i] = SX4_TEMP_DETACHED;
    }
    rec.unix_s = unix_s;
    return rec;
}

static void append_ok(log_ring_t *ring, uint32_t expected_seq,
                      uint32_t unix_s) {
    sx4_sample_rec_t rec = make_record(unix_s);
    CHECK_EQ_INT(log_ring_append(ring, &rec), SAMPLE_LOG_OK);
    CHECK_EQ_UINT(sx4_sample_rec_seq_get(&rec), expected_seq);
}

static void expect_record(log_ring_t *ring, uint32_t seq, uint32_t unix_s) {
    sx4_sample_rec_t rec;
    CHECK_EQ_INT(log_ring_read_seq(ring, seq, &rec), SAMPLE_LOG_OK);
    CHECK_EQ_UINT(sx4_sample_rec_seq_get(&rec), seq);
    CHECK_EQ_UINT(rec.unix_s, unix_s);
}

static void test_capacity_arithmetic(void) {
    CHECK_EQ_UINT(SAMPLE_LOG_SECTOR_SIZE, 4096u);
    CHECK_EQ_UINT(SAMPLE_LOG_HEADER_SIZE, 32u);
    CHECK_EQ_UINT(SAMPLE_LOG_RECORD_SIZE, 18u);
    CHECK_EQ_UINT(SAMPLE_LOG_RECORDS_PER_SECTOR, 225u);
    CHECK_EQ_UINT(SAMPLE_LOG_DEFAULT_SECTOR_COUNT, 1504u);
    CHECK_EQ_UINT(SAMPLE_LOG_CAPACITY_RECORDS, 338400u);
    CHECK_EQ_UINT(SAMPLE_LOG_SECTOR_SIZE - SAMPLE_LOG_HEADER_SIZE -
                      SAMPLE_LOG_RECORDS_PER_SECTOR * SAMPLE_LOG_RECORD_SIZE,
                  14u);
}

static void test_empty_mount_and_format(void) {
    fixture_t f;
    log_ring_t ring;
    log_ring_info_t info;

    fixture_init(&f, 4u);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK(info.needs_format);
    CHECK(!info.generation_known);
    CHECK_EQ_UINT(info.count, 0);
    CHECK_EQ_UINT(info.next_seq, 0);

    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_A), SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK(!info.needs_format);
    CHECK(info.generation_known);
    CHECK_EQ_UINT(info.generation, TEST_GENERATION_A);
    CHECK_EQ_UINT(info.next_seq, 0);

    /* A formatted but empty log survives a remount with the known generation. */
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, 0);
    CHECK_EQ_UINT(info.next_seq, 0);
    CHECK_EQ_UINT(info.generation, TEST_GENERATION_A);

    append_ok(&ring, 0, 1000);
    append_ok(&ring, 1, 1001);
    expect_record(&ring, 0, 1000);
    expect_record(&ring, 1, 1001);

    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, 2);
    CHECK_EQ_UINT(info.max_seq, 1);
    CHECK_EQ_UINT(info.next_seq, 2);
    expect_record(&ring, 1, 1001);
}

static void test_fill_wrap_and_oldest_erase(void) {
    fixture_t f;
    log_ring_t ring;
    log_ring_info_t info;
    const uint32_t capacity =
        3u * SAMPLE_LOG_RECORDS_PER_SECTOR; /* small but same geometry */

    fixture_init(&f, 3u);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_A), SAMPLE_LOG_OK);

    for (uint32_t i = 0; i < capacity; i++) {
        append_ok(&ring, i, 1000u + i);
    }
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, capacity);
    CHECK_EQ_UINT(info.min_seq, 0);
    CHECK_EQ_UINT(info.max_seq, capacity - 1u);
    CHECK_EQ_UINT(info.next_seq, capacity);
    CHECK_EQ_UINT(info.live_sectors, 3);
    expect_record(&ring, 0, 1000);

    /* The next write rotates: sector 0 (seq 0..224) is erased and reused. */
    append_ok(&ring, capacity, 1000u + capacity);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, capacity - 224u);
    CHECK_EQ_UINT(info.min_seq, SAMPLE_LOG_RECORDS_PER_SECTOR);
    CHECK_EQ_UINT(info.max_seq, capacity);
    CHECK_EQ_UINT(info.next_seq, capacity + 1u);
    CHECK_EQ_UINT(info.live_sectors, 3);
    CHECK_EQ_INT(log_ring_read_seq(&ring, 0, &(sx4_sample_rec_t){0}),
                 SAMPLE_LOG_ERR_RANGE);
    expect_record(&ring, SAMPLE_LOG_RECORDS_PER_SECTOR, 1000u + 225u);
    expect_record(&ring, capacity, 1000u + capacity);

    /* Fill sector 0 again (seq 675..899), then rotate over sector 1. */
    for (uint32_t seq = capacity + 1u;
         seq < capacity + SAMPLE_LOG_RECORDS_PER_SECTOR; seq++) {
        append_ok(&ring, seq, 1000u + seq);
    }
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, capacity);
    CHECK_EQ_UINT(info.min_seq, SAMPLE_LOG_RECORDS_PER_SECTOR);
    CHECK_EQ_UINT(info.max_seq, capacity + SAMPLE_LOG_RECORDS_PER_SECTOR - 1u);

    const uint32_t next = capacity + SAMPLE_LOG_RECORDS_PER_SECTOR;
    append_ok(&ring, next, 1000u + next);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.min_seq, 2u * SAMPLE_LOG_RECORDS_PER_SECTOR);
    CHECK_EQ_UINT(info.max_seq, next);
    CHECK_EQ_UINT(info.count, capacity - 224u);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.min_seq, 2u * SAMPLE_LOG_RECORDS_PER_SECTOR);
    CHECK_EQ_UINT(info.max_seq, next);
    expect_record(&ring, next, 1000u + next);
}

static void test_torn_tail_resumes(void) {
    fixture_t f;
    log_ring_t ring;
    log_ring_info_t info;

    fixture_init(&f, 2u);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_A), SAMPLE_LOG_OK);
    for (uint32_t i = 0; i < 5u; i++) {
        append_ok(&ring, i, 2000u + i);
    }

    /* Tear the next record after 7 bytes. */
    ram_log_io_fail_next(&f.ram, RAM_LOG_IO_OP_WRITE, 7u);
    sx4_sample_rec_t torn = make_record(9999);
    CHECK_EQ_INT(log_ring_append(&ring, &torn), SAMPLE_LOG_ERR_IO);
    /* Earlier records are still in storage; no further append is allowed on
     * this mount. */
    CHECK_EQ_INT(log_ring_append(&ring, &torn), SAMPLE_LOG_ERR_STATE);

    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, 5);
    CHECK_EQ_UINT(info.max_seq, 4);
    CHECK_EQ_UINT(info.next_seq, 5);
    for (uint32_t i = 0; i < 5u; i++) {
        expect_record(&ring, i, 2000u + i);
    }

    /* Resume at the torn slot; the in-flight record is the only loss. */
    append_ok(&ring, 5, 2005);
    expect_record(&ring, 5, 2005);
    CHECK_EQ_INT(log_ring_read_seq(&ring, 6, &(sx4_sample_rec_t){0}),
                 SAMPLE_LOG_ERR_RANGE);
}

static void test_dual_header_recovery(void) {
    fixture_t f;
    log_ring_t ring;
    log_ring_info_t info;

    fixture_init(&f, 2u);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_A), SAMPLE_LOG_OK);
    for (uint32_t i = 0; i < 10u; i++) {
        append_ok(&ring, i, 3000u + i);
    }

    /* Copy A torn: copy B alone must carry the sector. */
    memset(g_storage, 0x00, SAMPLE_LOG_HEADER_COPY_SIZE);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, 10);
    expect_record(&ring, 0, 3000);
    expect_record(&ring, 9, 3009);

    /* Both copies gone: the valid records plus the known generation rebuild
     * the header. */
    memset(g_storage, 0x00, SAMPLE_LOG_HEADER_SIZE);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, 10);
    CHECK_EQ_UINT(info.max_seq, 9);
    expect_record(&ring, 4, 3004);

    /* The reconstructed header is committed, so writing continues. */
    append_ok(&ring, 10, 3010);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    expect_record(&ring, 10, 3010);
}

static void test_generation_mismatch_is_reclaimed(void) {
    fixture_t f;
    log_ring_t ring;
    log_ring_info_t info;

    fixture_init(&f, 2u);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_A), SAMPLE_LOG_OK);
    /* Old generation spans both sectors: 225 + 5 records. */
    for (uint32_t i = 0; i < 230u; i++) {
        append_ok(&ring, i, 4000u + i);
    }

    /* A fresh generation: old headers are ignored immediately. */
    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_B), SAMPLE_LOG_OK);
    for (uint32_t i = 0; i < 5u; i++) {
        append_ok(&ring, i, 8000u + i);
    }
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_B),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.generation, TEST_GENERATION_B);
    CHECK_EQ_UINT(info.count, 5);
    CHECK_EQ_UINT(info.min_seq, 0);
    CHECK_EQ_UINT(info.max_seq, 4);
    expect_record(&ring, 0, 8000);

    /* Fill sector 0 with the new generation, then rotate onto the sector that
     * still holds old-generation records. It must be erased, not adopted. */
    for (uint32_t seq = 5u; seq < SAMPLE_LOG_RECORDS_PER_SECTOR; seq++) {
        append_ok(&ring, seq, 8000u + seq);
    }
    append_ok(&ring, SAMPLE_LOG_RECORDS_PER_SECTOR,
              8000u + SAMPLE_LOG_RECORDS_PER_SECTOR);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, SAMPLE_LOG_RECORDS_PER_SECTOR + 1u);
    CHECK_EQ_UINT(info.min_seq, 0);
    CHECK_EQ_UINT(info.max_seq, SAMPLE_LOG_RECORDS_PER_SECTOR);
    /* Old genA seq 225 (unix 4225) is gone; genB seq 225 (unix 8225) is here. */
    expect_record(&ring, SAMPLE_LOG_RECORDS_PER_SECTOR,
                  8000u + SAMPLE_LOG_RECORDS_PER_SECTOR);

    /* Unknown generation restores the only generation still on the ring. */
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.generation, TEST_GENERATION_B);
    CHECK_EQ_UINT(info.max_seq, SAMPLE_LOG_RECORDS_PER_SECTOR);
}

static void test_full_default_partition(void) {
    fixture_t f;
    log_ring_t ring;
    log_ring_info_t info;

    fixture_init(&f, SAMPLE_LOG_DEFAULT_SECTOR_COUNT);
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, false, 0), SAMPLE_LOG_OK);
    CHECK(ring.needs_format);
    CHECK_EQ_INT(log_ring_format(&ring, TEST_GENERATION_A), SAMPLE_LOG_OK);

    for (uint32_t seq = 0; seq < SAMPLE_LOG_CAPACITY_RECORDS; seq++) {
        sx4_sample_rec_t rec = make_record(10000u + seq);
        if (log_ring_append(&ring, &rec) != SAMPLE_LOG_OK ||
            sx4_sample_rec_seq_get(&rec) != seq) {
            CHECK(0);
            return;
        }
    }
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, SAMPLE_LOG_CAPACITY_RECORDS);
    CHECK_EQ_UINT(info.min_seq, 0);
    CHECK_EQ_UINT(info.max_seq, SAMPLE_LOG_CAPACITY_RECORDS - 1u);
    CHECK_EQ_UINT(info.next_seq, SAMPLE_LOG_CAPACITY_RECORDS);
    CHECK_EQ_UINT(info.live_sectors, SAMPLE_LOG_DEFAULT_SECTOR_COUNT);

    /* One more record wraps the whole ring and reclaims sector 0. */
    append_ok(&ring, SAMPLE_LOG_CAPACITY_RECORDS,
              10000u + SAMPLE_LOG_CAPACITY_RECORDS);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, SAMPLE_LOG_CAPACITY_RECORDS - 224u);
    CHECK_EQ_UINT(info.min_seq, SAMPLE_LOG_RECORDS_PER_SECTOR);
    CHECK_EQ_UINT(info.max_seq, SAMPLE_LOG_CAPACITY_RECORDS);
    CHECK_EQ_UINT(info.next_seq, SAMPLE_LOG_CAPACITY_RECORDS + 1u);

    /* Full-ring recovery sees the same bounds and oldest sequence. */
    CHECK_EQ_INT(log_ring_mount(&ring, &f.io, true, TEST_GENERATION_A),
                 SAMPLE_LOG_OK);
    log_ring_info(&ring, &info);
    CHECK_EQ_UINT(info.count, SAMPLE_LOG_CAPACITY_RECORDS - 224u);
    CHECK_EQ_UINT(info.min_seq, SAMPLE_LOG_RECORDS_PER_SECTOR);
    CHECK_EQ_UINT(info.max_seq, SAMPLE_LOG_CAPACITY_RECORDS);
    expect_record(&ring, SAMPLE_LOG_RECORDS_PER_SECTOR,
                  10000u + SAMPLE_LOG_RECORDS_PER_SECTOR);
    expect_record(&ring, SAMPLE_LOG_CAPACITY_RECORDS,
                  10000u + SAMPLE_LOG_CAPACITY_RECORDS);
}

int main(void) {
    test_capacity_arithmetic();
    test_empty_mount_and_format();
    test_fill_wrap_and_oldest_erase();
    test_torn_tail_resumes();
    test_dual_header_recovery();
    test_generation_mismatch_is_reclaimed();
    test_full_default_partition();
    return sx4_test_summary("sample_log_ring");
}
