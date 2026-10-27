/*
 * sx_radio_rx.c - bounded, allocation-free seam between the radio task and the
 * parser pipeline (design 03 section 3.6). Pure C; host-testable.
 */
#include "sx_radio_rx.h"

#include <stddef.h>
#include <string.h>

/* Design 02 section 2.1, in one place. */
const sx4_radio_params_t sx4_radio_params = {
    .spreading_factor = 9,
    .bandwidth_index = 4,        /* 125 kHz */
    .coding_rate = 0x01,         /* SX126X_LORA_CR_4_5 */
    .preamble_symbols = 10,
    .sync_word = 0x12,
    .crc_on = true,
    .tcxo_voltage = 3.3f,
    .use_regulator_ldo = true,
    .frequency_min_hz = 902000000u,
    .frequency_max_hz = 928000000u,
    .sync_x4_hz = 915000000u,
    .sync_x2_hz = 920000000u,
};

bool sx4_radio_frequency_valid(uint32_t frequency_hz) {
    return frequency_hz >= sx4_radio_params.frequency_min_hz &&
           frequency_hz <= sx4_radio_params.frequency_max_hz;
}

static sx4_radio_packet_t s_queue[SX4_RADIO_RX_QUEUE_DEPTH];
static uint32_t s_head; /* producer-owned index */
static uint32_t s_tail; /* consumer-owned index */
static uint32_t s_published;
static uint32_t s_dropped;

void sx4_radio_rx_reset(void) {
    memset(s_queue, 0, sizeof s_queue);
    s_head = 0;
    s_tail = 0;
    s_published = 0;
    s_dropped = 0;
}

bool sx4_radio_rx_publish(const uint8_t *payload, uint8_t length, int8_t rssi,
                          int8_t snr) {
    if (payload == NULL || length == 0 || length > SX4_RADIO_MAX_PAYLOAD) {
        return false;
    }

    uint32_t head = s_head;
    uint32_t next = (head + 1u) % SX4_RADIO_RX_QUEUE_DEPTH;
    if (next == __atomic_load_n(&s_tail, __ATOMIC_ACQUIRE)) {
        s_dropped++;
        return false;
    }

    sx4_radio_packet_t *slot = &s_queue[head];
    slot->rssi = rssi;
    slot->snr = snr;
    slot->length = length;
    memcpy(slot->payload, payload, length);
    if (length < SX4_RADIO_MAX_PAYLOAD) {
        memset(&slot->payload[length], 0, SX4_RADIO_MAX_PAYLOAD - length);
    }

    s_published++;
    __atomic_store_n(&s_head, next, __ATOMIC_RELEASE);
    return true;
}

bool sx4_radio_rx_take(sx4_radio_packet_t *out) {
    if (out == NULL) {
        return false;
    }

    uint32_t head = __atomic_load_n(&s_head, __ATOMIC_ACQUIRE);
    uint32_t tail = s_tail;
    if (head == tail) {
        return false;
    }

    memcpy(out, &s_queue[tail], sizeof *out);
    __atomic_store_n(&s_tail, (tail + 1u) % SX4_RADIO_RX_QUEUE_DEPTH,
                     __ATOMIC_RELEASE);
    return true;
}

uint32_t sx4_radio_rx_published_count(void) { return s_published; }

uint32_t sx4_radio_rx_dropped_count(void) { return s_dropped; }
