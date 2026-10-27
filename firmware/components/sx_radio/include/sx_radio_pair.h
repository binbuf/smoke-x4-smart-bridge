/*
 * sx_radio_pair.h - Smoke X pairing state machine and the single LoRa TX gate
 * (design 02 section 2.7, design 03 section 3.5.3).
 *
 * Pure C11: no ESP-IDF, no heap, no I/O. The firmware adapter in sx_radio.c
 * installs the NVS/radio callbacks; the host suite installs RAM/radio fakes.
 *
 *   UNPAIRED ------- sync beacon (6 commas) -------> SYNC_RECEIVED
 *      ^                                              |  first state packet
 *      | unpair                                       v
 *      +------------------------------------------- PAIRED (CONFIRMED)
 *                                                     |
 *                              10 min without state  v
 *                                                   LOST
 *                                                     |
 *                                   state packet      v
 *                                                   PAIRED
 *
 * TX rule: this component has exactly one call to the `send_ack` callback, in
 * the sync-beacon branch of sx4_radio_pair_on_packet(). No other public
 * function can transmit; the host test asserts both the single call site and
 * the runtime behaviour. sx_radio.c keeps the only LoRaSend() call behind that
 * callback.
 */
#ifndef SX4_SX_RADIO_PAIR_H
#define SX4_SX_RADIO_PAIR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Longest stored device ID (7 wire chars in the capture) plus NUL. */
#define SX4_PAIR_DEVICE_ID_MAX 16u

/* Unpaired scan alternates these two sync channels (design 02 section 2.7).
 * The X4 beacons on 915.0 MHz; 920.0 MHz covers the X2 defensively. Do not
 * add operating channels here: the beacon only carries the operating
 * frequency, it is never transmitted on it. */
#define SX4_PAIR_SYNC_CHANNEL_A_HZ 915000000u
#define SX4_PAIR_SYNC_CHANNEL_B_HZ 920000000u
#define SX4_PAIR_SCAN_INTERVAL_MS 3300u

/* A paired X4 is shown as LOST after this much silence. */
#define SX4_PAIR_LOST_TIMEOUT_MS 600000u

typedef enum {
    SX4_PAIR_UNPAIRED = 0,
    /* Beacon accepted, ACK sent, waiting for the first state packet. */
    SX4_PAIR_SYNC_RECEIVED = 1,
    /* PAIRED and CONFIRMED are the same state; the alias keeps the design
     * diagram readable. */
    SX4_PAIR_PAIRED = 2,
    SX4_PAIR_CONFIRMED = SX4_PAIR_PAIRED,
    /* Link status only: pairing is kept and the radio stays tuned. */
    SX4_PAIR_LOST = 3,
} sx4_pair_state_t;

typedef struct {
    char device_id[SX4_PAIR_DEVICE_ID_MAX];
    uint32_t frequency_hz;
    uint8_t num_probes;
} sx4_pair_record_t;

/*
 * Callbacks. All are required except `load`, which may be NULL for a fresh
 * device. `tune` reports whether the radio accepted the frequency (the
 * firmware adapter still applies the 902-928 MHz check itself). `send_ack` is
 * the only transmission hook and is called exactly once per accepted beacon.
 */
typedef struct {
    void *ctx;
    bool (*load)(void *ctx, sx4_pair_record_t *out);
    bool (*save)(void *ctx, const sx4_pair_record_t *record);
    bool (*clear)(void *ctx);
    bool (*tune)(void *ctx, uint32_t frequency_hz);
    bool (*send_ack)(void *ctx, const char *ack, size_t length);
} sx4_radio_pair_io_t;

typedef struct {
    uint32_t sync_accepted;
    uint32_t acks_sent;
    uint32_t state_packets;
    uint32_t confirmations;
    uint32_t save_failures;
    uint32_t lost_entries;
    uint32_t lost_recoveries;
    uint32_t rejected_syncs; /* malformed or out-of-band; no state change */
} sx4_radio_pair_counters_t;

/*
 * Load the persisted pairing (if any) and tune the radio. `now_ms` is a
 * monotonic millisecond clock. Returns false only for a bad callback set or a
 * failed tune when a stored pairing exists. An unpaired start tunes the first
 * scan channel.
 */
bool sx4_radio_pair_init(const sx4_radio_pair_io_t *io, uint64_t now_ms);

sx4_pair_state_t sx4_radio_pair_state(void);

/* Current pairing. True in SYNC_RECEIVED (pending, num_probes == 0), PAIRED
 * and LOST. The record is persisted only from PAIRED onward. */
bool sx4_radio_pair_record(sx4_pair_record_t *out);

/* Scan channel while UNPAIRED (the channel last tuned). */
uint32_t sx4_radio_pair_scan_frequency_hz(void);

/* Actual tuned frequency as last accepted by the tune callback. */
uint32_t sx4_radio_pair_tuned_frequency_hz(void);

/*
 * Classify one received payload by comma count and drive the FSM. Returns
 * true when the packet was relevant and accepted. A sync beacon is accepted
 * only while UNPAIRED; afterwards beacons are ignored until unpair.
 *
 * This is the only entry point that can reach the ACK transmission.
 */
bool sx4_radio_pair_on_packet(const uint8_t *payload, size_t length,
                              uint64_t now_ms);

/* Periodic housekeeping: 915/920 scan alternation and the LOST timeout. */
void sx4_radio_pair_tick(uint64_t now_ms);

/* Clear pairing through the callback, return to UNPAIRED and restart scan.
 * Pairing stays intact if the clear callback fails. */
bool sx4_radio_pair_unpair(uint64_t now_ms);

void sx4_radio_pair_counters_get(sx4_radio_pair_counters_t *out);
void sx4_radio_pair_counters_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_RADIO_PAIR_H */
