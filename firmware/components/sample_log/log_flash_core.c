/*
 * log_flash_core.c - boot recovery, pending-clear completion and storage state
 * for the raw sample ring (T19). Plain C11 over log_io.h; no ESP-IDF.
 */

#include "log_flash.h"

#include <string.h>

static bool hooks_complete(const log_flash_hooks_t *hooks) {
    return hooks != NULL && hooks->load_generation != NULL &&
           hooks->store_generation != NULL && hooks->new_generation != NULL &&
           hooks->begin_clear != NULL && hooks->clear_pending != NULL &&
           hooks->finish_clear != NULL;
}

static void set_read_only(log_flash_t *flash) {
    flash->storage = SAMPLE_LOG_STORAGE_READ_ONLY;
    flash->ready = false;
}

/* Read every sector and erase the ones that are not already blank. A power
 * cut mid-clear leaves the finished sectors blank, so a resumed clear only
 * re-erases the remainder.
 *
 * The scan buffer is deliberately small: clear and pending-clear recovery run
 * on the 3.5 KB esp_timer/main task stacks. A whole-sector (4 KB) stack buffer
 * overflows them and faults; 256 B keeps the stack use bounded. The sector
 * cache in the IDF adapter makes the extra reads cheap. */
#define CLEAR_SCAN_CHUNK 256u

static log_flash_status_t sector_is_blank(log_io_t *io, uint32_t base,
                                          bool *blank) {
    uint8_t buf[CLEAR_SCAN_CHUNK];
    *blank = true;
    for (uint32_t off = 0; off < SAMPLE_LOG_SECTOR_SIZE;
         off += (uint32_t)sizeof buf) {
        if (log_io_read(io, base + off, buf, sizeof buf) != LOG_IO_OK) {
            return LOG_FLASH_ERR_IO;
        }
        for (size_t i = 0; i < sizeof buf; i++) {
            if (buf[i] != 0xFFu) {
                *blank = false;
                return LOG_FLASH_OK;
            }
        }
    }
    return LOG_FLASH_OK;
}

static log_flash_status_t erase_nonblank_sectors(log_flash_t *flash) {
    log_io_t *io = &flash->ring.io;

    for (uint32_t sector = 0; sector < flash->ring.sector_count; sector++) {
        const uint32_t base = sector * SAMPLE_LOG_SECTOR_SIZE;
        bool blank = false;
        if (sector_is_blank(io, base, &blank) != LOG_FLASH_OK) {
            return LOG_FLASH_ERR_IO;
        }
        if (blank) {
            continue;
        }
        if (log_io_erase(io, base, SAMPLE_LOG_SECTOR_SIZE) != LOG_IO_OK) {
            return LOG_FLASH_ERR_IO;
        }
        flash->erased_sectors++;
    }
    return LOG_FLASH_OK;
}

static sample_log_storage_state_t state_for(const log_ring_t *ring) {
    if (ring->sector_count == 0) {
        return SAMPLE_LOG_STORAGE_READ_ONLY;
    }
    const uint32_t capacity =
        ring->sector_count * SAMPLE_LOG_RECORDS_PER_SECTOR;
    uint32_t near_full = capacity;
    if (ring->sector_count > 1u) {
        near_full = capacity - SAMPLE_LOG_RECORDS_PER_SECTOR;
    }
    return ring->count >= near_full ? SAMPLE_LOG_STORAGE_NEAR_FULL
                                    : SAMPLE_LOG_STORAGE_OK;
}

static log_flash_status_t mount_and_resolve_generation(log_flash_t *flash,
                                                       const log_io_t *io,
                                                       bool have_generation,
                                                       uint32_t generation) {
    const log_io_t io_copy = *io;
    sample_log_status_t status = log_ring_mount(
        &flash->ring, &io_copy, have_generation, generation);
    if (status == SAMPLE_LOG_ERR_IO) {
        return LOG_FLASH_ERR_IO;
    }
    if (status != SAMPLE_LOG_OK) {
        return LOG_FLASH_ERR_STATE;
    }
    if (have_generation) {
        return LOG_FLASH_OK;
    }

    log_ring_info_t info;
    log_ring_info(&flash->ring, &info);
    if (info.needs_format) {
        uint32_t fresh = 0;
        if (flash->hooks.new_generation(flash->hook_ctx, &fresh) != 0) {
            return LOG_FLASH_ERR_IO;
        }
        status = log_ring_format(&flash->ring, fresh);
        return status == SAMPLE_LOG_OK ? LOG_FLASH_OK : LOG_FLASH_ERR_STATE;
    }

    /* NVS was unreadable but the newest sector header restored the log.
     * Persist it before any append so the next boot keeps the same log. */
    if (flash->hooks.store_generation(flash->hook_ctx, info.generation) != 0) {
        return LOG_FLASH_ERR_IO;
    }
    return LOG_FLASH_OK;
}

