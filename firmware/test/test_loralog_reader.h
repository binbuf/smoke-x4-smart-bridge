/* test_loralog_reader.h — minimal .loralog parser for the host suites:
 * "# comments" skipped; lines are "boot t_ms rssi snr dir class payload".
 * rssi/snr may be "?" (our own transmissions). */
#ifndef TEST_LORALOG_READER_H
#define TEST_LORALOG_READER_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int boot;
    uint64_t t_ms;
    int rssi; /* 127 = unknown */
    int snr;
    int is_tx;
    char payload[192];
} loralog_line_t;

/* Returns the number of lines read into out[], or -1 if the file cannot
 * be opened. */
static int loralog_read(const char *path, loralog_line_t *out, int max) {
    FILE *f = fopen(path, "r");
    if (!f) {
        return -1;
    }
    char line[400];
    int n = 0;
    while (n < max && fgets(line, sizeof line, f)) {
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        loralog_line_t *e = &out[n];
        char rssi_s[8], snr_s[8], dir[8], cls[16];
        unsigned long long t = 0;
        if (sscanf(line, "%d %llu %7s %7s %7s %15s %191s", &e->boot, &t,
                   rssi_s, snr_s, dir, cls, e->payload) != 7) {
            continue;
        }
        e->t_ms = t;
        e->rssi = strcmp(rssi_s, "?") == 0 ? 127 : atoi(rssi_s);
        e->snr = strcmp(snr_s, "?") == 0 ? 127 : atoi(snr_s);
        e->is_tx = strcmp(dir, "tx") == 0;
        n++;
    }
    fclose(f);
    return n;
}

#endif /* TEST_LORALOG_READER_H */
