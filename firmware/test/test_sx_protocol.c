/*
 * test_sx_protocol.c - product parser coverage (T14).
 *
 * Drives firmware/components/sx_protocol/sx_protocol.c directly, with no
 * ESP-IDF and no radio. The vectors come from the same committed corpus the
 * protocol contract uses (protocol/fixtures/lora/parser-vectors.tsv); real
 * captures are replayed too. X2 rows are defensive parser checks only.
 */
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "lora_corpus.h"
#include "sx_protocol.h"
#include "test_util.h"

#ifndef SX4_FIXTURE_DIR
#error "SX4_FIXTURE_DIR must point at protocol/fixtures/lora"
#endif

#define MAX_VECTORS 64
#define MAX_CAPTURE_LINES 256
#define PAIRED_ID "LMXC[\\"

static void fixture_path(char *out, size_t out_size, const char *name) {
    snprintf(out, out_size, "%s/%s", SX4_FIXTURE_DIR, name);
}

static const sx4_parser_vector_t *find_vector(const sx4_parser_vector_t *vectors,
                                              size_t count, const char *name) {
    for (size_t i = 0; i < count; i++) {
        if (strcmp(vectors[i].name, name) == 0) {
            return &vectors[i];
        }
    }
    return NULL;
}

static void check_helpers(void) {
    CHECK_EQ_UINT(SX_PROTOCOL_MAX_PAYLOAD, 128u);
    CHECK_EQ_UINT(SX_PROTOCOL_NUM_COMMAS_SYNC, 6u);
    CHECK_EQ_UINT(SX_PROTOCOL_NUM_COMMAS_ACK, 2u);
    CHECK_EQ_UINT(SX_PROTOCOL_NUM_COMMAS_X2, 16u);
    CHECK_EQ_UINT(SX_PROTOCOL_NUM_COMMAS_X4, 26u);
    CHECK_EQ_INT(SX_PROTOCOL_TEMP_DETACHED, INT16_MIN);
    CHECK_EQ_INT(SX_PROTOCOL_TEMP_INVALID, INT16_MIN + 1);

    CHECK_EQ_UINT(sx_protocol_count_commas(NULL), 0u);
    CHECK_EQ_UINT(sx_protocol_count_commas(""), 0u);
    CHECK_EQ_UINT(sx_protocol_count_commas("a,b,c,"), 3u);
    CHECK_EQ_UINT(sx_protocol_probes_for_commas(16u), 2u);
    CHECK_EQ_UINT(sx_protocol_probes_for_commas(26u), 4u);
    CHECK_EQ_UINT(sx_protocol_probes_for_commas(0u), 0u);
    CHECK_EQ_UINT(sx_protocol_probes_for_commas(6u), 0u);
    CHECK_EQ_UINT(sx_protocol_probes_for_commas(25u), 0u);
}

static void check_arguments(void) {
    sx_protocol_sync_t sync;
    sx_protocol_state_t state;

    CHECK_EQ_INT(sx_protocol_parse_sync(NULL, &sync),
                 SX_PROTOCOL_ERR_ARGUMENT);
    CHECK_EQ_INT(sx_protocol_parse_sync("000000,LMXC[\\,160,50,191,54,", NULL),
                 SX_PROTOCOL_ERR_ARGUMENT);
    CHECK_EQ_INT(sx_protocol_parse_state(NULL, NULL, &state),
                 SX_PROTOCOL_ERR_ARGUMENT);
    CHECK_EQ_INT(
        sx_protocol_parse_state("LMXC[\\,30,1,1,0,0,", NULL, NULL),
        SX_PROTOCOL_ERR_ARGUMENT);
    CHECK_EQ_INT(sx_protocol_format_ack(NULL, NULL, 0), -1);
    sx_protocol_counters_get(NULL); /* must not crash */
}

static int parse_vector_state(const sx4_parser_vector_t *v,
                              sx_protocol_state_t *out) {
    const char *paired = PAIRED_ID;
    if (strcmp(v->category, "foreign-id") == 0) {
        paired = PAIRED_ID;
    } else if (v->device_id[0] != '-' && v->device_id[0] != '\0') {
        paired = v->device_id;
    }
    return sx_protocol_parse_state(v->payload, paired, out);
}

