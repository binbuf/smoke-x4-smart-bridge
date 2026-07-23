/* cook_novelty_log — the persisted novelty ring (F4.3, design 02 §2.7,
 * 04 §4.3): /cooks/novelty.log, partition-wide, plain text so it can be
 * pulled off the device and read directly.
 *
 * The FIRST instance of each distinct reason+value pair is pinned: when
 * the file exceeds its budget it compacts down to the pinned lines, so
 * later churn can never evict the evidence that mattered. Pure C11 over
 * cook_vfs. (The HTTP debug endpoints arrive with F9 in M2; the capture
 * half cannot be backfilled, which is why this runs now.)
 */
#ifndef COOK_NOVELTY_LOG_H
#define COOK_NOVELTY_LOG_H

#include <stdint.h>

#include "cook_vfs.h"

#ifdef __cplusplus
extern "C" {
#endif

#define COOK_NOVELTY_MAX_BYTES (64u * 1024u)
#define COOK_NOVELTY_MAX_LINES 512u

int cook_novelty_log_init(const cook_vfs_t *vfs);

/* Appends one line: "<t_ms> <reason> <value> <payload>". Compacts to the
 * pinned first-instances when the budget is exceeded. */
int cook_novelty_log_append(uint64_t t_ms, const char *reason,
                            const char *value, const char *payload);

/* Streams the file in chunks to cb (F4.5's /debug/novelty); cb returns 0
 * to continue. A missing file streams nothing and returns OK. */
int cook_novelty_log_stream(int (*cb)(void *ctx, const char *data,
                                      size_t len),
                            void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* COOK_NOVELTY_LOG_H */
