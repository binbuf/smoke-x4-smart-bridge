/*
 * lora_corpus.h - readers for the committed Smoke X fixture corpus.
 *
 * Two formats live under protocol/fixtures/lora/:
 *   - .loralog captures: "# comments" then
 *     "boot t_ms rssi snr dir class payload".
 *   - parser-vectors.tsv: one tab-separated vector per line, with expected
 *     parser outcome and provenance. The header documents each column.
 *
 * These readers are host-test support only; production firmware never reads
 * fixture files.
 */
#ifndef SX4_LORA_CORPUS_H
#define SX4_LORA_CORPUS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SX4_LORALOG_MAX_PAYLOAD 192
#define SX4_LORALOG_MAX_CLASS 16
#define SX4_VECTOR_MAX_PAYLOAD 192
#define SX4_VECTOR_MAX_NAME 48
#define SX4_VECTOR_MAX_CATEGORY 32
#define SX4_VECTOR_MAX_ID 16
#define SX4_VECTOR_MAX_PROVENANCE 96

typedef struct {
    int boot;
    unsigned long long t_ms;
    int rssi; /* 127 when the capture printed "?" */
    int snr;
    bool is_tx;
    char cls[SX4_LORALOG_MAX_CLASS];
    char payload[SX4_LORALOG_MAX_PAYLOAD];
} sx4_loralog_line_t;

/* Read a .loralog file. Returns 0 on success, -1 on an unreadable file,
 * a malformed line, or more than max_lines records. */
int sx4_loralog_read(const char *path, sx4_loralog_line_t *out,
                     size_t max_lines, size_t *count);

unsigned sx4_count_commas(const char *s);

/* 16 commas -> 2 probes, 26 -> 4, anything else -> 0. */
unsigned sx4_probes_for_commas(unsigned commas);

typedef enum {
    SX4_VECTOR_EXPECT_OK = 0,
    SX4_VECTOR_EXPECT_REJECT = 1,
    /* The parser may decode the sync, but the caller must reject the
     * frequency before retuning or transmitting. */
    SX4_VECTOR_EXPECT_OK_OUT_OF_BAND = 2,
} sx4_vector_expect_t;

typedef enum {
    SX4_VECTOR_KIND_SYNC = 0,
    SX4_VECTOR_KIND_STATE = 1,
} sx4_vector_kind_t;

typedef struct {
    char name[SX4_VECTOR_MAX_NAME];
    char category[SX4_VECTOR_MAX_CATEGORY];
    sx4_vector_kind_t kind;
    unsigned probes; /* 0 for sync; 2 or 4 for state */
    sx4_vector_expect_t expect;
    char device_id[SX4_VECTOR_MAX_ID];
    char units;           /* 'F', 'C', or '-' when not asserted */
    unsigned attached_mask; /* bit i set when probe i is attached */
    uint32_t frequency;   /* sync only; 0 when not asserted */
    char provenance[SX4_VECTOR_MAX_PROVENANCE];
    char payload[SX4_VECTOR_MAX_PAYLOAD];
    unsigned line;
} sx4_parser_vector_t;

/* Read parser-vectors.tsv. Returns 0 on success, -1 on any malformed row. */
int sx4_vectors_read(const char *path, sx4_parser_vector_t *out, size_t max,
                     size_t *count);

const char *sx4_vector_kind_name(sx4_vector_kind_t kind);
const char *sx4_vector_expect_name(sx4_vector_expect_t expect);

#ifdef __cplusplus
}
#endif

#endif /* SX4_LORA_CORPUS_H */
