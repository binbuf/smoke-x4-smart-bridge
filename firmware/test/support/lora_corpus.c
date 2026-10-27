#include "lora_corpus.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LORALOG_LINE_MAX 1024
#define VECTOR_COLUMNS 11

static void strip_eol(char *line) {
    size_t n = strlen(line);
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
        line[--n] = '\0';
    }
}

static int copy_text(char *dst, size_t dst_size, const char *src) {
    size_t n = strlen(src);
    if (n + 1 > dst_size) {
        return -1;
    }
    memcpy(dst, src, n + 1);
    return 0;
}

static int parse_int(const char *s, long *out) {
    char *end = NULL;
    errno = 0;
    long value = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0') {
        return -1;
    }
    *out = value;
    return 0;
}

static int parse_uint32(const char *s, uint32_t *out) {
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || value > UINT32_MAX) {
        return -1;
    }
    *out = (uint32_t)value;
    return 0;
}

unsigned sx4_count_commas(const char *s) {
    unsigned count = 0;
    if (s == NULL) {
        return 0;
    }
    for (; *s != '\0'; s++) {
        if (*s == ',') {
            count++;
        }
    }
    return count;
}

unsigned sx4_probes_for_commas(unsigned commas) {
    if (commas == 16) {
        return 2;
    }
    if (commas == 26) {
        return 4;
    }
    return 0;
}

int sx4_loralog_read(const char *path, sx4_loralog_line_t *out,
                     size_t max_lines, size_t *count) {
    if (path == NULL || out == NULL || count == NULL) {
        return -1;
    }
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return -1;
    }

    size_t n = 0;
    char line[LORALOG_LINE_MAX];
    int rc = 0;
    while (fgets(line, sizeof line, f) != NULL) {
        strip_eol(line);
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        if (n >= max_lines) {
            rc = -1;
            break;
        }

        char rssi_s[8] = {0};
        char snr_s[8] = {0};
        char dir[8] = {0};
        char cls[SX4_LORALOG_MAX_CLASS] = {0};
        char payload[SX4_LORALOG_MAX_PAYLOAD] = {0};
        int boot = 0;
        unsigned long long t_ms = 0;
        int fields = sscanf(line, "%d %llu %7s %7s %7s %15s %191[^\n]",
                            &boot, &t_ms, rssi_s, snr_s, dir, cls, payload);
        if (fields != 7) {
            rc = -1;
            break;
        }

        sx4_loralog_line_t *entry = &out[n];
        memset(entry, 0, sizeof *entry);
        entry->boot = boot;
        entry->t_ms = t_ms;
        if (strcmp(rssi_s, "?") == 0) {
            entry->rssi = 127;
        } else {
            long value = 0;
            if (parse_int(rssi_s, &value) != 0) {
                rc = -1;
                break;
            }
            entry->rssi = (int)value;
        }
        if (strcmp(snr_s, "?") == 0) {
            entry->snr = 0;
        } else {
            long value = 0;
            if (parse_int(snr_s, &value) != 0) {
                rc = -1;
                break;
            }
            entry->snr = (int)value;
        }
        if (strcmp(dir, "rx") == 0) {
            entry->is_tx = false;
        } else if (strcmp(dir, "tx") == 0) {
            entry->is_tx = true;
        } else {
            rc = -1;
            break;
        }
        memcpy(entry->cls, cls, sizeof entry->cls);
        memcpy(entry->payload, payload, sizeof entry->payload);
        n++;
    }

    fclose(f);
    if (rc != 0) {
        return -1;
    }
    *count = n;
    return 0;
}

const char *sx4_vector_kind_name(sx4_vector_kind_t kind) {
    return kind == SX4_VECTOR_KIND_SYNC ? "sync" : "state";
}

const char *sx4_vector_expect_name(sx4_vector_expect_t expect) {
    switch (expect) {
    case SX4_VECTOR_EXPECT_OK:
        return "ok";
    case SX4_VECTOR_EXPECT_REJECT:
        return "reject";
    case SX4_VECTOR_EXPECT_OK_OUT_OF_BAND:
        return "ok-out-of-band";
    default:
        return "?";
    }
}

static int split_tabs(char *line, char **fields, int max_fields) {
    int n = 0;
    fields[n++] = line;
    for (char *p = line; *p != '\0'; p++) {
        if (*p == '\t') {
            if (n >= max_fields) {
                return -1;
            }
            *p = '\0';
            fields[n++] = p + 1;
        }
    }
    return n;
}

