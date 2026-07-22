/* smoke_x_ctrl — the pairing state machine, stale-pairing watchdog, and
 * packet accounting (design 02 §2.4, §2.5, §2.7; tasks F3.4, F3.6, F3.7).
 *
 * Pure C11 over injected ops: the radio, the event sink, and the clock all
 * arrive from outside, so the full transition sequence runs in the host
 * suite. Persistence goes through app_config_store — the controller never
 * touches NVS itself.
 */
#ifndef SMOKE_X_CTRL_H
#define SMOKE_X_CTRL_H

#include <stdbool.h>
#include <stdint.h>

#include "smoke_x_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SMOKE_X_UNPAIRED = 0,
    SMOKE_X_SYNC_RECEIVED,
    SMOKE_X_CONFIRMED,
} smoke_x_pair_state_t;

typedef enum {
    SMOKE_X_EVT_SAMPLE,   /* payload: const smoke_x_sample_t* */
    SMOKE_X_EVT_SYNCED,   /* payload: const smoke_x_sync_t*   */
    SMOKE_X_EVT_PAIRED,   /* first state message confirmed     */
    SMOKE_X_EVT_UNPAIRED, /* explicit unpair                   */
    SMOKE_X_EVT_RESCAN,   /* watchdog re-scan (config-gated)   */
    SMOKE_X_EVT_BASE_LOST,
    SMOKE_X_EVT_BASE_FOUND,
} smoke_x_evt_t;

typedef struct {
    smoke_x_state_t state;
    int8_t rssi; /* per packet (F2.4) */
    int8_t snr;
    uint64_t t_ms; /* uptime at reception */
} smoke_x_sample_t;

/* BASE_LOST after N × 30 s with no valid state message (§2.7, N = 20). */
#define SMOKE_X_BASE_LOST_TIMEOUT_MS (20u * 30u * 1000u)
/* Optional re-scan after 60 min with no packets and no active cook. */
#define SMOKE_X_RESCAN_TIMEOUT_MS (60u * 60u * 1000u)

#define SMOKE_X_RF_MIN_HZ 902000000u
#define SMOKE_X_RF_MAX_HZ 928000000u

#define SMOKE_X_INTERVAL_BUCKETS 5

typedef struct {
    uint32_t valid;          /* state messages accepted */
    uint32_t parse_fail;     /* right comma count, bad fields */
    uint32_t unknown_commas; /* unclassifiable payloads */
    uint32_t id_mismatch;    /* foreign device dropped (F3.4) */
    uint32_t sync_ignored;   /* syncs while not scanning */
    uint32_t crc_fail;       /* radio-reported, via note_crc_error */
    /* Inter-packet intervals: <15 s, <45 s, <90 s, <300 s, ≥300 s. */
    uint32_t interval_hist[SMOKE_X_INTERVAL_BUCKETS];
} smoke_x_stats_t;

typedef struct {
    /* Retune the radio; called before the ACK so it never goes out on the
     * sync channel (§2.5 invariant 3). */
    int (*set_frequency)(void *ctx, uint32_t hz);
    /* The ONLY caller is the sync handler (§2.5 invariant 1). */
    int (*transmit)(void *ctx, const char *payload);
    /* Resume the 915↔920 alternating scan (F2.5 owns the cadence). */
    void (*start_scan)(void *ctx);
    void (*publish)(void *ctx, smoke_x_evt_t evt, const void *payload);
} smoke_x_ops_t;

/* Loads any persisted pairing: paired boots CONFIRMED on the stored
 * frequency; unpaired starts the scan. app_config_store must be inited. */
int smoke_x_ctrl_init(const smoke_x_ops_t *ops, void *ctx,
                      bool rescan_enabled, uint64_t now_ms);

smoke_x_pair_state_t smoke_x_ctrl_state(void);

/* Feed one received payload. Returns 0 if it advanced state or produced a
 * sample, -1 if it was dropped (counted in stats). */
int smoke_x_ctrl_on_payload(const char *payload, int8_t rssi, int8_t snr,
                            uint64_t now_ms);

/* Radio-level CRC failure accounting (the payload never reaches us). */
void smoke_x_ctrl_note_crc_error(void);

/* Drives the watchdog; call about once a second. */
void smoke_x_ctrl_tick(uint64_t now_ms);

/* Clears the persisted pairing and restarts the scan. Touches nothing
 * outside this device (§2.5 invariant 2). */
int smoke_x_ctrl_unpair(void);

const smoke_x_stats_t *smoke_x_ctrl_stats(void);

#ifdef __cplusplus
}
#endif

#endif /* SMOKE_X_CTRL_H */
