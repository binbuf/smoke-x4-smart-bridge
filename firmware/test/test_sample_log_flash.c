/*
 * Host tests for the sample-log flash/boot-recovery policy (T19).
 *
 * The ring runs over the RAM log_io fake; NVS is a small in-memory seam. No
 * ESP-IDF and no board. Scenarios: first mount, reboot recovery, torn tail,
 * pending-clear completion/resume, NVS generation loss, storage-state
 * transitions and failure mapping that must never report a successful write.
 */

#include <string.h>

#include "log_flash.h"
#include "ram_log_io.h"
#include "test_util.h"

#define TEST_SECTORS 4u
#define TEST_BYTES (TEST_SECTORS * SAMPLE_LOG_SECTOR_SIZE)
#define GEN_A 0x1234ABCDu
#define GEN_B 0x99887766u
#define GEN_C 0x0BADF00Du

static uint8_t g_storage[TEST_BYTES];

typedef struct {
    uint32_t generation;
    bool clear_pending;
    bool load_fails;
    uint32_t new_generation;
    int store_calls;
    int new_calls;
    int finish_calls;
} fake_nvs_t;

typedef struct {
    ram_log_io_t ram;
    log_io_t io;
    log_flash_t flash;
    fake_nvs_t nvs;
} fixture_t;

static int nvs_load(void *ctx, uint32_t *out) {
    fake_nvs_t *nvs = ctx;
    if (nvs->load_fails) {
        return -1;
    }
    *out = nvs->generation;
    return 0;
}

static int nvs_store(void *ctx, uint32_t generation) {
    fake_nvs_t *nvs = ctx;
    nvs->store_calls++;
    nvs->generation = generation;
    return 0;
}

static int nvs_new(void *ctx, uint32_t *out) {
    fake_nvs_t *nvs = ctx;
    nvs->new_calls++;
    nvs->generation = nvs->new_generation;
    *out = nvs->generation;
    return 0;
}

static bool nvs_clear_pending(void *ctx) {
    return ((fake_nvs_t *)ctx)->clear_pending;
}

static int nvs_finish_clear(void *ctx) {
    fake_nvs_t *nvs = ctx;
    nvs->finish_calls++;
    nvs->clear_pending = false;
    return 0;
}

static const log_flash_hooks_t HOOKS = {
    .load_generation = nvs_load,
    .store_generation = nvs_store,
    .new_generation = nvs_new,
    .clear_pending = nvs_clear_pending,
    .finish_clear = nvs_finish_clear,
};

static void fixture_init(fixture_t *f, uint32_t generation) {
    memset(f, 0, sizeof *f);
    CHECK_EQ_INT(ram_log_io_init(&f->ram, g_storage, TEST_BYTES,
                                 SAMPLE_LOG_SECTOR_SIZE),
                 0);
    ram_log_io_as_io(&f->ram, &f->io);
    f->nvs.generation = generation;
    f->nvs.new_generation = GEN_C;
}

static log_flash_status_t fixture_open(fixture_t *f) {
    return log_flash_open(&f->flash, &f->io, &HOOKS, &f->nvs);
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

static void append_ok(fixture_t *f, uint32_t expected_seq, uint32_t unix_s) {
    sx4_sample_rec_t rec = make_record(unix_s);
    CHECK_EQ_INT(log_flash_append(&f->flash, &rec), SAMPLE_LOG_OK);
    CHECK_EQ_UINT(sx4_sample_rec_seq_get(&rec), expected_seq);
}

static void expect_record(fixture_t *f, uint32_t seq, uint32_t unix_s) {
    sx4_sample_rec_t rec;
    CHECK_EQ_INT(log_flash_read_seq(&f->flash, seq, &rec), SAMPLE_LOG_OK);
    CHECK_EQ_UINT(sx4_sample_rec_seq_get(&rec), seq);
    CHECK_EQ_UINT(rec.unix_s, unix_s);
}

static void test_first_mount_and_append(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);

    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK(f.flash.ready);
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_OK);
    CHECK(f.flash.opened);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.generation, GEN_A);
    CHECK_EQ_UINT(info.count, 0);
    CHECK_EQ_UINT(info.next_seq, 0);

    append_ok(&f, 0, 1000);
    append_ok(&f, 1, 1030);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.count, 2);
    CHECK_EQ_UINT(info.min_seq, 0);
    CHECK_EQ_UINT(info.max_seq, 1);
    CHECK_EQ_UINT(info.next_seq, 2);
    expect_record(&f, 1, 1030);
}

