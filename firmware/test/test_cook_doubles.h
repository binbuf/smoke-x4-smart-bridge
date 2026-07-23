/* test_cook_doubles.h — shared doubles for the cook_store host suites: the
 * in-memory app_config backend and a malloc-backed cook_vfs with fault/
 * accounting hooks (fsync counter, read counter, controllable free_pct). */
#ifndef TEST_COOK_DOUBLES_H
#define TEST_COOK_DOUBLES_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app_config_store.h"
#include "cook_vfs.h"

/* ── app_config in-memory backend ─────────────────────────────────────── */

typedef struct {
    char ns[16];
    char key[16];
    size_t len;
    uint8_t val[80];
} cfg_entry_t;

static struct {
    cfg_entry_t entries[64];
    int count;
} g_cfg;

static cfg_entry_t *cfg_find(const char *ns, const char *key) {
    for (int i = 0; i < g_cfg.count; i++) {
        if (strcmp(g_cfg.entries[i].ns, ns) == 0 &&
            strcmp(g_cfg.entries[i].key, key) == 0) {
            return &g_cfg.entries[i];
        }
    }
    return NULL;
}

static int cfg_get(void *ctx, const char *ns, const char *key, void *out,
                   size_t *len) {
    (void)ctx;
    cfg_entry_t *e = cfg_find(ns, key);
    if (!e) {
        return APP_CONFIG_ERR_NOT_FOUND;
    }
    if (!out) {
        *len = e->len;
        return APP_CONFIG_OK;
    }
    if (*len < e->len) {
        return APP_CONFIG_ERR;
    }
    memcpy(out, e->val, e->len);
    *len = e->len;
    return APP_CONFIG_OK;
}

static int cfg_set(void *ctx, const char *ns, const char *key,
                   const void *val, size_t len) {
    (void)ctx;
    cfg_entry_t *e = cfg_find(ns, key);
    if (!e) {
        e = &g_cfg.entries[g_cfg.count++];
        snprintf(e->ns, sizeof e->ns, "%s", ns);
        snprintf(e->key, sizeof e->key, "%s", key);
    }
    memcpy(e->val, val, len);
    e->len = len;
    return APP_CONFIG_OK;
}

static int cfg_erase_all(void *ctx) {
    (void)ctx;
    g_cfg.count = 0;
    return APP_CONFIG_OK;
}

static const app_config_backend_t g_cfg_backend = {
    .get = cfg_get, .set = cfg_set, .erase_all = cfg_erase_all, .ctx = NULL};

static uint32_t cfg_rng(void) { return 7u; }

/* ── malloc-backed VFS ────────────────────────────────────────────────── */

#define MEMFS_MAX_FILES 80
#define MEMFS_MAX_FDS 16

typedef struct {
    char name[64];
    uint8_t *data;
    size_t len;
    size_t cap;
    int used;
} mem_file_t;

typedef struct {
    mem_file_t *file;
    size_t pos;
    int used;
} mem_fd_t;

static mem_file_t g_files[MEMFS_MAX_FILES];
static mem_fd_t g_fds[MEMFS_MAX_FDS];
static int g_free_pct = 90;   /* controllable per test */
static int g_fsync_calls;
static int g_read_calls;

static void memfs_reset(void) {
    for (int i = 0; i < MEMFS_MAX_FILES; i++) {
        if (g_files[i].used) {
            free(g_files[i].data);
        }
    }
    memset(g_files, 0, sizeof g_files);
    memset(g_fds, 0, sizeof g_fds);
    g_free_pct = 90;
    g_fsync_calls = 0;
    g_read_calls = 0;
}

static mem_file_t *memfs_find(const char *path) {
    for (int i = 0; i < MEMFS_MAX_FILES; i++) {
        if (g_files[i].used && strcmp(g_files[i].name, path) == 0) {
            return &g_files[i];
        }
    }
    return NULL;
}

static mem_file_t *memfs_create(const char *path) {
    mem_file_t *f = memfs_find(path);
    if (f) {
        f->len = 0;
        return f;
    }
    for (int i = 0; i < MEMFS_MAX_FILES; i++) {
        if (!g_files[i].used) {
            f = &g_files[i];
            memset(f, 0, sizeof *f);
            snprintf(f->name, sizeof f->name, "%s", path);
            f->used = 1;
            return f;
        }
    }
    return NULL;
}

/* Direct fixture injection for tests that hand-craft files. */
static __attribute__((unused)) mem_file_t *memfs_put(const char *path,
                                                     const void *data,
                                                     size_t len) {
    mem_file_t *f = memfs_create(path);
    if (!f) {
        return NULL;
    }
    f->data = realloc(f->data, len ? len : 1);
    memcpy(f->data, data, len);
    f->len = len;
    f->cap = len;
    return f;
}

