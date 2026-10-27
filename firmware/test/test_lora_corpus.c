/*
 * Host tests for the committed Smoke X fixture corpus.
 *
 * The product parser lands in T14. Until then this suite proves the corpus is
 * complete, well-formed and traceable: real captures load, reports exist,
 * malformed payloads really are malformed, and every synthetic vector has the
 * shape and metadata its expectation claims.
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lora_corpus.h"
#include "test_util.h"

#ifndef SX4_FIXTURE_DIR
#error "SX4_FIXTURE_DIR must point at protocol/fixtures/lora"
#endif

#define MAX_FIELDS 32
#define MAX_CAPTURE_LINES 128
#define MAX_VECTORS 64

typedef char field_set_t[MAX_FIELDS][SX4_VECTOR_MAX_PAYLOAD];

typedef struct {
    char field0[16];
    char device_id[16];
    uint32_t frequency;
} sync_view_t;

static int parse_long_field(const char *text, long *out) {
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (end == text || *end != '\0') {
        return -1;
    }
    *out = value;
    return 0;
}

static int parse_u8_field(const char *text, unsigned *out) {
    long value = 0;
    if (parse_long_field(text, &value) != 0 || value < 0 || value > 255) {
        return -1;
    }
    *out = (unsigned)value;
    return 0;
}

/* Mirrors the product rule: values outside int16, and sentinel collisions,
 * are malformed rather than clamped. */
static int parse_i16_field(const char *text, int *out) {
    long value = 0;
    if (parse_long_field(text, &value) != 0 || value > INT16_MAX ||
        value <= INT16_MIN + 1) {
        return -1;
    }
    *out = (int)value;
    return 0;
}

static int split_fields(const char *payload, field_set_t fields, int *count) {
    int n = 0;
    const char *start = payload;
    for (;;) {
        if (n >= MAX_FIELDS) {
            return -1;
        }
        const char *comma = strchr(start, ',');
        size_t len = comma == NULL ? strlen(start) : (size_t)(comma - start);
        if (len >= SX4_VECTOR_MAX_PAYLOAD) {
            return -1;
        }
        memcpy(fields[n], start, len);
        fields[n][len] = '\0';
        n++;
        if (comma == NULL) {
            break;
        }
        start = comma + 1;
    }
    *count = n;
    return 0;
}

static void copy_id(char *dst, size_t dst_size, const char *src) {
    size_t len = strlen(src);
    if (len + 1 > dst_size) {
        len = dst_size - 1;
    }
    memcpy(dst, src, len);
    dst[len] = '\0';
}

/* Returns 1 when the payload has the exact sync shape and numeric fields. */
static int decode_sync(const char *payload, sync_view_t *out) {
    size_t len = strlen(payload);
    if (len == 0 || len >= 128 || payload[len - 1] != ',' ||
        sx4_count_commas(payload) != 6) {
        return 0;
    }
    field_set_t fields;
    int count = 0;
    if (split_fields(payload, fields, &count) != 0 || count != 7 ||
        fields[6][0] != '\0') {
        return 0;
    }
    if (fields[0][0] == '\0' || fields[1][0] == '\0' ||
        strlen(fields[1]) > 7) {
        return 0;
    }
    uint32_t frequency = 0;
    for (int i = 0; i < 4; i++) {
        unsigned byte = 0;
        if (parse_u8_field(fields[2 + i], &byte) != 0) {
            return 0;
        }
        frequency |= (uint32_t)byte << (8 * i);
    }
    if (out != NULL) {
        copy_id(out->field0, sizeof out->field0, fields[0]);
        copy_id(out->device_id, sizeof out->device_id, fields[1]);
        out->frequency = frequency;
    }
    return 1;
}

/* Returns 1 when the payload has the exact state shape, numeric fields and
 * in-range values. Sets the attached mask when mask is non-NULL. */
