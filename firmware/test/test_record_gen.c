/* test_record_gen.c — the generated record codec against (a) published CRC
 * check values, (b) a hand-written hex vector, and (c) every shared golden
 * vector in protocol/fixtures/records/ — the same files the Dart tests
 * parse, asserting the same .expected values (P1.2 / P1.5).
 */
#include "record_gen.h"
#include "test_util.h"

#include <dirent.h>
#include <stdint.h>

/* ── fixture file helpers ─────────────────────────────────────────── */

static size_t read_hex(const char *path, uint8_t *out, size_t cap)
{
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return 0;
    }
    size_t n = 0;
    char line[512];
    while (fgets(line, sizeof line, f) != NULL) {
        if (line[0] == '#') {
            continue;
        }
        char *p = line;
        while (*p != '\0') {
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
                p++;
            }
            if (*p == '\0') {
                break;
            }
            unsigned v;
            if (sscanf(p, "%2x", &v) != 1 || n >= cap) {
                fclose(f);
                return 0;
            }
            out[n++] = (uint8_t)v;
            while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\r' &&
                   *p != '\n') {
                p++;
            }
        }
    }
    fclose(f);
    return n;
}

typedef struct {
    char key[32];
    char value[64];
} kv_t;

static size_t read_expected(const char *path, kv_t *out, size_t cap)
{
    FILE *f = fopen(path, "r");
    if (f == NULL) {
        return 0;
    }
    size_t n = 0;
    char line[256];
    while (fgets(line, sizeof line, f) != NULL && n < cap) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') {
            continue;
        }
        char *eq = strchr(line, '=');
        if (eq == NULL) {
            continue;
        }
        *eq = '\0';
        char *val = eq + 1;
        val[strcspn(val, "\r\n")] = '\0';
        snprintf(out[n].key, sizeof out[n].key, "%.31s", line);
        snprintf(out[n].value, sizeof out[n].value, "%.63s", val);
        n++;
    }
    fclose(f);
    return n;
}

static const char *kv_get(const kv_t *kv, size_t n, const char *key)
{
    for (size_t i = 0; i < n; i++) {
        if (strcmp(kv[i].key, key) == 0) {
            return kv[i].value;
        }
    }
    return NULL;
}

static long long kv_ll(const kv_t *kv, size_t n, const char *key)
{
    const char *v = kv_get(kv, n, key);
    CHECK(v != NULL);
    return v != NULL ? strtoll(v, NULL, 10) : 0;
}

static unsigned long long kv_ull(const kv_t *kv, size_t n, const char *key)
{
    const char *v = kv_get(kv, n, key);
    CHECK(v != NULL);
    return v != NULL ? strtoull(v, NULL, 10) : 0;
}

/* NUL-padded UTF-8 field → C string comparison against the expected value. */
static void check_padded_str(const char *field, size_t field_len,
                             const char *expected)
{
    char buf[64];
    size_t n = 0;
    while (n < field_len && field[n] != '\0' && n < sizeof buf - 1) {
        buf[n] = field[n];
        n++;
    }
    buf[n] = '\0';
    CHECK(expected != NULL && strcmp(buf, expected) == 0);
}

/* ── per-kind fixture checks ──────────────────────────────────────── */

