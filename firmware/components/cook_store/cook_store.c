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
#include "esp_partition.h"
#include "esp_system.h"
#include "esp_timer.h"

static const char *TAG = "cook_store";

#define COOKS_PARTITION "cooks"

/* The power log's boot marker carries the reset reason as a string; the pure
 * core stays ESP-IDF-free, so the mapping lives here in the glue. Kept in
 * step with app_api's reset_reason_name() (the /status spelling). */
static const char *reset_reason_str(void) {
    switch (esp_reset_reason()) {
        case ESP_RST_POWERON:
            return "poweron";
        case ESP_RST_SW:
            return "sw";
        case ESP_RST_PANIC:
            return "panic";
        case ESP_RST_WDT:
        case ESP_RST_INT_WDT:
        case ESP_RST_TASK_WDT:
            return "wdt";
        case ESP_RST_BROWNOUT:
            return "brownout";
        default:
            return "other";
    }
}

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

/* Has the `cooks` partition ever held a filesystem?
 *
 * Erased flash reads back as 0xFF. littlefs's superblock lives in the first
 * block, so an all-0xFF head means "never formatted" — the state every board
 * ships in, and the state `erase-flash` returns one to. Sampling the head is
 * enough: a formatted filesystem always writes a superblock there.
 *
 * Returns 1 blank, 0 formatted, -1 when the partition cannot be read at all
 * (treated as "not blank", so a read failure never triggers a format). */
static int cooks_partition_is_blank(void) {
    const esp_partition_t *part = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_ANY, COOKS_PARTITION);
    if (part == NULL) {
        return -1;
    }
    uint8_t head[64];
    if (esp_partition_read(part, 0, head, sizeof head) != ESP_OK) {
        return -1;
    }
    for (size_t i = 0; i < sizeof head; i++) {
        if (head[i] != 0xFF) {
            return 0;
        }
    }
    return 1;
}

int cook_store_init(void) {
    /* Format a blank partition BEFORE anything tries to mount it.
     *
     * This ordering is the whole fix, and it is not defensive programming —
     * it is a workaround for a crash that bricks a factory-fresh board.
     *
     * `esp_littlefs` mounts with `cfg.block_count = 0`, which asks littlefs to
     * recover the geometry from the superblock; `format_from_efs` sets a real
     * block count only for the duration of the format and zeroes it again
     * afterwards. On a blank partition there is no superblock to recover, the
     * mount fails (`Corrupted dir pair at {0x0, 0x1}`, LFS_ERR_CORRUPT/-84),
     * and it leaves the heap damaged on the way out: with comprehensive
     * poisoning enabled, free memory from 0x3fcedf50 up is overwritten with
     * 0xffffffff — erased-flash bytes read straight over the heap. The next
     * allocation then panics inside `tlsf_malloc` (StoreProhibited, EXCVADDR
     * 0x0000000b) and the board boot-loops forever, writing a core dump each
     * time round.
     *
     * Formatting first means that mount never happens, so the heap is never
     * damaged. Letting the component format *after* its own failed mount does
     * NOT work — tried, and it still crashes, because by then the damage is
     * done. Neither does aligning LITTLEFS_READ_SIZE/WRITE_SIZE to the page
     * size, and there is no newer component to upgrade to: 1.22.3 is current.
     *
     * The blank check is what keeps this safe. A partition that already holds
     * a filesystem is never formatted, so no cook is ever destroyed by this
     * path — and if the head cannot be read, the answer is "not blank". */
    const int blank = cooks_partition_is_blank();
    if (blank == 1) {
        ESP_LOGW(TAG, "/cooks is blank — formatting before first mount");
        const esp_err_t ferr = esp_littlefs_format(COOKS_PARTITION);
        if (ferr != ESP_OK) {
            ESP_LOGE(TAG, "littlefs format failed: %s", esp_err_to_name(ferr));
            return -1;
        }
    }

    /* `format_if_mount_failed` is deliberately FALSE, and this is the reason.
     *
     * A factory-fresh board — every board, out of the box, and any board after
     * `erase-flash` — has a blank `cooks` partition. littlefs then fails to
     * mount (`Corrupted dir pair at {0x0, 0x1}`, err -84) and the component
     * formats *from inside* `esp_littlefs_init`. On this target that path
     * corrupts the heap: with comprehensive poisoning on, free memory at
     * 0x3fcedf50 upward is overwritten with 0xffffffff — erased-flash bytes —
     * and the next allocation panics inside `tlsf_malloc` (StoreProhibited,
     * EXCVADDR 0x0000000b). The board then boot-loops forever, saving a core
     * dump each time.
     *
     * That is a bricked device out of the box, so this does not use the nested
     * path. Mount; if the mount fails, format through the standalone
     * `esp_littlefs_format` entry point and mount again. Formatting only ever
     * happens on a partition that would not mount, so no data is at risk —
     * and a second failure is reported rather than retried, because a board
     * that cannot make a filesystem must not spin. */
    const esp_vfs_littlefs_conf_t conf = {
        .base_path = COOK_STORE_DIR,
        .partition_label = COOKS_PARTITION,
        .format_if_mount_failed = false,
        .dont_mount = false,
    };
    esp_err_t err = esp_vfs_littlefs_register(&conf);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "/cooks did not mount (%s) — formatting once",
                 esp_err_to_name(err));
        err = esp_littlefs_format(COOKS_PARTITION);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "littlefs format failed: %s", esp_err_to_name(err));
            return -1;
        }
        err = esp_vfs_littlefs_register(&conf);
    }
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
    /* The boot marker's reason is what closes the brownout question across a
     * power cycle; the uptime here is a few seconds into boot. */
    const uint32_t boot_s =
        (uint32_t)((uint64_t)esp_timer_get_time() / 1000000ull);
    if (cook_power_log_init(&k_vfs, boot_s, reset_reason_str()) !=
        COOK_STORE_OK) {
        ESP_LOGW(TAG, "power log init failed — continuing without it");
    }
    return cook_store_core_init(&k_vfs, on_store_evt, NULL) == COOK_STORE_OK
               ? 0
               : -1;
}
