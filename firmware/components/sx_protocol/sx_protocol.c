/*
 * sx_protocol.c - pure-C parser for Smoke X LoRa payloads.
 *
 * Ported from smoke-x-receiver (MIT (c) 2022 G-Two) via
 * legacy/firmware/components/smoke_x/smoke_x_parser.c, reworked for the real
 * X4 captures in protocol/fixtures/lora/ and the canonical storage rules in
 * design 02 section 2.5.
 *
 * No heap: the largest accepted payload is 127 bytes and is copied to a
 * fixed stack buffer. strtok_r keeps the function reentrant; strict numeric
 * parsing means a malformed field is a refusal, never a silent zero. Every
 * output is built in a local struct and published only after the whole
 * payload validates, so a rejected packet cannot leave a partial sample.
 */
#include "sx_protocol.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static sx_protocol_counters_t s_counters;

static void note_parse_failure(void) { s_counters.parse_failures++; }

/* A valid wire payload is non-empty, shorter than the buffer, ends in the
 * single trailing comma, and contains no empty field. */
static bool payload_shape_ok(const char *payload) {
    if (payload == NULL) {
        return false;
    }
    const size_t len = strlen(payload);
    if (len == 0 || len >= SX_PROTOCOL_MAX_PAYLOAD) {
        return false;
    }
    if (payload[0] == ',' || payload[len - 1] != ',') {
        return false;
    }
    return strstr(payload, ",,") == NULL;
}

/* Copy a non-empty wire token, refusing truncation rather than clipping. */
static int copy_token(char *dst, size_t dst_size, const char *src) {
    const size_t len = strlen(src);
    if (len == 0 || len >= dst_size) {
        return -1;
    }
    memcpy(dst, src, len + 1);
    return 0;
}

/* Whole-token decimal integer; trailing characters, overflow and an empty
 * token are all refusals. */
static int parse_long(const char *text, long *out) {
    char *end = NULL;
    errno = 0;
    const long value = strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0') {
        return -1;
    }
    *out = value;
    return 0;
}

static int parse_i16(const char *text, int16_t *out) {
    long value = 0;
    if (parse_long(text, &value) != 0 || value > INT16_MAX ||
        value <= SX_PROTOCOL_TEMP_INVALID) {
        return -1; /* sentinel collisions count as malformed */
    }
    *out = (int16_t)value;
    return 0;
}

static int parse_u8(const char *text, uint8_t *out) {
    long value = 0;
    if (parse_long(text, &value) != 0 || value < 0 || value > UINT8_MAX) {
        return -1;
    }
    *out = (uint8_t)value;
    return 0;
}

/* F10 = (C10 x 9) / 5 + 320 (design 02 section 2.5). C10 is finer than F10,
 * so the integer division loses nothing meaningful. */
static bool celsius_tenths_to_fahrenheit(int16_t c10, int16_t *out_f10) {
    const int32_t f10 = ((int32_t)c10 * 9) / 5 + 320;
    if (f10 > INT16_MAX || f10 <= SX_PROTOCOL_TEMP_INVALID) {
        return false;
    }
    *out_f10 = (int16_t)f10;
    return true;
}

unsigned int sx_protocol_count_commas(const char *payload) {
    unsigned int count = 0;
    if (payload == NULL) {
        return 0;
    }
    for (const char *p = payload; *p != '\0'; p++) {
        if (*p == ',') {
            count++;
        }
    }
    return count;
}

unsigned int sx_protocol_probes_for_commas(unsigned int commas) {
    if (commas == SX_PROTOCOL_NUM_COMMAS_X2) {
        return 2;
    }
    if (commas == SX_PROTOCOL_NUM_COMMAS_X4) {
        return 4;
    }
    return 0;
}

