/* app_api_emit — the streaming emit layer (F9.2, design 06 §6.1).
 *
 * The no-materialisation rule made structural: every response body flows
 * through one chunked emitter over an injected sink with a single ≤ 2 KB
 * buffer. There is no other way to send a body — that is what makes the
 * rule unbreakable rather than remembered. The reference materialised
 * JSON into a 16 KB buffer and started returning 500 at ~600 records;
 * this component is why that cannot happen here.
 */
#ifndef APP_API_EMIT_H
#define APP_API_EMIT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define APP_API_EMIT_BUF 2048

/* Called with each flushed chunk. Return 0 to continue. */
typedef int (*app_api_sink_t)(void *ctx, const char *data, size_t len);

typedef struct {
    app_api_sink_t sink;
    void *sink_ctx;
    /* Set by out_begin before any body byte. */
    int status;
    const char *content_type;
    /* Internals. */
    char buf[APP_API_EMIT_BUF];
    size_t len;
    size_t total;   /* body bytes emitted so far */
    size_t peak;    /* high-water mark of buf usage (asserted in tests) */
    bool begun;
    bool aborted;
} app_api_out_t;

void app_api_out_init(app_api_out_t *out, app_api_sink_t sink, void *ctx);

/* Status + content type, exactly once, before any body. */
void app_api_out_begin(app_api_out_t *out, int status,
                       const char *content_type);

/* Body emission: raw bytes, a string, or printf-formatted. A formatted
 * piece longer than the buffer is a programming error and trips a flush
 * split — pieces are kept small by construction. */
void app_api_emit_raw(app_api_out_t *out, const void *data, size_t len);
void app_api_emit_str(app_api_out_t *out, const char *s);
void app_api_emit_fmt(app_api_out_t *out, const char *fmt, ...)
    __attribute__((format(printf, 2, 3)));

/* JSON string escaping for untrusted text (names, marks). */
void app_api_emit_json_str(app_api_out_t *out, const char *s);

/* Flush the tail. Returns total body bytes. */
size_t app_api_out_finish(app_api_out_t *out);

#ifdef __cplusplus
}
#endif

#endif /* APP_API_EMIT_H */
