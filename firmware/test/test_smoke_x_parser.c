/* Host tests for the smoke_x parser (F3.1–F3.5).
 *
 * Seed corpus ported from the reference's test_smoke_x_parser.c (MIT © 2022
 * G-Two), then extended with real X4 vectors from the 2026-07-21 capture
 * (protocol/fixtures/lora/x4-events-10min.loralog). Two reference-era
 * assertions are deliberately inverted by that evidence:
 *   - new_alarm lives in the trailing field (the reference read header
 *     field 3, which rests at 1 on a real X4 — permanently "alarmed")
 *   - a detached X4 probe freezes its last temp; only the state field is
 *     trustworthy, so detached must parse to the sentinel
 */
#include <string.h>

#include "smoke_x_parser.h"
#include "test_util.h"

/* Real X2 packet captured from a device log (reference corpus). */
static const char *X2_REAL = "|abCDe,30,1,1,0,848,1,125,32,0,849,0,260,195,0,0,";

/* Real X4 packets captured off the air, 2026-07-21. */
static const char *X4_SYNC = "000000,LMXC[\\,160,50,191,54,";
static const char *X4_BASELINE =
    "LMXC[\\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,"
    "32,0,0,";
static const char *X4_ALARM_EDGE =
    "LMXC[\\,30,1,2,0,1052,1,105,32,0,822,0,160,32,0,829,0,160,32,0,835,0,"
    "160,32,0,1,";
static const char *X4_DETACHED_FROZEN =
    "LMXC[\\,30,1,1,0,1054,0,160,32,0,797,0,160,32,0,790,0,160,32,3,809,0,"
    "160,32,0,0,";
static const char *X4_CELSIUS =
    "LMXC[\\,30,0,1,0,381,1,37,8,0,285,0,71,0,0,288,0,71,0,0,273,0,71,0,0,0,";

static void test_count_commas(void) {
    CHECK_EQ_INT(smoke_x_parser_count_commas(X2_REAL),
                 SMOKE_X_PARSER_NUM_COMMAS_X2);
    CHECK_EQ_INT(smoke_x_parser_count_commas(X4_BASELINE),
                 SMOKE_X_PARSER_NUM_COMMAS_X4);
    CHECK_EQ_INT(smoke_x_parser_count_commas(X4_SYNC),
                 SMOKE_X_PARSER_NUM_COMMAS_SYNC);
    CHECK_EQ_INT(smoke_x_parser_count_commas(""), 0);
    CHECK_EQ_INT(smoke_x_parser_count_commas(NULL), 0);
}

static void test_probes_for_commas(void) {
    CHECK_EQ_INT(smoke_x_parser_probes_for_commas(16), 2);
    CHECK_EQ_INT(smoke_x_parser_probes_for_commas(26), 4);
    CHECK_EQ_INT(smoke_x_parser_probes_for_commas(6), 0);
    CHECK_EQ_INT(smoke_x_parser_probes_for_commas(0), 0);
}

static void test_parse_x2_real_packet(void) {
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(X2_REAL, 2, &out), 0);
    CHECK_EQ_INT(out.num_probes, 2);
    CHECK(strcmp(out.device_id, "|abCDe") == 0);
    CHECK_EQ_INT(out.hdr_field1, 30);
    CHECK_EQ_INT(out.units, SMOKE_X_UNITS_F);
    CHECK_EQ_INT(out.hdr_field3, 1);
    /* Reference read new_alarm from header field 3 (== 1 here); the real X4
     * capture shows the trailing field is the alarm pulse, and it is 0. */
    CHECK(!out.new_alarm);

    CHECK(out.probes[0].attached);
    CHECK_EQ_INT(out.probes[0].temp_x10, 848);
    CHECK(out.probes[0].alarm_armed);
    CHECK_EQ_INT(out.probes[0].alarm_high, 125);
    CHECK_EQ_INT(out.probes[0].alarm_low, 32);

    CHECK(out.probes[1].attached);
    CHECK_EQ_INT(out.probes[1].temp_x10, 849);
    CHECK(!out.probes[1].alarm_armed);
    CHECK_EQ_INT(out.probes[1].alarm_high, 260);
    CHECK_EQ_INT(out.probes[1].alarm_low, 195);

    CHECK(!out.billows_attached);
}

