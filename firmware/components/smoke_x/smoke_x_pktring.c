/* smoke_x_pktring — fixed RAM ring of recent raw payloads (F4.1). */
#include "smoke_x_pktring.h"

#include <stdio.h>
#include <string.h>

static smoke_x_pkt_t s_ring[SMOKE_X_PKTRING_SIZE];
static size_t s_next; /* slot for the next push */
static size_t s_count;

void smoke_x_pktring_reset(void) {
    s_next = 0;
    s_count = 0;
}

void smoke_x_pktring_push(const char *payload, int8_t rssi, int8_t snr,
                          uint64_t t_ms) {
    if (!payload) {
        return;
    }
    smoke_x_pkt_t *slot = &s_ring[s_next];
    snprintf(slot->payload, sizeof slot->payload, "%s", payload);
    slot->rssi = rssi;
    slot->snr = snr;
    slot->t_ms = t_ms;
    s_next = (s_next + 1) % SMOKE_X_PKTRING_SIZE;
    if (s_count < SMOKE_X_PKTRING_SIZE) {
        s_count++;
    }
}

size_t smoke_x_pktring_count(void) { return s_count; }

const smoke_x_pkt_t *smoke_x_pktring_get(size_t idx) {
    if (idx >= s_count) {
        return NULL;
    }
    const size_t pos =
        (s_next + SMOKE_X_PKTRING_SIZE - 1 - idx) % SMOKE_X_PKTRING_SIZE;
    return &s_ring[pos];
}
