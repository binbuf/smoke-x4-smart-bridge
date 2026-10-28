/*
 * bridge_state.c - clock, anchor persistence and the live snapshot (T20).
 *
 * Plain C11, no ESP-IDF, no heap. The clock advances from an injected
 * monotonic millisecond source and is persisted as the {unix_s, uptime_s}
 * pair through bridge_config. The snapshot is published with a sequence lock
 * so a reader never sees a half-updated copy.
 */
#include "bridge_state.h"

#include <stdatomic.h>
#include <stddef.h>
#include <string.h>

#include "bridge_config.h"

#define SECONDS_PER_MS 1000u

typedef struct {
    bridge_state_time_source_t time;

    bool clock_valid;
    bool clock_estimated;
    uint64_t base_unix_s;   /* wall time at base_uptime_ms */
    uint64_t base_uptime_ms;
    uint32_t last_anchor_uptime_s;

    bool have_record_time;
    uint32_t last_record_unix_s;

    bool have_sample;
    uint64_t last_sample_ms;

    bool persisted_once;
    uint64_t next_persist_ms;

    bridge_state_live_t live;
} bridge_state_state_t;

static bridge_state_state_t s_state;
static atomic_uint s_version;
static bridge_state_change_fn s_change_fn;
static void *s_change_ctx;

/* ---- sequence lock ------------------------------------------------------- */

static void state_write_begin(void) {
    atomic_fetch_add_explicit(&s_version, 1u, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);
}

static void state_write_end(void) {
    atomic_fetch_add_explicit(&s_version, 1u, memory_order_release);
}

/*
 * Snapshot observers run after the write completes, so they can call
 * bridge_state_snapshot() without deadlocking. They are deliberately outside
 * the seqlock: the BLE hand-off only copies 20 bytes into a bounded queue.
 */
static void notify_change(void) {
    bridge_state_change_fn fn = s_change_fn;
    if (fn != NULL) {
        fn(s_change_ctx);
    }
}

void bridge_state_set_change_hook(bridge_state_change_fn fn, void *ctx) {
    s_change_fn = fn;
    s_change_ctx = ctx;
}

static void state_read(bridge_state_state_t *out) {
    for (;;) {
        unsigned int before =
            atomic_load_explicit(&s_version, memory_order_acquire);
        if ((before & 1u) != 0u) {
            continue;
        }
        *out = s_state;
        atomic_thread_fence(memory_order_acquire);
        unsigned int after =
            atomic_load_explicit(&s_version, memory_order_relaxed);
        if (before == after) {
            return;
        }
    }
}

/* ---- time helpers -------------------------------------------------------- */

static uint64_t uptime_ms(void) {
    if (s_state.time.uptime_ms == NULL) {
        return 0;
    }
    return s_state.time.uptime_ms(s_state.time.ctx);
}

/* Caller holds the write lock (or is single-threaded during init). */
static uint64_t clock_now_s(const bridge_state_state_t *state) {
    if (!state->clock_valid || state->base_unix_s == 0) {
        return 0;
    }
    uint64_t now = uptime_ms();
    uint64_t elapsed_ms =
        now >= state->base_uptime_ms ? now - state->base_uptime_ms : 0;
    return state->base_unix_s + elapsed_ms / SECONDS_PER_MS;
}

static void clear_live(bridge_state_live_t *live) {
    memset(live, 0, sizeof(*live));
    for (unsigned int i = 0; i < BRIDGE_STATE_NUM_PROBES; i++) {
        live->temp_f10[i] = SX4_TEMP_DETACHED;
    }
    live->battery_pct = BRIDGE_STATE_SOC_UNKNOWN;
}

/* ---- init ---------------------------------------------------------------- */

bridge_state_result_t bridge_state_core_init(
    const bridge_state_time_source_t *time_source, uint32_t elapsed_sleep_s) {
    if (time_source == NULL || time_source->uptime_ms == NULL) {
        return BRIDGE_STATE_ERR_ARGUMENT;
    }

    bridge_config_clock_t stored;
    memset(&stored, 0, sizeof(stored));
    bool restored = false;
    if (bridge_config_clock_get_full(&stored) == BRIDGE_CONFIG_OK &&
        stored.valid && stored.anchor_s != 0) {
        restored = true;
    }

    state_write_begin();
    memset(&s_state, 0, sizeof(s_state));
    s_state.time = *time_source;
    clear_live(&s_state.live);

    uint64_t now = uptime_ms();
    if (restored) {
        /*
         * Advance by the part of the {anchor, uptime} pair we can trust. When
         * the uptime source survives a deep-sleep wake, now >= stored uptime;
         * a normal reboot resets it, so only the reported sleep time (if the
         * platform knows it) is added. Either way the clock is estimated.
         */
        uint64_t elapsed_ms = (uint64_t)elapsed_sleep_s * SECONDS_PER_MS;
        if (stored.uptime_s <= UINT64_MAX / SECONDS_PER_MS) {
            uint64_t stored_ms = stored.uptime_s * SECONDS_PER_MS;
            if (stored.uptime_s != 0 && now >= stored_ms) {
                elapsed_ms = now - stored_ms;
            }
        }
        s_state.clock_valid = true;
        s_state.clock_estimated = true;
        s_state.base_unix_s = stored.anchor_s + elapsed_ms / SECONDS_PER_MS;
        s_state.base_uptime_ms = now;
        s_state.last_anchor_uptime_s = (uint32_t)(now / SECONDS_PER_MS);
        s_state.persisted_once = true;
        s_state.next_persist_ms = now + BRIDGE_STATE_CLOCK_PERSIST_MS;
    } else {
        s_state.clock_valid = false;
        s_state.clock_estimated = false;
        s_state.base_unix_s = 0;
        s_state.base_uptime_ms = now;
        s_state.last_anchor_uptime_s = 0;
        s_state.persisted_once = false;
        s_state.next_persist_ms = 0;
    }
    state_write_end();
    return BRIDGE_STATE_OK;
}

