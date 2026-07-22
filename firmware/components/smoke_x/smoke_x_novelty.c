/* smoke_x_novelty — seen-set novelty detection (F4.2, design 02 §2.7). */
#include "smoke_x_novelty.h"

#include <stdio.h>
#include <string.h>

#define MAX_SEEN 96

typedef struct {
    uint8_t reason;
    char value[24];
} seen_key_t;

static smoke_x_novelty_sink_t s_sink;
static void *s_sink_ctx;

static seen_key_t s_seen[MAX_SEEN];
static int s_seen_count;

/* Baselines seeded silently by the first state packet, so whatever state a
 * cook starts in never fires; only departures from it do. */
static bool s_units_seeded;
static bool s_billows_seeded;

/* alarm_edge: the packet before the transition. */
static bool s_have_prev_state;
static bool s_prev_new_alarm;
static char s_prev_payload[SMOKE_X_PARSER_MAX_PAYLOAD];

static const char *const k_reason_names[SMOKE_X_NOVEL_REASON_COUNT] = {
    "first",  "field1", "trailing", "probe_state", "alarm_edge",
    "billows", "units",  "sync",     "unparsed",    "id_mismatch",
};

const char *smoke_x_novelty_reason_name(smoke_x_novelty_reason_t r) {
    return (r < SMOKE_X_NOVEL_REASON_COUNT) ? k_reason_names[r] : "?";
}

/* True when (reason, value) was newly added — i.e. novel. */
static bool mark_seen(smoke_x_novelty_reason_t reason, const char *value) {
    for (int i = 0; i < s_seen_count; i++) {
        if (s_seen[i].reason == reason &&
            strncmp(s_seen[i].value, value, sizeof s_seen[i].value) == 0) {
            return false;
        }
    }
    if (s_seen_count >= MAX_SEEN) {
        return false; /* full: stop reporting rather than thrash */
    }
    s_seen[s_seen_count].reason = (uint8_t)reason;
    snprintf(s_seen[s_seen_count].value, sizeof s_seen[s_seen_count].value,
             "%s", value);
    s_seen_count++;
    return true;
}

static void emit(smoke_x_novelty_reason_t reason, const char *value,
                 const char *payload, const char *prev, int8_t rssi,
                 int8_t snr, uint64_t t_ms) {
    if (!s_sink) {
        return;
    }
    smoke_x_novelty_entry_t e;
    e.reason = reason;
    snprintf(e.value, sizeof e.value, "%s", value);
    snprintf(e.payload, sizeof e.payload, "%s", payload);
    snprintf(e.prev_payload, sizeof e.prev_payload, "%s", prev ? prev : "");
    e.t_ms = t_ms;
    e.rssi = rssi;
    e.snr = snr;
    s_sink(&e, s_sink_ctx);
}

static void note(smoke_x_novelty_reason_t reason, const char *value,
                 const char *payload, const char *prev, int8_t rssi,
                 int8_t snr, uint64_t t_ms) {
    if (mark_seen(reason, value)) {
        emit(reason, value, payload, prev, rssi, snr, t_ms);
    }
}

void smoke_x_novelty_init(smoke_x_novelty_sink_t sink, void *ctx) {
    s_sink = sink;
    s_sink_ctx = ctx;
    s_seen_count = 0;
    s_units_seeded = false;
    s_billows_seeded = false;
    s_have_prev_state = false;

    /* Known-normal values never fire: field1 has only ever been 30, header
     * field 3 rests at 1, probe states 0 (attached) and 3 (detached) are
     * expected (x4-events-10min). */
    mark_seen(SMOKE_X_NOVEL_FIELD1, "30");
    mark_seen(SMOKE_X_NOVEL_TRAILING, "1");
    mark_seen(SMOKE_X_NOVEL_PROBE_STATE, "0");
    mark_seen(SMOKE_X_NOVEL_PROBE_STATE, "3");
}