static void check_vector_corpus(void) {
    char path[512];
    fixture_path(path, sizeof path, "parser-vectors.tsv");

    sx4_parser_vector_t vectors[MAX_VECTORS];
    size_t count = 0;
    CHECK_EQ_INT(sx4_vectors_read(path, vectors, MAX_VECTORS, &count), 0);
    CHECK(count >= 20);

    unsigned sync_ok = 0;
    unsigned state_ok = 0;
    unsigned rejects = 0;

    for (size_t i = 0; i < count; i++) {
        const sx4_parser_vector_t *v = &vectors[i];
        if (v->kind == SX4_VECTOR_KIND_SYNC) {
            sx_protocol_sync_t sync;
            memset(&sync, 0, sizeof sync);
            const sx_protocol_result_t result =
                sx_protocol_parse_sync(v->payload, &sync);
            if (v->expect == SX4_VECTOR_EXPECT_REJECT) {
                CHECK(result != SX_PROTOCOL_OK);
                rejects++;
                continue;
            }
            CHECK_EQ_INT(result, SX_PROTOCOL_OK);
            if (result != SX_PROTOCOL_OK) {
                continue;
            }
            CHECK_EQ_UINT(sync.frequency_hz, v->frequency);
            if (v->device_id[0] != '-' && v->device_id[0] != '\0') {
                CHECK_STR_EQ(sync.device_id, v->device_id);
            }
            /* Out-of-band sync is a caller decision; the parser decodes it. */
            sync_ok++;
            continue;
        }

        sx_protocol_state_t state;
        memset(&state, 0, sizeof state);
        const sx_protocol_result_t result =
            (sx_protocol_result_t)parse_vector_state(v, &state);
        if (v->expect == SX4_VECTOR_EXPECT_REJECT) {
            CHECK(result != SX_PROTOCOL_OK);
            rejects++;
            continue;
        }
        if (strcmp(v->category, "foreign-id") == 0) {
            CHECK_EQ_INT(result, SX_PROTOCOL_ERR_FOREIGN_DEVICE);
            rejects++;
            continue;
        }
        CHECK_EQ_INT(result, SX_PROTOCOL_OK);
        if (result != SX_PROTOCOL_OK) {
            continue;
        }
        state_ok++;
        CHECK_EQ_UINT(state.num_probes, v->probes);
        if (v->device_id[0] != '-' && v->device_id[0] != '\0') {
            CHECK_STR_EQ(state.device_id, v->device_id);
        }

        unsigned attached_mask = 0;
        for (unsigned p = 0; p < state.num_probes; p++) {
            const sx_protocol_probe_t *probe = &state.probes[p];
            if (probe->attached) {
                attached_mask |= 1u << p;
                CHECK(probe->temp_f10 != SX_PROTOCOL_TEMP_DETACHED);
            } else {
                CHECK_EQ_INT(probe->state, 3);
                CHECK_EQ_INT(probe->temp_f10, SX_PROTOCOL_TEMP_DETACHED);
            }
        }
        CHECK_EQ_UINT(attached_mask, v->attached_mask);

        if (v->units == 'C') {
            CHECK_EQ_INT(state.units, SX_PROTOCOL_UNITS_CELSIUS);
            CHECK(state.source_celsius);
        } else if (v->units == 'F') {
            CHECK_EQ_INT(state.units, SX_PROTOCOL_UNITS_FAHRENHEIT);
            CHECK(!state.source_celsius);
        }

        if (strcmp(v->category, "billows") == 0) {
            CHECK(state.billows_attached);
            /* Candidate only: the max<->target relation is not validated
             * until M5, so it must not be exposed as a target yet. */
            CHECK(!state.billows_target_valid);
        }
    }

    CHECK(sync_ok >= 3);
    CHECK(state_ok >= 7);
    CHECK(rejects >= 7);
}

