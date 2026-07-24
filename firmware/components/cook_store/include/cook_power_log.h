/* cook_power_log — the persisted battery power log (follow-on to F12).
 *
 * /cooks/power.log, plain text so it can be pulled off the device and read
 * directly — the same discipline as cook_novelty_log. Battery is otherwise
 * live-only (/status.power, BLE live_state.soc_pct) and persisted nowhere,
 * so an offline brownout leaves no trace and the discharge curve is never
 * captured. This log fixes both: the last flushed line before a brownout is
 * the cause of death, and the whole run is a discharge curve. reset_reason
 * alone cannot do this — a battery brownout stays dead until USB is plugged,
 * and that power-on overwrites the brownout reason.
 *
 * One line per entry, space-separated, chosen to be greppable:
 *
 *     <uptime_s> <mv> <soc> <charging>     data:  e.g. "66120 3612 8 0"
 *     <uptime_s> BOOT <reason>             marker: e.g. "0 BOOT brownout"
 *
 * The second field distinguishes them: a decimal is a reading, the literal
 * BOOT is a power-cycle marker. `grep BOOT power.log` lists every boot, and
 * each marker sits directly after the last reading of the previous run, so
 * the log reads "…8% at 18h22m, then BOOT brownout" — the line that closes
 * the brownout question.
 *
 * Unlike the novelty ring (which pins the FIRST instance of each pair), this
 * is a plain FIFO: when it overflows its budget it evicts the OLDEST lines.
 * For brownout forensics the recent decline and the death point must
 * survive; losing the earliest lines is fine. Pure C11 over cook_vfs — the
 * device binding supplies the real uptime and reset-reason string.
 */
#ifndef COOK_POWER_LOG_H
#define COOK_POWER_LOG_H

#include <stdbool.h>
#include <stdint.h>

#include "cook_vfs.h"

#ifdef __cplusplus
extern "C" {
#endif

/* FIFO budget. At the 60 s append cadence (app_power throttles to that) a
 * 24 h run is 1440 lines of ~15 B each — ~23 KB — so a normal cook never
 * wraps. The caps bound multi-day runs; on overflow the log compacts down
 * to the newest COOK_POWER_KEEP_LINES, dropping the oldest. The line cap
 * governs in typical operation (2000 lines ≈ 32 KB, reached first); the
 * byte cap is the hard flash bound that also catches unusually long lines.
 * KEEP is below MAX so a compaction is not immediately re-triggered. */
#define COOK_POWER_MAX_LINES 2000u
#define COOK_POWER_MAX_BYTES (48u * 1024u)
#define COOK_POWER_KEEP_LINES 1500u

/* Adopts the existing file (counting its lines so the caps stay exact across
 * a remount) and appends a "<uptime_s> BOOT <reason>" marker. reset_reason is
 * the glue's mapped esp_reset_reason() string ("poweron", "brownout", …);
 * NULL logs "unknown". */
int cook_power_log_init(const cook_vfs_t *vfs, uint32_t uptime_s,
                        const char *reset_reason);

/* Appends one reading: "<uptime_s> <mv> <soc> <charging>". soc is the
 * BRIDGE_SOC_* percent (255 = unknown); charging is emitted as 0/1. Evicts
 * the oldest lines when the budget is exceeded. */
int cook_power_log_append(uint32_t uptime_s, uint16_t mv, uint8_t soc,
                          bool charging);

/* Streams the file in chunks to cb (the /debug/power endpoint); cb returns 0
 * to continue. A missing file streams nothing and returns OK. */
int cook_power_log_stream(int (*cb)(void *ctx, const char *data, size_t len),
                          void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* COOK_POWER_LOG_H */
