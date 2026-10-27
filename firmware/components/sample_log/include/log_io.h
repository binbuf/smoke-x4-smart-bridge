/*
 * log_io.h - byte-oriented flash seam for the sample log ring.
 *
 * The ring core (T18) reasons in byte offsets over a raw partition. This
 * interface is the only thing it knows about storage, so host tests can run
 * the same code against RAM while the firmware adapter wraps
 * esp_partition_read/write/erase (T19).
 *
 * Pure C11: no ESP-IDF, no heap, no global state.
 */
#ifndef SX4_LOG_IO_H
#define SX4_LOG_IO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LOG_IO_OK = 0,
    LOG_IO_ERR_INVAL = -1, /* null interface/buffer or bad geometry */
    LOG_IO_ERR_RANGE = -2, /* offset/length outside the partition */
    LOG_IO_ERR_IO = -3,    /* adapter or simulated device failure */
} log_io_status_t;

typedef struct {
    /* All calls return log_io_status_t. A zero-length transfer is a no-op. */
    int (*read)(void *ctx, uint32_t offset, void *dst, size_t len);
    int (*write)(void *ctx, uint32_t offset, const void *src, size_t len);
    /* offset and len must be sector-aligned multiples of io->sector_size. */
    int (*erase)(void *ctx, uint32_t offset, size_t len);
} log_io_ops_t;

typedef struct {
    const log_io_ops_t *ops;
    void *ctx;
    uint32_t capacity;    /* bytes in the raw partition */
    uint32_t sector_size; /* erase granularity in bytes */
} log_io_t;

static inline int log_io_read(log_io_t *io, uint32_t offset, void *dst,
                              size_t len) {
    if (io == NULL || io->ops == NULL || io->ops->read == NULL) {
        return LOG_IO_ERR_INVAL;
    }
    if (dst == NULL && len != 0) {
        return LOG_IO_ERR_INVAL;
    }
    return io->ops->read(io->ctx, offset, dst, len);
}

static inline int log_io_write(log_io_t *io, uint32_t offset, const void *src,
                               size_t len) {
    if (io == NULL || io->ops == NULL || io->ops->write == NULL) {
        return LOG_IO_ERR_INVAL;
    }
    if (src == NULL && len != 0) {
        return LOG_IO_ERR_INVAL;
    }
    return io->ops->write(io->ctx, offset, src, len);
}

static inline int log_io_erase(log_io_t *io, uint32_t offset, size_t len) {
    if (io == NULL || io->ops == NULL || io->ops->erase == NULL) {
        return LOG_IO_ERR_INVAL;
    }
    return io->ops->erase(io->ctx, offset, len);
}

#ifdef __cplusplus
}
#endif

#endif /* SX4_LOG_IO_H */