static int decode_state(const char *payload, unsigned probes,
                        field_set_t fields_out, unsigned *mask) {
    if (probes != 2 && probes != 4) {
        return 0;
    }
    size_t len = strlen(payload);
    const unsigned expected_commas = 6u + 5u * probes;
    if (len == 0 || len >= 128 || payload[len - 1] != ',' ||
        sx4_count_commas(payload) != expected_commas) {
        return 0;
    }
    field_set_t fields;
    int count = 0;
    if (split_fields(payload, fields, &count) != 0 ||
        count != (int)expected_commas + 1 || fields[count - 1][0] != '\0') {
        return 0;
    }
    if (fields[0][0] == '\0' || strlen(fields[0]) > 7) {
        return 0;
    }
    unsigned value = 0;
    if (parse_u8_field(fields[1], &value) != 0) {
        return 0;
    }
    long units = 0;
    if (parse_long_field(fields[2], &units) != 0) {
        return 0;
    }
    if (parse_u8_field(fields[3], &value) != 0) {
        return 0;
    }

    unsigned attached = 0;
    for (unsigned p = 0; p < probes; p++) {
        const int base = 4 + (int)(5 * p);
        unsigned state = 0;
        int temp = 0;
        long armed = 0;
        int high = 0;
        int low = 0;
        if (parse_u8_field(fields[base], &state) != 0 ||
            parse_i16_field(fields[base + 1], &temp) != 0 ||
            parse_long_field(fields[base + 2], &armed) != 0 ||
            parse_i16_field(fields[base + 3], &high) != 0 ||
            parse_i16_field(fields[base + 4], &low) != 0) {
            return 0;
        }
        if (state != 3) {
            attached |= 1u << p;
        }
    }
    long billows = 0;
    long new_alarm = 0;
    if (parse_long_field(fields[4 + 5 * (int)probes], &billows) != 0 ||
        parse_long_field(fields[5 + 5 * (int)probes], &new_alarm) != 0) {
        return 0;
    }
    if (fields_out != NULL) {
        memcpy(fields_out, fields, sizeof fields);
    }
    if (mask != NULL) {
        *mask = attached;
    }
    return 1;
}

typedef struct {
    size_t lines;
    size_t syncs;
    size_t acks;
    size_t states;
    size_t x2_states;
    unsigned detached;
    unsigned detached_zero_temp;
    unsigned alarms;
    unsigned units_f;
    unsigned units_c;
    int all_hdr1_30;
    int all_attached_temps_plausible;
    uint32_t first_sync_frequency;
    char first_sync_id[16];
    char first_sync_field0[16];
} capture_stats_t;

static int analyze_capture(const char *path, capture_stats_t *stats) {
    sx4_loralog_line_t lines[MAX_CAPTURE_LINES];
    size_t count = 0;
    if (sx4_loralog_read(path, lines, MAX_CAPTURE_LINES, &count) != 0) {
        return 0;
    }
    memset(stats, 0, sizeof *stats);
    stats->all_hdr1_30 = 1;
    stats->all_attached_temps_plausible = 1;

    for (size_t i = 0; i < count; i++) {
        const sx4_loralog_line_t *line = &lines[i];
        stats->lines++;
        const unsigned commas = sx4_count_commas(line->payload);
        if (line->is_tx) {
            if (strcmp(line->cls, "ack2") != 0 || commas != 2 ||
                strstr(line->payload, "SUCCESS,") == NULL) {
                return 0;
            }
            stats->acks++;
            continue;
        }
        if (strcmp(line->cls, "sync6") == 0) {
            sync_view_t sync;
            if (!decode_sync(line->payload, &sync) || sync.frequency < 902000000u ||
                sync.frequency > 928000000u) {
                return 0;
            }
            if (stats->syncs == 0) {
                stats->first_sync_frequency = sync.frequency;
                copy_id(stats->first_sync_id, sizeof stats->first_sync_id,
                        sync.device_id);
                copy_id(stats->first_sync_field0,
                        sizeof stats->first_sync_field0, sync.field0);
            }
            stats->syncs++;
            continue;
        }

        unsigned probes = 0;
        if (strcmp(line->cls, "state16") == 0) {
            probes = 2;
        } else if (strcmp(line->cls, "state26") == 0) {
            probes = 4;
        } else {
            return 0;
        }
        field_set_t fields;
        unsigned mask = 0;
        if (!decode_state(line->payload, probes, fields, &mask)) {
            return 0;
        }
        stats->states++;
        if (probes == 2) {
            stats->x2_states++;
        }

        unsigned hdr1 = 0;
        long units = 0;
        if (parse_u8_field(fields[1], &hdr1) != 0 ||
            parse_long_field(fields[2], &units) != 0) {
            return 0;
        }
        if (hdr1 != 30) {
            stats->all_hdr1_30 = 0;
        }
        if (units == 1) {
            stats->units_f++;
        } else {
            stats->units_c++;
        }

        for (unsigned p = 0; p < probes; p++) {
            const int base = 4 + (int)(5 * p);
            unsigned state = 0;
            int temp = 0;
            if (parse_u8_field(fields[base], &state) != 0 ||
                parse_i16_field(fields[base + 1], &temp) != 0) {
                return 0;
            }
            if (state == 3) {
                stats->detached++;
                if (temp == 0) {
                    stats->detached_zero_temp++;
                }
            } else if (temp <= -600 || temp >= 6000) {
                stats->all_attached_temps_plausible = 0;
            }
        }
        long new_alarm = 0;
        if (parse_long_field(fields[5 + 5 * (int)probes], &new_alarm) != 0) {
            return 0;
        }
        if (new_alarm != 0) {
            stats->alarms++;
        }
    }
    return 1;
}