static int parse_attached_mask(const char *text, unsigned probes,
                               unsigned *mask) {
    if (strcmp(text, "-") == 0) {
        *mask = 0;
        return 0;
    }
    if (strlen(text) != probes) {
        return -1;
    }
    unsigned value = 0;
    for (unsigned i = 0; i < probes; i++) {
        if (text[i] == '1') {
            value |= 1u << i;
        } else if (text[i] != '0') {
            return -1;
        }
    }
    *mask = value;
    return 0;
}

int sx4_vectors_read(const char *path, sx4_parser_vector_t *out, size_t max,
                     size_t *count) {
    if (path == NULL || out == NULL || count == NULL) {
        return -1;
    }
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return -1;
    }

    size_t n = 0;
    unsigned line_no = 0;
    char line[LORALOG_LINE_MAX];
    int rc = 0;
    while (fgets(line, sizeof line, f) != NULL) {
        line_no++;
        if (strchr(line, '\n') == NULL && strlen(line) == sizeof line - 1) {
            rc = -1;
            break;
        }
        strip_eol(line);
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        if (n >= max) {
            rc = -1;
            break;
        }

        char *fields[VECTOR_COLUMNS];
        if (split_tabs(line, fields, VECTOR_COLUMNS) != VECTOR_COLUMNS) {
            rc = -1;
            break;
        }

        sx4_parser_vector_t *v = &out[n];
        memset(v, 0, sizeof *v);
        v->line = line_no;
        if (copy_text(v->name, sizeof v->name, fields[0]) != 0 ||
            copy_text(v->category, sizeof v->category, fields[1]) != 0 ||
            copy_text(v->device_id, sizeof v->device_id, fields[5]) != 0 ||
            copy_text(v->provenance, sizeof v->provenance, fields[9]) != 0 ||
            copy_text(v->payload, sizeof v->payload, fields[10]) != 0) {
            rc = -1;
            break;
        }
        if (v->name[0] == '\0' || v->category[0] == '\0' ||
            v->payload[0] == '\0') {
            rc = -1;
            break;
        }

        if (strcmp(fields[2], "sync") == 0) {
            v->kind = SX4_VECTOR_KIND_SYNC;
            if (strcmp(fields[3], "-") != 0) {
                rc = -1;
                break;
            }
        } else if (strcmp(fields[2], "state") == 0) {
            v->kind = SX4_VECTOR_KIND_STATE;
            if (strcmp(fields[3], "2") == 0) {
                v->probes = 2;
            } else if (strcmp(fields[3], "4") == 0) {
                v->probes = 4;
            } else {
                rc = -1;
                break;
            }
        } else {
            rc = -1;
            break;
        }

        if (strcmp(fields[4], "ok") == 0) {
            v->expect = SX4_VECTOR_EXPECT_OK;
        } else if (strcmp(fields[4], "reject") == 0) {
            v->expect = SX4_VECTOR_EXPECT_REJECT;
        } else if (strcmp(fields[4], "ok-out-of-band") == 0) {
            v->expect = SX4_VECTOR_EXPECT_OK_OUT_OF_BAND;
        } else {
            rc = -1;
            break;
        }

        if (strcmp(fields[6], "-") == 0) {
            v->units = '-';
        } else if (strcmp(fields[6], "F") == 0 ||
                   strcmp(fields[6], "C") == 0) {
            v->units = fields[6][0];
        } else {
            rc = -1;
            break;
        }

        if (v->kind == SX4_VECTOR_KIND_SYNC) {
            if (strcmp(fields[7], "-") != 0) {
                rc = -1;
                break;
            }
            if (strcmp(fields[8], "-") == 0) {
                v->frequency = 0;
            } else if (parse_uint32(fields[8], &v->frequency) != 0) {
                rc = -1;
                break;
            }
        } else {
            if (strcmp(fields[8], "-") != 0) {
                rc = -1;
                break;
            }
            if (parse_attached_mask(fields[7], v->probes,
                                    &v->attached_mask) != 0) {
                rc = -1;
                break;
            }
        }

        n++;
    }

    fclose(f);
    if (rc != 0) {
        fprintf(stderr, "parser-vectors: malformed row ending at line %u\n",
                line_no);
        return -1;
    }
    *count = n;
    return 0;
}