sx_protocol_result_t sx_protocol_parse_sync(const char *payload,
                                            sx_protocol_sync_t *out) {
    if (payload == NULL || out == NULL) {
        return SX_PROTOCOL_ERR_ARGUMENT;
    }
    if (!payload_shape_ok(payload) ||
        sx_protocol_count_commas(payload) != SX_PROTOCOL_NUM_COMMAS_SYNC) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    char tmp[SX_PROTOCOL_MAX_PAYLOAD];
    memcpy(tmp, payload, strlen(payload) + 1);

    char *save = NULL;
    char *token = strtok_r(tmp, ",", &save);
    if (token == NULL) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    sx_protocol_sync_t parsed;
    memset(&parsed, 0, sizeof parsed);
    if (copy_token(parsed.field0, sizeof parsed.field0, token) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    token = strtok_r(NULL, ",", &save);
    if (token == NULL ||
        copy_token(parsed.device_id, sizeof parsed.device_id, token) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    /* Frequency bytes arrive little-endian; compose explicitly so the value
     * is independent of host endianness. Range validation belongs to the
     * pairing caller (design 02 section 2.7). */
    uint32_t frequency_hz = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t byte = 0;
        token = strtok_r(NULL, ",", &save);
        if (token == NULL || parse_u8(token, &byte) != 0) {
            note_parse_failure();
            return SX_PROTOCOL_ERR_FORMAT;
        }
        frequency_hz |= (uint32_t)byte << (8 * i);
    }
    parsed.frequency_hz = frequency_hz;

    /* The trailing comma leaves only delimiters; any extra token is
     * trailing garbage. */
    if (strtok_r(NULL, ",", &save) != NULL) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    *out = parsed;
    s_counters.sync_beacons++;
    return SX_PROTOCOL_OK;
}

sx_protocol_result_t sx_protocol_parse_state(const char *payload,
                                             const char *paired_device_id,
                                             sx_protocol_state_t *out) {
    if (payload == NULL || out == NULL) {
        return SX_PROTOCOL_ERR_ARGUMENT;
    }
    if (!payload_shape_ok(payload)) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    const unsigned int commas = sx_protocol_count_commas(payload);
    const unsigned int num_probes = sx_protocol_probes_for_commas(commas);
    if (num_probes == 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    char tmp[SX_PROTOCOL_MAX_PAYLOAD];
    memcpy(tmp, payload, strlen(payload) + 1);

    char *save = NULL;
    char *token = strtok_r(tmp, ",", &save);
    if (token == NULL) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    sx_protocol_state_t parsed;
    memset(&parsed, 0, sizeof parsed);
    if (copy_token(parsed.device_id, sizeof parsed.device_id, token) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }
    parsed.num_probes = (uint8_t)num_probes;

    /* Foreign frames are dropped before the rest of the fields are parsed:
     * two Smoke X units in range must never interleave. */
    if (paired_device_id != NULL &&
        strcmp(parsed.device_id, paired_device_id) != 0) {
        s_counters.foreign_device_packets++;
        return SX_PROTOCOL_ERR_FOREIGN_DEVICE;
    }

    token = strtok_r(NULL, ",", &save);
    if (token == NULL || parse_u8(token, &parsed.hdr_field1) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    token = strtok_r(NULL, ",", &save);
    long units_raw = 0;
    if (token == NULL || parse_long(token, &units_raw) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }
    parsed.units = units_raw == 1 ? SX_PROTOCOL_UNITS_FAHRENHEIT
                                  : SX_PROTOCOL_UNITS_CELSIUS;
    parsed.source_celsius = parsed.units == SX_PROTOCOL_UNITS_CELSIUS;

    token = strtok_r(NULL, ",", &save);
    if (token == NULL || parse_u8(token, &parsed.hdr_field3) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    for (unsigned int i = 0; i < num_probes; i++) {
        sx_protocol_probe_t *probe = &parsed.probes[i];

        token = strtok_r(NULL, ",", &save);
        if (token == NULL || parse_u8(token, &probe->state) != 0) {
            note_parse_failure();
            return SX_PROTOCOL_ERR_FORMAT;
        }
        probe->attached = probe->state != 3;

        int16_t temp_active = 0;
        token = strtok_r(NULL, ",", &save);
        if (token == NULL || parse_i16(token, &temp_active) != 0) {
            note_parse_failure();
            return SX_PROTOCOL_ERR_FORMAT;
        }
        if (!probe->attached) {
            /* The X4 freezes the last reading in the temp field; that number
             * is not a temperature. Never let it reach the sample. */
            probe->temp_f10 = SX_PROTOCOL_TEMP_DETACHED;
        } else if (parsed.source_celsius) {
            if (!celsius_tenths_to_fahrenheit(temp_active,
                                              &probe->temp_f10)) {
                note_parse_failure();
                return SX_PROTOCOL_ERR_RANGE;
            }
        } else {
            probe->temp_f10 = temp_active;
        }

        long armed = 0;
        token = strtok_r(NULL, ",", &save);
        if (token == NULL || parse_long(token, &armed) != 0) {
            note_parse_failure();
            return SX_PROTOCOL_ERR_FORMAT;
        }
        probe->alarm_armed = armed != 0;

        token = strtok_r(NULL, ",", &save);
        if (token == NULL || parse_i16(token, &probe->alarm_high_deg) != 0) {
            note_parse_failure();
            return SX_PROTOCOL_ERR_FORMAT;
        }
        token = strtok_r(NULL, ",", &save);
        if (token == NULL || parse_i16(token, &probe->alarm_low_deg) != 0) {
            note_parse_failure();
            return SX_PROTOCOL_ERR_FORMAT;
        }
    }

    long billows = 0;
    token = strtok_r(NULL, ",", &save);
    if (token == NULL || parse_long(token, &billows) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }
    parsed.billows_attached = billows != 0;

    long new_alarm = 0;
    token = strtok_r(NULL, ",", &save);
    if (token == NULL || parse_long(token, &new_alarm) != 0) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }
    parsed.new_alarm = new_alarm != 0;

    /* Strict field count: no token may follow the trailing comma. */
    if (strtok_r(NULL, ",", &save) != NULL) {
        note_parse_failure();
        return SX_PROTOCOL_ERR_FORMAT;
    }

    /* T56 confirmed the relation on a real X4+Billows: probe 4's `max` equals
     * the set temp on the base at 225/250/275 °F and `min` stays 0. The target
     * is only meaningful while the Billows is attached; after detach the X4
     * falls back to the non-fan max/min defaults, so do not expose those. */
    if (parsed.billows_attached && num_probes == 4) {
        parsed.billows_target_deg = parsed.probes[3].alarm_high_deg;
        parsed.billows_target_units = parsed.units;
        parsed.billows_target_valid = true;
    }

    *out = parsed;
    s_counters.valid_state_packets++;
    return SX_PROTOCOL_OK;
}

int sx_protocol_format_ack(const char *device_id, char *buf,
                           size_t buf_size) {
    if (device_id == NULL || buf == NULL || buf_size == 0) {
        return -1;
    }
    const size_t len = strlen(device_id);
    if (len == 0 || len >= SX_PROTOCOL_DEVICE_ID_LEN ||
        strchr(device_id, ',') != NULL) {
        return -1;
    }
    const int written = snprintf(buf, buf_size, "%s,SUCCESS,", device_id);
    if (written < 0 || (size_t)written >= buf_size) {
        return -1;
    }
    s_counters.ack_attempts++;
    return written;
}

void sx_protocol_counters_get(sx_protocol_counters_t *out) {
    if (out == NULL) {
        return;
    }
    *out = s_counters;
}

void sx_protocol_counters_reset(void) { memset(&s_counters, 0, sizeof s_counters); }

void sx_protocol_note_crc_failure(void) { s_counters.crc_failures++; }

#ifdef ESP_PLATFORM
#include "esp_log.h"

static const char *TAG = "sx4.protocol";

esp_err_t sx_protocol_init(void) {
    sx_protocol_counters_reset();
    ESP_LOGD(TAG, "parser ready (no heap, %u-byte max payload)",
             (unsigned)SX_PROTOCOL_MAX_PAYLOAD);
    return ESP_OK;
}
#endif
