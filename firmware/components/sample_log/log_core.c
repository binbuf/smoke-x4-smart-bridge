/*
 * log_core.c - firmware-facing sample-record codec (T17).
 *
 * The generated protocol codec owns the bytes; this file owns the record
 * semantics: compile-time size agreement, explicit wire size, and the
 * sentinel/attach-bit consistency rule. See log_core.h.
 */

#include "log_core.h"

#include <string.h>

size_t sample_log_record_size(void) { return SAMPLE_LOG_RECORD_SIZE; }

bool sample_log_record_probe_attached(const sx4_sample_rec_t *rec,
                                      unsigned probe) {
    if (rec == NULL || probe >= 4u) {
        return false;
    }
    return (rec->flags & (uint8_t)(1u << probe)) != 0;
}

bool sample_log_record_validate(const sx4_sample_rec_t *rec) {
    if (rec == NULL) {
        return false;
    }
    for (unsigned probe = 0; probe < 4u; probe++) {
        const bool attached = sample_log_record_probe_attached(rec, probe);
        const bool detached = sx4_temp_is_detached(rec->temp[probe]);
        /* The fast-filter bit must agree with the sentinel in both
         * directions: attached=0 with a numeric temp is corrupt, and
         * attached=1 with TEMP_DETACHED is equally corrupt. */
        if (attached == detached) {
            return false;
        }
    }
    return true;
}

sample_log_status_t sample_log_record_encode(const sx4_sample_rec_t *rec,
                                             uint8_t *out, size_t cap) {
    if (rec == NULL || out == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (cap < SAMPLE_LOG_RECORD_SIZE) {
        return SAMPLE_LOG_ERR_SIZE;
    }
    if (!sample_log_record_validate(rec)) {
        return SAMPLE_LOG_ERR_LAYOUT;
    }
    /* The generated encoder returns 0 on failure; cap was already checked. */
    if (sx4_sample_rec_encode(rec, out, cap) != SAMPLE_LOG_RECORD_SIZE) {
        return SAMPLE_LOG_ERR_SIZE;
    }
    return SAMPLE_LOG_OK;
}

sample_log_status_t sample_log_record_decode(const uint8_t *in, size_t len,
                                             sx4_sample_rec_t *out) {
    if (in == NULL || out == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (len < SAMPLE_LOG_RECORD_SIZE) {
        return SAMPLE_LOG_ERR_SIZE;
    }

    /* Decode into a local so a rejected record never exposes partial data. */
    sx4_sample_rec_t decoded;
    memset(&decoded, 0, sizeof(decoded));
    if (!sx4_sample_rec_decode(in, SAMPLE_LOG_RECORD_SIZE, &decoded)) {
        return SAMPLE_LOG_ERR_CRC;
    }
    if (!sample_log_record_validate(&decoded)) {
        return SAMPLE_LOG_ERR_LAYOUT;
    }

    *out = decoded;
    return SAMPLE_LOG_OK;
}
