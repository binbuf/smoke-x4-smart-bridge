/*
 * ble_stats.h - pure `stats` characteristic encoder (design 05 section 5.10).
 *
 * The firmware gathers one fresh snapshot (sample-log extent, bridge_state,
 * battery, heap, protocol counters) and calls ble_stats_encode(). The host
 * tests build the view directly and pin the 60-byte layout at empty log and
 * full ring. Nothing here caches or reads hardware.
 */
#ifndef SX4_BLE_STATS_H
#define SX4_BLE_STATS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Empty-log sentinel for min_seq/max_seq (design 05 section 5.10). */
#define BLE_STATS_SEQ_NONE 0xFFFFFFFFu
/* Frozen record capacity: 1,504 sectors x 225 records. */
#define BLE_STATS_CAPACITY 338400u

typedef struct {
    uint8_t flags; /* SX4_STATS_FLAG_* */
    uint32_t uptime_s;
    uint32_t records_stored;
    uint32_t records_capacity;
    uint32_t min_seq;
    uint32_t max_seq;
    uint32_t generation;
    uint32_t packets_ok;
    uint32_t packets_bad;
    uint16_t battery_mv;
    uint8_t battery_pct; /* 255 = unknown */
    int8_t lora_rssi;
    int8_t lora_snr;
    uint32_t heap_free;
    uint32_t heap_min;
    uint16_t dropped_samples;
    uint32_t oldest_unix_s; /* 0 = unknown/empty */
    uint32_t newest_unix_s; /* 0 = unknown/empty */
} ble_stats_view_t;

/*
 * Build the stats flag byte. Bit 7 (billows_control) is never set; the MVP
 * has no control path even if a caller passes true by mistake.
 */
uint8_t ble_stats_build_flags(bool smoke_paired, bool smoke_live,
                              bool advertising, bool connected,
                              bool clock_valid, bool storage_ok,
                              bool billows_attached);

/*
 * Encode the fixed 60-byte payload. Returns SX4_STATS_SIZE, 0 for a bad
 * argument or a too-small buffer. Reserved bytes are always 0 and `ver` is 1.
 */
size_t ble_stats_encode(const ble_stats_view_t *view, uint8_t *out,
                        size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_STATS_H */
