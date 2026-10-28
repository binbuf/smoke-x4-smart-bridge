/*
 * log_flash.c - ESP-IDF adapter for the raw `samples` partition (T19).
 *
 * The partition is raw: no LittleFS, no wear levelling, no file system. Reads
 * go through a one-sector cache so boot recovery reads each 4 KB sector once
 * instead of issuing an esp_partition_read for every 18-byte record. Writes
 * and erases invalidate the cache.
 *
 * NVS generation/clear state comes from bridge_config (the only NVS owner).
 * Recovery policy itself lives in the pure-C log_flash_core.c.
 */

#include "log_flash.h"

#include <inttypes.h>
#include <string.h>

#include "bridge_config.h"
#include "esp_log.h"
#include "esp_partition.h"
#include "esp_timer.h"

static const char *TAG = "sx4.log.flash";

typedef struct {
    const esp_partition_t *partition;
    uint8_t cache[SAMPLE_LOG_SECTOR_SIZE];
    uint32_t cache_offset;
    bool cache_valid;
} idf_io_ctx_t;

static idf_io_ctx_t s_ctx;

static int idf_read(void *ctx, uint32_t offset, void *dst, size_t len) {
    idf_io_ctx_t *io = ctx;
    if (io == NULL || io->partition == NULL || dst == NULL ||
        offset > io->partition->size ||
        len > (size_t)(io->partition->size - offset)) {
        return LOG_IO_ERR_RANGE;
    }
    uint8_t *out = dst;
    while (len > 0) {
        /*
         * Sector headers are 32 bytes at a sector base. Serving them directly
         * avoids filling the whole-sector cache just to inspect a header: the
         * mount pass reads all 1,504 headers first, and the record pass then
         * loads each 4 KB sector exactly once. A record read never matches
         * this shape (it starts after the header).
         */
        const bool header_read =
            len <= SAMPLE_LOG_HEADER_SIZE * 2u &&
            offset % SAMPLE_LOG_SECTOR_SIZE == 0;
        const bool hit =
            io->cache_valid && offset >= io->cache_offset &&
            offset < io->cache_offset + SAMPLE_LOG_SECTOR_SIZE;
        if (header_read && !hit) {
            if (esp_partition_read(io->partition, offset, out, len) != ESP_OK) {
                return LOG_IO_ERR_IO;
            }
            offset += (uint32_t)len;
            out += len;
            len = 0;
            break;
        }
        if (!hit) {
            const uint32_t base = offset - (offset % SAMPLE_LOG_SECTOR_SIZE);
            if (esp_partition_read(io->partition, base, io->cache,
                                   sizeof io->cache) != ESP_OK) {
                io->cache_valid = false;
                return LOG_IO_ERR_IO;
            }
            io->cache_offset = base;
            io->cache_valid = true;
        }
        const uint32_t in_sector = offset - io->cache_offset;
        size_t chunk = SAMPLE_LOG_SECTOR_SIZE - in_sector;
        if (chunk > len) {
            chunk = len;
        }
        memcpy(out, io->cache + in_sector, chunk);
        out += chunk;
        offset += (uint32_t)chunk;
        len -= chunk;
    }
    return LOG_IO_OK;
}

static int idf_write(void *ctx, uint32_t offset, const void *src, size_t len) {
    idf_io_ctx_t *io = ctx;
    if (io == NULL || io->partition == NULL ||
        (src == NULL && len != 0) || offset > io->partition->size ||
        len > (size_t)(io->partition->size - offset)) {
        return LOG_IO_ERR_RANGE;
    }
    if (len == 0) {
        return LOG_IO_OK;
    }
    io->cache_valid = false;
    return esp_partition_write(io->partition, offset, src, len) == ESP_OK
               ? LOG_IO_OK
               : LOG_IO_ERR_IO;
}

static int idf_erase(void *ctx, uint32_t offset, size_t len) {
    idf_io_ctx_t *io = ctx;
    if (io == NULL || io->partition == NULL ||
        offset % SAMPLE_LOG_SECTOR_SIZE != 0 ||
        len % SAMPLE_LOG_SECTOR_SIZE != 0 ||
        offset > io->partition->size ||
        len > (size_t)(io->partition->size - offset)) {
        return LOG_IO_ERR_RANGE;
    }
    if (len == 0) {
        return LOG_IO_OK;
    }
    io->cache_valid = false;
    return esp_partition_erase_range(io->partition, offset, len) == ESP_OK
               ? LOG_IO_OK
               : LOG_IO_ERR_IO;
}