static void check_named_vectors(void) {
    char path[512];
    fixture_path(path, sizeof path, "parser-vectors.tsv");
    sx4_parser_vector_t vectors[MAX_VECTORS];
    size_t count = 0;
    CHECK_EQ_INT(sx4_vectors_read(path, vectors, MAX_VECTORS, &count), 0);

    const sx4_parser_vector_t *baseline =
        find_vector(vectors, count, "x4-baseline");
    CHECK(baseline != NULL);
    if (baseline != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(sx_protocol_parse_state(baseline->payload, PAIRED_ID,
                                             &state),
                     SX_PROTOCOL_OK);
        CHECK_EQ_UINT(state.num_probes, 4u);
        CHECK_STR_EQ(state.device_id, PAIRED_ID);
        CHECK_EQ_UINT(state.hdr_field1, 30u);
        CHECK_EQ_UINT(state.hdr_field3, 1u);
        CHECK_EQ_INT(state.probes[0].temp_f10, 811);
        CHECK_EQ_INT(state.probes[1].temp_f10, 801);
        CHECK_EQ_INT(state.probes[2].temp_f10, 807);
        CHECK_EQ_INT(state.probes[3].temp_f10, 807);
        CHECK(!state.billows_attached);
        CHECK(!state.new_alarm);
        CHECK(!state.source_celsius);
        CHECK_EQ_INT(state.probes[0].alarm_high_deg, 160);
        CHECK_EQ_INT(state.probes[0].alarm_low_deg, 32);
    }

    const sx4_parser_vector_t *alarm =
        find_vector(vectors, count, "x4-alarm-edge");
    CHECK(alarm != NULL);
    if (alarm != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(
            sx_protocol_parse_state(alarm->payload, PAIRED_ID, &state),
            SX_PROTOCOL_OK);
        CHECK(state.new_alarm);
        CHECK_EQ_UINT(state.hdr_field3, 2u);
        CHECK(state.probes[0].alarm_armed);
        CHECK_EQ_INT(state.probes[0].temp_f10, 1052);
        CHECK_EQ_INT(state.probes[0].alarm_high_deg, 105);
    }

    const sx4_parser_vector_t *detached =
        find_vector(vectors, count, "x4-detached-frozen");
    CHECK(detached != NULL);
    if (detached != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(
            sx_protocol_parse_state(detached->payload, PAIRED_ID, &state),
            SX_PROTOCOL_OK);
        CHECK(state.probes[3].attached == false);
        CHECK_EQ_INT(state.probes[3].state, 3);
        CHECK_EQ_INT(state.probes[3].temp_f10, SX_PROTOCOL_TEMP_DETACHED);
        /* The capture's frozen field is 809; it must never surface. */
        CHECK(state.probes[3].temp_f10 != 809);
        CHECK_EQ_INT(state.probes[0].temp_f10, 1054);
    }

    const sx4_parser_vector_t *celsius =
        find_vector(vectors, count, "x4-celsius");
    CHECK(celsius != NULL);
    if (celsius != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(
            sx_protocol_parse_state(celsius->payload, PAIRED_ID, &state),
            SX_PROTOCOL_OK);
        CHECK(state.source_celsius);
        CHECK_EQ_INT(state.units, SX_PROTOCOL_UNITS_CELSIUS);
        /* 38.1 C -> 100.5 F, 28.5 C -> 83.3 F, 28.8 C -> 83.8 F,
         * 27.3 C -> 81.1 F. */
        CHECK_EQ_INT(state.probes[0].temp_f10, 1005);
        CHECK_EQ_INT(state.probes[1].temp_f10, 833);
        CHECK_EQ_INT(state.probes[2].temp_f10, 838);
        CHECK_EQ_INT(state.probes[3].temp_f10, 811);
        /* Alarm setpoints stay in the packet's active unit. */
        CHECK_EQ_INT(state.probes[0].alarm_high_deg, 37);
    }

    const sx4_parser_vector_t *billows =
        find_vector(vectors, count, "billows-attached");
    CHECK(billows != NULL);
    if (billows != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(
            sx_protocol_parse_state(billows->payload, PAIRED_ID, &state),
            SX_PROTOCOL_OK);
        CHECK(state.billows_attached);
        CHECK_EQ_INT(state.billows_target_deg, 160);
        CHECK_EQ_INT(state.billows_target_units,
                     SX_PROTOCOL_UNITS_FAHRENHEIT);
        CHECK(!state.billows_target_valid);
    }

    const sx4_parser_vector_t *target =
        find_vector(vectors, count, "billows-target-candidate");
    CHECK(target != NULL);
    if (target != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(
            sx_protocol_parse_state(target->payload, PAIRED_ID, &state),
            SX_PROTOCOL_OK);
        CHECK(state.billows_attached);
        CHECK_EQ_INT(state.billows_target_deg, 250);
        CHECK(!state.billows_target_valid);
    }

    const sx4_parser_vector_t *x2 = find_vector(vectors, count, "x2-real-state");
    CHECK(x2 != NULL);
    if (x2 != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(
            sx_protocol_parse_state(x2->payload, x2->device_id, &state),
            SX_PROTOCOL_OK);
        CHECK_EQ_UINT(state.num_probes, 2u);
        CHECK_EQ_INT(state.probes[0].temp_f10, 848);
        CHECK_EQ_INT(state.probes[1].temp_f10, 849);
        CHECK(state.probes[0].alarm_armed);
    }

    const sx4_parser_vector_t *x2_detached =
        find_vector(vectors, count, "x2-detached-zeroed");
    CHECK(x2_detached != NULL);
    if (x2_detached != NULL) {
        sx_protocol_state_t state;
        CHECK_EQ_INT(sx_protocol_parse_state(x2_detached->payload,
                                             x2_detached->device_id, &state),
                     SX_PROTOCOL_OK);
        CHECK(state.probes[1].attached == false);
        CHECK_EQ_INT(state.probes[1].temp_f10, SX_PROTOCOL_TEMP_DETACHED);
    }
}

