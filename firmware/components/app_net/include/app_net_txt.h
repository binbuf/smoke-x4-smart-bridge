/* app_net_txt — the live mDNS TXT record set (F8.6, design 05 §5.5).
 *
 * `id model fw api probes paired session mode` is what lets the app's
 * picker say "Smoke Bridge · 4 probes · cooking" BEFORE connecting, so it
 * must be rebuilt on pairing/session/mode transitions — the glue calls
 * this builder each time; the builder itself is pure. */
#ifndef APP_NET_TXT_H
#define APP_NET_TXT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define APP_NET_TXT_COUNT 8
#define APP_NET_TXT_KEY_MAX 8
#define APP_NET_TXT_VAL_MAX 16

typedef struct {
    char key[APP_NET_TXT_KEY_MAX];
    char value[APP_NET_TXT_VAL_MAX];
} app_net_txt_record_t;

typedef struct {
    char id[8];      /* "A4F2" — last two MAC bytes in hex */
    const char *model;
    const char *fw;
    uint8_t probes;  /* 0 when unpaired */
    bool paired;
    uint32_t session_id; /* 0 = none */
    bool sta_mode;
} app_net_txt_state_t;

/* Fills out[APP_NET_TXT_COUNT] in the §5.5 order; returns the count. */
int app_net_txt_build(const app_net_txt_state_t *st,
                      app_net_txt_record_t out[APP_NET_TXT_COUNT]);

#ifdef __cplusplus
}
#endif

#endif /* APP_NET_TXT_H */
