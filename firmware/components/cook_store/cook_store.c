/* cook_store — LittleFS mount + POSIX VFS binding (F5.5 device half).
 * Everything above the cook_vfs seam is host-tested; this file only maps
 * the seam onto the mounted filesystem. */
#include "cook_store.h"

#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "esp_littlefs.h"
#include "esp_log.h"

static const char *TAG = "cook_store";

#define COOKS_PARTITION "cooks"

static int vfs_open(void *ctx, const char *path, int flags) {
    (void)ctx;
    int oflags = O_RDONLY;
    if (flags == COOK_VFS_RDWR) {
        oflags = O_RDWR;
    } else if (flags == COOK_VFS_CREATE) {
        oflags = O_RDWR | O_CREAT | O_TRUNC;
    }
    return open(path, oflags, 0644);
}

static int vfs_close(void *ctx, int fd) {
    (void)ctx;
    return close(fd);
}

static long vfs_read(void *ctx, int fd, void *buf, size_t n) {
    (void)ctx;
    return (long)read(fd, buf, n);
}

static long vfs_write(void *ctx, int fd, const void *buf, size_t n) {
    (void)ctx;
    return (long)write(fd, buf, n);
}

static long vfs_seek(void *ctx, int fd, long off, int whence) {
    (void)ctx;
    return (long)lseek(fd, off, whence == COOK_VFS_END ? SEEK_END : SEEK_SET);
}

static int vfs_truncate(void *ctx, int fd, long len) {
    (void)ctx;
    return ftruncate(fd, len);
}

static int vfs_fsync(void *ctx, int fd) {
    (void)ctx;
    return fsync(fd);
}

static long vfs_size(void *ctx, int fd) {
    (void)ctx;
    struct stat st;
    if (fstat(fd, &st) != 0) {
        return -1;
    }
    return (long)st.st_size;
}

static int vfs_remove(void *ctx, const char *path) {
    (void)ctx;
    return unlink(path);
}

static int vfs_rename(void *ctx, const char *from, const char *to) {
    (void)ctx;
    return rename(from, to);
}

static int vfs_list(void *ctx, const char *dir,
                    void (*cb)(const char *name, void *u), void *u) {
    (void)ctx;
    DIR *d = opendir(dir);
    if (!d) {
        return -1;
    }
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_type != DT_DIR) {
            cb(e->d_name, u);
        }
    }
    closedir(d);
    return 0;
}

static int vfs_free_pct(void *ctx) {
    (void)ctx;
    size_t total = 0, used = 0;
    if (esp_littlefs_info(COOKS_PARTITION, &total, &used) != ESP_OK ||
        total == 0) {
        return 0; /* unknowable reads as full: fail safe, not silent */
    }
    return (int)(((total - used) * 100u) / total);
}

static const cook_vfs_t k_vfs = {
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

static void on_store_evt(cook_store_evt_t evt, uint32_t id, void *ctx) {
    (void)ctx;
    /* BRIDGE_EVENT wiring arrives with the F2/F3 glue; log for now. */
    ESP_LOGI(TAG, "store event %d, session %08X", (int)evt, (unsigned)id);
}

int cook_store_fs_info(uint32_t *total_b, uint32_t *used_b) {
    size_t total = 0, used = 0;
    if (esp_littlefs_info(COOKS_PARTITION, &total, &used) != ESP_OK) {
        return -1;
    }
    *total_b = (uint32_t)total;
    *used_b = (uint32_t)used;
    return 0;
}

int cook_store_init(void) {
    const esp_vfs_littlefs_conf_t conf = {
        .base_path = COOK_STORE_DIR,
        .partition_label = COOKS_PARTITION,
        .format_if_mount_failed = true,
        .dont_mount = false,
    };
    esp_err_t err = esp_vfs_littlefs_register(&conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "littlefs mount failed: %s", esp_err_to_name(err));
        return -1;
    }
    size_t total = 0, used = 0;
    if (esp_littlefs_info(COOKS_PARTITION, &total, &used) == ESP_OK) {
        ESP_LOGI(TAG, "/cooks mounted: %u KB used of %u KB",
                 (unsigned)(used / 1024), (unsigned)(total / 1024));
    }
    if (cook_novelty_log_init(&k_vfs) != COOK_STORE_OK) {
        ESP_LOGW(TAG, "novelty log init failed — continuing without it");
    }
    return cook_store_core_init(&k_vfs, on_store_evt, NULL) == COOK_STORE_OK
               ? 0
               : -1;
}