static void fixture_path(char *out, size_t out_size, const char *name) {
    snprintf(out, out_size, "%s/%s", SX4_FIXTURE_DIR, name);
}

static int file_nonempty(const char *path) {
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return 0;
    }
    int c = fgetc(f);
    fclose(f);
    return c != EOF;
}

static void test_real_captures(void) {
    char path[512];
    capture_stats_t stats;

    fixture_path(path, sizeof path, "x4-events-10min.loralog");
    CHECK(analyze_capture(path, &stats));
    CHECK(stats.lines >= 39);
    CHECK_EQ_UINT(stats.syncs, 1);
    CHECK_EQ_UINT(stats.acks, 1);
    CHECK(stats.states >= 36);
    CHECK_EQ_UINT(stats.detached, 3);
    CHECK_EQ_UINT(stats.detached_zero_temp, 0);
    CHECK_EQ_UINT(stats.alarms, 3);
    CHECK(stats.all_hdr1_30);
    CHECK(stats.all_attached_temps_plausible);
    CHECK_EQ_UINT(stats.first_sync_frequency, 918500000u);
    CHECK_STR_EQ(stats.first_sync_id, "LMXC[\\");
    CHECK_STR_EQ(stats.first_sync_field0, "000000");

    fixture_path(path, sizeof path, "x4-passive-session.loralog");
    CHECK(analyze_capture(path, &stats));
    CHECK(stats.states >= 54);
    CHECK_EQ_UINT(stats.syncs, 0);
    CHECK_EQ_UINT(stats.acks, 0);
    CHECK_EQ_UINT(stats.alarms, 0);
    CHECK_EQ_UINT(stats.units_f, stats.states);
    CHECK(stats.all_hdr1_30);
    CHECK(stats.all_attached_temps_plausible);

    fixture_path(path, sizeof path, "first-x4-contact.loralog");
    CHECK(analyze_capture(path, &stats));
    CHECK(stats.states >= 1);
    CHECK(stats.all_hdr1_30);
    CHECK(stats.all_attached_temps_plausible);
}

static void test_malformed_capture(void) {
    char path[512];
    fixture_path(path, sizeof path, "malformed.loralog");
    sx4_loralog_line_t lines[32];
    size_t count = 0;
    CHECK_EQ_INT(sx4_loralog_read(path, lines, 32, &count), 0);
    CHECK_EQ_UINT(count, 10);
    for (size_t i = 0; i < count; i++) {
        sync_view_t sync;
        CHECK(!decode_sync(lines[i].payload, &sync));
        CHECK(!decode_state(lines[i].payload, 2, NULL, NULL));
        CHECK(!decode_state(lines[i].payload, 4, NULL, NULL));
    }
}

static int has_vector(const sx4_parser_vector_t *vectors, size_t count,
                      const char *name) {
    for (size_t i = 0; i < count; i++) {
        if (strcmp(vectors[i].name, name) == 0) {
            return 1;
        }
    }
    return 0;
}

