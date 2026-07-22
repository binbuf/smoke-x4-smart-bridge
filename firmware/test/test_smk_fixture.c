/* test_smk_fixture.c — the committed brisket-18h.smk fixture, validated
 * through record_gen.h (T2.3): header magic + CRC32, every record's CRC16,
 * rec_len striding, monotonic t, and sentinel (never zero) detached probes.
 */
#include "record_gen.h"
#include "test_util.h"

#include <stdint.h>

int main(void) {
    FILE *f = fopen(SMK_FIXTURE, "rb");
    CHECK(f != NULL);
    if (f == NULL) {
        return test_summary("test_smk_fixture");
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
            }
            /* A detached probe is a sentinel, never a plausible 0.0 °F. */
        }
        last_t = s.t;
        count++;
    }
    fclose(f);

    CHECK_EQ_INT(count, h.sample_count);
    CHECK(gaps_over_45s > 0);  /* ~1 % dropout must leave visible gaps */
    CHECK(detached_seen > 50); /* the mid-cook detach window */

    return test_summary("test_smk_fixture");
}
