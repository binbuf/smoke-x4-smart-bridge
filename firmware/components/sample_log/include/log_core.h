/*
 * log_core.h - firmware-facing sample-record codec and semantic validation.
 *
 * The byte layout, CRC-16/CCITT-FALSE and 24-bit sequence codec are owned by
 * the generated protocol contract (protocol/gen/records.h, from
 * protocol/records.yaml; design 04 section 4.2). This module is the single
 * firmware boundary over that generated codec: it adds the sentinel/attach-bit
 * consistency rules from design 04 and exposes the wire size explicitly, so
 * ring code (T18) never uses sizeof(sx4_sample_rec_t) as the record size.
 *
 * Pure C11: no ESP-IDF, no heap, no host-endian assumptions. A failed decode
 * leaves the caller's record untouched.
 */
#ifndef SX4_LOG_CORE_H
#define SX4_LOG_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Wire size of one record. Readers must use this (or sample_log_record_size())
 * rather than sizeof(). The value is 18 today; a future sector-header version
 * may grow it and readers skip the trailing bytes.
 */
#define SAMPLE_LOG_RECORD_SIZE SX4_RECORD_SIZE

_Static_assert(SAMPLE_LOG_RECORD_SIZE == 18u,
               "sample record wire size is 18 bytes");
_Static_assert(SAMPLE_LOG_RECORD_SIZE == SX4_SAMPLE_REC_SIZE,
               "wire size and packed struct size must agree");

_Static_assert(SX4_TEMP_DETACHED == -32768,
               "TEMP_DETACHED must be INT16_MIN");
_Static_assert(SX4_TEMP_INVALID == -32767,
               "TEMP_INVALID must be INT16_MIN + 1");

typedef enum {
    SAMPLE_LOG_OK = 0,
    SAMPLE_LOG_ERR_ARGUMENT = -1, /* null pointer */
    SAMPLE_LOG_ERR_SIZE = -2,     /* buffer shorter than one record */
    SAMPLE_LOG_ERR_CRC = -3,      /* CRC-16 mismatch */
    SAMPLE_LOG_ERR_LAYOUT = -4,   /* attach bit and sentinel disagree */
} sample_log_status_t;

/* Wire size readers should use (18). */
size_t sample_log_record_size(void);

/*
 * Validate the in-memory record's sentinel/attachment consistency.
 *
 * For each of the four probes, the corresponding attached flag (bits 0..3)
 * must agree with the temperature sentinel:
 *   flag 0 -> temp == TEMP_DETACHED
 *   flag 1 -> temp != TEMP_DETACHED (TEMP_INVALID is allowed)
 *
 * A record that disagrees is corrupt and must not be encoded or accepted on
 * read. Returns true when the record is internally consistent.
 */
bool sample_log_record_validate(const sx4_sample_rec_t *rec);

/* Probe index 0..3; out-of-range or null returns false. */
bool sample_log_record_probe_attached(const sx4_sample_rec_t *rec,
                                      unsigned probe);

/*
 * Encode a record. seq is written as 24-bit little-endian, unix_s and the four
 * i16 temperatures little-endian, then the flags byte and the CRC over bytes
 * 0..15. Returns SAMPLE_LOG_OK and sets *out to SAMPLE_LOG_RECORD_SIZE bytes.
 *
 * SAMPLE_LOG_ERR_LAYOUT is returned (nothing written) when validation fails.
 */
sample_log_status_t sample_log_record_encode(const sx4_sample_rec_t *rec,
                                             uint8_t *out, size_t cap);

/*
 * Decode and verify one record.
 *
 * *in may contain more than one record; only the first SAMPLE_LOG_RECORD_SIZE
 * bytes are consumed, so callers can advance by sample_log_record_size().
 * Returns SAMPLE_LOG_ERR_CRC for a bad CRC and SAMPLE_LOG_ERR_LAYOUT for an
 * attach-bit/sentinel mismatch. On any error *out is untouched.
 */
sample_log_status_t sample_log_record_decode(const uint8_t *in, size_t len,
                                             sx4_sample_rec_t *out);

#ifdef __cplusplus
}
#endif

#endif /* SX4_LOG_CORE_H */
