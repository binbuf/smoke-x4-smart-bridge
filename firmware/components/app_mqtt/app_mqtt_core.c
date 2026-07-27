/* app_mqtt_core.c — the pure publisher. No ESP-IDF, host-tested.
 *
 * All JSON is built with a bounded-append helper: once the buffer is full,
 * snprintf is called with size 0 (writes nothing) but still returns the
 * would-be length, so the running offset keeps growing and the final
 * `off >= cap` check reports the overflow as -1 rather than a truncated doc.
 */
#include "app_mqtt_core.h"

#include <stdio.h>
#include <string.h>

#include "record_gen.h" /* BRIDGE_TEMP_DETACHED / _INVALID, BRIDGE_SOC_UNKNOWN */

/* Bounded append into (out, cap) at running offset `off`. Evaluates to on
 * overflow: keeps counting so the caller's `off >= cap` catches it. */
#define APPEND(...)                                                       \
    do {                                                                  \
        int _r = snprintf(out + off, off < cap ? cap - off : 0u,          \
                          __VA_ARGS__);                                   \
        if (_r < 0) {                                                     \
            return -1;                                                    \
        }                                                                 \
        off += (size_t)_r;                                                \
    } while (0)

bool app_mqtt_core_should_run(bool enabled, bool sta_up) {
    return enabled && sta_up;
}

static int finish(size_t off, size_t cap) {
    if (off >= cap) {
        return -1; /* truncated — the caller must grow the buffer */
    }
    return (int)off;
}

int app_mqtt_core_state_topic(const char *prefix, char *out, size_t cap) {
    size_t off = 0;
    APPEND("%s/state", prefix);
    return finish(off, cap);
}

int app_mqtt_core_avail_topic(const char *prefix, char *out, size_t cap) {
    size_t off = 0;
    APPEND("%s/availability", prefix);
    return finish(off, cap);
}

/* One tenths-°F reading as a JSON number, or `null` when detached/invalid. */
static void fmt_temp(int16_t v, char *buf, size_t cap) {
    if (v == BRIDGE_TEMP_DETACHED || v == BRIDGE_TEMP_INVALID) {
        snprintf(buf, cap, "null");
        return;
    }
    int whole = v / 10;
    int frac = v % 10;
    if (frac < 0) {
        frac = -frac;
    }
    if (v < 0 && whole == 0) {
        snprintf(buf, cap, "-0.%d", frac); /* keep the sign for -0.x */
    } else {
        snprintf(buf, cap, "%d.%d", whole, frac);
    }
}

int app_mqtt_core_build_state(const app_mqtt_state_t *s, char *out,
                              size_t cap) {
    size_t off = 0;
    APPEND("{");
    for (int i = 0; i < 4; i++) {
        char t[16];
        fmt_temp(s->temp_f10[i], t, sizeof t);
        APPEND("%s\"probe_%d\":%s", i == 0 ? "" : ",", i + 1, t);
    }
    APPEND(",\"base_lost\":\"%s\"", s->base_lost ? "ON" : "OFF");
    APPEND(",\"session\":\"%s\"", s->session_active ? "ON" : "OFF");
    if (s->soc_pct == BRIDGE_SOC_UNKNOWN) {
        APPEND(",\"battery\":null");
    } else {
        APPEND(",\"battery\":%u", (unsigned)s->soc_pct);
    }
    APPEND(",\"rssi\":%d", (int)s->lora_rssi);
    APPEND("}");
    return finish(off, cap);
}

/* The fixed tail of entities after the temperature probes. Kept as data so a
 * new sensor is one row, and the count stays a single source of truth. */
typedef struct {
    const char *component; /* "sensor" / "binary_sensor" */
    const char *object_id; /* HA object id and unique-id suffix */
    const char *name;      /* user-facing */
    const char *value_key; /* key in the state JSON */
    const char *dev_cla;   /* HA device_class, or NULL */
    const char *unit;      /* unit_of_meas, or NULL */
    bool binary;           /* emits pl_on/pl_off */
} mqtt_entity_t;