static void test_parse_x4_real_baseline(void) {
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_BASELINE, 4, &out), 0);
    CHECK(strcmp(out.device_id, "LMXC[\\") == 0);
    CHECK_EQ_INT(out.num_probes, 4);
    CHECK_EQ_INT(out.units, SMOKE_X_UNITS_F);
    CHECK_EQ_INT(out.probes[0].temp_x10, 811);
    CHECK_EQ_INT(out.probes[1].temp_x10, 801);
    CHECK_EQ_INT(out.probes[2].temp_x10, 807);
    CHECK_EQ_INT(out.probes[3].temp_x10, 807);
    for (int i = 0; i < 4; i++) {
        CHECK(out.probes[i].attached);
        CHECK(!out.probes[i].alarm_armed);
        CHECK_EQ_INT(out.probes[i].alarm_high, 160);
        CHECK_EQ_INT(out.probes[i].alarm_low, 32);
    }
    CHECK(!out.billows_attached);
    CHECK(!out.new_alarm);
}

static void test_parse_x4_alarm_edge(void) {
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_ALARM_EDGE, 4, &out), 0);
    CHECK_EQ_INT(out.hdr_field3, 2);
    CHECK(out.probes[0].alarm_armed);
    CHECK_EQ_INT(out.probes[0].alarm_high, 105);
    CHECK_EQ_INT(out.probes[0].temp_x10, 1052);
    CHECK(out.new_alarm); /* trailing field, edge-triggered (Q8) */
}

static void test_parse_x4_detached_freezes_temp(void) {
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_DETACHED_FROZEN, 4, &out), 0);
    CHECK(!out.probes[3].attached);
    CHECK_EQ_INT(out.probes[3].state, 3);
    /* The wire said 809 — a frozen stale reading. The sentinel, never the
     * number, is what reaches the caller. */
    CHECK_EQ_INT(out.probes[3].temp_x10, SMOKE_X_TEMP_DETACHED);
    CHECK(out.probes[0].attached);
    CHECK_EQ_INT(out.probes[0].temp_x10, 1054);
}

static void test_parse_x2_detached_zeroed(void) {
    /* The X2 zeroes the group on detach (reference corpus) — same sentinel. */
    const char *raw = "|abCDe,30,1,0,0,848,0,125,32,3,0,0,0,0,0,0,";
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(raw, 2, &out), 0);
    CHECK(out.probes[0].attached);
    CHECK(!out.probes[1].attached);
    CHECK_EQ_INT(out.probes[1].temp_x10, SMOKE_X_TEMP_DETACHED);
}

static void test_parse_celsius_real(void) {
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_CELSIUS, 4, &out), 0);
    CHECK_EQ_INT(out.units, SMOKE_X_UNITS_C);
    /* Tenths of the ACTIVE unit: 381 = 38.1 °C, and the alarm band is whole
     * degrees C (99/47 °F became 37/8 on air). */
    CHECK_EQ_INT(out.probes[0].temp_x10, 381);
    CHECK_EQ_INT(out.probes[0].alarm_high, 37);
    CHECK_EQ_INT(out.probes[0].alarm_low, 8);
    CHECK_EQ_INT(out.probes[1].alarm_high, 71);
    CHECK_EQ_INT(out.probes[1].alarm_low, 0);
}

static void test_units_change_detected_by_value(void) {
    /* F3.3: a unit change is a value comparison — surviving memcpy, unlike
     * the reference's pointer-identity check. */
    smoke_x_state_t f = {0}, c = {0}, copy;
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_BASELINE, 4, &f), 0);
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_CELSIUS, 4, &c), 0);
    memcpy(&copy, &f, sizeof copy);
    CHECK(copy.units == f.units);
    CHECK(copy.units != c.units);
}

static void test_parse_billows(void) {
    const char *raw = "|abCDe,30,1,0,0,848,0,125,32,0,849,0,260,195,1,0,";
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(raw, 2, &out), 0);
    CHECK(out.billows_attached);
    /* The overloaded target field decodes as alarm_high (D11: stored, no
     * v1 feature on top). */
    CHECK_EQ_INT(out.probes[0].alarm_high, 125);
}

