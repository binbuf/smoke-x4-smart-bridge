/* app_mqtt_core — the pure publisher (05 §5.7 add-on).
 *
 * Topic building, the retained state JSON, Home Assistant MQTT Discovery, and
 * the run/stop gating — all ESP-IDF-free and host-tested, exactly like every
 * other `_core` in this tree. The glue (app_mqtt.c) owns the esp-mqtt client
 * and the event subscriptions; this file decides *what* to say, never *how*.
 *
 * The temperature invariant the whole project holds reaches here too: a
 * detached probe and an unknown battery render as JSON `null`, never `0`.
 */
#ifndef APP_MQTT_CORE_H
#define APP_MQTT_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The device snapshot the publisher renders. Detached probes carry
 * BRIDGE_TEMP_DETACHED (or _INVALID); an unknown battery is BRIDGE_SOC_UNKNOWN
 * (record_gen.h). */
typedef struct {
    int16_t temp_f10[4]; /* canonical tenths °F */
    uint8_t num_probes;  /* 2 or 4 — bounds the temperature entities */
    bool paired;
    bool base_lost;
    bool session_active;
    uint32_t session_id;
    uint8_t soc_pct; /* 0..100, or BRIDGE_SOC_UNKNOWN */
    bool charging;
    int8_t lora_rssi; /* dBm */
} app_mqtt_state_t;

/* The client runs only when enabled AND the STA uplink is up: MQTT needs a
 * route to the broker, which AP-hosting and the fallback ladder do not have.
 * Kept as a one-liner so the gate is a testable fact, not a scattered `if`. */
bool app_mqtt_core_should_run(bool enabled, bool sta_up);

/* Topic builders under `prefix` (e.g. "smokebridge"): the retained state topic
 * and the LWT/availability topic. Return the length written (excl. NUL), or -1
 * if it would not fit. */
int app_mqtt_core_state_topic(const char *prefix, char *out, size_t cap);
int app_mqtt_core_avail_topic(const char *prefix, char *out, size_t cap);

/* The retained state JSON, e.g.
 *   {"probe_1":225.4,"probe_2":null,...,"base_lost":"OFF","session":"ON",
 *    "battery":87,"rssi":-92}
 * Returns bytes written (excl. NUL), or -1 on overflow. */
int app_mqtt_core_build_state(const app_mqtt_state_t *s, char *out, size_t cap);

/* How many discovery entities exist for `num_probes` (temps + the fixed
 * tail: battery, signal, base-lost, session). */
int app_mqtt_core_entity_count(uint8_t num_probes);

/* Home Assistant MQTT Discovery. For entity `i` in [0, entity_count) it fills
 * `topic` ("homeassistant/<component>/<node>/<object>/config") and `payload`
 * (the discovery doc, keyed to the state + availability topics and one shared
 * `device` block on `node_id`) and returns 1. Returns 0 when `i` is past the
 * last entity, or -1 on overflow. `node_id` is the stable bridge id (so a
 * reflash keeps the same entities); `device_name` is the user-facing name. */
int app_mqtt_core_discovery(int i, const char *prefix, const char *node_id,
                            const char *device_name, uint8_t num_probes,
                            char *topic, size_t topic_cap, char *payload,
                            size_t payload_cap);

#ifdef __cplusplus
}
#endif

#endif /* APP_MQTT_CORE_H */
