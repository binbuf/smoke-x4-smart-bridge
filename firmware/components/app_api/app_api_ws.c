/* app_api_ws — registry, keepalive, frames (F9.9). */
#include "app_api_ws.h"

#include "app_alarm_core.h"
#include "record_gen.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    bool used;
    uint32_t topics;
    uint64_t last_ping_sent_ms;
    int missed;
} ws_client_t;

static ws_client_t s_clients[APP_API_WS_MAX_CLIENTS];

int app_api_ws_add(uint64_t now_ms) {
    for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
        if (!s_clients[i].used) {
            s_clients[i] = (ws_client_t){.used = true,
                                         .topics = WS_TOPIC_ALL,
                                         .last_ping_sent_ms = now_ms,
                                         .missed = 0};
            return i;
        }
    }
    return -1; /* the hard cap: third client refused (06 §6.3) */
}

void app_api_ws_remove(int slot) {
    if (slot >= 0 && slot < APP_API_WS_MAX_CLIENTS) {
        s_clients[slot].used = false;
    }
}

int app_api_ws_count(void) {
    int n = 0;
    for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
        n += s_clients[i].used ? 1 : 0;
    }
    return n;
}

uint32_t app_api_ws_topics(int slot) {
    return (slot >= 0 && slot < APP_API_WS_MAX_CLIENTS &&
            s_clients[slot].used)
               ? s_clients[slot].topics
               : 0;
}

static uint32_t topic_bit(const char *name, size_t len) {
    static const struct {
        const char *name;
        uint32_t bit;
    } map[] = {
        {"sample", WS_TOPIC_SAMPLE},   {"alarm", WS_TOPIC_ALARM},
        {"session", WS_TOPIC_SESSION}, {"net", WS_TOPIC_NET},
        {"power", WS_TOPIC_POWER},     {"pairing", WS_TOPIC_PAIRING},
        {"ota", WS_TOPIC_OTA},
    };
    for (size_t i = 0; i < sizeof map / sizeof map[0]; i++) {
        if (strlen(map[i].name) == len &&
            strncmp(map[i].name, name, len) == 0) {
            return map[i].bit;
        }
    }
    return 0;
}

int app_api_ws_on_message(int slot, const char *text, char *reply,
                          size_t reply_cap, int *acked_alarm_id) {
    *acked_alarm_id = -1;
    if (reply_cap > 0) {
        reply[0] = '\0';
    }
    if (slot < 0 || slot >= APP_API_WS_MAX_CLIENTS ||
        !s_clients[slot].used || !text) {
        return -1;
    }
    if (strstr(text, "\"subscribe\"")) {
        const char *topics = strstr(text, "\"topics\"");
        if (topics) {
            const char *open = strchr(topics, '[');
            const char *close = open ? strchr(open, ']') : NULL;
            if (open && close) {
                uint32_t mask = 0;
                const char *p = open;
                while ((p = strchr(p, '"')) != NULL && p < close) {
                    const char *end = strchr(p + 1, '"');
                    if (!end || end > close) {
                        break;
                    }
                    mask |= topic_bit(p + 1, (size_t)(end - p - 1));
                    p = end + 1;
                }
                s_clients[slot].topics = mask;
            }
        }
        return 0;
    }
    if (strstr(text, "\"ping\"")) {
        snprintf(reply, reply_cap, "{\"type\":\"pong\"}");
        return 0;
    }
    if (strstr(text, "\"ack_alarm\"")) {
        const char *id = strstr(text, "\"id\"");
        if (id) {
            const char *colon = strchr(id, ':');
            if (colon) {
                *acked_alarm_id = atoi(colon + 1);
            }
        }
        return 0;
    }
    return 0; /* unknown type: ignored, additive contract */
}

int app_api_ws_pings_due(uint64_t now_ms,
                         int slots[APP_API_WS_MAX_CLIENTS]) {
    int n = 0;
    for (int i = 0; i < APP_API_WS_MAX_CLIENTS; i++) {
        if (s_clients[i].used &&
            now_ms - s_clients[i].last_ping_sent_ms >=
                APP_API_WS_PING_INTERVAL_MS) {
            s_clients[i].last_ping_sent_ms = now_ms;
            s_clients[i].missed++;
            slots[n++] = i;
        }
    }
    return n;
}

void app_api_ws_pong(int slot) {
    if (slot >= 0 && slot < APP_API_WS_MAX_CLIENTS) {
        s_clients[slot].missed = 0;
    }
}

bool app_api_ws_expired(int slot, uint64_t now_ms) {
    (void)now_ms;
    return slot >= 0 && slot < APP_API_WS_MAX_CLIENTS &&
           s_clients[slot].used && s_clients[slot].missed > 2;
}

/* ── frames — key order matches the sim byte-for-byte ─────────────────── */

void app_api_ws_hello(app_api_out_t *out, const char *fw, bool have_time,
                      uint64_t server_time_ms) {
    app_api_emit_fmt(out, "{\"type\":\"hello\",\"fw\":\"%s\",\"api\":\"v1\","
                          "\"server_time_ms\":",
                     fw);
    if (have_time) {
        app_api_emit_fmt(out, "%llu}", (unsigned long long)server_time_ms);
    } else {
        app_api_emit_str(out, "null}");
    }
}