static void test_reboot_recovery_resumes_sequence(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    append_ok(&f, 0, 10);
    append_ok(&f, 1, 40);
    append_ok(&f, 2, 70);

    /* Same raw bytes, fresh mount: this is the reboot path. */
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.count, 3);
    CHECK_EQ_UINT(info.next_seq, 3);
    CHECK_EQ_UINT(info.generation, GEN_A);
    expect_record(&f, 0, 10);
    append_ok(&f, 3, 100);
    expect_record(&f, 3, 100);
}

static void test_torn_tail_resumes_at_last_valid_sequence(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    for (uint32_t i = 0; i < 5u; i++) {
        append_ok(&f, i, 100u + i * 30u);
    }

    /* Tear the in-flight record (seq 4, index 4): flip a byte after the CRC
     * layout was committed only partially, as a power cut can. */
    g_storage[SAMPLE_LOG_HEADER_SIZE + 4u * SAMPLE_LOG_RECORD_SIZE + 7u] ^= 0xFFu;

    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.count, 4);
    CHECK_EQ_UINT(info.max_seq, 3);
    CHECK_EQ_UINT(info.next_seq, 4);
    CHECK_EQ_UINT(f.flash.storage, SAMPLE_LOG_STORAGE_OK);
    expect_record(&f, 3, 190);

    /* Only the in-flight record was lost; the writer continues at seq 4. */
    append_ok(&f, 4, 250);
    expect_record(&f, 4, 250);
    expect_record(&f, 0, 100);
}

static void test_pending_clear_finishes_and_ignores_old_generation(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    /* Two sectors of old-generation data. */
    for (uint32_t i = 0; i < SAMPLE_LOG_RECORDS_PER_SECTOR + 1u; i++) {
        append_ok(&f, i, 1000u + i);
    }
    CHECK_EQ_UINT(f.ram.erase_calls, 2u);

    /* The app started a clear: NVS has a new generation and clear_pending.
     * Simulate a power cut after sector 0 was erased. */
    f.nvs.generation = GEN_B;
    f.nvs.clear_pending = true;
    CHECK_EQ_INT(log_io_erase(&f.io, 0, SAMPLE_LOG_SECTOR_SIZE), LOG_IO_OK);
    const uint32_t erases_before = f.ram.erase_calls;

    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK(!f.nvs.clear_pending);
    CHECK_EQ_INT(f.nvs.finish_calls, 1);
    CHECK(f.flash.ready);
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_OK);
    /* Only the remaining non-blank sector had to be erased. */
    CHECK_EQ_UINT(f.ram.erase_calls - erases_before, 1u);
    CHECK_EQ_UINT(f.flash.erased_sectors, 1u);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.generation, GEN_B);
    CHECK_EQ_UINT(info.count, 0);
    CHECK_EQ_UINT(info.next_seq, 0);

    /* Old-generation sequences are gone, not resurrected. */
    sx4_sample_rec_t rec;
    CHECK_EQ_INT(log_flash_read_seq(&f.flash, 0, &rec), SAMPLE_LOG_ERR_RANGE);
    CHECK_EQ_INT(log_flash_read_seq(&f.flash, 225, &rec),
                 SAMPLE_LOG_ERR_RANGE);

    /* The new log starts at zero on the new generation. */
    append_ok(&f, 0, 7000);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.generation, GEN_B);
}

static void test_clear_erase_failure_keeps_clear_pending(void) {
    fixture_t f;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    append_ok(&f, 0, 10);

    f.nvs.generation = GEN_B;
    f.nvs.clear_pending = true;
    ram_log_io_fail_next(&f.ram, RAM_LOG_IO_OP_ERASE, 0);

    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_ERR_IO);
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_READ_ONLY);
    CHECK(!f.flash.ready);
    CHECK(f.nvs.clear_pending);
    CHECK_EQ_INT(f.nvs.finish_calls, 0);
}

