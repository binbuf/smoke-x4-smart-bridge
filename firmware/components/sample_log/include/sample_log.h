/*
 * sample_log.h - raw sample-ring lifecycle (design 03 sections 3.4, 3.5.4,
 * 3.6, design 04 section 4.3).
 *
 * The public surface binds the pure ring (T18) to the raw `samples` partition
 * (T19). Boot calls sample_log_init() before the radio starts; the writer then
 * calls sample_log_append() with a decoded record. Storage state is part of the
 * API so the UI, stats and BLE never have to guess whether recording works.
 *
 * This header is firmware-only: it pulls in the ESP-IDF error type. The ring
 * core and recovery policy stay in plain C (log_core.h, log_flash.h).
 */
#ifndef SX4_SAMPLE_LOG_H
#define SX4_SAMPLE_LOG_H

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "log_core.h"
#include "log_storage.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Storage state for the UI and stats (design 03 section 3.5.4).
 *
 * SAMPLE_LOG_STORAGE_OK        normal recording; rotation is normal and stays OK.
 * SAMPLE_LOG_STORAGE_NEAR_FULL diagnostic only: within one sector of capacity.
 *                              Rotation always frees the oldest sector, so this
 *                              is practically unreachable; never an error.
 * SAMPLE_LOG_STORAGE_READ_ONLY an esp_partition read/write/erase failed or the
 *                              ring could not be mounted. Persistent until the
 *                              next boot; storage_ok must be 0.
 *
 * The enum and SAMPLE_LOG_NEAR_FULL_RECORDS live in log_storage.h so the pure
 * recovery core can report them too.
 */

/*
 * Mount the raw `samples` partition and recover the ring. Runs before the
 * writer accepts records. Reads the NVS generation and finishes a pending
 * clear. Failure is not fatal: the bridge reports "storage unavailable" and
 * keeps showing live values.
 */
esp_err_t sample_log_init(void);

/* True when the ring accepted records and no storage failure has happened. */
bool sample_log_ready(void);

/* Current storage state; READ_ONLY after an unrecoverable flash failure. */
sample_log_storage_state_t sample_log_storage_state(void);

/* Convenience for `stats.flags.storage_ok` / `live.flags.storage_ok`: false
 * only for READ_ONLY. NEAR_FULL still records. */
bool sample_log_storage_ok(void);

/*
 * Append one sample. The ring assigns rec->seq. Returns ESP_FAIL for a flash
 * failure (storage becomes READ_ONLY and no success is reported), ESP_ERR_INVALID_ARG
 * for a bad record, ESP_ERR_INVALID_STATE when not mounted/failed, or ESP_OK.
 *
 * On ESP_FAIL the in-flight record is lost; callers must not retry into the
 * same failed mount (reboot recovery is the retry path).
 */
esp_err_t sample_log_append(sx4_sample_rec_t *rec);

/* Read one committed record by sequence, re-checking CRC/layout. */
esp_err_t sample_log_read_seq(uint32_t seq, sx4_sample_rec_t *out);

/* Bookkeeping snapshot for stats/sync (no flash I/O). */
bool sample_log_get_info(log_ring_info_t *out);

/* Boot recovery duration and sectors erased finishing a pending clear. */
uint32_t sample_log_recovery_ms(void);
uint32_t sample_log_cleared_sectors(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SAMPLE_LOG_H */