void app_api_ws_sample(app_api_out_t *out, const bridge_evt_sample_t *s,
                       bool have_unix, uint64_t unix_ms) {
    app_api_emit_fmt(out, "{\"type\":\"sample\",\"t\":%u,\"unix_ms\":",
                     (unsigned)s->t_rel_s);
    if (have_unix) {
        app_api_emit_fmt(out, "%llu", (unsigned long long)unix_ms);
    } else {
        app_api_emit_str(out, "null");
    }
    app_api_emit_str(out, ",\"temps_f10\":[");
    for (int i = 0; i < 4; i++) {
        if (i) {
            app_api_emit_str(out, ",");
        }
        if (s->temp_f10[i] == INT16_MIN || s->temp_f10[i] == INT16_MIN + 1) {
            app_api_emit_str(out, "null");
        } else {
            app_api_emit_fmt(out, "%d", (int)s->temp_f10[i]);
        }
    }
    app_api_emit_fmt(out, "],\"flags\":{\"billows\":%s},\"rssi\":%d}",
                     (s->flags & 0x10) ? "true" : "false", (int)s->rssi);
}

void app_api_ws_net(app_api_out_t *out, const char *mode, const char *state,
                    const char *ip) {
    app_api_emit_fmt(out,
                     "{\"type\":\"net\",\"mode\":\"%s\",\"state\":\"%s\","
                     "\"ip\":\"%s\"}",
                     mode, state, ip);
}

void app_api_ws_pairing(app_api_out_t *out, bool paired,
                        const char *device_id, int num_probes) {
    app_api_emit_fmt(out, "{\"type\":\"pairing\",\"paired\":%s",
                     paired ? "true" : "false");
    if (paired) {
        app_api_emit_str(out, ",\"device_id\":");
        app_api_emit_json_str(out, device_id);
        app_api_emit_fmt(out, ",\"num_probes\":%d}", num_probes);
    } else {
        app_api_emit_str(out, "}");
    }
}

void app_api_ws_alarm(app_api_out_t *out, const bridge_evt_alarm_t *e,
                      const char *message) {
    static const char *const kActions[] = {"raised", "cleared", "acked"};
    app_api_emit_fmt(
        out,
        "{\"type\":\"alarm\",\"action\":\"%s\",\"id\":%u,"
        "\"rule\":\"%s\",\"severity\":\"%s\",\"probe\":%u",
        kActions[e->action < 3 ? e->action : 0], (unsigned)e->alarm_id,
        bridge_alarm_rule_str(e->rule),
        bridge_alarm_severity_str(app_alarm_rule_severity(e->rule)),
        (unsigned)e->probe);
    /* A detached probe is null on the wire, never 0 — the invariant this
     * project has held end to end since M0. */
    if (e->value_f10 == BRIDGE_TEMP_DETACHED ||
        e->value_f10 == BRIDGE_TEMP_INVALID) {
        app_api_emit_str(out, ",\"value_f10\":null");
    } else {
        app_api_emit_fmt(out, ",\"value_f10\":%d", (int)e->value_f10);
    }
    if (message != NULL) {
        app_api_emit_str(out, ",\"message\":");
        app_api_emit_json_str(out, message);
    }
    app_api_emit_str(out, "}");
}

void app_api_ws_power(app_api_out_t *out, const bridge_evt_power_t *e) {
    app_api_emit_str(out, "{\"type\":\"power\",\"soc_pct\":");
    if (e->soc_pct == BRIDGE_SOC_UNKNOWN) {
        app_api_emit_str(out, "null");
    } else {
        app_api_emit_fmt(out, "%u", (unsigned)e->soc_pct);
    }
    app_api_emit_fmt(out,
                     ",\"mv\":%u,\"charging\":%s,\"saver\":%s}",
                     (unsigned)e->mv, e->charging ? "true" : "false",
                     e->saver ? "true" : "false");
}

void app_api_ws_session(app_api_out_t *out, const char *action, uint32_t id,
                        const char *name) {
    app_api_emit_fmt(out, "{\"type\":\"session\",\"action\":\"%s\","
                          "\"id\":%u",
                     action, (unsigned)id);
    if (name) {
        app_api_emit_str(out, ",\"name\":");
        app_api_emit_json_str(out, name);
    }
    app_api_emit_str(out, "}");
}

/* F14.5 — 06 §6.3's ota frame. `phase` is one of the spec's enum values;
 * the device never emits `receiving` because it streams straight to
 * flash, so `writing` is true from the first chunk. */
void app_api_ws_ota(app_api_out_t *out, const char *phase, int pct) {
    app_api_emit_str(out, "{\"type\":\"ota\",\"phase\":");
    app_api_emit_json_str(out, phase ? phase : "");
    app_api_emit_fmt(out, ",\"pct\":%d}", pct);
}