static void check_sync_and_ack(void) {
    static const char sync_payload[] = "000000,LMXC[\\,160,50,191,54,";
    sx_protocol_sync_t sync;
    memset(&sync, 0, sizeof sync);
    CHECK_EQ_INT(sx_protocol_parse_sync(sync_payload, &sync), SX_PROTOCOL_OK);
    CHECK_STR_EQ(sync.field0, "000000");
    CHECK_STR_EQ(sync.device_id, PAIRED_ID);
    CHECK_EQ_UINT(sync.frequency_hz, 918500000u);

    char ack[32];
    memset(ack, 0, sizeof ack);
    const int written = sx_protocol_format_ack(PAIRED_ID, ack, sizeof ack);
    CHECK_EQ_INT(written, 15);
    CHECK_STR_EQ(ack, "LMXC[\\,SUCCESS,");

    CHECK_EQ_INT(sx_protocol_format_ack("", ack, sizeof ack), -1);
    CHECK_EQ_INT(sx_protocol_format_ack("TOOLONGID", ack, sizeof ack), -1);
    CHECK_EQ_INT(sx_protocol_format_ack("LM,XC", ack, sizeof ack), -1);
    char tiny[4];
    CHECK_EQ_INT(sx_protocol_format_ack(PAIRED_ID, tiny, sizeof tiny), -1);
}

static void check_rejection_is_atomic(void) {
    static const char *bad_payloads[] = {
        /* wrong comma count */
        "LMXC[\\,30,1,0,0,700,0,200,100,0,0,",
        /* 26 commas but trailing garbage instead of the final comma */
        "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0X",
        /* empty field: two consecutive commas at the same comma count */
        "LMXC[\\,30,1,,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0,",
        /* non-numeric temperature */
        "LMXC[\\,30,1,1,0,8x8,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0,",
        /* empty temperature field */
        "LMXC[\\,30,1,1,0,,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0,",
        /* extra field after new_alarm */
        "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0,7,",
        /* leading comma / missing device id */
        ",30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0,",
    };

    for (size_t i = 0; i < sizeof bad_payloads / sizeof bad_payloads[0]; i++) {
        sx_protocol_state_t state;
        memset(&state, 0xA5, sizeof state);
        const sx_protocol_state_t before = state;
        const sx_protocol_result_t result =
            sx_protocol_parse_state(bad_payloads[i], PAIRED_ID, &state);
        CHECK(result != SX_PROTOCOL_OK);
        CHECK(memcmp(&state, &before, sizeof state) == 0);
    }

    /* Oversized input is rejected, not truncated. */
    char oversized[SX_PROTOCOL_MAX_PAYLOAD + 8];
    memset(oversized, 'x', sizeof oversized);
    oversized[sizeof oversized - 1] = '\0';
    sx_protocol_state_t state;
    memset(&state, 0xA5, sizeof state);
    CHECK_EQ_INT(sx_protocol_parse_state(oversized, PAIRED_ID, &state),
                 SX_PROTOCOL_ERR_FORMAT);

    /* Foreign ID is dropped before field parsing and never touches *out. */
    memset(&state, 0xA5, sizeof state);
    const sx_protocol_state_t before = state;
    static const char foreign[] =
        "OTHRID,30,1,1,0,700,0,160,32,0,700,0,160,32,0,700,0,160,32,0,700,"
        "0,160,32,0,0,";
    CHECK_EQ_INT(sx_protocol_parse_state(foreign, PAIRED_ID, &state),
                 SX_PROTOCOL_ERR_FOREIGN_DEVICE);
    CHECK(memcmp(&state, &before, sizeof state) == 0);
}