static const mqtt_entity_t k_tail[] = {
    {"sensor", "battery", "Battery", "battery", "battery", "%", false},
    {"sensor", "rssi", "Signal", "rssi", "signal_strength", "dBm", false},
    {"binary_sensor", "base_lost", "Base Lost", "base_lost", "problem", NULL,
     true},
    {"binary_sensor", "session", "Cook Session", "session", "running", NULL,
     true},
};

#define TAIL_N ((int)(sizeof k_tail / sizeof k_tail[0]))

int app_mqtt_core_entity_count(uint8_t num_probes) {
    int n = num_probes > 4 ? 4 : (int)num_probes;
    return n + TAIL_N;
}

/* Emit one discovery doc. HA's abbreviated keys keep the retained doc small on
 * a heap-tight part. The unit is written as the JSON escape \u00b0F so the
 * source stays ASCII-only. */
static int emit_doc(char *out, size_t cap, const char *prefix,
                    const char *node_id, const char *device_name,
                    const char *component, const char *object_id,
                    const char *name, const char *value_key,
                    const char *dev_cla, const char *unit, bool binary) {
    (void)component;
    size_t off = 0;
    APPEND("{\"name\":\"%s\"", name);
    APPEND(",\"uniq_id\":\"%s_%s\"", node_id, object_id);
    APPEND(",\"stat_t\":\"%s/state\"", prefix);
    APPEND(",\"avty_t\":\"%s/availability\"", prefix);
    APPEND(",\"val_tpl\":\"{{ value_json.%s }}\"", value_key);
    if (dev_cla != NULL) {
        APPEND(",\"dev_cla\":\"%s\"", dev_cla);
    }
    if (unit != NULL) {
        if (strcmp(unit, "F") == 0) {
            APPEND(",\"unit_of_meas\":\"\\u00b0F\"");
        } else {
            APPEND(",\"unit_of_meas\":\"%s\"", unit);
        }
    }
    if (binary) {
        APPEND(",\"pl_on\":\"ON\",\"pl_off\":\"OFF\"");
    }
    APPEND(",\"dev\":{\"ids\":[\"%s\"],\"name\":\"%s\","
           "\"mf\":\"BinBuf\",\"mdl\":\"Smoke X Bridge\"}}",
           node_id, device_name);
    return finish(off, cap);
}

int app_mqtt_core_discovery(int i, const char *prefix, const char *node_id,
                            const char *device_name, uint8_t num_probes,
                            char *topic, size_t topic_cap, char *payload,
                            size_t payload_cap) {
    int nprobes = num_probes > 4 ? 4 : (int)num_probes;
    if (i < 0 || i >= nprobes + TAIL_N) {
        return 0; /* past the last entity */
    }

    const char *component;
    const char *object_id;
    const char *name;
    const char *value_key;
    const char *dev_cla;
    const char *unit;
    bool binary;
    char obj_buf[16];
    char name_buf[16];

    if (i < nprobes) {
        snprintf(obj_buf, sizeof obj_buf, "probe_%d", i + 1);
        snprintf(name_buf, sizeof name_buf, "Probe %d", i + 1);
        component = "sensor";
        object_id = obj_buf;
        name = name_buf;
        value_key = obj_buf;
        dev_cla = "temperature";
        unit = "F";
        binary = false;
    } else {
        const mqtt_entity_t *e = &k_tail[i - nprobes];
        component = e->component;
        object_id = e->object_id;
        name = e->name;
        value_key = e->value_key;
        dev_cla = e->dev_cla;
        unit = e->unit;
        binary = e->binary;
    }

    int tr = snprintf(topic, topic_cap, "homeassistant/%s/%s/%s/config",
                      component, node_id, object_id);
    if (tr < 0 || (size_t)tr >= topic_cap) {
        return -1;
    }
    if (emit_doc(payload, payload_cap, prefix, node_id, device_name, component,
                 object_id, name, value_key, dev_cla, unit, binary) < 0) {
        return -1;
    }
    return 1;
}
