/* app_api_emit — chunked body emission through one ≤ 2 KB buffer (F9.2). */
#include "app_api_emit.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void app_api_out_init(app_api_out_t *out, app_api_sink_t sink, void *ctx) {
    memset(out, 0, sizeof *out);
    out->sink = sink;
    out->sink_ctx = ctx;
    out->status = 200;
    out->content_type = "application/json";
}

void app_api_out_begin(app_api_out_t *out, int status,
                       const char *content_type) {
    out->status = status;
    out->content_type = content_type;
    out->begun = true;
}

static void flush(app_api_out_t *out) {
    if (out->len == 0 || out->aborted) {
        out->len = 0;
        return;
    }
    if (out->sink(out->sink_ctx, out->buf, out->len) != 0) {
        out->aborted = true; /* client went away: stop producing */
    }
    out->total += out->len;
    out->len = 0;
}

void app_api_emit_raw(app_api_out_t *out, const void *data, size_t len) {
    const char *p = data;
    while (len > 0 && !out->aborted) {
        const size_t room = APP_API_EMIT_BUF - out->len;
        const size_t n = len < room ? len : room;
        memcpy(out->buf + out->len, p, n);
        out->len += n;
        if (out->len > out->peak) {
            out->peak = out->len;
        }
        p += n;
        len -= n;
        if (out->len == APP_API_EMIT_BUF) {
            flush(out);
        }
    }
}

void app_api_emit_str(app_api_out_t *out, const char *s) {
    app_api_emit_raw(out, s, strlen(s));
}

void app_api_emit_fmt(app_api_out_t *out, const char *fmt, ...) {
    char piece[256];
    va_list ap;
    va_start(ap, fmt);
    const int n = vsnprintf(piece, sizeof piece, fmt, ap);
    va_end(ap);
    if (n <= 0) {
        return;
    }
    if ((size_t)n < sizeof piece) {
        app_api_emit_raw(out, piece, (size_t)n);
        return;
    }
    /* Overflow used to emit the first 255 bytes and say nothing, so a
     * format string that outgrew the stack buffer produced JSON that was
     * well-formed right up to where it was severed. F13.8 hit exactly
     * that with twelve tunables in one call and worked around it by
     * splitting the call — but the trap stayed armed for the next
     * endpoint. Retry on the heap, and if even that fails, abort the
     * response rather than emit a truncated body: a client can retry a
     * failed request, but it cannot detect a plausible-looking lie. */
    char *big = malloc((size_t)n + 1);
    if (big == NULL) {
        out->aborted = true;
        return;
    }
    va_start(ap, fmt);
    const int m = vsnprintf(big, (size_t)n + 1, fmt, ap);
    va_end(ap);
    if (m > 0) {
        app_api_emit_raw(out, big, (size_t)m);
    }
    free(big);
}

void app_api_emit_json_str(app_api_out_t *out, const char *s) {
    app_api_emit_raw(out, "\"", 1);
    for (const char *p = s; *p; p++) {
        const unsigned char c = (unsigned char)*p;
        switch (c) {
            case '"':
                app_api_emit_raw(out, "\\\"", 2);
                break;
            case '\\':
                app_api_emit_raw(out, "\\\\", 2);
                break;
            case '\n':
                app_api_emit_raw(out, "\\n", 2);
                break;
            case '\r':
                app_api_emit_raw(out, "\\r", 2);
                break;
            case '\t':
                app_api_emit_raw(out, "\\t", 2);
                break;
            default:
                if (c < 0x20) {
                    char esc[8];
                    snprintf(esc, sizeof esc, "\\u%04x", c);
                    app_api_emit_raw(out, esc, 6);
                } else {
                    app_api_emit_raw(out, p, 1);
                }
        }
    }
    app_api_emit_raw(out, "\"", 1);
}

size_t app_api_out_finish(app_api_out_t *out) {
    flush(out);
    return out->total;
}
