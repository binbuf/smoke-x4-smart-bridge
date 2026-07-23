/* cook_novelty_log — persisted pinned novelty ring (F4.3). */
#include "cook_novelty_log.h"

#include <stdio.h>
#include <string.h>

#include "cook_store_core.h" /* COOK_STORE_DIR, error codes */

#define LOG_PATH COOK_STORE_DIR "/novelty.log"
#define TMP_PATH COOK_STORE_DIR "/novelty.tmp"
#define MAX_LINE 200
#define MAX_PINNED 128

static const cook_vfs_t *s_vfs;
static uint32_t s_lines_since_check;

typedef struct {
    char reason[12];
    char value[24];
} pin_key_t;

int cook_novelty_log_init(const cook_vfs_t *vfs) {
    if (!vfs) {
        return COOK_STORE_ERR;
    }
    s_vfs = vfs;
    s_lines_since_check = 0;
    return COOK_STORE_OK;
}

/* Extracts fields 2 and 3 (reason, value) from a log line. */
static int line_key(const char *line, pin_key_t *key) {
    const char *p = strchr(line, ' '); /* skip t_ms */
    if (!p) {
        return -1;
    }
    p++;
    const char *reason_end = strchr(p, ' ');
    if (!reason_end || (size_t)(reason_end - p) >= sizeof key->reason) {
        return -1;
    }
    memcpy(key->reason, p, (size_t)(reason_end - p));
    key->reason[reason_end - p] = '\0';
    p = reason_end + 1;
    const char *value_end = strchr(p, ' ');
    if (!value_end) {
        value_end = p + strlen(p);
    }
    size_t vlen = (size_t)(value_end - p);
    if (vlen >= sizeof key->value) {
        vlen = sizeof key->value - 1;
    }
    memcpy(key->value, p, vlen);
    key->value[vlen] = '\0';
    return 0;
}

/* Streams the log through a line-splitting window, keeping only the first
 * instance of each reason+value pair — the pinned evidence. */
static int compact(void) {
    static pin_key_t seen[MAX_PINNED];
    int seen_count = 0;

    const int in = s_vfs->open(s_vfs->ctx, LOG_PATH, COOK_VFS_RDONLY);
    if (in < 0) {
        return COOK_STORE_ERR;
    }
    const int out = s_vfs->open(s_vfs->ctx, TMP_PATH, COOK_VFS_CREATE);
    if (out < 0) {
        s_vfs->close(s_vfs->ctx, in);
        return COOK_STORE_ERR;
    }

    char carry[MAX_LINE + 1];
    size_t carry_len = 0;
    char buf[256];
    long n;
    int rc = COOK_STORE_OK;
    while ((n = s_vfs->read(s_vfs->ctx, in, buf, sizeof buf)) > 0) {
        for (long i = 0; i < n; i++) {
            const char c = buf[i];
            if (c != '\n') {
                if (carry_len < MAX_LINE) {
                    carry[carry_len++] = c;
                }
                continue;
            }
            carry[carry_len] = '\0';
            pin_key_t key;
            if (carry_len > 0 && line_key(carry, &key) == 0) {
                bool dup = false;
                for (int k = 0; k < seen_count; k++) {
                    if (strcmp(seen[k].reason, key.reason) == 0 &&
                        strcmp(seen[k].value, key.value) == 0) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) {
                    if (seen_count < MAX_PINNED) {
                        seen[seen_count++] = key;
                    }
                    carry[carry_len] = '\n';
                    if (s_vfs->write(s_vfs->ctx, out, carry, carry_len + 1) !=
                        (long)(carry_len + 1)) {
                        rc = COOK_STORE_ERR;
                    }
                }
            }
            carry_len = 0;
        }
    }
    s_vfs->fsync(s_vfs->ctx, out);
    s_vfs->close(s_vfs->ctx, out);
    s_vfs->close(s_vfs->ctx, in);
    if (rc == COOK_STORE_OK) {
        s_vfs->remove(s_vfs->ctx, LOG_PATH);
        rc = s_vfs->rename(s_vfs->ctx, TMP_PATH, LOG_PATH) == 0
                 ? COOK_STORE_OK
                 : COOK_STORE_ERR;
    }
    return rc;
}

int cook_novelty_log_append(uint64_t t_ms, const char *reason,
                            const char *value, const char *payload) {
    if (!s_vfs || !reason || !value) {
        return COOK_STORE_ERR;
    }
    char line[MAX_LINE + 2];
    const int len =
        snprintf(line, sizeof line, "%llu %s %s %s\n",
                 (unsigned long long)t_ms, reason, value,
                 payload ? payload : "");
    if (len < 0) {
        return COOK_STORE_ERR;
    }
    const size_t wlen = (size_t)len < sizeof line - 1 ? (size_t)len
                                                      : sizeof line - 1;

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
    }
    s_vfs->close(s_vfs->ctx, fd);

    s_lines_since_check++;
    if (rc == COOK_STORE_OK &&
        (size > (long)COOK_NOVELTY_MAX_BYTES ||
         s_lines_since_check > COOK_NOVELTY_MAX_LINES)) {
        s_lines_since_check = 0;
        rc = compact();
    }
    return rc;
}
