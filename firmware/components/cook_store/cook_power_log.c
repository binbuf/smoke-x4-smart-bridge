/* cook_power_log — persisted battery power log, FIFO ring (follow-on to
 * F12). Mirrors cook_novelty_log's shape over cook_vfs, but evicts the
 * OLDEST lines rather than pinning first-instances. See the header for the
 * line format and why this exists. */
#include "cook_power_log.h"

#include <stdio.h>
#include <string.h>

#include "cook_store_core.h" /* COOK_STORE_DIR, error codes */

#define LOG_PATH COOK_STORE_DIR "/power.log"
#define TMP_PATH COOK_STORE_DIR "/power.tmp"
/* "<10-digit uptime> <5-digit mv> <3-digit soc> <1> \n" and the boot
 * marker "<uptime> BOOT <reason>" both fit comfortably here. */
#define MAX_LINE 64

static const cook_vfs_t *s_vfs;
static uint32_t s_line_count; /* true count of lines in LOG_PATH */

/* Counts '\n' bytes in the open file from its current position to EOF. */
static uint32_t count_lines(int fd) {
    uint32_t lines = 0;
    char buf[256];
    long n;
    while ((n = s_vfs->read(s_vfs->ctx, fd, buf, sizeof buf)) > 0) {
        for (long i = 0; i < n; i++) {
            if (buf[i] == '\n') {
                lines++;
            }
        }
    }
    return lines;
}

int cook_power_log_init(const cook_vfs_t *vfs, uint32_t uptime_s,
                        const char *reset_reason) {
    if (!vfs) {
        return COOK_STORE_ERR;
    }
    s_vfs = vfs;

    /* Seed the line count from any file left by a previous boot, so the caps
     * stay exact across a remount and the pre-brownout history is retained. */
    s_line_count = 0;
    const int fd = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_RDONLY);
    if (fd >= 0) {
        s_line_count = count_lines(fd);
        s_vfs->close(s_vfs->ctx, fd);
    }

    char marker[MAX_LINE];
    const int len = snprintf(marker, sizeof marker, "%lu BOOT %s\n",
                             (unsigned long)uptime_s,
                             reset_reason ? reset_reason : "unknown");
    if (len < 0) {
        return COOK_STORE_ERR;
    }
    const size_t wlen =
        (size_t)len < sizeof marker - 1 ? (size_t)len : sizeof marker - 1;

    int wfd = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_RDWR);
    if (wfd < 0) {
        wfd = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_CREATE);
    }
    if (wfd < 0) {
        return COOK_STORE_ERR;
    }
    int rc = COOK_STORE_ERR;
    if (s_vfs->seek(s_vfs->ctx, wfd, 0, COOK_VFS_END) >= 0 &&
        s_vfs->write(s_vfs->ctx, wfd, marker, wlen) == (long)wlen &&
        s_vfs->fsync(s_vfs->ctx, wfd) == 0) {
        s_line_count++;
        rc = COOK_STORE_OK;
    }
    s_vfs->close(s_vfs->ctx, wfd);
    return rc;
}

/* Rewrites the log keeping only its newest COOK_POWER_KEEP_LINES lines,
 * evicting the oldest. Two streaming passes: count, then byte-copy the tail
 * (exact bytes, so the format round-trips untouched). */
