/* cook_vfs — the filesystem seam cook_store's core is written against.
 *
 * The device binding implements it over LittleFS' POSIX VFS; the host suite
 * implements it in memory. Everything interesting in cook_store — recovery,
 * retention, the streaming read — runs against this interface, which is
 * what makes the truncate-at-every-offset test (F5.3) possible at all.
 */
#ifndef COOK_VFS_H
#define COOK_VFS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    COOK_VFS_RDONLY = 0,
    COOK_VFS_RDWR = 1,        /* existing file */
    COOK_VFS_CREATE = 2,      /* create empty, read+write */
};

enum { COOK_VFS_SET = 0, COOK_VFS_END = 2 };

typedef struct {
    void *ctx;
    /* fd ≥ 0 on success, < 0 on failure/missing. */
    int (*open)(void *ctx, const char *path, int flags);
    int (*close)(void *ctx, int fd);
    long (*read)(void *ctx, int fd, void *buf, size_t n);
    long (*write)(void *ctx, int fd, const void *buf, size_t n);
    long (*seek)(void *ctx, int fd, long off, int whence);
    int (*truncate)(void *ctx, int fd, long len);
    int (*fsync)(void *ctx, int fd);
    long (*size)(void *ctx, int fd);
    int (*remove)(void *ctx, const char *path);
    int (*rename)(void *ctx, const char *from, const char *to);
    /* Calls cb once per file name (no directories) in `dir`. */
    int (*list)(void *ctx, const char *dir,
                void (*cb)(const char *name, void *u), void *u);
    /* Free space, whole percent 0..100. */
    int (*free_pct)(void *ctx);
} cook_vfs_t;

#ifdef __cplusplus
}
#endif

#endif /* COOK_VFS_H */