static void observe_state(const char *payload, unsigned int num_probes,
                          const char *paired_id, int8_t rssi, int8_t snr,
                          uint64_t t_ms) {
    smoke_x_state_t st;
    if (smoke_x_parser_parse_state(payload, num_probes, &st) != 0) {
        char v[24];
        snprintf(v, sizeof v, "%.23s", payload);
        note(SMOKE_X_NOVEL_UNPARSED, v, payload, NULL, rssi, snr, t_ms);
        return;
    }

    /* A foreign device's values must not poison our seen-sets. */
    if (paired_id && paired_id[0] != '\0' &&
        strncmp(st.device_id, paired_id, SMOKE_X_DEVICE_ID_LEN) != 0) {
        note(SMOKE_X_NOVEL_ID_MISMATCH, st.device_id, payload, NULL, rssi,
             snr, t_ms);
        return;
    }

    char v[24];
    snprintf(v, sizeof v, "state%u", num_probes == 4 ? 26u : 16u);
    note(SMOKE_X_NOVEL_FIRST, v, payload, NULL, rssi, snr, t_ms);

    snprintf(v, sizeof v, "%u", st.hdr_field1);
    note(SMOKE_X_NOVEL_FIELD1, v, payload, NULL, rssi, snr, t_ms);

    snprintf(v, sizeof v, "%u", st.hdr_field3);
    note(SMOKE_X_NOVEL_TRAILING, v, payload, NULL, rssi, snr, t_ms);

    for (unsigned int i = 0; i < num_probes; i++) {
        snprintf(v, sizeof v, "%u", st.probes[i].state);
        note(SMOKE_X_NOVEL_PROBE_STATE, v, payload, NULL, rssi, snr, t_ms);
    }

    /* alarm_edge: rising edge of new_alarm, both packets kept (Q8). */
    if (s_have_prev_state && !s_prev_new_alarm && st.new_alarm) {
        note(SMOKE_X_NOVEL_ALARM_EDGE, "rising", payload, s_prev_payload,
             rssi, snr, t_ms);
    }

    /* billows / units: value-keyed with a silent baseline, so a flip fires
     * once per distinct value and flipping back never re-fires. The billows
     * key folds in the overloaded target so a target move is novel too. */
    if (st.billows_attached) {
        snprintf(v, sizeof v, "1@%d", st.probes[0].alarm_high);
    } else {
        snprintf(v, sizeof v, "0");
    }
    if (!s_billows_seeded) {
        s_billows_seeded = true;
        mark_seen(SMOKE_X_NOVEL_BILLOWS, v);
    } else {
        note(SMOKE_X_NOVEL_BILLOWS, v, payload, NULL, rssi, snr, t_ms);
    }

    snprintf(v, sizeof v, "%d", (int)st.units);
    if (!s_units_seeded) {
        s_units_seeded = true;
        mark_seen(SMOKE_X_NOVEL_UNITS, v);
    } else {
        note(SMOKE_X_NOVEL_UNITS, v, payload, NULL, rssi, snr, t_ms);
    }

    s_have_prev_state = true;
    s_prev_new_alarm = st.new_alarm;
    snprintf(s_prev_payload, sizeof s_prev_payload, "%s", payload);
}

void smoke_x_novelty_observe(const char *payload, const char *paired_id,
                             int8_t rssi, int8_t snr, uint64_t t_ms) {
    if (!payload) {
        return;
    }
    const unsigned int commas = smoke_x_parser_count_commas(payload);

    if (commas == SMOKE_X_PARSER_NUM_COMMAS_SYNC) {
        smoke_x_sync_t sync;
        char v[24];
        if (smoke_x_parser_parse_sync(payload, &sync) == 0) {
            snprintf(v, sizeof v, "%s@%lu", sync.field0,
                     (unsigned long)sync.frequency);
            note(SMOKE_X_NOVEL_SYNC, v, payload, NULL, rssi, snr, t_ms);
        } else {
            snprintf(v, sizeof v, "%.23s", payload);
            note(SMOKE_X_NOVEL_UNPARSED, v, payload, NULL, rssi, snr, t_ms);
        }
        return;
    }

    const unsigned int probes = smoke_x_parser_probes_for_commas(commas);
    if (probes != 0) {
        observe_state(payload, probes, paired_id, rssi, snr, t_ms);
        return;
    }

    char v[24];
    snprintf(v, sizeof v, "%.23s", payload);
    note(SMOKE_X_NOVEL_UNPARSED, v, payload, NULL, rssi, snr, t_ms);
}