static void check_sample(const uint8_t *bytes, size_t len, const kv_t *kv,
                         size_t n)
{
    CHECK_EQ_INT(len, BRIDGE_SAMPLE_REC_SIZE);
    bridge_sample_rec_t s;
    const bool crc_ok = bridge_sample_rec_decode(bytes, &s);
    CHECK_EQ_INT(crc_ok ? 1 : 0, kv_ll(kv, n, "crc_ok"));
    CHECK_EQ_INT(s.t, kv_ll(kv, n, "t"));
    char key[24];
    for (int i = 0; i < 4; i++) {
        snprintf(key, sizeof key, "temp%d", i);
        CHECK_EQ_INT(s.temp[i], kv_ll(kv, n, key));
        snprintf(key, sizeof key, "temp%d_null", i);
        const int is_sentinel = s.temp[i] == BRIDGE_TEMP_DETACHED ||
                                s.temp[i] == BRIDGE_TEMP_INVALID;
        CHECK_EQ_INT(is_sentinel, kv_ll(kv, n, key));
    }
    CHECK_EQ_INT(s.flags, kv_ll(kv, n, "flags"));
    CHECK_EQ_INT(bridge_sample_rec_p1_alarm(s.flags),
                 kv_ll(kv, n, "flag_p1_alarm"));
    CHECK_EQ_INT(bridge_sample_rec_p2_alarm(s.flags),
                 kv_ll(kv, n, "flag_p2_alarm"));
    CHECK_EQ_INT(bridge_sample_rec_p3_alarm(s.flags),
                 kv_ll(kv, n, "flag_p3_alarm"));
    CHECK_EQ_INT(bridge_sample_rec_p4_alarm(s.flags),
                 kv_ll(kv, n, "flag_p4_alarm"));
    CHECK_EQ_INT(bridge_sample_rec_billows(s.flags),
                 kv_ll(kv, n, "flag_billows"));
    CHECK_EQ_INT(bridge_sample_rec_new_alarm(s.flags),
                 kv_ll(kv, n, "flag_new_alarm"));
    CHECK_EQ_INT(bridge_sample_rec_source_celsius(s.flags),
                 kv_ll(kv, n, "flag_source_celsius"));
    CHECK_EQ_INT(s.rssi, kv_ll(kv, n, "rssi"));

    /* Byte-identical round-trip. */
    uint8_t out[BRIDGE_SAMPLE_REC_SIZE];
    bridge_sample_rec_encode(&s, out);
    CHECK(memcmp(out, bytes, sizeof out) == 0);
}

static void check_header(const uint8_t *bytes, size_t len, const kv_t *kv,
                         size_t n)
{
    CHECK_EQ_INT(len, BRIDGE_SESSION_HEADER_SIZE);
    bridge_session_header_t h;
    const bool crc_ok = bridge_session_header_decode(bytes, &h);
    CHECK_EQ_INT(crc_ok ? 1 : 0, kv_ll(kv, n, "crc_ok"));
    CHECK_EQ_INT(bridge_session_header_magic_ok(&h) ? 1 : 0,
                 kv_ll(kv, n, "magic_ok"));
    CHECK_EQ_INT(h.version, kv_ll(kv, n, "version"));
    CHECK_EQ_INT(h.hdr_len, kv_ll(kv, n, "hdr_len"));
    CHECK_EQ_INT(h.rec_len, kv_ll(kv, n, "rec_len"));
    CHECK_EQ_INT(h.num_probes, kv_ll(kv, n, "num_probes"));
    CHECK_EQ_INT(bridge_session_header_clock_valid(h.flags),
                 kv_ll(kv, n, "flag_clock_valid"));
    CHECK_EQ_INT(bridge_session_header_closed(h.flags),
                 kv_ll(kv, n, "flag_closed"));
    CHECK_EQ_INT(bridge_session_header_pinned(h.flags),
                 kv_ll(kv, n, "flag_pinned"));
    CHECK_EQ_INT(bridge_session_header_source_celsius(h.flags),
                 kv_ll(kv, n, "flag_source_celsius"));
    CHECK_EQ_INT(h.session_id, kv_ll(kv, n, "session_id"));
    CHECK(h.started_unix_ms == kv_ull(kv, n, "started_unix_ms"));
    CHECK(h.ended_unix_ms == kv_ull(kv, n, "ended_unix_ms"));
    CHECK_EQ_INT(h.started_uptime_s, kv_ll(kv, n, "started_uptime_s"));
    CHECK_EQ_INT(h.sample_period_s, kv_ll(kv, n, "sample_period_s"));
    CHECK_EQ_INT(h.sample_count, kv_ll(kv, n, "sample_count"));
    check_padded_str(h.device_id, sizeof h.device_id,
                     kv_get(kv, n, "device_id"));
    check_padded_str(h.name, sizeof h.name, kv_get(kv, n, "name"));
    char key[24];
    for (int i = 0; i < 4; i++) {
        snprintf(key, sizeof key, "probe_name%d", i);
        check_padded_str(h.probe_name[i], 12, kv_get(kv, n, key));
        snprintf(key, sizeof key, "probe_role%d", i);
        CHECK_EQ_INT(h.probe_role[i], kv_ll(kv, n, key));
        snprintf(key, sizeof key, "probe_target%d", i);
        CHECK_EQ_INT(h.probe_target[i], kv_ll(kv, n, key));
    }
    CHECK_EQ_INT(h.mark_count, kv_ll(kv, n, "mark_count"));

    uint8_t out[BRIDGE_SESSION_HEADER_SIZE];
    bridge_session_header_encode(&h, out);
    CHECK(memcmp(out, bytes, sizeof out) == 0);
}

