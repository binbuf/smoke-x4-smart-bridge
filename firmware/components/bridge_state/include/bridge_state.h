/*
 * bridge_state.h - live snapshot, wall clock and counters (design 03 sections
 * 3.5, 3.6 and 3.8; design 04 section 4.4).
 *
 * The core (bridge_state.c) is plain C11 with no ESP-IDF dependency. Time comes
 * from an injected monotonic millisecond source; the anchor pair is persisted
 * through bridge_config, the only NVS owner. bridge_state_esp.c installs the
 * ESP timer and is the firmware boot hook.
 *
 * Clock rules:
 *   - unix_s == 0 means "unknown"; records then carry unix_s = 0 and clear the
 *     clock-valid flag.
 *   - A restored anchor is marked estimated until the app calls
 *     bridge_state_set_time().
 *   - set_time() never moves the clock backwards; corrections affect future
 *     records only.
 *   - The anchor pair {unix_s, uptime_s} is written at most once per
 *     BRIDGE_STATE_CLOCK_PERSIST_MS (10 minutes), never per sample.
 */
#ifndef SX4_BRIDGE_STATE_H
#define SX4_BRIDGE_STATE_H

#include <stdbool.h>
#include <stdint.h>

#include "records.h" /* SX4_LIVE_FLAG_*, SX4_TEMP_*, SX4_BATTERY_UNKNOWN */

