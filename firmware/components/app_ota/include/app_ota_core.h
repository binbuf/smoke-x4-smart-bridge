/* app_ota_core — the OTA upload path as a pure core (F14.1, F14.2).
 *
 * No ESP-IDF, no allocation, no globals a test cannot reach. Everything
 * that decides — whether an upload is admitted, whether the bytes are a
 * firmware image at all, how far along it is, and what phase to report —
 * runs on the host. The IDF glue supplies four functions that touch flash
 * and one that reboots.
 *
 * Why the image is inspected BEFORE a byte reaches flash (design 06 §6.2,
 * decisions in docs/tasks/M6-hardening-and-release.md): the likeliest
 * mis-upload is not a corrupt file, it is the WRONG ONE OF THE TWO FILES
 * THIS PROJECT SHIPS — the merged image (flashable at 0x0, starts with the
 * bootloader) instead of the app-only OTA image. Writing the merged image
 * into an OTA slot produces a board that does not boot, and there is no
 * second board (§12.6 rule 8).
 */
#ifndef APP_OTA_CORE_H
#define APP_OTA_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* esp_image_header_t (24 B) + esp_image_segment_header_t (8 B) +
 * esp_app_desc_t's first 256 B. Offsets below are read off a real build,
 * not off a struct definition — protocol/fixtures/ota/ carries the first
 * 288 bytes of the actual heltec-v3 image, of bootloader.bin, and of
 * partition-table.bin, and the tests parse those. */
#define APP_OTA_HEADER_MIN 288u
#define APP_OTA_CHIP_ID_ESP32S3 0x0009u

typedef enum {
    APP_OTA_IMG_OK = 0,
    /* Fewer than APP_OTA_HEADER_MIN bytes so far: the caller is streaming
     * and must be able to ask again, not reject an upload that has barely
     * started. */
    APP_OTA_IMG_UNDECIDED,
    APP_OTA_IMG_BAD_MAGIC,    /* not an ESP image at all */
    APP_OTA_IMG_WRONG_CHIP,   /* an image for a different part */
    APP_OTA_IMG_NO_APP_DESC,  /* the merged image, or bootloader.bin */
} app_ota_img_verdict_t;

typedef struct {
    app_ota_img_verdict_t verdict;
    uint16_t chip_id;
    /* Read and REPORTED, never enforced: a fork that renames its CMake
     * project should not be locked out of its own hardware. The SHA-256,
     * the rollback gate and rule 8 are the real protections. */
    char version[33];
    char project[33];
    char idf_ver[33];
} app_ota_image_info_t;

/* Inspects the first bytes of an upload. `out` is always filled (zeroed
 * first), so a caller may report the strings even on a verdict it
 * refuses. Returns the verdict, which is also in out->verdict. */
app_ota_img_verdict_t app_ota_image_inspect(const void *buf, size_t len,
                                            app_ota_image_info_t *out);

/* A short, distinct reason per verdict. "invalid image" with no detail is
 * what makes a support conversation take an hour. */
const char *app_ota_image_verdict_str(app_ota_img_verdict_t v);

/* ── the upload session ────────────────────────────────────────────── */

/* 06 §6.3's WsOtaFrame.phase enum. The device never emits `receiving`:
 * it streams straight to flash, so `writing` is true from the first
 * chunk. The value exists because the contract carries it. */
typedef enum {
    APP_OTA_PHASE_IDLE = 0,
    APP_OTA_PHASE_RECEIVING,
    APP_OTA_PHASE_WRITING,
    APP_OTA_PHASE_VERIFYING,
    APP_OTA_PHASE_REBOOTING,
    APP_OTA_PHASE_FAILED,
} app_ota_phase_t;

const char *app_ota_phase_str(app_ota_phase_t p);

typedef enum {
    APP_OTA_ADMIT_OK = 0,
    APP_OTA_ADMIT_SESSION_ACTIVE, /* 409 — nobody discovers a bad flash
                                     14 hours into a brisket */
    APP_OTA_ADMIT_IN_PROGRESS,    /* 503 */
    APP_OTA_ADMIT_EMPTY,          /* 400 */
} app_ota_admit_t;

/* Everything that touches flash or reboots. `ctx` is passed back
 * verbatim so a test can hand in its own recorder. */
typedef struct {
    int (*begin)(void *ctx, size_t total_hint);
    int (*write)(void *ctx, const void *data, size_t n);
    int (*end)(void *ctx); /* where the SHA-256 is actually checked */
    int (*set_boot)(void *ctx);
    void (*reboot_later)(void *ctx, uint32_t delay_ms);
    const char *(*slot_name)(void *ctx); /* "ota_1" */
    void *ctx;
} app_ota_ops_t;

/* Progress is emitted on every phase change and every whole 5 % — never
 * per chunk. A 1.3 MB image in 4 KB reads is 320 chunks and the
 * WebSocket cap is two clients (06 §6.3). */
#define APP_OTA_PROGRESS_STEP_PCT 5
/* Small queue rather than a single flag: finish() produces `verifying`
 * and `rebooting` back to back, and a flag would coalesce them into
 * whichever the caller happened to drain. */
#define APP_OTA_PROGRESS_QUEUE 4

typedef struct {
    app_ota_phase_t phase;
    int pct;
} app_ota_progress_t;

typedef struct {
    app_ota_phase_t phase;
    size_t declared; /* Content-Length */
    size_t received;
    const char *fail_reason; /* NULL unless phase == FAILED */

    /* Header accumulation: the first APP_OTA_HEADER_MIN bytes are held
     * here and inspected before begin(), then flushed through write(). */
    uint8_t hdr[APP_OTA_HEADER_MIN];
    size_t hdr_len;
    bool header_checked;
    app_ota_image_info_t info;

    const app_ota_ops_t *ops;

    /* Progress bookkeeping. */
    int last_pct;          /* last queued percent, -1 = none */
    app_ota_phase_t last_phase;
    app_ota_progress_t queue[APP_OTA_PROGRESS_QUEUE];
    uint8_t q_head;
    uint8_t q_count;
} app_ota_session_t;

/* Pure admission (06 §6.2). `force` is `?force=1`. */
app_ota_admit_t app_ota_session_admit(const app_ota_session_t *s,
                                      bool session_active, bool force,
                                      size_t content_len);
const char *app_ota_admit_str(app_ota_admit_t a);

/* Arms a session. Does NOT call ops->begin — that happens once the
 * header has been inspected, so a bad image never opens a slot. */
void app_ota_session_begin(app_ota_session_t *s, const app_ota_ops_t *ops,
                           size_t content_len);

/* Feeds one received chunk. Returns 0, or -1 with s->phase == FAILED and
 * s->fail_reason set. */
int app_ota_session_feed(app_ota_session_t *s, const void *data, size_t n);

/* End of body: verify (ops->end), set the boot partition, schedule the
 * reboot. Returns 0 or -1. */
int app_ota_session_finish(app_ota_session_t *s);

void app_ota_session_fail(app_ota_session_t *s, const char *reason);

/* Returns the session to IDLE so the NEXT upload is admitted. A failed
 * upload that wedges the endpoint at 503 forever is the bug this
 * exists to not have. */
void app_ota_session_reset(app_ota_session_t *s);

int app_ota_session_pct(const app_ota_session_t *s);

/* True once, per due progress event, filling phase/pct. The caller
 * drains it after each feed/finish/fail and pushes a WebSocket frame. */
bool app_ota_session_take_progress(app_ota_session_t *s,
                                   app_ota_phase_t *phase, int *pct);

#ifdef __cplusplus
}
#endif

#endif /* APP_OTA_CORE_H */
