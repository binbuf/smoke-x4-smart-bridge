/*
 * ram_log_io.h - RAM-backed log_io fake for host ring tests.
 *
 * The fake behaves like a small NOR partition: init/reset fill the backing
 * store with 0xFF, writes and reads are bounded, and erase is sector-aligned.
 * Tests can inject a read/write/erase failure and, for writes and erases,
 * commit only a prefix of the requested bytes to model a torn operation.
 *
 * No allocation: the caller owns the storage.
 */
#ifndef SX4_RAM_LOG_IO_H
#define SX4_RAM_LOG_IO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "log_io.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    RAM_LOG_IO_OP_READ = 0,
    RAM_LOG_IO_OP_WRITE = 1,
    RAM_LOG_IO_OP_ERASE = 2,
} ram_log_io_op_t;

typedef struct {
    uint8_t *storage;
    uint32_t capacity;
    uint32_t sector_size;

    uint32_t read_calls;
    uint32_t write_calls;
    uint32_t erase_calls;
    uint32_t bytes_read;
    uint32_t bytes_written;
    uint32_t bytes_erased;

    bool fail_pending;
    ram_log_io_op_t fail_op;
    uint32_t fail_after_bytes;
} ram_log_io_t;

/* Validate geometry, fill storage with 0xFF and clear statistics. Returns 0
 * on success, -1 on bad arguments (including capacity not a sector multiple). */
int ram_log_io_init(ram_log_io_t *ram, uint8_t *storage, uint32_t capacity,
                    uint32_t sector_size);

/* Fill storage with 0xFF and clear statistics and failure injection. */
void ram_log_io_reset(ram_log_io_t *ram);

/* Arrange for the next matching operation to return LOG_IO_ERR_IO after
 * touching fail_after_bytes (clamped to the request). One-shot. */
void ram_log_io_fail_next(ram_log_io_t *ram, ram_log_io_op_t op,
                          uint32_t fail_after_bytes);

/* Fill a log_io_t whose ops/ctx/capacity/sector_size refer to this fake. */
void ram_log_io_as_io(ram_log_io_t *ram, log_io_t *out);

#ifdef __cplusplus
}
#endif

#endif /* SX4_RAM_LOG_IO_H */
