/* app_api_ws — WebSocket fan-out: client registry, topic filters, frame
 * builders, keepalive bookkeeping (F9.9, design 06 §6.3). Pure; the
 * httpd_ws glue adapts send/receive.
 *
 * Spike result (the F9 epic flag): esp_http_server completes the
 * WebSocket handshake BEFORE invoking the URI handler for
 * `.is_websocket` routes, so a pre-handshake JSON 503 is not possible on
 * the device. The fallback is the documented one: accept, then close
 * with 1013 (Try Again Later). The sim keeps the 503 (Dart can refuse
 * pre-upgrade); openapi.yaml documents both refusal shapes.
 */
#ifndef APP_API_WS_H
#define APP_API_WS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_api_emit.h"
#include "bridge_event_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define APP_API_WS_MAX_CLIENTS 2
#define APP_API_WS_PING_INTERVAL_MS 30000u
#define APP_API_WS_CLOSE_TRY_LATER 1013

typedef enum {
    WS_TOPIC_SAMPLE = 1u << 0,
    WS_TOPIC_ALARM = 1u << 1,
    WS_TOPIC_SESSION = 1u << 2,
    WS_TOPIC_NET = 1u << 3,
    WS_TOPIC_POWER = 1u << 4,
    WS_TOPIC_PAIRING = 1u << 5,
    WS_TOPIC_OTA = 1u << 6,
    WS_TOPIC_ALL = 0x7F,
} app_api_ws_topic_t;

/* Registry. `slot` identifies a client (0..MAX-1). Returns the slot or
 * -1 when full — the caller then refuses (503 on host/sim; 1013 close
 * on device, per the spike above). */
int app_api_ws_add(uint64_t now_ms);
void app_api_ws_remove(int slot);
int app_api_ws_count(void);
uint32_t app_api_ws_topics(int slot);

/* Client → server messages: subscribe / ping / ack_alarm. Returns 0 and
 * fills reply (may be empty) — an unknown type is ignored (additive
 * contract). ack_alarm surfaces through *acked_alarm_id (or -1). */
int app_api_ws_on_message(int slot, const char *text, char *reply,
                          size_t reply_cap, int *acked_alarm_id);

/* Keepalive: server ping every 30 s, drop after two missed. `due` fills
 * slots needing a ping; returns how many. `pong` clears the miss count.
 * `expired` returns true when the slot missed two and must be dropped. */
int app_api_ws_pings_due(uint64_t now_ms, int slots[APP_API_WS_MAX_CLIENTS]);
void app_api_ws_pong(int slot);
bool app_api_ws_expired(int slot, uint64_t now_ms);

/* ── frame builders — byte-identical to the sim's frames ── */
void app_api_ws_hello(app_api_out_t *out, const char *fw,
                      bool have_time, uint64_t server_time_ms);
void app_api_ws_sample(app_api_out_t *out, const bridge_evt_sample_t *s,
                       bool have_unix, uint64_t unix_ms);
void app_api_ws_net(app_api_out_t *out, const char *mode, const char *state,
                    const char *ip);
void app_api_ws_pairing(app_api_out_t *out, bool paired,
                        const char *device_id, int num_probes);
void app_api_ws_session(app_api_out_t *out, const char *action, uint32_t id,
                        const char *name);
/* F13.8 — 06 §6.3's alarm frame. `message` is the human sentence the app
 * shows in a notification; NULL omits it. */
void app_api_ws_alarm(app_api_out_t *out, const bridge_evt_alarm_t *e,
                      const char *message);
/* F12.5 — 06 §6.3's power frame. soc == BRIDGE_SOC_UNKNOWN emits null
 * rather than a plausible-looking 255. */
void app_api_ws_power(app_api_out_t *out, const bridge_evt_power_t *e);

#ifdef __cplusplus
}
#endif

#endif /* APP_API_WS_H */