static const log_io_ops_t s_ops = {
    .read = idf_read,
    .write = idf_write,
    .erase = idf_erase,
};

static int nvs_load_generation(void *ctx, uint32_t *out) {
    (void)ctx;
    return bridge_config_get_generation(out) == BRIDGE_CONFIG_OK ? 0 : -1;
}

static int nvs_store_generation(void *ctx, uint32_t generation) {
    (void)ctx;
    return bridge_config_set_generation(generation) == BRIDGE_CONFIG_OK ? 0
                                                                        : -1;
}

static int nvs_new_generation(void *ctx, uint32_t *out) {
    (void)ctx;
    return bridge_config_regenerate_generation(out) == BRIDGE_CONFIG_OK ? 0
                                                                        : -1;
}

static int nvs_begin_clear(void *ctx, uint32_t *out) {
    (void)ctx;
    return bridge_config_begin_log_clear(out) == BRIDGE_CONFIG_OK ? 0 : -1;
}

static bool nvs_clear_pending(void *ctx) {
    (void)ctx;
    bridge_config_log_t log;
    if (bridge_config_get_log(&log) != BRIDGE_CONFIG_OK) {
        return false;
    }
    return log.clear_pending;
}

static int nvs_finish_clear(void *ctx) {
    (void)ctx;
    return bridge_config_finish_log_clear() == BRIDGE_CONFIG_OK ? 0 : -1;
}

static const log_flash_hooks_t s_hooks = {
    .load_generation = nvs_load_generation,
    .store_generation = nvs_store_generation,
    .new_generation = nvs_new_generation,
    .begin_clear = nvs_begin_clear,
    .clear_pending = nvs_clear_pending,
    .finish_clear = nvs_finish_clear,
};

esp_err_t log_flash_open_partition(log_flash_t *flash) {
    if (flash == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    const esp_partition_t *partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, (esp_partition_subtype_t)0x40, "samples");
    if (partition == NULL) {
        ESP_LOGE(TAG, "raw `samples` partition not found");
        return ESP_ERR_NOT_FOUND;
    }
    if (partition->size % SAMPLE_LOG_SECTOR_SIZE != 0) {
        ESP_LOGE(TAG, "samples size %" PRIu32 " is not a whole sector",
                 partition->size);
        return ESP_ERR_INVALID_SIZE;
    }

    memset(&s_ctx, 0, sizeof s_ctx);
    s_ctx.partition = partition;

    const log_io_t io = {
        .ops = &s_ops,
        .ctx = &s_ctx,
        .capacity = partition->size,
        .sector_size = SAMPLE_LOG_SECTOR_SIZE,
    };

    const int64_t started_us = esp_timer_get_time();
    const log_flash_status_t status =
        log_flash_open(flash, &io, &s_hooks, NULL);
    const int64_t elapsed_us = esp_timer_get_time() - started_us;
    flash->recovery_ms = (uint32_t)((elapsed_us + 999) / 1000);

    log_ring_info_t info;
    if (status == LOG_FLASH_OK && log_flash_info(flash, &info)) {
        ESP_LOGI(TAG,
                 "recovered in %" PRIu32 " ms: gen %08" PRIx32
                 ", seq %" PRIu32 "..%" PRIu32 ", next %" PRIu32
                 ", %" PRIu32 " records, %" PRIu32
                 " sectors cleared, state %s",
                 flash->recovery_ms, info.generation, info.min_seq, info.max_seq,
                 info.next_seq, info.count, flash->erased_sectors,
                 flash->storage == SAMPLE_LOG_STORAGE_OK ? "OK"
                 : flash->storage == SAMPLE_LOG_STORAGE_NEAR_FULL
                     ? "NEAR_FULL"
                     : "READ_ONLY");
        return ESP_OK;
    }

    ESP_LOGE(TAG, "recovery failed after %" PRIu32 " ms",
             flash->recovery_ms);
    return status == LOG_FLASH_ERR_STATE ? ESP_ERR_INVALID_STATE : ESP_FAIL;
}