log_flash_status_t log_flash_open(log_flash_t *flash, const log_io_t *io,
                                  const log_flash_hooks_t *hooks,
                                  void *hook_ctx) {
    if (flash == NULL || io == NULL || !hooks_complete(hooks)) {
        return LOG_FLASH_ERR_ARGUMENT;
    }

    memset(flash, 0, sizeof *flash);
    flash->hooks = *hooks;
    flash->hook_ctx = hook_ctx;
    flash->storage = SAMPLE_LOG_STORAGE_READ_ONLY;

    if (io->sector_size != SAMPLE_LOG_SECTOR_SIZE || io->capacity == 0 ||
        io->capacity % SAMPLE_LOG_SECTOR_SIZE != 0 ||
        io->capacity / SAMPLE_LOG_SECTOR_SIZE > SAMPLE_LOG_MAX_SECTORS) {
        return LOG_FLASH_ERR_ARGUMENT;
    }

    /* Give the ring its geometry before any I/O or clear sweep. The real mount
     * resets the bookkeeping but keeps this io/geometry copy. */
    flash->ring.io = *io;
    flash->ring.sector_count = io->capacity / SAMPLE_LOG_SECTOR_SIZE;

    if (hooks->clear_pending(hook_ctx)) {
        if (erase_nonblank_sectors(flash) != LOG_FLASH_OK) {
            set_read_only(flash);
            return LOG_FLASH_ERR_IO;
        }
        if (hooks->finish_clear(hook_ctx) != 0) {
            set_read_only(flash);
            return LOG_FLASH_ERR_IO;
        }
    }

    uint32_t generation = 0;
    bool have_generation =
        hooks->load_generation(hook_ctx, &generation) == 0;

    log_flash_status_t status =
        mount_and_resolve_generation(flash, io, have_generation, generation);
    if (status != LOG_FLASH_OK) {
        set_read_only(flash);
        return status;
    }

    flash->opened = true;
    flash->ready = true;
    flash->storage = state_for(&flash->ring);
    return LOG_FLASH_OK;
}

sample_log_status_t log_flash_append(log_flash_t *flash, sx4_sample_rec_t *rec) {
    if (flash == NULL || rec == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (!flash->ready ||
        flash->storage == SAMPLE_LOG_STORAGE_READ_ONLY) {
        return SAMPLE_LOG_ERR_STATE;
    }

    const sample_log_status_t status = log_ring_append(&flash->ring, rec);
    if (status == SAMPLE_LOG_ERR_IO) {
        /* esp_partition failed: never claim the record landed, and stay
         * unavailable until the next boot (design 07 storage overlay). */
        set_read_only(flash);
        return status;
    }
    if (status == SAMPLE_LOG_OK) {
        flash->storage = state_for(&flash->ring);
    }
    return status;
}

sample_log_status_t log_flash_read_seq(log_flash_t *flash, uint32_t seq,
                                       sx4_sample_rec_t *out) {
    if (flash == NULL || out == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (!flash->opened) {
        return SAMPLE_LOG_ERR_STATE;
    }
    const sample_log_status_t status = log_ring_read_seq(&flash->ring, seq, out);
    if (status == SAMPLE_LOG_ERR_IO) {
        set_read_only(flash);
    }
    return status;
}

bool log_flash_info(const log_flash_t *flash, log_ring_info_t *out) {
    if (flash == NULL || out == NULL || !flash->opened) {
        return false;
    }
    log_ring_info(&flash->ring, out);
    return true;
}

log_flash_status_t log_flash_clear(log_flash_t *flash) {
    if (flash == NULL) {
        return LOG_FLASH_ERR_ARGUMENT;
    }
    if (!flash->opened || flash->storage == SAMPLE_LOG_STORAGE_READ_ONLY) {
        return LOG_FLASH_ERR_STATE;
    }

    /* Stop appends while the ring is remounted. The caller serializes tasks. */
    flash->ready = false;

    uint32_t generation = 0;
    if (flash->hooks.begin_clear(flash->hook_ctx, &generation) != 0) {
        /* Nothing was erased and the old ring is still valid. */
        flash->ready = true;
        return LOG_FLASH_ERR_IO;
    }

    if (erase_nonblank_sectors(flash) != LOG_FLASH_OK) {
        /* Pending clear stays set: boot resumes and finishes the erase. */
        set_read_only(flash);
        return LOG_FLASH_ERR_IO;
    }
    if (flash->hooks.finish_clear(flash->hook_ctx) != 0) {
        set_read_only(flash);
        return LOG_FLASH_ERR_IO;
    }

    if (log_ring_format(&flash->ring, generation) != SAMPLE_LOG_OK) {
        set_read_only(flash);
        return LOG_FLASH_ERR_STATE;
    }
    flash->ready = true;
    flash->storage = state_for(&flash->ring);
    return LOG_FLASH_OK;
}