static int compact(void) {
    int in = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_RDONLY);
    if (in < 0) {
        return COOK_STORE_ERR;
    }
    const uint32_t total = count_lines(in);
    const uint32_t skip =
        total > COOK_POWER_KEEP_LINES ? total - COOK_POWER_KEEP_LINES : 0;
    if (skip == 0) {
        s_line_count = total;
        s_vfs->close(s_vfs->ctx, in);
        return COOK_STORE_OK; /* nothing old enough to evict */
    }
    if (s_vfs->seek(s_vfs->ctx, in, 0, COOK_VFS_SET) < 0) {
        s_vfs->close(s_vfs->ctx, in);
        return COOK_STORE_ERR;
    }
    const int out = s_vfs->open(s_vfs->ctx, TMP_PATH, COOK_VFS_CREATE);
    if (out < 0) {
        s_vfs->close(s_vfs->ctx, in);
        return COOK_STORE_ERR;
    }

    uint32_t line_idx = 0; /* index of the line the current byte belongs to */
    char buf[256];
    long n;
    int rc = COOK_STORE_OK;
    while ((n = s_vfs->read(s_vfs->ctx, in, buf, sizeof buf)) > 0) {
        long seg = 0; /* start of the not-yet-flushed run in buf */
        for (long i = 0; i < n; i++) {
            if (buf[i] != '\n') {
                continue;
            }
            if (line_idx >= skip) {
                const long l = i - seg + 1; /* include the newline */
                if (s_vfs->write(s_vfs->ctx, out, buf + seg, (size_t)l) != l) {
                    rc = COOK_STORE_ERR;
                }
            }
            line_idx++;
            seg = i + 1;
        }
        /* A line that straddles this buffer boundary: flush its tail now if
         * it belongs to a kept line; line_idx only advances on the newline. */
        if (seg < n && line_idx >= skip) {
            const long l = n - seg;
            if (s_vfs->write(s_vfs->ctx, out, buf + seg, (size_t)l) != l) {
                rc = COOK_STORE_ERR;
            }
        }
    }
    s_vfs->fsync(s_vfs->ctx, out);
    s_vfs->close(s_vfs->ctx, out);
    s_vfs->close(s_vfs->ctx, in);
    if (rc == COOK_STORE_OK) {
        s_vfs->remove(s_vfs->ctx, LOG_PATH);
        if (s_vfs->rename(s_vfs->ctx, TMP_PATH, LOG_PATH) == 0) {
            s_line_count = total - skip;
        } else {
            rc = COOK_STORE_ERR;
        }
    }
    return rc;
}

int cook_power_log_append(uint32_t uptime_s, uint16_t mv, uint8_t soc,
                          bool charging) {
    if (!s_vfs) {
        return COOK_STORE_ERR;
    }
    char line[MAX_LINE];
    const int len = snprintf(line, sizeof line, "%lu %u %u %u\n",
                             (unsigned long)uptime_s, (unsigned)mv,
                             (unsigned)soc, charging ? 1u : 0u);
    if (len < 0) {
        return COOK_STORE_ERR;
    }
    const size_t wlen =
        (size_t)len < sizeof line - 1 ? (size_t)len : sizeof line - 1;

    int fd = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_RDWR);
    if (fd < 0) {
        fd = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_CREATE);
    }
    if (fd < 0) {
        return COOK_STORE_ERR;
    }
    int rc = COOK_STORE_ERR;
    long size = -1;
    if (s_vfs->seek(s_vfs->ctx, fd, 0, COOK_VFS_END) >= 0 &&
        s_vfs->write(s_vfs->ctx, fd, line, wlen) == (long)wlen &&
        s_vfs->fsync(s_vfs->ctx, fd) == 0) {
        rc = COOK_STORE_OK;
        size = s_vfs->size(s_vfs->ctx, fd);
        s_line_count++;
    }
    s_vfs->close(s_vfs->ctx, fd);

    if (rc == COOK_STORE_OK &&
        (size > (long)COOK_POWER_MAX_BYTES ||
         s_line_count > COOK_POWER_MAX_LINES)) {
        rc = compact();
    }
    return rc;
}

int cook_power_log_stream(int (*cb)(void *ctx, const char *data, size_t len),
                          void *ctx) {
    if (!s_vfs || !cb) {
        return COOK_STORE_ERR;
    }
    const int fd = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_RDONLY);
    if (fd < 0) {
        return COOK_STORE_OK; /* nothing captured yet */
    }
    char buf[512];
    long n;
    while ((n = s_vfs->read(s_vfs->ctx, fd, buf, sizeof buf)) > 0) {
        if (cb(ctx, buf, (size_t)n) != 0) {
            break;
        }
    }
    s_vfs->close(s_vfs->ctx, fd);
    return COOK_STORE_OK;
}