static int vfs_open(void *ctx, const char *path, int flags) {
    (void)ctx;
    mem_file_t *f =
        (flags == COOK_VFS_CREATE) ? memfs_create(path) : memfs_find(path);
    if (!f) {
        return -1;
    }
    for (int i = 0; i < MEMFS_MAX_FDS; i++) {
        if (!g_fds[i].used) {
            g_fds[i].file = f;
            g_fds[i].pos = 0;
            g_fds[i].used = 1;
            return i;
        }
    }
    return -1;
}

static int vfs_close(void *ctx, int fd) {
    (void)ctx;
    if (fd < 0 || fd >= MEMFS_MAX_FDS || !g_fds[fd].used) {
        return -1;
    }
    g_fds[fd].used = 0;
    return 0;
}

static long vfs_read(void *ctx, int fd, void *buf, size_t n) {
    (void)ctx;
    if (fd < 0 || fd >= MEMFS_MAX_FDS || !g_fds[fd].used) {
        return -1;
    }
    g_read_calls++;
    mem_fd_t *d = &g_fds[fd];
    size_t avail = d->file->len > d->pos ? d->file->len - d->pos : 0;
    if (n > avail) {
        n = avail;
    }
    memcpy(buf, d->file->data + d->pos, n);
    d->pos += n;
    return (long)n;
}

static long vfs_write(void *ctx, int fd, const void *buf, size_t n) {
    (void)ctx;
    if (fd < 0 || fd >= MEMFS_MAX_FDS || !g_fds[fd].used) {
        return -1;
    }
    mem_fd_t *d = &g_fds[fd];
    mem_file_t *f = d->file;
    const size_t end = d->pos + n;
    if (end > f->cap) {
        size_t cap = f->cap ? f->cap * 2 : 1024;
        while (cap < end) {
            cap *= 2;
        }
        f->data = realloc(f->data, cap);
        f->cap = cap;
    }
    memcpy(f->data + d->pos, buf, n);
    d->pos = end;
    if (end > f->len) {
        f->len = end;
    }
    return (long)n;
}

static long vfs_seek(void *ctx, int fd, long off, int whence) {
    (void)ctx;
    if (fd < 0 || fd >= MEMFS_MAX_FDS || !g_fds[fd].used) {
        return -1;
    }
    mem_fd_t *d = &g_fds[fd];
    long target = (whence == COOK_VFS_END) ? (long)d->file->len + off : off;
    if (target < 0) {
        return -1;
    }
    d->pos = (size_t)target;
    return target;
}

static int vfs_truncate(void *ctx, int fd, long len) {
    (void)ctx;
    if (fd < 0 || fd >= MEMFS_MAX_FDS || !g_fds[fd].used || len < 0) {
        return -1;
    }
    if ((size_t)len < g_fds[fd].file->len) {
        g_fds[fd].file->len = (size_t)len;
    }
    return 0;
}

static int vfs_fsync(void *ctx, int fd) {
    (void)ctx;
    (void)fd;
    g_fsync_calls++;
    return 0;
}

static long vfs_size(void *ctx, int fd) {
    (void)ctx;
    if (fd < 0 || fd >= MEMFS_MAX_FDS || !g_fds[fd].used) {
        return -1;
    }
    return (long)g_fds[fd].file->len;
}

static int vfs_remove(void *ctx, const char *path) {
    (void)ctx;
    mem_file_t *f = memfs_find(path);
    if (!f) {
        return -1;
    }
    free(f->data);
    memset(f, 0, sizeof *f);
    return 0;
}

static int vfs_rename(void *ctx, const char *from, const char *to) {
    (void)ctx;
    mem_file_t *f = memfs_find(from);
    if (!f) {
        return -1;
    }
    snprintf(f->name, sizeof f->name, "%s", to);
    return 0;
}

static int vfs_list(void *ctx, const char *dir,
                    void (*cb)(const char *name, void *u), void *u) {
    (void)ctx;
    const size_t dlen = strlen(dir);
    for (int i = 0; i < MEMFS_MAX_FILES; i++) {
        if (g_files[i].used && strncmp(g_files[i].name, dir, dlen) == 0 &&
            g_files[i].name[dlen] == '/') {
            cb(g_files[i].name + dlen + 1, u);
        }
    }
    return 0;
}

static int vfs_free_pct(void *ctx) {
    (void)ctx;
    return g_free_pct;
}

static const cook_vfs_t g_vfs = {
    .ctx = NULL,
    .open = vfs_open,
    .close = vfs_close,
    .read = vfs_read,
    .write = vfs_write,
    .seek = vfs_seek,
    .truncate = vfs_truncate,
    .fsync = vfs_fsync,
    .size = vfs_size,
    .remove = vfs_remove,
    .rename = vfs_rename,
    .list = vfs_list,
    .free_pct = vfs_free_pct,
};

#endif /* TEST_COOK_DOUBLES_H */