#ifdef __cplusplus
extern "C" {
#endif

/* Anchor cadence: at most one NVS write per ten minutes. */
#define BRIDGE_STATE_CLOCK_PERSIST_MS (10u * 60u * 1000u)
/* Retry delay after a failed anchor write. */
#define BRIDGE_STATE_CLOCK_RETRY_MS (60u * 1000u)
/* The UI's liveness rule (design 03 section 3.6). */
#define BRIDGE_STATE_LIVE_TIMEOUT_S 90u
#define BRIDGE_STATE_NUM_PROBES 4u

typedef enum {
    BRIDGE_STATE_OK = 0,
    BRIDGE_STATE_ERR_ARGUMENT = -1,
    BRIDGE_STATE_ERR_TIME = -2,    /* correction would move time backwards */
    BRIDGE_STATE_ERR_STORAGE = -3, /* anchor write failed; retry later */
    BRIDGE_STATE_ERR_NOT_READY = -4,
} bridge_state_result_t;

/* Monotonic millisecond source. The firmware installs esp_timer_get_time();
 * the host test installs a fake clock. The source must not run backwards. */
typedef struct {
    uint64_t (*uptime_ms)(void *ctx);
    void *ctx;
} bridge_state_time_source_t;

typedef struct {
    uint64_t unix_s;               /* current best UTC seconds; 0 = unknown */
    bool valid;                    /* time is known (exact or estimated) */
    bool estimated;                /* restored from NVS, not app-set yet */
    uint32_t last_anchor_uptime_s; /* uptime of the current RAM anchor */
} bridge_state_clock_t;

/*
 * One immutable copy of the live values read by the UI and (later) BLE `live`.
 * `flags` uses SX4_LIVE_FLAG_*; clock/liveness/billows bits are recomputed on
 * every snapshot read. Unknown battery is BRIDGE_STATE_SOC_UNKNOWN.
 */
typedef struct {
    uint32_t seq;              /* last stored sample sequence */
    bool have_seq;             /* false before the first stored sample */
    int16_t temp_f10[BRIDGE_STATE_NUM_PROBES]; /* canonical F tenths */
    uint8_t attached_mask;     /* bit 0..3: probe attached in the last sample */
    uint8_t flags;             /* SX4_LIVE_FLAG_* */
    int16_t billows_target_f10; /* 0 when unavailable */
    bool billows_target_valid;  /* false until the Billows relation is proven */
    uint16_t age_s;            /* seconds since the last valid state packet */
    uint32_t uptime_s;         /* device uptime at snapshot read */
    uint16_t battery_mv;
    uint8_t battery_pct;       /* 255 = unknown */
    int8_t rssi_lora;
    int8_t snr_lora;
} bridge_state_live_t;

/* One validated state packet from sample_pipe (T21). */
typedef struct {
    uint32_t seq;
    bool have_seq;         /* true when the log assigned `seq` to this sample */
    int16_t temp_f10[BRIDGE_STATE_NUM_PROBES];
    uint8_t attached_mask; /* bit 0..3 */
    bool billows_attached;
    int16_t billows_target_f10;
    bool billows_target_valid;
    int8_t rssi_lora;
    int8_t snr_lora;
} bridge_state_sample_t;

/*
 * Load the persisted anchor, reset the snapshot and install the time source.
 * A stored anchor restores the clock as estimated; `elapsed_sleep_s` is added
 * only when the platform knows the off-time (0 otherwise). Safe to call again
 * to model a reboot in tests. bridge_config must already be initialised for the
 * anchor to load; otherwise the clock starts unknown.
 */
bridge_state_result_t bridge_state_core_init(
    const bridge_state_time_source_t *time_source, uint32_t elapsed_sleep_s);

/* Current clock. `out` is all-or-nothing; never returns partial state. */
bridge_state_result_t bridge_state_now(bridge_state_clock_t *out);

/*
 * App `set_time` path (T29 wires BLE later). Takes UTC seconds.
 * Returns BRIDGE_STATE_ERR_TIME when the new time is earlier than the current
 * clock; past records and the monotonic sample time are never rewound.
 */
bridge_state_result_t bridge_state_set_time(uint64_t unix_s);

/*
 * Periodic housekeeping: persist the anchor pair when valid and due. Call from
 * the housekeeping loop; it never writes more than once per ten minutes.
 */
bridge_state_result_t bridge_state_tick(void);

/*
 * Update the snapshot from one valid state packet. Call only after the parser
 * and pairing checks accepted the frame. Does not touch NVS.
 */
bridge_state_result_t bridge_state_update(const bridge_state_sample_t *sample);

/* Copy the live snapshot with per-read age and clock/liveness flags. */
bridge_state_result_t bridge_state_snapshot(bridge_state_live_t *out);

/*
 * Stamp a record with the current time and clock-valid flag. While the clock is
 * unknown the record gets unix_s = 0 and bit 5 cleared. The internal
 * last-record time never decreases, so a correction cannot reorder timestamps.
 * T21 calls this immediately before handing the record to the log writer.
 */
bridge_state_result_t bridge_state_stamp_record(sx4_sample_rec_t *rec);

/* Device-level live flags owned by other tasks (T21/T24/T27/T28). */
void bridge_state_set_smoke_paired(bool paired);
void bridge_state_set_storage_ok(bool ok);
void bridge_state_set_display_on(bool on);
void bridge_state_set_sync_active(bool active);
void bridge_state_set_billows_output(bool output);

/* Battery (T24): mV plus percent, or BRIDGE_STATE_SOC_UNKNOWN for unknown. */
void bridge_state_set_battery(uint16_t millivolts, uint8_t percent);

/*
 * Optional observer for the live snapshot (T28). The callback runs after every
 * stored-sample publication, every flag transition and a successful set_time,
 * in the caller's task context. It must not block or call back into the
 * setters; bridge_state_snapshot() is safe from it. Passing NULL unregisters.
 */
typedef void (*bridge_state_change_fn)(void *ctx);
void bridge_state_set_change_hook(bridge_state_change_fn fn, void *ctx);

#define BRIDGE_STATE_SOC_UNKNOWN SX4_BATTERY_UNKNOWN

#ifdef ESP_PLATFORM
#include "esp_err.h"
/* Firmware boot hook: install esp_timer and restore the persisted anchor. */
esp_err_t bridge_state_init(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_BRIDGE_STATE_H */
