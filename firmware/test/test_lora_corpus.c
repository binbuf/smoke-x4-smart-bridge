/* F3.8: the parser against the WHOLE committed capture corpus — every real
 * payload in protocol/fixtures/lora/ must parse to sane values, and every
 * payload in the adversarial corpus must be refused. This is the test that
 * runs real air, not synthetic vectors. */
#include <string.h>

#include "smoke_x_parser.h"
#include "test_loralog_reader.h"
#include "test_util.h"

#define MAX_LINES 512

static loralog_line_t g_lines[MAX_LINES];

static void check_real_capture(const char *name, int expect_min_states) {
    char path[256];
    snprintf(path, sizeof path, "%s/%s", FIXTURES_LORA_DIR, name);
    const int n = loralog_read(path, g_lines, MAX_LINES);
    CHECK(n > 0);

    int states = 0, syncs = 0;
    for (int i = 0; i < n; i++) {
        const loralog_line_t *e = &g_lines[i];
        if (e->is_tx) {
            continue; /* our own ACK */
        }
        const unsigned commas = smoke_x_parser_count_commas(e->payload);
        const unsigned probes = smoke_x_parser_probes_for_commas(commas);
        if (commas == SMOKE_X_PARSER_NUM_COMMAS_SYNC) {
            smoke_x_sync_t sync;
            CHECK_EQ_INT(smoke_x_parser_parse_sync(e->payload, &sync), 0);
            /* A real sync always decodes to an in-band frequency. */
            CHECK(sync.frequency >= 902000000u &&
                  sync.frequency <= 928000000u);
            syncs++;
            continue;
        }
        CHECK(probes != 0); /* every real capture line classifies */
        if (probes == 0) {
            continue;
        }
        smoke_x_state_t st;
        CHECK_EQ_INT(smoke_x_parser_parse_state(e->payload, probes, &st), 0);
        CHECK_EQ_INT(st.hdr_field1, 30); /* Q1: never left 30 */
        for (unsigned p = 0; p < probes; p++) {
            const int16_t v = st.probes[p].temp_x10;
            /* Attached probes read a plausible temperature; detached
             * probes read the sentinel and nothing else. */
            if (st.probes[p].attached) {
                CHECK(v > -600 && v < 6000);
            } else {
                CHECK_EQ_INT(v, SMOKE_X_TEMP_DETACHED);
            }
        }
        states++;
    }
    CHECK(states >= expect_min_states);
    (void)syncs;
}

static void test_real_captures_parse(void) {
    check_real_capture("x4-events-10min.loralog", 30);
    check_real_capture("x4-passive-session.loralog", 50);
    check_real_capture("first-x4-contact.loralog", 1);
}

static void test_known_values_from_the_event_capture(void) {
    char path[256];
    snprintf(path, sizeof path, "%s/x4-events-10min.loralog",
             FIXTURES_LORA_DIR);
    const int n = loralog_read(path, g_lines, MAX_LINES);
    CHECK(n > 30);

    /* The sync beacon: field0 000000 (not the X2 docs' 020001), 918.5 MHz. */
    smoke_x_sync_t sync;
    CHECK_EQ_INT(smoke_x_parser_parse_sync(g_lines[0].payload, &sync), 0);
    CHECK(strcmp(sync.field0, "000000") == 0);
    CHECK(sync.frequency == 918500000u);

    /* Every new_alarm pulse in the capture lasts exactly one packet. */
    int pulses = 0, sustained = 0;
    bool prev = false;
    for (int i = 0; i < n; i++) {
        if (g_lines[i].is_tx) {
            continue;
        }
        const unsigned probes = smoke_x_parser_probes_for_commas(
            smoke_x_parser_count_commas(g_lines[i].payload));
        if (probes == 0) {
            continue;
        }
        smoke_x_state_t st;
        if (smoke_x_parser_parse_state(g_lines[i].payload, probes, &st) !=
            0) {
            continue;
        }
        if (st.new_alarm) {
            if (prev) {
                sustained++;
            } else {
                pulses++;
            }
        }
        prev = st.new_alarm;
    }
    CHECK_EQ_INT(pulses, 3);    /* three alarm events that night */
    CHECK_EQ_INT(sustained, 0); /* edge-triggered: never two in a row */
}

static void test_malformed_corpus_is_refused(void) {
    char path[256];
    snprintf(path, sizeof path, "%s/malformed.loralog", FIXTURES_LORA_DIR);
    const int n = loralog_read(path, g_lines, MAX_LINES);
    CHECK(n >= 10);
    for (int i = 0; i < n; i++) {
        smoke_x_state_t st;
        smoke_x_sync_t sync;
        /* No parser accepts an adversarial payload — no crash, no silent
         * zero, just -1 from every entry point. */
        CHECK_EQ_INT(smoke_x_parser_parse_state(g_lines[i].payload, 2, &st),
                     -1);
        CHECK_EQ_INT(smoke_x_parser_parse_state(g_lines[i].payload, 4, &st),
                     -1);
        CHECK_EQ_INT(smoke_x_parser_parse_sync(g_lines[i].payload, &sync),
                     -1);
    }
}

int main(void) {
    test_real_captures_parse();
    test_known_values_from_the_event_capture();
    test_malformed_corpus_is_refused();
    return test_summary("test_lora_corpus");
}
