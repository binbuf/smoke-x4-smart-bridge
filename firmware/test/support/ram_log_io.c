#include "ram_log_io.h"

#include <string.h>

static bool range_ok(const ram_log_io_t *ram, uint32_t offset, size_t len) {
    if (ram == NULL || ram->storage == NULL) {
        return false;
    }
    if (len > ram->capacity || offset > ram->capacity) {
        return false;
    }
    return (size_t)(ram->capacity - offset) >= len;
}

static bool take_failure(ram_log_io_t *ram, ram_log_io_op_t op,
                         uint32_t request_len, uint32_t *partial) {
    if (!ram->fail_pending || ram->fail_op != op) {
        return false;
    }
    ram->fail_pending = false;
    *partial = ram->fail_after_bytes;
    if (*partial > request_len) {
        *partial = request_len;
    }
    return true;
}

static int ram_read(void *ctx, uint32_t offset, void *dst, size_t len) {
    ram_log_io_t *ram = ctx;
    ram->read_calls++;
    if (!range_ok(ram, offset, len)) {
        return LOG_IO_ERR_RANGE;
    }
    uint32_t partial = 0;
    if (take_failure(ram, RAM_LOG_IO_OP_READ, (uint32_t)len, &partial)) {
        if (partial > 0) {
            memcpy(dst, ram->storage + offset, partial);
            ram->bytes_read += partial;
        }
        return LOG_IO_ERR_IO;
    }
    if (len > 0) {
        memcpy(dst, ram->storage + offset, len);
        ram->bytes_read += (uint32_t)len;
    }
    return LOG_IO_OK;
}

static int ram_write(void *ctx, uint32_t offset, const void *src, size_t len) {
    ram_log_io_t *ram = ctx;
    ram->write_calls++;
    if (!range_ok(ram, offset, len)) {
        return LOG_IO_ERR_RANGE;
    }
    uint32_t partial = 0;
    if (take_failure(ram, RAM_LOG_IO_OP_WRITE, (uint32_t)len, &partial)) {
        if (partial > 0) {
            memcpy(ram->storage + offset, src, partial);
            ram->bytes_written += partial;
        }
        return LOG_IO_ERR_IO;
    }
    if (len > 0) {
        memcpy(ram->storage + offset, src, len);
        ram->bytes_written += (uint32_t)len;
    }
    return LOG_IO_OK;
}

static int ram_erase(void *ctx, uint32_t offset, size_t len) {
    ram_log_io_t *ram = ctx;
    ram->erase_calls++;
    if (ram->sector_size == 0 || offset % ram->sector_size != 0 ||
        len == 0 || len % ram->sector_size != 0) {
        return LOG_IO_ERR_RANGE;
    }
    if (!range_ok(ram, offset, len)) {
        return LOG_IO_ERR_RANGE;
    }
    uint32_t partial = 0;
    if (take_failure(ram, RAM_LOG_IO_OP_ERASE, (uint32_t)len, &partial)) {
        if (partial > 0) {
            memset(ram->storage + offset, 0xFF, partial);
            ram->bytes_erased += partial;
        }
        return LOG_IO_ERR_IO;
    }
    memset(ram->storage + offset, 0xFF, len);
    ram->bytes_erased += (uint32_t)len;
    return LOG_IO_OK;
}

static const log_io_ops_t RAM_OPS = {
    .read = ram_read,
    .write = ram_write,
    .erase = ram_erase,
};

int ram_log_io_init(ram_log_io_t *ram, uint8_t *storage, uint32_t capacity,
                    uint32_t sector_size) {
    if (ram == NULL || storage == NULL || capacity == 0 || sector_size == 0 ||
        capacity % sector_size != 0) {
        return -1;
    }
    memset(ram, 0, sizeof *ram);
    ram->storage = storage;
    ram->capacity = capacity;
    ram->sector_size = sector_size;
    memset(storage, 0xFF, capacity);
    return 0;
}

void ram_log_io_reset(ram_log_io_t *ram) {
    if (ram == NULL || ram->storage == NULL) {
        return;
    }
    uint32_t capacity = ram->capacity;
    uint32_t sector_size = ram->sector_size;
    uint8_t *storage = ram->storage;
    memset(ram, 0, sizeof *ram);
    ram->storage = storage;
    ram->capacity = capacity;
    ram->sector_size = sector_size;
    memset(storage, 0xFF, capacity);
}

void ram_log_io_fail_next(ram_log_io_t *ram, ram_log_io_op_t op,
                          uint32_t fail_after_bytes) {
    if (ram == NULL) {
        return;
    }
    ram->fail_pending = true;
    ram->fail_op = op;
    ram->fail_after_bytes = fail_after_bytes;
}

void ram_log_io_as_io(ram_log_io_t *ram, log_io_t *out) {
    if (out == NULL) {
        return;
    }
    out->ops = ram == NULL ? NULL : &RAM_OPS;
    out->ctx = ram;
    out->capacity = ram == NULL ? 0 : ram->capacity;
    out->sector_size = ram == NULL ? 0 : ram->sector_size;
}
