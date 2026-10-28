/*
 * log_flash.h - boot recovery and clear policy for the raw sample ring (T19).
 *
 * This layer sits between the pure ring (log_core.h) and the storage byte seam
 * (log_io.h). It owns the boot decisions that are not geometry:
 *
 *   - mount with the NVS generation, or adopt/regenerate it when NVS is lost;
 *   - finish an interrupted clear by erasing every non-blank sector;
 *   - append through the ring and turn transport failures into READ_ONLY;
 *   - report OK / NEAR_FULL / READ_ONLY for the UI and stats.
 *
 * It is plain C11 over `log_io` and a small NVS hook seam, so host tests run it
 * against the RAM fake. The ESP-IDF partition adapter lives in log_flash.c.
 */
#ifndef SX4_LOG_FLASH_H
#define SX4_LOG_FLASH_H

#include <stdbool.h>
#include <stdint.h>

#include "log_core.h"
#include "log_storage.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LOG_FLASH_OK = 0,
    LOG_FLASH_ERR_ARGUMENT = -1,
    LOG_FLASH_ERR_IO = -2,     /* read/write/erase or NVS hook failure */
    LOG_FLASH_ERR_STATE = -3,  /* no generation and none recoverable */
} log_flash_status_t;

/*
 * NVS seam. Every callback returns 0 on success, non-zero on failure.
 * `load_generation` may fail when NVS is unreadable; the core then tries to
 * adopt the newest sector header. `new_generation` must persist before it
 * returns, so the erase that follows can never resurrect old records.
 *
 * `begin_clear` is the runtime clear (T48): persist the new generation and
 * `clear_pending` before the caller erases anything. `finish_clear` clears the
 * flag after the erase completed. `new_generation` is the boot-time "blank log"
 * path and does not set `clear_pending`.
 */
typedef struct {
    int (*load_generation)(void *ctx, uint32_t *out);
    int (*store_generation)(void *ctx, uint32_t generation);
    int (*new_generation)(void *ctx, uint32_t *out);
    int (*begin_clear)(void *ctx, uint32_t *out);
    bool (*clear_pending)(void *ctx);
    int (*finish_clear)(void *ctx);
} log_flash_hooks_t;

typedef struct {
    log_ring_t ring;
    log_flash_hooks_t hooks;
    void *hook_ctx;
    sample_log_storage_state_t storage;
    bool ready;
    bool opened;
    uint32_t recovery_ms;    /* filled by the firmware adapter */
    uint32_t erased_sectors; /* sectors erased finishing a pending clear */
} log_flash_t;

/*
 * Mount and recover. `io` must outlive the log_flash_t (the ring copies it).
 *
 * A pending clear is completed synchronously before the ring is mounted: the
 * writer has not started, so no current-generation records can exist and every
 * non-blank sector is old data. Already-blank sectors are skipped so a clear
 * interrupted by power loss resumes with only the remaining erase work.
 *
 * A storage failure leaves storage == READ_ONLY and ready == false.
 */
log_flash_status_t log_flash_open(log_flash_t *flash, const log_io_t *io,
                                  const log_flash_hooks_t *hooks,
                                  void *hook_ctx);

/* Append; a transport failure flips the log to READ_ONLY and is never
 * reported as success. Non-I/O record errors leave the state unchanged. */
sample_log_status_t log_flash_append(log_flash_t *flash, sx4_sample_rec_t *rec);

/* Read one record. An I/O failure also flips the log to READ_ONLY. */
sample_log_status_t log_flash_read_seq(log_flash_t *flash, uint32_t seq,
                                       sx4_sample_rec_t *out);

/* No-I/O bookkeeping snapshot. Returns false when never opened. */
bool log_flash_info(const log_flash_t *flash, log_ring_info_t *out);

/*
 * Runtime `clear_history` (T48): persist a new random generation and
 * `clear_pending`, erase every non-blank sector, clear the pending flag, and
 * restart the ring empty with the new generation. Pairing and config live in
 * other namespaces and are untouched.
 *
 * Appends must be serialized with this call (the firmware singleton owns a
 * mutex). A failed begin leaves the old generation/ring usable; a failed erase
 * parks the log READ_ONLY until the next boot, where the pending clear resumes.
 */
log_flash_status_t log_flash_clear(log_flash_t *flash);

#ifdef ESP_PLATFORM
#include "esp_err.h"
/* Open the raw `samples` partition with the bridge_config NVS hooks and a
 * sector-cached esp_partition byte seam. Measures recovery time into
 * flash->recovery_ms. */
esp_err_t log_flash_open_partition(log_flash_t *flash);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_LOG_FLASH_H */
