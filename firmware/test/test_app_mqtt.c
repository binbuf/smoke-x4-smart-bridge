/* test_app_mqtt.c — the pure MQTT / Home Assistant publisher (A16, 05 §5.7).
 *
 * Topic building, the retained state JSON (with the null-not-zero invariant),
 * the discovery-doc shape and device grouping, the entity count, and the
 * STA/enable gate — all with no ESP-IDF and no broker.
 */
#include "app_mqtt_core.h"

#include <string.h>

#include "record_gen.h"
#include "test_util.h"

static void test_gating(void) {
    CHECK(app_mqtt_core_should_run(true, true));
    CHECK(!app_mqtt_core_should_run(true, false)); /* no uplink */
    CHECK(!app_mqtt_core_should_run(false, true)); /* disabled */
    CHECK(!app_mqtt_core_should_run(false, false));
}

static void test_topics(void) {
    char buf[64];
    CHECK(app_mqtt_core_state_topic("smokebridge", buf, sizeof buf) > 0);
    CHECK(strcmp(buf, "smokebridge/state") == 0);
    CHECK(app_mqtt_core_avail_topic("smokebridge", buf, sizeof buf) > 0);
    CHECK(strcmp(buf, "smokebridge/availability") == 0);
    /* Overflow is reported, not truncated silently. */
    char tiny[4];
    CHECK(app_mqtt_core_state_topic("smokebridge", tiny, sizeof tiny) == -1);
}

static void test_state(void) {
    app_mqtt_state_t s;
    memset(&s, 0, sizeof s);
    s.temp_f10[0] = 2254;                 /* 225.4 F */
    s.temp_f10[1] = BRIDGE_TEMP_DETACHED; /* -> null */
    s.temp_f10[2] = BRIDGE_TEMP_INVALID;  /* -> null */
    s.temp_f10[3] = -405;                 /* -40.5 F */
    s.num_probes = 4;
    s.base_lost = false;
    s.session_active = true;
    s.soc_pct = 87;
    s.lora_rssi = -92;

    char buf[256];
    CHECK(app_mqtt_core_build_state(&s, buf, sizeof buf) > 0);
    CHECK(strstr(buf, "\"probe_1\":225.4") != NULL);
    CHECK(strstr(buf, "\"probe_2\":null") != NULL); /* detached, NOT 0 */
    CHECK(strstr(buf, "\"probe_3\":null") != NULL); /* invalid,  NOT 0 */
    CHECK(strstr(buf, "\"probe_4\":-40.5") != NULL);
    CHECK(strstr(buf, "\"base_lost\":\"OFF\"") != NULL);
    CHECK(strstr(buf, "\"session\":\"ON\"") != NULL);
    CHECK(strstr(buf, "\"battery\":87") != NULL);
    CHECK(strstr(buf, "\"rssi\":-92") != NULL);
    /* The invariant, stated as a negative: no detached probe leaked a 0. */
    CHECK(strstr(buf, "\"probe_2\":0") == NULL);

    /* An unknown battery is null, never 0. */
    s.soc_pct = BRIDGE_SOC_UNKNOWN;
    CHECK(app_mqtt_core_build_state(&s, buf, sizeof buf) > 0);
    CHECK(strstr(buf, "\"battery\":null") != NULL);
    CHECK(strstr(buf, "\"battery\":0") == NULL);
}

static void test_entity_count(void) {
    CHECK_EQ_INT(app_mqtt_core_entity_count(4), 8); /* 4 temps + 4 tail */
    CHECK_EQ_INT(app_mqtt_core_entity_count(2), 6);
}

static void test_discovery(void) {
    char topic[128];
    char payload[512];

    /* Entity 0 = the probe_1 temperature sensor. */
    int r = app_mqtt_core_discovery(0, "smokebridge", "smokebridge_a4f2",
                                    "SmokeBridge-A4F2", 4, topic, sizeof topic,
                                    payload, sizeof payload);
    CHECK_EQ_INT(r, 1);
    CHECK(strcmp(topic,
                 "homeassistant/sensor/smokebridge_a4f2/probe_1/config") == 0);
    CHECK(strstr(payload, "\"uniq_id\":\"smokebridge_a4f2_probe_1\"") != NULL);
    CHECK(strstr(payload, "\"stat_t\":\"smokebridge/state\"") != NULL);
    CHECK(strstr(payload, "\"avty_t\":\"smokebridge/availability\"") != NULL);
    CHECK(strstr(payload, "\"val_tpl\":\"{{ value_json.probe_1 }}\"") != NULL);
    CHECK(strstr(payload, "\"dev_cla\":\"temperature\"") != NULL);
    CHECK(strstr(payload, "\\u00b0F") != NULL); /* °F as an ASCII escape */
    /* One shared device block, keyed on the stable node id. */
    CHECK(strstr(payload, "\"ids\":[\"smokebridge_a4f2\"]") != NULL);
    CHECK(strstr(payload, "\"name\":\"SmokeBridge-A4F2\"") != NULL);

    /* Entity 6 = the base-lost binary sensor. */
    r = app_mqtt_core_discovery(6, "smokebridge", "smokebridge_a4f2",
                                "SmokeBridge-A4F2", 4, topic, sizeof topic,
                                payload, sizeof payload);
    CHECK_EQ_INT(r, 1);
    CHECK(strstr(topic, "homeassistant/binary_sensor/") != NULL);
    CHECK(strstr(topic, "/base_lost/config") != NULL);
    CHECK(strstr(payload, "\"pl_on\":\"ON\"") != NULL);
    CHECK(strstr(payload, "\"pl_off\":\"OFF\"") != NULL);

    /* Past the last entity → 0 (done). */
    r = app_mqtt_core_discovery(app_mqtt_core_entity_count(4), "smokebridge",
                                "n", "N", 4, topic, sizeof topic, payload,
                                sizeof payload);
    CHECK_EQ_INT(r, 0);

    /* With 2 probes, entity 2 is the battery — probe_3/4 do not exist. */
    r = app_mqtt_core_discovery(2, "smokebridge", "n", "N", 2, topic,
                                sizeof topic, payload, sizeof payload);
    CHECK_EQ_INT(r, 1);
    CHECK(strstr(topic, "/battery/config") != NULL);
}

int main(void) {
    test_gating();
    test_topics();
    test_state();
    test_entity_count();
    test_discovery();
    return test_summary("test_app_mqtt");
}