static void check_mark(const uint8_t *bytes, size_t len, const kv_t *kv,
                       size_t n)
{
    CHECK_EQ_INT(len, BRIDGE_MARK_REC_SIZE);
    bridge_mark_rec_t m;
    const bool crc_ok = bridge_mark_rec_decode(bytes, &m);
    CHECK_EQ_INT(crc_ok ? 1 : 0, kv_ll(kv, n, "crc_ok"));
    CHECK_EQ_INT(m.t, kv_ll(kv, n, "t"));
    CHECK_EQ_INT(m.kind, kv_ll(kv, n, "mark_kind"));
    CHECK_EQ_INT(m.probe, kv_ll(kv, n, "probe"));
    check_padded_str(m.text, sizeof m.text, kv_get(kv, n, "text"));

    uint8_t out[BRIDGE_MARK_REC_SIZE];
    bridge_mark_rec_encode(&m, out);
    CHECK(memcmp(out, bytes, sizeof out) == 0);
}

/* ── tests ────────────────────────────────────────────────────────── */

static void test_crc_check_values(void)
{
    const uint8_t check[] = "123456789";
    CHECK_EQ_INT(bridge_crc16(check, 9), 0x29B1);
    CHECK(bridge_crc32(check, 9) == 0xCBF43926u);
}

