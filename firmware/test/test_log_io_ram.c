/*
 * Host tests for the RAM-backed log_io fake.
 *
 * These cover the fake itself - geometry, bounds, counter, erase and torn
 * operation injection - so ring tests (T18) can trust it as a seam. No ring
 * code exists yet.
 */
#include <string.h>

#include "log_io.h"
#include "ram_log_io.h"
#include "test_util.h"

#define SECTOR_SIZE 4096u
#define SECTOR_COUNT 4u
#define CAPACITY (SECTOR_SIZE * SECTOR_COUNT)

static uint8_t g_storage[CAPACITY];

static int all_bytes(const uint8_t *data, size_t len, uint8_t value) {
    for (size_t i = 0; i < len; i++) {
        if (data[i] != value) {
            return 0;
        }
    }
    return 1;
}

static void test_init_geometry(void) {
    ram_log_io_t ram;
    CHECK_EQ_INT(ram_log_io_init(NULL, g_storage, CAPACITY, SECTOR_SIZE), -1);
    CHECK_EQ_INT(ram_log_io_init(&ram, NULL, CAPACITY, SECTOR_SIZE), -1);
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, 0, SECTOR_SIZE), -1);
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, 0), -1);
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY - 1, SECTOR_SIZE),
                 -1);
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, SECTOR_SIZE), 0);
    CHECK(all_bytes(g_storage, CAPACITY, 0xFF));
    CHECK_EQ_UINT(ram.capacity, CAPACITY);
    CHECK_EQ_UINT(ram.sector_size, SECTOR_SIZE);

    log_io_t io;
    ram_log_io_as_io(&ram, &io);
    CHECK(io.ops != NULL);
    CHECK(io.ctx == &ram);
    CHECK_EQ_UINT(io.capacity, CAPACITY);
    CHECK_EQ_UINT(io.sector_size, SECTOR_SIZE);
}

static void test_write_read_round_trip(void) {
    ram_log_io_t ram;
    log_io_t io;
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, SECTOR_SIZE), 0);
    ram_log_io_as_io(&ram, &io);

    const uint8_t source[8] = {0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80};
    const uint32_t offset = SECTOR_SIZE + 100u;
    CHECK_EQ_INT(log_io_write(&io, offset, source, sizeof source), LOG_IO_OK);
    CHECK_EQ_UINT(ram.write_calls, 1);
    CHECK_EQ_UINT(ram.bytes_written, sizeof source);
    CHECK(memcmp(g_storage + offset, source, sizeof source) == 0);

    uint8_t target[8] = {0};
    CHECK_EQ_INT(log_io_read(&io, offset, target, sizeof target), LOG_IO_OK);
    CHECK_EQ_UINT(ram.read_calls, 1);
    CHECK_EQ_UINT(ram.bytes_read, sizeof target);
    CHECK(memcmp(target, source, sizeof target) == 0);

    /* Zero-length operations are valid no-ops inside the capacity. */
    CHECK_EQ_INT(log_io_read(&io, CAPACITY, NULL, 0), LOG_IO_OK);
    CHECK_EQ_INT(log_io_write(&io, CAPACITY, NULL, 0), LOG_IO_OK);
}

static void test_erase(void) {
    ram_log_io_t ram;
    log_io_t io;
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, SECTOR_SIZE), 0);
    ram_log_io_as_io(&ram, &io);

    memset(g_storage + 2u * SECTOR_SIZE, 0x00, SECTOR_SIZE);
    CHECK_EQ_INT(log_io_erase(&io, 2u * SECTOR_SIZE, SECTOR_SIZE), LOG_IO_OK);
    CHECK(all_bytes(g_storage + 2u * SECTOR_SIZE, SECTOR_SIZE, 0xFF));
    CHECK_EQ_UINT(ram.erase_calls, 1);
    CHECK_EQ_UINT(ram.bytes_erased, SECTOR_SIZE);

    /* Unaligned erases are refused before touching storage; a zero-length
     * aligned erase is a no-op, matching read/write. */
    memset(g_storage + 3u * SECTOR_SIZE, 0x00, SECTOR_SIZE);
    CHECK_EQ_INT(log_io_erase(&io, 3u * SECTOR_SIZE + 1u, SECTOR_SIZE),
                 LOG_IO_ERR_RANGE);
    CHECK_EQ_INT(log_io_erase(&io, 3u * SECTOR_SIZE, 0), LOG_IO_OK);
    CHECK_EQ_INT(log_io_erase(&io, CAPACITY, SECTOR_SIZE), LOG_IO_ERR_RANGE);
    CHECK(all_bytes(g_storage + 3u * SECTOR_SIZE, SECTOR_SIZE, 0x00));
}