static void test_write_failure_is_read_only_and_not_success(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    append_ok(&f, 0, 10);

    sx4_sample_rec_t rec = make_record(40);
    ram_log_io_fail_next(&f.ram, RAM_LOG_IO_OP_WRITE, 0);
    CHECK_EQ_INT(log_flash_append(&f.flash, &rec), SAMPLE_LOG_ERR_IO);
    /* The failed record was never assigned a sequence and is not counted. */
    CHECK_EQ_UINT(rec.seq[0] | (rec.seq[1] << 8) | (rec.seq[2] << 16), 0u);
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_READ_ONLY);
    CHECK(!f.flash.ready);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.count, 1);
    CHECK_EQ_UINT(info.next_seq, 1);

    /* A failed mount is not retried in place; writers stay rejected. */
    rec = make_record(70);
    CHECK_EQ_INT(log_flash_append(&f.flash, &rec), SAMPLE_LOG_ERR_STATE);

    /* Reboot recovers the earlier record and continues at seq 1. */
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.count, 1);
    CHECK_EQ_UINT(info.next_seq, 1);
    append_ok(&f, 1, 100);
}

static void test_read_failure_is_read_only(void) {
    fixture_t f;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    append_ok(&f, 0, 10);

    sx4_sample_rec_t rec;
    ram_log_io_fail_next(&f.ram, RAM_LOG_IO_OP_READ, 0);
    CHECK_EQ_INT(log_flash_read_seq(&f.flash, 0, &rec), SAMPLE_LOG_ERR_IO);
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_READ_ONLY);
}

static void test_nvs_loss_adopts_newest_header(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    append_ok(&f, 0, 10);
    append_ok(&f, 1, 40);

    f.nvs.load_fails = true;
    const int stores_before = f.nvs.store_calls;
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK_EQ_INT(f.nvs.store_calls, stores_before + 1);
    CHECK_EQ_UINT(f.nvs.generation, GEN_A);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.next_seq, 2);
    expect_record(&f, 1, 40);
}

static void test_blank_log_without_generation_formats(void) {
    fixture_t f;
    log_ring_info_t info;
    fixture_init(&f, GEN_A);
    f.nvs.load_fails = true;

    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);
    CHECK_EQ_INT(f.nvs.new_calls, 1);
    CHECK_EQ_UINT(f.nvs.generation, GEN_C);
    CHECK(log_flash_info(&f.flash, &info));
    CHECK_EQ_UINT(info.generation, GEN_C);
    CHECK_EQ_UINT(info.next_seq, 0);
    append_ok(&f, 0, 1);
}

static void test_storage_becomes_near_full_only_at_capacity_edge(void) {
    fixture_t f;
    fixture_init(&f, GEN_A);
    CHECK_EQ_INT(fixture_open(&f), LOG_FLASH_OK);

    /* 4 sectors -> 900 records; one sector free = 675 records. */
    for (uint32_t i = 0; i < SAMPLE_LOG_RECORDS_PER_SECTOR * 3u - 1u; i++) {
        append_ok(&f, i, i);
    }
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_OK);
    append_ok(&f, SAMPLE_LOG_RECORDS_PER_SECTOR * 3u - 1u,
              SAMPLE_LOG_RECORDS_PER_SECTOR * 3u - 1u);
    CHECK_EQ_INT(f.flash.storage, SAMPLE_LOG_STORAGE_NEAR_FULL);
    /* NEAR_FULL still records: storage_ok is only false for READ_ONLY. */
    CHECK(f.flash.ready);
}

int main(void) {
    test_first_mount_and_append();
    test_reboot_recovery_resumes_sequence();
    test_torn_tail_resumes_at_last_valid_sequence();
    test_pending_clear_finishes_and_ignores_old_generation();
    test_clear_erase_failure_keeps_clear_pending();
    test_write_failure_is_read_only_and_not_success();
    test_read_failure_is_read_only();
    test_nvs_loss_adopts_newest_header();
    test_blank_log_without_generation_formats();
    test_storage_becomes_near_full_only_at_capacity_edge();
    return sx4_test_summary("sample-log-flash");
}