static void test_vector_corpus(void) {
    char path[512];
    fixture_path(path, sizeof path, "parser-vectors.tsv");
    sx4_parser_vector_t vectors[MAX_VECTORS];
    size_t count = 0;
    CHECK_EQ_INT(sx4_vectors_read(path, vectors, MAX_VECTORS, &count), 0);
    CHECK_EQ_UINT(count, 21);

    int have_x4 = 0;
    int have_x2 = 0;
    int have_malformed = 0;
    int have_foreign = 0;
    int have_detached = 0;
    int have_celsius = 0;
    int have_billows = 0;
    int have_out_of_range = 0;
    int foreign_ids = 0;
    int celsius_vectors = 0;
    int detached_vectors = 0;
    int billows_vectors = 0;
    int oversized_rejects = 0;
    int x2_vectors = 0;

    for (size_t i = 0; i < count; i++) {
        const sx4_parser_vector_t *v = &vectors[i];
        CHECK(v->name[0] != '\0');
        CHECK(v->category[0] != '\0');
        CHECK(v->provenance[0] != '\0');
        CHECK(v->payload[0] != '\0');
        have_x4 |= strcmp(v->category, "x4") == 0;
        have_x2 |= strcmp(v->category, "x2-defensive") == 0;
        have_malformed |= strcmp(v->category, "malformed") == 0;
        have_foreign |= strcmp(v->category, "foreign-id") == 0;
        have_detached |= strcmp(v->category, "detached") == 0;
        have_celsius |= strcmp(v->category, "celsius") == 0;
        have_billows |= strcmp(v->category, "billows") == 0;
        have_out_of_range |= strcmp(v->category, "out-of-range") == 0;

        if (v->kind == SX4_VECTOR_KIND_SYNC) {
            sync_view_t sync;
            int ok = decode_sync(v->payload, &sync);
            if (v->expect == SX4_VECTOR_EXPECT_REJECT) {
                CHECK(!ok);
                continue;
            }
            CHECK(ok);
            if (!ok) {
                continue;
            }
            CHECK_EQ_UINT(sync.frequency, v->frequency);
            if (strcmp(v->device_id, "-") != 0) {
                CHECK_STR_EQ(sync.device_id, v->device_id);
            }
            if (v->expect == SX4_VECTOR_EXPECT_OK_OUT_OF_BAND) {
                CHECK(sync.frequency < 902000000u ||
                      sync.frequency > 928000000u);
            }
            continue;
        }

        unsigned mask = 0;
        field_set_t fields;
        int ok = decode_state(v->payload, v->probes, fields, &mask);
        if (v->expect == SX4_VECTOR_EXPECT_REJECT) {
            CHECK(!ok);
            if (strlen(v->payload) >= 128) {
                oversized_rejects++;
            }
            continue;
        }
        CHECK(ok);
        if (!ok) {
            continue;
        }
        CHECK_EQ_UINT(mask, v->attached_mask);
        if (strcmp(v->device_id, "-") != 0) {
            CHECK_STR_EQ(fields[0], v->device_id);
        }
        if (v->units != '-') {
            long units = 0;
            CHECK_EQ_INT(parse_long_field(fields[2], &units), 0);
            CHECK_EQ_INT(units == 1 ? 'F' : 'C', v->units);
        }
        if (v->probes == 2) {
            x2_vectors++;
        }
        if (v->units == 'C') {
            celsius_vectors++;
        }
        if (strcmp(v->category, "foreign-id") == 0) {
            foreign_ids++;
            CHECK(strcmp(fields[0], "LMXC[\\") != 0);
        }
        if (strcmp(v->category, "detached") == 0) {
            detached_vectors++;
            CHECK(mask != ((1u << v->probes) - 1u));
        }
        if (strcmp(v->category, "billows") == 0) {
            billows_vectors++;
            long billows = 0;
            CHECK_EQ_INT(
                parse_long_field(fields[4 + 5 * (int)v->probes], &billows), 0);
            CHECK(billows != 0);
        }
    }

    CHECK(have_x4 && have_x2 && have_malformed && have_foreign &&
          have_detached && have_celsius && have_billows && have_out_of_range);
    CHECK(foreign_ids >= 1);
    CHECK(celsius_vectors >= 1);
    CHECK(detached_vectors >= 1);
    CHECK(billows_vectors >= 1);
    CHECK(oversized_rejects >= 1);
    CHECK(x2_vectors >= 1);

    CHECK(has_vector(vectors, count, "x4-baseline"));
    CHECK(has_vector(vectors, count, "x4-alarm-edge"));
    CHECK(has_vector(vectors, count, "x4-detached-frozen"));
    CHECK(has_vector(vectors, count, "x4-celsius"));
    CHECK(has_vector(vectors, count, "x4-sync"));
    CHECK(has_vector(vectors, count, "x2-real-state"));
    CHECK(has_vector(vectors, count, "x2-sync-reference"));
    CHECK(has_vector(vectors, count, "x2-detached-zeroed"));
    CHECK(has_vector(vectors, count, "foreign-id-state"));
    CHECK(has_vector(vectors, count, "billows-attached"));
    CHECK(has_vector(vectors, count, "out-of-range-sync"));
    CHECK(has_vector(vectors, count, "malformed-state-nonnumeric"));
    CHECK(has_vector(vectors, count, "malformed-sync-bad-byte"));
}

static void test_provenance_files(void) {
    char path[512];
    const char *reports[] = {
        "x4-events-10min.report.md",
        "x4-passive-session.report.md",
        "first-x4-contact.report.md",
    };
    for (size_t i = 0; i < sizeof reports / sizeof reports[0]; i++) {
        fixture_path(path, sizeof path, reports[i]);
        CHECK(file_nonempty(path));
    }

    fixture_path(path, sizeof path, "README.md");
    CHECK(file_nonempty(path));

    FILE *f = fopen(path, "r");
    CHECK(f != NULL);
    if (f != NULL) {
        char text[8192];
        size_t n = fread(text, 1, sizeof text - 1, f);
        text[n] = '\0';
        fclose(f);
        CHECK(strstr(text, "provenance") != NULL);
        CHECK(strstr(text, "X2-era") != NULL);
        CHECK(strstr(text, "defensive") != NULL);
        CHECK(strstr(text, "parser-vectors.tsv") != NULL);
    }
}

int main(void) {
    test_real_captures();
    test_malformed_capture();
    test_vector_corpus();
    test_provenance_files();
    return sx4_test_summary("lora_corpus");
}