/* ---- clock --------------------------------------------------------------- */

bridge_state_result_t bridge_state_now(bridge_state_clock_t *out) {
    if (out == NULL) {
        return BRIDGE_STATE_ERR_ARGUMENT;
    }
    bridge_state_state_t snapshot;
    state_read(&snapshot);
    memset(out, 0, sizeof(*out));
    if (!snapshot.clock_valid) {
        return BRIDGE_STATE_OK;
    }
    out->unix_s = clock_now_s(&snapshot);
    out->valid = out->unix_s != 0;
    out->estimated = snapshot.clock_estimated;
    out->last_anchor_uptime_s = snapshot.last_anchor_uptime_s;
    return BRIDGE_STATE_OK;
}

bridge_state_result_t bridge_state_set_time(uint64_t unix_s) {
    if (unix_s == 0) {
        return BRIDGE_STATE_ERR_ARGUMENT; /* 0 means unknown, never a time */
    }

    uint64_t now = uptime_ms();
    bridge_state_result_t result = BRIDGE_STATE_OK;
    state_write_begin();
    if (s_state.clock_valid) {
        uint64_t current = clock_now_s(&s_state);
        if (unix_s < current) {
            result = BRIDGE_STATE_ERR_TIME;
        }
    }
    if (result == BRIDGE_STATE_OK) {
        s_state.clock_valid = true;
        s_state.clock_estimated = false;
        s_state.base_unix_s = unix_s;
        s_state.base_uptime_ms = now;
        s_state.last_anchor_uptime_s = (uint32_t)(now / SECONDS_PER_MS);
        if (!s_state.persisted_once) {
            s_state.next_persist_ms = now;
        }
    }
    state_write_end();

    if (result == BRIDGE_STATE_OK) {
        /* Persist promptly on the first set; the normal 10-minute cadence
         * applies afterwards. A storage failure keeps the RAM clock valid. */
        (void)bridge_state_tick();
        notify_change();
    }
    return result;
}

bridge_state_result_t bridge_state_tick(void) {
    bridge_state_state_t snapshot;
    state_read(&snapshot);
    if (!snapshot.clock_valid) {
        return BRIDGE_STATE_OK;
    }

    uint64_t now = uptime_ms();
    if (now < snapshot.next_persist_ms) {
        return BRIDGE_STATE_OK;
    }

    uint64_t anchor_s = clock_now_s(&snapshot);
    if (anchor_s == 0) {
        return BRIDGE_STATE_OK;
    }
    bridge_config_clock_t stored = {
        .anchor_s = anchor_s,
        .uptime_s = now / SECONDS_PER_MS,
        .valid = true,
    };
    bridge_config_result_t rc = bridge_config_clock_set_full(&stored);

    state_write_begin();
    if (rc == BRIDGE_CONFIG_OK) {
        s_state.persisted_once = true;
        s_state.last_anchor_uptime_s = (uint32_t)(now / SECONDS_PER_MS);
        s_state.next_persist_ms = now + BRIDGE_STATE_CLOCK_PERSIST_MS;
    } else {
        s_state.next_persist_ms = now + BRIDGE_STATE_CLOCK_RETRY_MS;
    }
    state_write_end();

    return rc == BRIDGE_CONFIG_OK ? BRIDGE_STATE_OK
                                  : BRIDGE_STATE_ERR_STORAGE;
}

/* ---- record time --------------------------------------------------------- */

