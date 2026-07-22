/* smoke_x_parser.c — pure-C parser for Smoke X LoRa payloads.
 *
 * Ported from smoke-x-receiver (MIT © 2022 G-Two); reworked per F3.2–F3.5
 * and the real X4 captures in protocol/fixtures/lora/. No heap (a ~120 B
 * max payload fits a stack buffer), strtok_r throughout, strict numeric
 * parsing — a non-numeric field is a parse error, never a silent zero.
 */
#include "smoke_x_parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned int smoke_x_parser_count_commas(const char *msg) {
    if (!msg) {
        return 0;
    }
    unsigned int n = 0;
    for (const char *p = msg; *p; p++) {
        if (*p == ',') {
            n++;
        }
    }
    return n;
}

unsigned int smoke_x_parser_probes_for_commas(unsigned int commas) {
    if (commas == SMOKE_X_PARSER_NUM_COMMAS_X2) {
        return 2;
    }
    if (commas == SMOKE_X_PARSER_NUM_COMMAS_X4) {
        return 4;
    }
    return 0;
}

/* Whole-token decimal integer; anything else is a refusal. */
static int parse_long(const char *t, long *out) {
    char *end;
    const long v = strtol(t, &end, 10);
    if (end == t || *end != '\0') {
        return -1;
    }
    *out = v;
    return 0;
}

static int parse_i16(const char *t, int16_t *out) {
    long v;
    if (parse_long(t, &v) != 0 || v > INT16_MAX || v <= SMOKE_X_TEMP_INVALID) {
        return -1; /* sentinel collision counts as malformed */
    }
    *out = (int16_t)v;
    return 0;
}

static int parse_u8(const char *t, uint8_t *out) {
    long v;
    if (parse_long(t, &v) != 0 || v < 0 || v > 255) {
        return -1;
    }
    *out = (uint8_t)v;
    return 0;
}

static int copy_payload(const char *msg, char *buf, size_t buf_size) {
    const size_t len = strlen(msg);
    if (len == 0 || len >= buf_size) {
        return -1;
    }
    memcpy(buf, msg, len + 1);
    return 0;
}

int smoke_x_parser_parse_sync(const char *msg, smoke_x_sync_t *out) {
    if (!msg || !out) {
        return -1;
    }
    char tmp[SMOKE_X_PARSER_MAX_PAYLOAD];
    if (copy_payload(msg, tmp, sizeof tmp) != 0) {
        return -1;
    }

    char *save;
    char *t = strtok_r(tmp, ",", &save);
    if (!t) {
        return -1;
    }
    snprintf(out->field0, sizeof out->field0, "%s", t);

    t = strtok_r(NULL, ",", &save);
    if (!t) {
        return -1;
    }
    snprintf(out->device_id, sizeof out->device_id, "%s", t);

    /* Frequency bytes arrive little-endian; compose explicitly so the
     * result is independent of host endianness. */
    uint32_t freq = 0;
    for (int i = 0; i < 4; i++) {
        t = strtok_r(NULL, ",", &save);
        uint8_t b;
        if (!t || parse_u8(t, &b) != 0) {
            return -1;
        }
        freq |= (uint32_t)b << (8 * i);
    }
    out->frequency = freq;
    return 0;
}

int smoke_x_parser_parse_state(const char *msg, unsigned int num_probes,
                               smoke_x_state_t *out) {
    if (!msg || !out || (num_probes != 2 && num_probes != 4)) {
        return -1;
    }
    char tmp[SMOKE_X_PARSER_MAX_PAYLOAD];
    if (copy_payload(msg, tmp, sizeof tmp) != 0) {
        return -1;
    }

    char *save;
    char *t = strtok_r(tmp, ",", &save);
    if (!t) {
        return -1;
    }
    /* Captured, not discarded: the controller compares it against the
     * paired ID so two Smoke X units in range cannot interleave (F3.4). */
    snprintf(out->device_id, sizeof out->device_id, "%s", t);
    out->num_probes = (uint8_t)num_probes;

    t = strtok_r(NULL, ",", &save);
    if (!t || parse_u8(t, &out->hdr_field1) != 0) {
        return -1;
    }

    t = strtok_r(NULL, ",", &save);
    long units_raw;
    if (!t || parse_long(t, &units_raw) != 0) {
        return -1;
    }
    out->units = units_raw == 1 ? SMOKE_X_UNITS_F : SMOKE_X_UNITS_C;

    t = strtok_r(NULL, ",", &save);
    if (!t || parse_u8(t, &out->hdr_field3) != 0) {
        return -1;
    }

    for (unsigned int i = 0; i < num_probes; i++) {
        smoke_x_probe_t *p = &out->probes[i];
        t = strtok_r(NULL, ",", &save);
        if (!t || parse_u8(t, &p->state) != 0) {
            return -1;
        }
        p->attached = p->state != 3;

        int16_t temp;
        t = strtok_r(NULL, ",", &save);
        if (!t || parse_i16(t, &temp) != 0) {
            return -1;
        }
        /* A detached probe's temp field freezes at its last reading on the
         * X4 (and reads 0 on the X2) — either way it is not a temperature.
         * The sentinel makes it structurally unable to reach a graph. */
        p->temp_x10 = p->attached ? temp : SMOKE_X_TEMP_DETACHED;

        long armed;
        t = strtok_r(NULL, ",", &save);
        if (!t || parse_long(t, &armed) != 0) {
            return -1;
        }
        p->alarm_armed = armed != 0;

        t = strtok_r(NULL, ",", &save);
        if (!t || parse_i16(t, &p->alarm_high) != 0) {
            return -1;
        }
        t = strtok_r(NULL, ",", &save);
        if (!t || parse_i16(t, &p->alarm_low) != 0) {
            return -1;
        }
    }

    long v;
    t = strtok_r(NULL, ",", &save);
    if (!t || parse_long(t, &v) != 0) {
        return -1;
    }
    out->billows_attached = v != 0;

    t = strtok_r(NULL, ",", &save);
    if (!t || parse_long(t, &v) != 0) {
        return -1;
    }
    out->new_alarm = v != 0;

    /* Strict field count: trailing garbage is a malformed payload. */
    if (strtok_r(NULL, ",", &save) != NULL) {
        return -1;
    }
    return 0;
}

int smoke_x_parser_format_success(const char *device_id, char *buf,
                                  size_t buf_size) {
    if (!device_id || !buf || buf_size == 0) {
        return -1;
    }
    const int n = snprintf(buf, buf_size, "%s,SUCCESS,", device_id);
    if (n < 0 || (size_t)n >= buf_size) {
        return -1;
    }
    return n;
}
