/* app_net_txt — pure TXT record builder (F8.6). */
#include "app_net_txt.h"

#include <stdarg.h>
#include <stdio.h>

static void set(app_net_txt_record_t *r, const char *key, const char *fmt,
                ...) {
    snprintf(r->key, sizeof r->key, "%s", key);
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(r->value, sizeof r->value, fmt, ap);
    va_end(ap);
}

int app_net_txt_build(const app_net_txt_state_t *st,
                      app_net_txt_record_t out[APP_NET_TXT_COUNT]) {
    /* The §5.5 order, exactly:
     * id model fw api probes paired session mode */
    set(&out[0], "id", "%s", st->id);
    set(&out[1], "model", "%s", st->model);
    set(&out[2], "fw", "%s", st->fw);
    set(&out[3], "api", "v1");
    set(&out[4], "probes", "%u", (unsigned)st->probes);
    set(&out[5], "paired", "%d", st->paired ? 1 : 0);
    set(&out[6], "session", "%u", (unsigned)st->session_id);
    set(&out[7], "mode", "%s", st->sta_mode ? "sta" : "ap");
    return APP_NET_TXT_COUNT;
}