static void test_parse_sync_real_x4(void) {
    smoke_x_sync_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_sync(X4_SYNC, &out), 0);
    CHECK(strcmp(out.field0, "000000") == 0);
    CHECK(strcmp(out.device_id, "LMXC[\\") == 0);
    CHECK(out.frequency == 918500000u);
}

static void test_parse_sync_reference_vector(void) {
    const char *raw = "020001,|abCDe,160,32,69,54,";
    smoke_x_sync_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_sync(raw, &out), 0);
    CHECK(strcmp(out.field0, "020001") == 0);
    CHECK(strcmp(out.device_id, "|abCDe") == 0);
    CHECK(out.frequency == 910500000u);
}

static void test_parse_sync_rejects_bad_inputs(void) {
    smoke_x_sync_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_sync(NULL, &out), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_sync(X4_SYNC, NULL), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_sync("", &out), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_sync("020001,|abCDe,160,32,", &out), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_sync("020001,|abCDe,160,32,69,xx,", &out),
                 -1);
}

static void test_format_success(void) {
    char buf[32];
    const int n = smoke_x_parser_format_success("|abCDe", buf, sizeof buf);
    CHECK(n > 0);
    CHECK(strcmp(buf, "|abCDe,SUCCESS,") == 0);
    CHECK_EQ_INT(n, (int)strlen("|abCDe,SUCCESS,"));
    CHECK_EQ_INT(smoke_x_parser_count_commas(buf),
                 SMOKE_X_PARSER_NUM_COMMAS_SUCCESS);
}

static void test_format_success_rejects_overflow(void) {
    char buf[8];
    CHECK_EQ_INT(smoke_x_parser_format_success("|abCDe", buf, sizeof buf), -1);
    CHECK_EQ_INT(smoke_x_parser_format_success(NULL, buf, sizeof buf), -1);
    CHECK_EQ_INT(smoke_x_parser_format_success("|abCDe", NULL, sizeof buf), -1);
    CHECK_EQ_INT(smoke_x_parser_format_success("|abCDe", buf, 0), -1);
}

static void test_parse_rejects_bad_inputs(void) {
    smoke_x_state_t out = {0};
    CHECK_EQ_INT(smoke_x_parser_parse_state(NULL, 2, &out), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_state(X2_REAL, 2, NULL), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_state(X2_REAL, 3, &out), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_state("", 2, &out), -1);
    CHECK_EQ_INT(smoke_x_parser_parse_state("|too,short", 2, &out), -1);
    /* Truncated mid-group. */
    CHECK_EQ_INT(
        smoke_x_parser_parse_state("|abCDe,30,1,0,0,848,0,125,", 2, &out), -1);
    /* Non-numeric temp must refuse, not read as zero. */
    CHECK_EQ_INT(smoke_x_parser_parse_state(
                     "|abCDe,30,1,0,0,8x8,1,125,32,0,849,0,260,195,0,0,", 2,
                     &out),
                 -1);
    /* Trailing garbage beyond the field count. */
    CHECK_EQ_INT(smoke_x_parser_parse_state(
                     "|abCDe,30,1,0,0,848,1,125,32,0,849,0,260,195,0,0,7,", 2,
                     &out),
                 -1);
    /* An X4 payload parsed as an X2 comes up short — wrong probe count must
     * not "work". */
    CHECK_EQ_INT(smoke_x_parser_parse_state(X4_BASELINE, 2, &out), -1);
    /* Oversized payload is rejected, not truncated. */
    char big[SMOKE_X_PARSER_MAX_PAYLOAD + 8];
    memset(big, '1', sizeof big - 1);
    big[sizeof big - 1] = '\0';
    CHECK_EQ_INT(smoke_x_parser_parse_state(big, 2, &out), -1);
}

int main(void) {
    test_count_commas();
    test_probes_for_commas();
    test_parse_x2_real_packet();
    test_parse_x4_real_baseline();
    test_parse_x4_alarm_edge();
    test_parse_x4_detached_freezes_temp();
    test_parse_x2_detached_zeroed();
    test_parse_celsius_real();
    test_units_change_detected_by_value();
    test_parse_billows();
    test_parse_sync_real_x4();
    test_parse_sync_reference_vector();
    test_parse_sync_rejects_bad_inputs();
    test_format_success();
    test_format_success_rejects_overflow();
    test_parse_rejects_bad_inputs();
    return test_summary("test_smoke_x_parser");
}
