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

static size_t read_hex(const char *path, uint8_t *out, size_t cap) {
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

static size_t read_expected(const char *path, kv_t *out, size_t cap) {
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

static const char *kv_get(const kv_t *kv, size_t n, const char *key) {
    for (size_t i = 0; i < n; i++) {
        if (strcmp(kv[i].key, key) == 0) {
            return kv[i].value;
        }
    }
    return NULL;
}

static long long kv_ll(const kv_t *kv, size_t n, const char *key) {
    const char *v = kv_get(kv, n, key);
    CHECK(v != NULL);
    return v != NULL ? strtoll(v, NULL, 10) : 0;
}

static unsigned long long kv_ull(const kv_t *kv, size_t n, const char *key) {
    const char *v = kv_get(kv, n, key);
    CHECK(v != NULL);
    return v != NULL ? strtoull(v, NULL, 10) : 0;
}

/* NUL-padded UTF-8 field → C string comparison against the expected value. */
static void check_padded_str(const char *field, size_t field_len,
                             const char *expected) {
    char buf[64];
    size_t n = 0;
    while (n < field_len && field[n] != '\0' && n < sizeof buf - 1) {
        buf[n] = field[n];
        n++;
    }
    buf[n] = '\0';
    CHECK(expected != NULL && strcmp(buf, expected) == 0);
}

/* Length-delimited (NOT NUL-padded) field — the BLE variable payloads. */
static void check_len_str(const char *field, size_t len, const char *expected) {
    char buf[80];
    if (len >= sizeof buf) {
        CHECK(!"length-delimited field longer than the test buffer");
        return;
    }
    memcpy(buf, field, len);
    buf[len] = '\0';
    CHECK(expected != NULL && strcmp(buf, expected) == 0);
}

/* ── per-kind fixture checks ──────────────────────────────────────── */

static void check_sample(const uint8_t *bytes, size_t len, const kv_t *kv,
                         size_t n) {
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
                         size_t n) {
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
                       size_t n) {
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

/* ── BLE payload fixture checks (P3.2, ble-gatt §5) ───────────────── */

static void check_device_info(const uint8_t *bytes, size_t len, const kv_t *kv,
                              size_t n) {
    CHECK_EQ_INT(len, BRIDGE_DEVICE_INFO_SIZE);
    bridge_device_info_t d;
    bridge_device_info_decode(bytes, &d);
    CHECK_EQ_INT(d.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(d.api, kv_ll(kv, n, "api"));
    CHECK_EQ_INT(d.probes, kv_ll(kv, n, "probes"));
    CHECK_EQ_INT(d.caps, kv_ll(kv, n, "caps"));
    CHECK_EQ_INT(bridge_device_info_wifi_ap(d.caps), kv_ll(kv, n, "cap_wifi_ap"));
    CHECK_EQ_INT(bridge_device_info_wifi_sta(d.caps),
                 kv_ll(kv, n, "cap_wifi_sta"));
    CHECK_EQ_INT(bridge_device_info_wifi_enterprise(d.caps),
                 kv_ll(kv, n, "cap_wifi_enterprise"));
    CHECK_EQ_INT(bridge_device_info_history_preview(d.caps),
                 kv_ll(kv, n, "cap_history_preview"));
    CHECK_EQ_INT(bridge_device_info_ota(d.caps), kv_ll(kv, n, "cap_ota"));
    CHECK_EQ_INT(bridge_device_info_battery(d.caps),
                 kv_ll(kv, n, "cap_battery"));
    check_padded_str(d.id, sizeof d.id, kv_get(kv, n, "id"));
    check_padded_str(d.model, sizeof d.model, kv_get(kv, n, "model"));
    check_padded_str(d.fw, sizeof d.fw, kv_get(kv, n, "fw"));

    uint8_t out[BRIDGE_DEVICE_INFO_SIZE];
    bridge_device_info_encode(&d, out);
    CHECK(memcmp(out, bytes, sizeof out) == 0);
}

static void check_wifi_scan_ctrl(const uint8_t *bytes, size_t len,
                                 const kv_t *kv, size_t n) {
    CHECK_EQ_INT(len, BRIDGE_WIFI_SCAN_CTRL_SIZE);
    bridge_wifi_scan_ctrl_t c;
    bridge_wifi_scan_ctrl_decode(bytes, &c);
    CHECK_EQ_INT(c.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(c.cmd, kv_ll(kv, n, "cmd"));

    uint8_t out[BRIDGE_WIFI_SCAN_CTRL_SIZE];
    bridge_wifi_scan_ctrl_encode(&c, out);
    CHECK(memcmp(out, bytes, sizeof out) == 0);
}

static void check_live_state(const uint8_t *bytes, size_t len, const kv_t *kv,
                             size_t n) {
    CHECK_EQ_INT(len, BRIDGE_LIVE_STATE_SIZE);
    bridge_live_state_t s;
    bridge_live_state_decode(bytes, &s);
    CHECK_EQ_INT(s.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(s.flags, kv_ll(kv, n, "flags"));
    CHECK_EQ_INT(bridge_live_state_paired(s.flags), kv_ll(kv, n, "flag_paired"));
    CHECK_EQ_INT(bridge_live_state_session_active(s.flags),
                 kv_ll(kv, n, "flag_session_active"));
    CHECK_EQ_INT(bridge_live_state_billows(s.flags),
                 kv_ll(kv, n, "flag_billows"));
    CHECK_EQ_INT(bridge_live_state_alarm_active(s.flags),
                 kv_ll(kv, n, "flag_alarm_active"));
    CHECK_EQ_INT(bridge_live_state_clock_valid(s.flags),
                 kv_ll(kv, n, "flag_clock_valid"));
    char key[24];
    for (int i = 0; i < 4; i++) {
        snprintf(key, sizeof key, "temp%d", i);
        CHECK_EQ_INT(s.temp[i], kv_ll(kv, n, key));
        snprintf(key, sizeof key, "temp%d_null", i);
        const int is_sentinel = s.temp[i] == BRIDGE_TEMP_DETACHED ||
                                s.temp[i] == BRIDGE_TEMP_INVALID;
        CHECK_EQ_INT(is_sentinel, kv_ll(kv, n, key));
    }
    CHECK_EQ_INT(s.soc_pct, kv_ll(kv, n, "soc_pct"));
    CHECK_EQ_INT(s.soc_pct == BRIDGE_SOC_UNKNOWN, kv_ll(kv, n, "soc_unknown"));
    CHECK_EQ_INT(s.rssi_lora, kv_ll(kv, n, "rssi_lora"));
    CHECK_EQ_INT(s.session_t, kv_ll(kv, n, "session_t"));

    uint8_t out[BRIDGE_LIVE_STATE_SIZE];
    bridge_live_state_encode(&s, out);
    CHECK(memcmp(out, bytes, sizeof out) == 0);
}

static void check_net_status(const uint8_t *bytes, size_t len, const kv_t *kv,
                             size_t n) {
    bridge_net_status_t s;
    CHECK_EQ_INT(bridge_net_status_unpack(bytes, len, &s), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(s.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(s.mode, kv_ll(kv, n, "mode"));
    CHECK_EQ_INT(s.state, kv_ll(kv, n, "state"));
    CHECK_EQ_INT(s.wifi_rssi, kv_ll(kv, n, "wifi_rssi"));
    char ip[20];
    snprintf(ip, sizeof ip, "%u.%u.%u.%u", s.ip[0], s.ip[1], s.ip[2], s.ip[3]);
    const char *ip_exp = kv_get(kv, n, "ip");
    CHECK(ip_exp != NULL && strcmp(ip, ip_exp) == 0);
    check_len_str(s.ssid, s.ssid_len, kv_get(kv, n, "ssid"));
    check_len_str(s.host, s.host_len, kv_get(kv, n, "host"));

    uint8_t out[BRIDGE_NET_STATUS_MAX_SIZE];
    CHECK_EQ_INT(bridge_net_status_pack(&s, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_wifi_scan_result(const uint8_t *bytes, size_t len,
                                   const kv_t *kv, size_t n) {
    bridge_wifi_scan_result_t r;
    CHECK_EQ_INT(bridge_wifi_scan_result_unpack(bytes, len, &r), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(r.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(r.index, kv_ll(kv, n, "index"));
    CHECK_EQ_INT(r.total, kv_ll(kv, n, "total"));
    CHECK_EQ_INT(r.rssi, kv_ll(kv, n, "rssi"));
    CHECK_EQ_INT(r.auth, kv_ll(kv, n, "auth"));
    CHECK_EQ_INT(r.channel, kv_ll(kv, n, "channel"));
    check_len_str(r.ssid, r.ssid_len, kv_get(kv, n, "ssid"));

    uint8_t out[BRIDGE_WIFI_SCAN_RESULT_MAX_SIZE];
    CHECK_EQ_INT(bridge_wifi_scan_result_pack(&r, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_wifi_config(const uint8_t *bytes, size_t len, const kv_t *kv,
                              size_t n) {
    bridge_wifi_config_t c;
    CHECK_EQ_INT(bridge_wifi_config_unpack(bytes, len, &c), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(c.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(c.mode, kv_ll(kv, n, "mode"));
    CHECK_EQ_INT(c.auth, kv_ll(kv, n, "auth"));
    check_len_str(c.ssid, c.ssid_len, kv_get(kv, n, "ssid"));
    check_len_str(c.psk, c.psk_len, kv_get(kv, n, "psk"));
    check_len_str(c.user, c.user_len, kv_get(kv, n, "user"));

    uint8_t out[BRIDGE_WIFI_CONFIG_MAX_SIZE];
    CHECK_EQ_INT(bridge_wifi_config_pack(&c, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_device_control(const uint8_t *bytes, size_t len,
                                 const kv_t *kv, size_t n) {
    bridge_device_control_t c;
    CHECK_EQ_INT(bridge_device_control_unpack(bytes, len, &c), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(c.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(c.op, kv_ll(kv, n, "op"));
    CHECK_EQ_INT(c.body_len, kv_ll(kv, n, "body_len"));
    if (c.op == BRIDGE_CONTROL_OP_SET_TIME) {
        CHECK_EQ_INT(c.body_len, BRIDGE_CTRL_SET_TIME_SIZE);
        bridge_ctrl_set_time_t t;
        bridge_ctrl_set_time_decode(c.body, &t);
        CHECK(t.unix_ms == kv_ull(kv, n, "unix_ms"));
        CHECK_EQ_INT(t.tz_offset_min, kv_ll(kv, n, "tz_offset_min"));
    }

    uint8_t out[BRIDGE_DEVICE_CONTROL_MAX_SIZE];
    CHECK_EQ_INT(bridge_device_control_pack(&c, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_result(const uint8_t *bytes, size_t len, const kv_t *kv,
                         size_t n) {
    bridge_result_t r;
    CHECK_EQ_INT(bridge_result_unpack(bytes, len, &r), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(r.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(r.op_echo, kv_ll(kv, n, "op_echo"));
    CHECK_EQ_INT(r.status, kv_ll(kv, n, "status"));
    check_len_str(r.detail, r.len, kv_get(kv, n, "detail"));

    uint8_t out[BRIDGE_RESULT_MAX_SIZE];
    CHECK_EQ_INT(bridge_result_pack(&r, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_history_preview(const uint8_t *bytes, size_t len,
                                  const kv_t *kv, size_t n) {
    bridge_history_preview_t h;
    CHECK_EQ_INT(bridge_history_preview_unpack(bytes, len, &h), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(h.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(h.probe_index, kv_ll(kv, n, "probe_index"));
    CHECK_EQ_INT(h.count, kv_ll(kv, n, "count"));
    CHECK_EQ_INT(h.bucket_min, kv_ll(kv, n, "bucket_min"));
    CHECK(h.count <= 120);
    char key[24];
    for (int i = 0; i < h.count; i++) {
        snprintf(key, sizeof key, "v%d", i);
        CHECK_EQ_INT(h.values[i], kv_ll(kv, n, key));
        snprintf(key, sizeof key, "v%d_null", i);
        const int is_sentinel = h.values[i] == BRIDGE_TEMP_DETACHED ||
                                h.values[i] == BRIDGE_TEMP_INVALID;
        CHECK_EQ_INT(is_sentinel, kv_ll(kv, n, key));
    }

    uint8_t out[BRIDGE_HISTORY_PREVIEW_MAX_SIZE];
    CHECK_EQ_INT(bridge_history_preview_pack(&h, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

/* ── v1.1 full history over BLE (§5.10–§5.11) ─────────────────────── */

static void check_history_ctrl(const uint8_t *bytes, size_t len,
                               const kv_t *kv, size_t n) {
    CHECK_EQ_INT(len, BRIDGE_HISTORY_CTRL_SIZE);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    bridge_history_ctrl_t c;
    bridge_history_ctrl_decode(bytes, &c);
    CHECK_EQ_INT(c.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(c.req, kv_ll(kv, n, "req"));
    CHECK_EQ_INT(c.stride, kv_ll(kv, n, "stride"));
    CHECK_EQ_INT(c.session_id, kv_ll(kv, n, "session_id"));
    CHECK_EQ_INT(c.from_t, kv_ll(kv, n, "from_t"));
    CHECK(c.to_t == (uint32_t)kv_ll(kv, n, "to_t"));

    uint8_t out[BRIDGE_HISTORY_CTRL_SIZE];
    bridge_history_ctrl_encode(&c, out);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_history_session(const uint8_t *bytes, size_t len,
                                  const kv_t *kv, size_t n) {
    CHECK_EQ_INT(len, BRIDGE_HISTORY_SESSION_SIZE);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    bridge_history_session_t s;
    bridge_history_session_decode(bytes, &s);
    CHECK_EQ_INT(s.session_id, kv_ll(kv, n, "session_id"));
    CHECK(s.started_unix_ms == (uint64_t)kv_ll(kv, n, "started_unix_ms"));
    CHECK(s.ended_unix_ms == (uint64_t)kv_ll(kv, n, "ended_unix_ms"));
    CHECK_EQ_INT(s.sample_count, kv_ll(kv, n, "sample_count"));
    CHECK_EQ_INT(s.sample_period_s, kv_ll(kv, n, "sample_period_s"));
    CHECK_EQ_INT(s.num_probes, kv_ll(kv, n, "num_probes"));
    CHECK_EQ_INT(s.flags, kv_ll(kv, n, "flags"));
    CHECK_EQ_INT(bridge_history_session_clock_valid(s.flags),
                 kv_ll(kv, n, "flag_clock_valid"));
    CHECK_EQ_INT(bridge_history_session_closed(s.flags),
                 kv_ll(kv, n, "flag_closed"));
    CHECK_EQ_INT(bridge_history_session_pinned(s.flags),
                 kv_ll(kv, n, "flag_pinned"));
    /* The em-dash auto-name of 04 §4.6 is 26 BYTES; a 24-byte field
     * clipped it, which is why this one is 28. Held here so a future
     * shrink is a red test rather than a truncated cook name. */
    check_padded_str(s.name, sizeof s.name, kv_get(kv, n, "name"));

    uint8_t out[BRIDGE_HISTORY_SESSION_SIZE];
    bridge_history_session_encode(&s, out);
    CHECK(memcmp(out, bytes, len) == 0);
}

static void check_history_data(const uint8_t *bytes, size_t len,
                               const kv_t *kv, size_t n) {
    bridge_history_data_t f;
    CHECK_EQ_INT(bridge_history_data_unpack(bytes, len, &f), (int)len);
    CHECK_EQ_INT(len, kv_ll(kv, n, "wire_len"));
    CHECK_EQ_INT(f.ver, kv_ll(kv, n, "ver"));
    CHECK_EQ_INT(f.kind, kv_ll(kv, n, "data_kind"));
    CHECK_EQ_INT(f.seq, kv_ll(kv, n, "seq"));
    CHECK_EQ_INT(f.flags, kv_ll(kv, n, "flags"));
    CHECK_EQ_INT(bridge_history_data_last(f.flags), kv_ll(kv, n, "last"));
    CHECK_EQ_INT(f.count, kv_ll(kv, n, "count"));
    CHECK_EQ_INT(f.len, kv_ll(kv, n, "len"));
    /* The 7-byte fixed prefix must arrive whole in the first chunk even at
     * the 20-byte default MTU — the §4 guarantee the client's reassembler
     * reads the length from. */
    CHECK(len - f.len == 7u);

    if (f.kind == BRIDGE_HISTORY_KIND_SAMPLES) {
        CHECK_EQ_INT(f.len, f.count * BRIDGE_SAMPLE_REC_SIZE);
        /* Records travel VERBATIM: decoding one straight out of the frame
         * payload must reproduce what was written, CRC included. */
        for (int i = 0; i < f.count; i++) {
            bridge_sample_rec_t rec;
            /* decode returns the CRC verdict: a record that travelled
             * verbatim still verifies, which is the whole reason the
             * stream does not re-encode. */
            CHECK(bridge_sample_rec_decode(
                f.payload + i * BRIDGE_SAMPLE_REC_SIZE, &rec));
            char key[24];
            snprintf(key, sizeof key, "s%d_t", i);
            CHECK_EQ_INT(rec.t, kv_ll(kv, n, key));
        }
        CHECK_EQ_INT(kv_ll(kv, n, "s1_temp2_null"), 1);
    } else if (f.kind == BRIDGE_HISTORY_KIND_END) {
        /* The terminator is the only frame that reports a status, and it
         * always carries exactly one byte of it. */
        CHECK_EQ_INT(f.count, 0);
        CHECK_EQ_INT(f.len, 1);
        CHECK_EQ_INT(f.payload[0], kv_ll(kv, n, "status"));
        CHECK(bridge_history_data_last(f.flags));
    }

    uint8_t out[BRIDGE_HISTORY_DATA_MAX_SIZE];
    CHECK_EQ_INT(bridge_history_data_pack(&f, out, sizeof out), (int)len);
    CHECK(memcmp(out, bytes, len) == 0);
}

/* ── tests ────────────────────────────────────────────────────────── */

static void test_crc_check_values(void) {
    const uint8_t check[] = "123456789";
    CHECK_EQ_INT(bridge_crc16(check, 9), 0x29B1);
    CHECK(bridge_crc32(check, 9) == 0xCBF43926u);
}

static void test_hand_written_vector(void) {
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

static void test_corrupt_crc_detected(void) {
    bridge_sample_rec_t s = {0};
    s.t = 42;
    s.temp[0] = 2431;
    uint8_t buf[16];
    bridge_sample_rec_encode(&s, buf);
    buf[4] ^= 0xFF;
    bridge_sample_rec_t d;
    CHECK(!bridge_sample_rec_decode(buf, &d));
}

static void test_fixture_corpus(void) {
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
        snprintf(hex_path, sizeof hex_path, "%s/%s", FIXTURES_DIR, ent->d_name);
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
        } else if (strcmp(kind, "device_info") == 0) {
            check_device_info(bytes, len, kv, n);
        } else if (strcmp(kind, "wifi_scan_ctrl") == 0) {
            check_wifi_scan_ctrl(bytes, len, kv, n);
        } else if (strcmp(kind, "live_state") == 0) {
            check_live_state(bytes, len, kv, n);
        } else if (strcmp(kind, "net_status") == 0) {
            check_net_status(bytes, len, kv, n);
        } else if (strcmp(kind, "wifi_scan_result") == 0) {
            check_wifi_scan_result(bytes, len, kv, n);
        } else if (strcmp(kind, "wifi_config") == 0) {
            check_wifi_config(bytes, len, kv, n);
        } else if (strcmp(kind, "device_control") == 0) {
            check_device_control(bytes, len, kv, n);
        } else if (strcmp(kind, "result") == 0) {
            check_result(bytes, len, kv, n);
        } else if (strcmp(kind, "history_preview") == 0) {
            check_history_preview(bytes, len, kv, n);
        } else if (strcmp(kind, "history_ctrl") == 0) {
            check_history_ctrl(bytes, len, kv, n);
        } else if (strcmp(kind, "history_session") == 0) {
            check_history_session(bytes, len, kv, n);
        } else if (strcmp(kind, "history_data") == 0) {
            check_history_data(bytes, len, kv, n);
        } else {
            CHECK(!"unknown fixture kind");
        }
    }
    closedir(dir);
    /* The P1.5 corpus (5 samples + 2 headers + 1 mark) plus P3.2's twelve
     * BLE payload vectors — one per characteristic, plus the states that
     * have historically been got wrong (sentinels, AP vs STA, cancel) —
     * plus v1.1's four history vectors (§5.10–§5.11: the request, a
     * session entry, a mid-stream samples frame, the terminator). */
    CHECK_EQ_INT(fixtures_seen, 24);
}

static void test_var_payload_roundtrip(void) {
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

int main(void) {
    test_crc_check_values();
    test_hand_written_vector();
    test_corrupt_crc_detected();
    test_fixture_corpus();
    test_var_payload_roundtrip();
    return test_summary("test_record_gen");
}