static void check_counters(void) {
    sx_protocol_counters_reset();
    sx_protocol_counters_t counters;
    sx_protocol_counters_get(&counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 0u);
    CHECK_EQ_UINT(counters.parse_failures, 0u);
    CHECK_EQ_UINT(counters.crc_failures, 0u);
    CHECK_EQ_UINT(counters.foreign_device_packets, 0u);
    CHECK_EQ_UINT(counters.sync_beacons, 0u);
    CHECK_EQ_UINT(counters.ack_attempts, 0u);

    static const char baseline[] =
        "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,"
        "0,160,32,0,0,";
    static const char foreign[] =
        "OTHRID,30,1,1,0,700,0,160,32,0,700,0,160,32,0,700,0,160,32,0,700,"
        "0,160,32,0,0,";
    static const char sync_payload[] = "000000,LMXC[\\,160,50,191,54,";
    static const char malformed[] = "LMXC[\\,30,1,0,0,700,0,200,100,0,0,";

    sx_protocol_state_t state;
    CHECK_EQ_INT(sx_protocol_parse_state(baseline, PAIRED_ID, &state),
                 SX_PROTOCOL_OK);
    CHECK_EQ_INT(sx_protocol_parse_state(foreign, PAIRED_ID, &state),
                 SX_PROTOCOL_ERR_FOREIGN_DEVICE);
    CHECK_EQ_INT(
        sx_protocol_parse_state(malformed, PAIRED_ID, &state),
        SX_PROTOCOL_ERR_FORMAT);

    sx_protocol_sync_t sync;
    CHECK_EQ_INT(sx_protocol_parse_sync(sync_payload, &sync), SX_PROTOCOL_OK);

    char ack[32];
    CHECK(sx_protocol_format_ack(PAIRED_ID, ack, sizeof ack) > 0);

    sx_protocol_note_crc_failure();

    sx_protocol_counters_get(&counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 1u);
    CHECK_EQ_UINT(counters.parse_failures, 1u);
    CHECK_EQ_UINT(counters.crc_failures, 1u);
    CHECK_EQ_UINT(counters.foreign_device_packets, 1u);
    CHECK_EQ_UINT(counters.sync_beacons, 1u);
    CHECK_EQ_UINT(counters.ack_attempts, 1u);

    sx_protocol_counters_reset();
    sx_protocol_counters_get(&counters);
    CHECK_EQ_UINT(counters.valid_state_packets, 0u);
    CHECK_EQ_UINT(counters.foreign_device_packets, 0u);
}

static void check_capture(const char *name, int expect_reject) {
    char path[512];
    fixture_path(path, sizeof path, name);

    sx4_loralog_line_t lines[MAX_CAPTURE_LINES];
    size_t count = 0;
    CHECK_EQ_INT(sx4_loralog_read(path, lines, MAX_CAPTURE_LINES, &count), 0);
    CHECK(count > 0);

    unsigned parsed = 0;
    for (size_t i = 0; i < count; i++) {
        const sx4_loralog_line_t *line = &lines[i];
        if (line->is_tx) {
            continue;
        }
        const unsigned commas = sx4_count_commas(line->payload);
        if (commas == SX_PROTOCOL_NUM_COMMAS_ACK) {
            /* ACK is not a parser input; it is the one frame the bridge
             * transmits (and captures show the stock receiver's ACK). */
            continue;
        }
        sx_protocol_result_t result;
        if (commas == SX_PROTOCOL_NUM_COMMAS_SYNC) {
            sx_protocol_sync_t sync;
            result = sx_protocol_parse_sync(line->payload, &sync);
        } else if (commas == SX_PROTOCOL_NUM_COMMAS_X2 ||
                   commas == SX_PROTOCOL_NUM_COMMAS_X4) {
            sx_protocol_state_t state;
            result = sx_protocol_parse_state(line->payload, NULL, &state);
        } else {
            result = SX_PROTOCOL_ERR_FORMAT;
        }
        if (expect_reject) {
            CHECK(result != SX_PROTOCOL_OK);
        } else {
            if (result != SX_PROTOCOL_OK) {
                fprintf(stderr, "%s line %zu rejected (%d): %s\n", name, i,
                        (int)result, line->payload);
            }
            CHECK_EQ_INT(result, SX_PROTOCOL_OK);
            if (result == SX_PROTOCOL_OK) {
                parsed++;
            }
        }
    }
    if (expect_reject) {
        CHECK_EQ_UINT(parsed, 0u);
    } else {
        CHECK(parsed > 0);
    }
}

static void check_real_captures(void) {
    check_capture("x4-events-10min.loralog", 0);
    check_capture("x4-passive-session.loralog", 0);
    check_capture("first-x4-contact.loralog", 0);
    check_capture("x4-t10-25min.loralog", 0);
    check_capture("x4-billows-225-250-275.loralog", 0);
    check_capture("malformed.loralog", 1);
}

int main(void) {
    check_helpers();
    check_arguments();
    check_vector_corpus();
    check_named_vectors();
    check_sync_and_ack();
    check_rejection_is_atomic();
    check_counters();
    check_real_captures();
    return sx4_test_summary("sx_protocol");
}
