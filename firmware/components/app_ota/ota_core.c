/* ota_core.c — F14.2: the upload session. Admission, header-first
 * validation, byte accounting, the phase machine, and throttled progress.
 * Pure C11 over an injected ops struct, so the whole OTA path — including
 * an esp_ota_end() that fails SHA-256 — runs on the host. */
#include "app_ota_core.h"

#include <string.h>

const char *app_ota_phase_str(app_ota_phase_t p) {
    switch (p) {
    case APP_OTA_PHASE_IDLE:
        return "idle";
    case APP_OTA_PHASE_RECEIVING:
        return "receiving";
    case APP_OTA_PHASE_WRITING:
        return "writing";
    case APP_OTA_PHASE_VERIFYING:
        return "verifying";
    case APP_OTA_PHASE_REBOOTING:
        return "rebooting";
    case APP_OTA_PHASE_FAILED:
        return "failed";
    }
    return "unknown";
}

const char *app_ota_admit_str(app_ota_admit_t a) {
    switch (a) {
    case APP_OTA_ADMIT_OK:
        return "ok";
    case APP_OTA_ADMIT_SESSION_ACTIVE:
        return "session_active";
    case APP_OTA_ADMIT_IN_PROGRESS:
        return "ota_in_progress";
    case APP_OTA_ADMIT_EMPTY:
        return "invalid_body";
    }
    return "unknown";
}

app_ota_admit_t app_ota_session_admit(const app_ota_session_t *s,
                                      bool session_active, bool force,
                                      size_t content_len) {
    /* An upload already in flight outranks everything: two writers into
     * one slot is not a race worth losing. */
    if (s && s->phase != APP_OTA_PHASE_IDLE &&
        s->phase != APP_OTA_PHASE_FAILED) {
        return APP_OTA_ADMIT_IN_PROGRESS;
    }
    if (content_len == 0) {
        return APP_OTA_ADMIT_EMPTY;
    }
    if (session_active && !force) {
        return APP_OTA_ADMIT_SESSION_ACTIVE;
    }
    return APP_OTA_ADMIT_OK;
}

void app_ota_session_reset(app_ota_session_t *s) {
    if (!s) {
        return;
    }
    memset(s, 0, sizeof *s);
    s->phase = APP_OTA_PHASE_IDLE;
    s->last_phase = APP_OTA_PHASE_IDLE;
    s->last_pct = -1;
}

static void note_progress(app_ota_session_t *s) {
    const app_ota_progress_t ev = {.phase = s->phase,
                                   .pct = app_ota_session_pct(s)};
    s->last_phase = ev.phase;
    s->last_pct = ev.pct;
    if (s->q_count == APP_OTA_PROGRESS_QUEUE) {
        /* Full only if nobody drained. Overwrite the NEWEST, never the
         * oldest: the terminal phase is the one that must survive. */
        const uint8_t last =
            (uint8_t)((s->q_head + s->q_count - 1u) % APP_OTA_PROGRESS_QUEUE);
        s->queue[last] = ev;
        return;
    }
    s->queue[(s->q_head + s->q_count) % APP_OTA_PROGRESS_QUEUE] = ev;
    s->q_count++;
}

void app_ota_session_begin(app_ota_session_t *s, const app_ota_ops_t *ops,
                           size_t content_len) {
    app_ota_session_reset(s);
    s->ops = ops;
    s->declared = content_len;
    /* `writing` from the first chunk: the device streams straight to
     * flash, so `receiving` would be a lie about a buffer it does not
     * have. */
    s->phase = APP_OTA_PHASE_WRITING;
}

int app_ota_session_pct(const app_ota_session_t *s) {
    if (!s || s->declared == 0) {
        return 0;
    }
    if (s->received >= s->declared) {
        return 100;
    }
    return (int)((uint64_t)s->received * 100u / (uint64_t)s->declared);
}

void app_ota_session_fail(app_ota_session_t *s, const char *reason) {
    if (!s) {
        return;
    }
    s->phase = APP_OTA_PHASE_FAILED;
    s->fail_reason = reason;
    note_progress(s);
}

bool app_ota_session_take_progress(app_ota_session_t *s,
                                   app_ota_phase_t *phase, int *pct) {
    if (!s || s->q_count == 0) {
        return false;
    }
    const app_ota_progress_t ev = s->queue[s->q_head];
    s->q_head = (uint8_t)((s->q_head + 1u) % APP_OTA_PROGRESS_QUEUE);
    s->q_count--;
    if (phase) {
        *phase = ev.phase;
    }
    if (pct) {
        *pct = ev.pct;
    }
    return true;
}

