/* test_smk_fixture.c — the committed .smk fixtures, validated through
 * record_gen.h (T2.3): header magic + CRC32, every record's CRC16, rec_len
 * striding, monotonic t, and sentinel (never zero) detached probes.
 *
 * Two fixtures, exercised by the same reader because they stress different
 * shapes of the same contract:
 *
 *   brisket-18h.smk  — SYNTHETIC. Built to carry a mid-cook detach window
 *                      and ~1 % dropout, so the reader is proven against
 *                      sentinels and gaps.
 *   overnight-18h.smk — REAL. 18.85 h of an actual Smoke X4 pulled off the
 *                      board: a clean link (no >45 s gap), four probes
 *                      attached throughout, real sensor noise on a real
 *                      cooling curve. Proves the pipeline on a pristine
 *                      capture, where "no sentinels" is the correct answer
 *                      rather than a reader that silently dropped them.
 */
#include "record_gen.h"
#include "test_util.h"

#include <stdint.h>

typedef struct {
    const char *path;
    const char *label;
    bool expect_gaps;     /* synthetic dropout must leave visible gaps */
    bool expect_detached; /* synthetic detach window vs a clean real cook */
} fixture_case_t;

static void check_fixture(const fixture_case_t *fc) {
    FILE *f = fopen(fc->path, "rb");
    CHECK(f != NULL);
    if (f == NULL) {
        return;
    }

    uint8_t hdr[BRIDGE_SESSION_HEADER_SIZE];
    CHECK_EQ_INT(fread(hdr, 1, sizeof hdr, f), sizeof hdr);

    bridge_session_header_t h;
    CHECK(bridge_session_header_decode(hdr, &h));
    CHECK(bridge_session_header_magic_ok(&h));
    CHECK_EQ_INT(h.version, BRIDGE_RECORD_VERSION);
    CHECK_EQ_INT(h.hdr_len, BRIDGE_SESSION_HEADER_SIZE);
    CHECK_EQ_INT(h.rec_len, BRIDGE_SAMPLE_REC_SIZE);
    CHECK_EQ_INT(h.num_probes, 4);
    CHECK(h.sample_count > 2000);

    /* Stride by rec_len from the header, not sizeof — the reader rule. */
    uint32_t count = 0;
    uint32_t last_t = 0;
    uint32_t gaps_over_45s = 0;
    uint32_t detached_seen = 0;
    uint32_t zero_temp_seen = 0;
    uint8_t rec[64];
    while (fread(rec, 1, h.rec_len, f) == h.rec_len) {
        bridge_sample_rec_t s;
        CHECK(bridge_sample_rec_decode(rec, &s));
        if (count > 0) {
            CHECK(s.t > last_t);
            if (s.t - last_t > 45) {
                gaps_over_45s++;
            }
        }
        for (int i = 0; i < 4; i++) {
            if (s.temp[i] == BRIDGE_TEMP_DETACHED) {
                detached_seen++;
            } else if (s.temp[i] == 0) {
                /* A real reading is never exactly 0.0 °F; a sentinel that
                 * leaked through as 0 is the bug this catches. */
                zero_temp_seen++;
            }
        }
        last_t = s.t;
        count++;
    }
    fclose(f);

    CHECK_EQ_INT(count, h.sample_count);
    CHECK_EQ_INT(zero_temp_seen, 0);
    if (fc->expect_gaps) {
        CHECK(gaps_over_45s > 0);
    } else {
        CHECK_EQ_INT(gaps_over_45s, 0);
    }
    if (fc->expect_detached) {
        CHECK(detached_seen > 50);
    } else {
        CHECK_EQ_INT(detached_seen, 0);
    }
}

int main(void) {
    const fixture_case_t cases[] = {
        {SMK_FIXTURE_SYNTH, "brisket-18h (synthetic)", true, true},
        {SMK_FIXTURE_REAL, "overnight-18h (real)", false, false},
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        check_fixture(&cases[i]);
    }
    return test_summary("test_smk_fixture");
}
