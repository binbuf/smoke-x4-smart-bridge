/*
 * ble_stats.c - pure `stats` encoder (T47).
 *
 * All field sources are supplied by the firmware snapshot in ble_service.c;
 * this file only maps them onto the generated 60-byte codec and enforces the
 * MVP rule that `billows_control` is never advertised.
 */
#include "ble_stats.h"

#include <string.h>

uint8_t ble_stats_build_flags(bool smoke_paired, bool smoke_live,
                              bool advertising, bool connected,
                              bool clock_valid, bool storage_ok,
                              bool billows_attached) {
    uint8_t flags = 0;
    if (smoke_paired) {
        flags |= SX4_STATS_FLAG_SMOKE_PAIRED;
    }
    if (smoke_live) {
        flags |= SX4_STATS_FLAG_SMOKE_LIVE;
    }
    if (advertising) {
        flags |= SX4_STATS_FLAG_ADVERTISING;
    }
    if (connected) {
        flags |= SX4_STATS_FLAG_CONNECTED;
    }
    if (clock_valid) {
        flags |= SX4_STATS_FLAG_CLOCK_VALID;
    }
    if (storage_ok) {
        flags |= SX4_STATS_FLAG_STORAGE_OK;
    }
    if (billows_attached) {
        flags |= SX4_STATS_FLAG_BILLOWS_ATTACHED;
    }
    /* Bit 7 is reserved and always 0 in the MVP. */
    return (uint8_t)(flags & (uint8_t)~SX4_STATS_FLAG_BILLOWS_CONTROL);
}

size_t ble_stats_encode(const ble_stats_view_t *view, uint8_t *out,
                        size_t cap) {
    sx4_stats_t stats;

    if (view == NULL || out == NULL || cap < SX4_STATS_SIZE) {
        return 0;
    }

    memset(&stats, 0, sizeof(stats));
    stats.ver = 1;
    stats.flags =
        (uint8_t)(view->flags & (uint8_t)~SX4_STATS_FLAG_BILLOWS_CONTROL);
    stats.uptime_s = view->uptime_s;
    stats.records_stored = view->records_stored;
    stats.records_capacity = view->records_capacity;
    stats.min_seq = view->min_seq;
    stats.max_seq = view->max_seq;
    stats.generation = view->generation;
    stats.packets_ok = view->packets_ok;
    stats.packets_bad = view->packets_bad;
    stats.battery_mv = view->battery_mv;
    stats.battery_pct = view->battery_pct;
    stats.lora_rssi = view->lora_rssi;
    stats.lora_snr = view->lora_snr;
    stats.reserved0 = 0;
    stats.heap_free = view->heap_free;
    stats.heap_min = view->heap_min;
    stats.dropped_samples = view->dropped_samples;
    stats.reserved1 = 0;
    stats.oldest_unix_s = view->oldest_unix_s;
    stats.newest_unix_s = view->newest_unix_s;
    return sx4_stats_encode(&stats, out, cap);
}