bridge_state_result_t bridge_state_stamp_record(sx4_sample_rec_t *rec) {
    if (rec == NULL) {
        return BRIDGE_STATE_ERR_ARGUMENT;
    }

    state_write_begin();
    if (s_state.clock_valid) {
        uint64_t now_s = clock_now_s(&s_state);        if (now_s > UINT32_MAX) {
            now_s = UINT32_MAX;
        }
        uint32_t stamp = (uint32_t)now_s;
        if (s_state.have_record_time && stamp < s_state.last_record_unix_s) {
            stamp = s_state.last_record_unix_s; /* never reorder timestamps */
        }
        rec->unix_s = stamp;
        rec->flags |= SX4_RECORD_FLAG_CLOCK_VALID;
        s_state.last_record_unix_s = stamp;
        s_state.have_record_time = true;
    } else {
        rec->unix_s = 0;
        rec->flags &= (uint8_t)~SX4_RECORD_FLAG_CLOCK_VALID;
    }
    state_write_end();
    return BRIDGE_STATE_OK;
}

/* ---- snapshot ------------------------------------------------------------ */

bridge_state_result_t bridge_state_update(
    const bridge_state_sample_t *sample) {
    if (sample == NULL) {
        return BRIDGE_STATE_ERR_ARGUMENT;
    }

    uint64_t now = uptime_ms();
    state_write_begin();
    bridge_state_live_t *live = &s_state.live;
    live->seq = sample->seq;
    for (unsigned int i = 0; i < BRIDGE_STATE_NUM_PROBES; i++) {
        live->temp_f10[i] = sample->temp_f10[i];
    }
    live->attached_mask =
        (uint8_t)(sample->attached_mask & ((1u << BRIDGE_STATE_NUM_PROBES) - 1u));
    live->seq = sample->seq;
    live->have_seq = sample->have_seq;
    live->billows_target_f10 = sample->billows_target_f10;
    live->billows_target_valid = sample->billows_target_valid;
    live->rssi_lora = sample->rssi_lora;
    live->snr_lora = sample->snr_lora;
    if (sample->billows_attached) {
        live->flags |= SX4_LIVE_FLAG_BILLOWS_ATTACHED;
    } else {
        live->flags &= (uint8_t)~SX4_LIVE_FLAG_BILLOWS_ATTACHED;
    }
    s_state.have_sample = true;
    s_state.last_sample_ms = now;
    state_write_end();
    notify_change();
    return BRIDGE_STATE_OK;
}

bridge_state_result_t bridge_state_snapshot(bridge_state_live_t *out) {
    if (out == NULL) {
        return BRIDGE_STATE_ERR_ARGUMENT;
    }
    bridge_state_state_t snapshot;
    state_read(&snapshot);
    uint64_t now = uptime_ms();

    *out = snapshot.live;
    uint64_t age_ms =
        snapshot.have_sample && now >= snapshot.last_sample_ms
            ? now - snapshot.last_sample_ms
            : 0;
    uint64_t age_s = age_ms / SECONDS_PER_MS;
    out->age_s = age_s > UINT16_MAX ? UINT16_MAX : (uint16_t)age_s;
    out->uptime_s = (uint32_t)(now / SECONDS_PER_MS);

    if (snapshot.clock_valid) {
        out->flags |= SX4_LIVE_FLAG_CLOCK_VALID;
    } else {
        out->flags &= (uint8_t)~SX4_LIVE_FLAG_CLOCK_VALID;
    }
    bool live = snapshot.have_sample && out->age_s <= BRIDGE_STATE_LIVE_TIMEOUT_S;
    if (live) {
        out->flags |= SX4_LIVE_FLAG_SMOKE_LIVE;
    } else {
        out->flags &= (uint8_t)~SX4_LIVE_FLAG_SMOKE_LIVE;
    }
    return BRIDGE_STATE_OK;
}

/* ---- device-level snapshot fields --------------------------------------- */

static void set_flag(uint8_t bit, bool on) {
    bool changed;
    state_write_begin();
    uint8_t before = s_state.live.flags;
    if (on) {
        s_state.live.flags |= bit;
    } else {
        s_state.live.flags &= (uint8_t)~bit;
    }
    changed = before != s_state.live.flags;
    state_write_end();
    if (changed) {
        notify_change();
    }
}

void bridge_state_set_smoke_paired(bool paired) {
    set_flag(SX4_LIVE_FLAG_SMOKE_PAIRED, paired);
}

void bridge_state_set_storage_ok(bool ok) {
    set_flag(SX4_LIVE_FLAG_STORAGE_OK, ok);
}

void bridge_state_set_display_on(bool on) {
    set_flag(SX4_LIVE_FLAG_DISPLAY_ON, on);
}

void bridge_state_set_sync_active(bool active) {
    set_flag(SX4_LIVE_FLAG_SYNC_ACTIVE, active);
}

void bridge_state_set_billows_output(bool output) {
    set_flag(SX4_LIVE_FLAG_BILLOWS_OUTPUT, output);
}

void bridge_state_set_battery(uint16_t millivolts, uint8_t percent) {
    state_write_begin();
    s_state.live.battery_mv = millivolts;
    s_state.live.battery_pct = percent;
    state_write_end();
}

void bridge_state_set_dropped_samples(uint32_t count) {
    state_write_begin();
    s_state.live.dropped_samples = count;
    state_write_end();
}