/* Emits on a phase change, or on crossing a whole APP_OTA_PROGRESS_STEP_PCT
 * boundary — never per chunk. */
static void maybe_note_progress(app_ota_session_t *s) {
    if (s->phase != s->last_phase) {
        note_progress(s);
        return;
    }
    const int pct = app_ota_session_pct(s);
    const int step = APP_OTA_PROGRESS_STEP_PCT;
    if (s->last_pct < 0 || (pct / step) > (s->last_pct / step)) {
        note_progress(s);
    }
}

int app_ota_session_feed(app_ota_session_t *s, const void *data, size_t n) {
    if (!s || !s->ops) {
        return -1;
    }
    if (s->phase == APP_OTA_PHASE_FAILED) {
        return -1; /* a chunk after failure is dropped, not accounted */
    }
    if (s->phase != APP_OTA_PHASE_WRITING) {
        app_ota_session_fail(s, "not_receiving");
        return -1;
    }
    if (n == 0) {
        return 0;
    }

    const uint8_t *p = (const uint8_t *)data;
    size_t left = n;

    /* Header first: hold up to APP_OTA_HEADER_MIN bytes, inspect, and only
     * THEN open a slot. A refused image never calls begin(), so it cannot
     * leave a half-erased partition behind. */
    if (!s->header_checked) {
        const size_t want = APP_OTA_HEADER_MIN - s->hdr_len;
        const size_t take = left < want ? left : want;
        memcpy(s->hdr + s->hdr_len, p, take);
        s->hdr_len += take;
        p += take;
        left -= take;

        if (s->hdr_len < APP_OTA_HEADER_MIN) {
            /* Still undecided. Nothing has been written; the accounting
             * catches up when the header completes. */
            s->received += take;
            maybe_note_progress(s);
            return 0;
        }

        if (app_ota_image_inspect(s->hdr, s->hdr_len, &s->info) !=
            APP_OTA_IMG_OK) {
            app_ota_session_fail(s,
                                 app_ota_image_verdict_str(s->info.verdict));
            return -1;
        }
        s->header_checked = true;

        if (s->ops->begin(s->ops->ctx, s->declared) != 0) {
            app_ota_session_fail(s, "ota_begin_failed");
            return -1;
        }
        if (s->ops->write(s->ops->ctx, s->hdr, s->hdr_len) != 0) {
            app_ota_session_fail(s, "ota_write_failed");
            return -1;
        }
        s->received += take;
    }

    if (left > 0) {
        if (s->ops->write(s->ops->ctx, p, left) != 0) {
            app_ota_session_fail(s, "ota_write_failed");
            return -1;
        }
        s->received += left;
    }
    maybe_note_progress(s);
    return 0;
}

int app_ota_session_finish(app_ota_session_t *s) {
    if (!s || !s->ops) {
        return -1;
    }
    if (s->phase == APP_OTA_PHASE_FAILED) {
        return -1;
    }
    if (!s->header_checked) {
        /* The body ended before a whole header arrived. */
        app_ota_session_fail(s, app_ota_image_verdict_str(
                                    APP_OTA_IMG_UNDECIDED));
        return -1;
    }
    if (s->declared != 0 && s->received != s->declared) {
        app_ota_session_fail(s, "short_body");
        return -1;
    }

    s->phase = APP_OTA_PHASE_VERIFYING;
    maybe_note_progress(s);

    /* esp_ota_end(): the SHA-256 and image-validity check. A failure
     * here MUST leave the boot partition alone — that is what keeps a
     * corrupt image from ever being booted. */
    if (s->ops->end(s->ops->ctx) != 0) {
        app_ota_session_fail(s, "image_validation_failed");
        return -1;
    }
    if (s->ops->set_boot(s->ops->ctx) != 0) {
        app_ota_session_fail(s, "set_boot_failed");
        return -1;
    }

    s->phase = APP_OTA_PHASE_REBOOTING;
    maybe_note_progress(s);
    /* Deferred, so the HTTP reply reaches the client before the socket
     * dies under it. */
    s->ops->reboot_later(s->ops->ctx, 500u);
    return 0;
}