static void test_hand_written_vector(void)
{
    /* t=1; temp = [100, DETACHED, INVALID, -580 (-58.0 °F, probe min)];
     * flags = 0x40 (source_celsius); rssi = -100; CRC-16 = 0xA8B9. */
    static const uint8_t vec[16] = {
        0x01, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x80,
        0x01, 0x80, 0xBC, 0xFD, 0x40, 0x9C, 0xB9, 0xA8,
    };
    bridge_sample_rec_t s;
    CHECK(bridge_sample_rec_decode(vec, &s));
    CHECK_EQ_INT(s.t, 1);
    CHECK_EQ_INT(s.temp[0], 100);
    CHECK_EQ_INT(s.temp[1], BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT(s.temp[2], BRIDGE_TEMP_INVALID);
    CHECK_EQ_INT(s.temp[3], -580);
    CHECK(bridge_sample_rec_source_celsius(s.flags));
    CHECK(!bridge_sample_rec_p1_alarm(s.flags));
    CHECK_EQ_INT(s.rssi, -100);

    uint8_t out[16];
    bridge_sample_rec_encode(&s, out);
    CHECK(memcmp(out, vec, 16) == 0);
}

static void test_corrupt_crc_detected(void)
{
    bridge_sample_rec_t s = {0};
    s.t = 42;
    s.temp[0] = 2431;
    uint8_t buf[16];
    bridge_sample_rec_encode(&s, buf);
    buf[4] ^= 0xFF;
    bridge_sample_rec_t d;
    CHECK(!bridge_sample_rec_decode(buf, &d));
}

static void test_fixture_corpus(void)
{
    DIR *dir = opendir(FIXTURES_DIR);
    CHECK(dir != NULL);
    if (dir == NULL) {
        return;
    }
    int fixtures_seen = 0;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        const char *dot = strrchr(ent->d_name, '.');
        if (dot == NULL || strcmp(dot, ".hex") != 0) {
            continue;
        }
        fixtures_seen++;
        char hex_path[512];
        char exp_path[512];
        snprintf(hex_path, sizeof hex_path, "%s/%s", FIXTURES_DIR,
                 ent->d_name);
        snprintf(exp_path, sizeof exp_path, "%s/%.*s.expected", FIXTURES_DIR,
                 (int)(dot - ent->d_name), ent->d_name);

        uint8_t bytes[512];
        const size_t len = read_hex(hex_path, bytes, sizeof bytes);
        kv_t kv[64];
        const size_t n = read_expected(exp_path, kv, 64);
        CHECK(len > 0);
        CHECK(n > 0);

        const char *kind = kv_get(kv, n, "kind");
        CHECK(kind != NULL);
        if (kind == NULL) {
            continue;
        }
        printf("  fixture %s (%s)\n", ent->d_name, kind);
        if (strcmp(kind, "sample") == 0) {
            check_sample(bytes, len, kv, n);
        } else if (strcmp(kind, "header") == 0) {
            check_header(bytes, len, kv, n);
        } else if (strcmp(kind, "mark") == 0) {
            check_mark(bytes, len, kv, n);
        } else {
            CHECK(!"unknown fixture kind");
        }
    }
    closedir(dir);
    /* The P1.5 corpus: 5 samples + 2 headers + 1 mark. */
    CHECK_EQ_INT(fixtures_seen, 8);
}

static void test_var_payload_roundtrip(void)
{
    bridge_live_state_t ls = {0};
    ls.ver = 1;
    ls.flags = BRIDGE_LIVE_STATE_FLAGS_PAIRED;
    ls.temp[0] = 2431;
    ls.temp[1] = BRIDGE_TEMP_DETACHED;
    ls.soc_pct = 71;
    ls.rssi_lora = -70;
    ls.session_t = 43200;
    uint8_t buf[BRIDGE_LIVE_STATE_SIZE];
    bridge_live_state_encode(&ls, buf);
    /* live_state must fit an unnegotiated 23-byte ATT MTU (R7). */
    CHECK(BRIDGE_LIVE_STATE_SIZE <= 20);
    bridge_live_state_t d;
    bridge_live_state_decode(buf, &d);
    CHECK_EQ_INT(d.temp[1], BRIDGE_TEMP_DETACHED);
    CHECK_EQ_INT(d.session_t, 43200);

    bridge_wifi_config_t wc = {0};
    wc.ver = 1;
    wc.mode = BRIDGE_NET_MODE_STA;
    wc.ssid_len = 8;
    memcpy(wc.ssid, "Backyard", 8);
    wc.psk_len = 10;
    memcpy(wc.psk, "hunter2boo", 10);
    uint8_t wire[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    const int len = bridge_wifi_config_pack(&wc, wire, sizeof wire);
    CHECK_EQ_INT(len, 6 + 8 + 10);
    bridge_wifi_config_t back;
    CHECK_EQ_INT(bridge_wifi_config_unpack(wire, (size_t)len, &back), len);
    CHECK(memcmp(back.ssid, "Backyard", 8) == 0);
    CHECK_EQ_INT(back.psk_len, 10);

    /* Truncated buffer must be rejected, not read past. */
    CHECK_EQ_INT(bridge_wifi_config_unpack(wire, (size_t)len - 3, &back), -1);
}

int main(void)
{
    test_crc_check_values();
    test_hand_written_vector();
    test_corrupt_crc_detected();
    test_fixture_corpus();
    test_var_payload_roundtrip();
    return test_summary("test_record_gen");
}