static void test_bounds_and_null_interface(void) {
    ram_log_io_t ram;
    log_io_t io;
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, SECTOR_SIZE), 0);
    ram_log_io_as_io(&ram, &io);

    uint8_t byte = 0;
    CHECK_EQ_INT(log_io_read(&io, CAPACITY, &byte, 1), LOG_IO_ERR_RANGE);
    uint8_t data[4] = {1, 2, 3, 4};
    CHECK_EQ_INT(log_io_write(&io, CAPACITY - 2u, data, sizeof data),
                 LOG_IO_ERR_RANGE);
    CHECK(all_bytes(g_storage + CAPACITY - 2u, 2, 0xFF));

    CHECK_EQ_INT(log_io_read(&io, 0, NULL, 1), LOG_IO_ERR_INVAL);
    CHECK_EQ_INT(log_io_write(&io, 0, NULL, 1), LOG_IO_ERR_INVAL);

    log_io_t empty = {0};
    CHECK_EQ_INT(log_io_read(&empty, 0, &byte, 1), LOG_IO_ERR_INVAL);
    CHECK_EQ_INT(log_io_write(&empty, 0, &byte, 1), LOG_IO_ERR_INVAL);
    CHECK_EQ_INT(log_io_erase(&empty, 0, SECTOR_SIZE), LOG_IO_ERR_INVAL);
}

static void test_failure_injection(void) {
    ram_log_io_t ram;
    log_io_t io;
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, SECTOR_SIZE), 0);
    ram_log_io_as_io(&ram, &io);

    const uint8_t source[6] = {1, 2, 3, 4, 5, 6};
    ram_log_io_fail_next(&ram, RAM_LOG_IO_OP_WRITE, 3);
    CHECK_EQ_INT(log_io_write(&io, 0, source, sizeof source), LOG_IO_ERR_IO);
    CHECK_EQ_UINT(ram.bytes_written, 3);
    CHECK(memcmp(g_storage, source, 3) == 0);
    CHECK(all_bytes(g_storage + 3, 3, 0xFF));

    /* The failure was one-shot. */
    CHECK_EQ_INT(log_io_write(&io, 0, source, sizeof source), LOG_IO_OK);
    CHECK(memcmp(g_storage, source, sizeof source) == 0);

    uint8_t target[6] = {0};
    ram_log_io_fail_next(&ram, RAM_LOG_IO_OP_READ, 2);
    CHECK_EQ_INT(log_io_read(&io, 0, target, sizeof target), LOG_IO_ERR_IO);
    CHECK_EQ_UINT(ram.bytes_read, 2);
    CHECK(target[0] == 1 && target[1] == 2 && target[2] == 0);

    memset(g_storage, 0x00, 2u * SECTOR_SIZE);
    ram_log_io_fail_next(&ram, RAM_LOG_IO_OP_ERASE, SECTOR_SIZE);
    CHECK_EQ_INT(log_io_erase(&io, 0, 2u * SECTOR_SIZE), LOG_IO_ERR_IO);
    CHECK(all_bytes(g_storage, SECTOR_SIZE, 0xFF));
    CHECK(all_bytes(g_storage + SECTOR_SIZE, SECTOR_SIZE, 0x00));
    CHECK_EQ_UINT(ram.bytes_erased, SECTOR_SIZE);

    /* A failure queued for another operation does not fire. */
    ram_log_io_fail_next(&ram, RAM_LOG_IO_OP_ERASE, 0);
    CHECK_EQ_INT(log_io_read(&io, 0, target, 1), LOG_IO_OK);
    CHECK_EQ_INT(log_io_erase(&io, SECTOR_SIZE, SECTOR_SIZE), LOG_IO_ERR_IO);
}

static void test_torn_tail_preview(void) {
    ram_log_io_t ram;
    log_io_t io;
    CHECK_EQ_INT(ram_log_io_init(&ram, g_storage, CAPACITY, SECTOR_SIZE), 0);
    ram_log_io_as_io(&ram, &io);

    uint8_t record[18];
    memset(record, 0xA5, sizeof record);
    CHECK_EQ_INT(log_io_write(&io, 0, record, sizeof record), LOG_IO_OK);

    uint8_t torn[18];
    memset(torn, 0x5A, sizeof torn);
    ram_log_io_fail_next(&ram, RAM_LOG_IO_OP_WRITE, 7);
    CHECK_EQ_INT(log_io_write(&io, 18, torn, sizeof torn), LOG_IO_ERR_IO);

    CHECK(memcmp(g_storage, record, sizeof record) == 0);
    CHECK(memcmp(g_storage + 18, torn, 7) == 0);
    CHECK(all_bytes(g_storage + 25, 11, 0xFF));
}

int main(void) {
    test_init_geometry();
    test_write_read_round_trip();
    test_erase();
    test_bounds_and_null_interface();
    test_failure_injection();
    test_torn_tail_preview();
    return sx4_test_summary("log_io_ram");
}
