/* smoke_x_novelty — the novelty seen-set (F4.2, design 02 §2.7).
 *
 * Logging every raw packet costs ~345 KB/24 h; instead a seen-set of the
 * values every normally-constant field has ever taken persists a packet
 * only when something is NEW. Six of the eight open protocol questions
 * close by themselves once this runs in the background of every cook.
 *
 * Reason names follow the design table; two are mapped onto the field
 * layout proven by x4-events-10min: `trailing` watches header field 3 (the
 * remaining mystery field — rests at 1, dances to 2), and `alarm_edge`
 * watches the trailing new_alarm field's rising edge, capturing the packet
 * on each side of the transition.
 *
 * Pure C11 over an injected sink; persistence (F4.3) attaches later.
 */
#ifndef SMOKE_X_NOVELTY_H
#define SMOKE_X_NOVELTY_H

#include <stdint.h>

#include "smoke_x_parser.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SMOKE_X_NOVEL_FIRST = 0,   /* first packet of each state/unknown class */
    SMOKE_X_NOVEL_FIELD1,      /* Q1: header field 1 leaves 30 */
    SMOKE_X_NOVEL_TRAILING,    /* header field 3 takes an unseen value */
    SMOKE_X_NOVEL_PROBE_STATE, /* Q4: probe state neither 0 nor 3 */
    SMOKE_X_NOVEL_ALARM_EDGE,  /* Q8: new_alarm rising edge, both packets */
    SMOKE_X_NOVEL_BILLOWS,     /* Q5: billows flips or target moves */
    SMOKE_X_NOVEL_UNITS,       /* units field changes */
    SMOKE_X_NOVEL_SYNC,        /* Q2/Q6: unseen sync content */
    SMOKE_X_NOVEL_UNPARSED,    /* unknown comma count or parse failure */
    SMOKE_X_NOVEL_ID_MISMATCH, /* foreign device on our channel */
    SMOKE_X_NOVEL_REASON_COUNT,
} smoke_x_novelty_reason_t;

typedef struct {
    smoke_x_novelty_reason_t reason;
    char value[24];   /* the dedupe key detail, human-readable */
    char payload[SMOKE_X_PARSER_MAX_PAYLOAD];
    /* alarm_edge carries the packet BEFORE the transition too. */
    char prev_payload[SMOKE_X_PARSER_MAX_PAYLOAD];
    uint64_t t_ms;
    int8_t rssi;
    int8_t snr;
} smoke_x_novelty_entry_t;

typedef void (*smoke_x_novelty_sink_t)(const smoke_x_novelty_entry_t *entry,
                                       void *ctx);

const char *smoke_x_novelty_reason_name(smoke_x_novelty_reason_t r);

/* Resets all seen-sets. Known-normal values are pre-seeded (field1=30,
 * hdr_field3=1, probe states 0 and 3) so the steady state produces zero
 * entries from the first packet on. */
void smoke_x_novelty_init(smoke_x_novelty_sink_t sink, void *ctx);

/* Observe one received payload. Independent of the pairing controller so
 * dropped packets (foreign, malformed) still leave evidence. `paired_id`
 * is the current pairing (or NULL/"" when unpaired). */
void smoke_x_novelty_observe(const char *payload, const char *paired_id,
                             int8_t rssi, int8_t snr, uint64_t t_ms);

#ifdef __cplusplus
}
#endif

#endif /* SMOKE_X_NOVELTY_H */
