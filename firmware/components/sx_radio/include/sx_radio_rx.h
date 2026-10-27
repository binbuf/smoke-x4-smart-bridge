/*
 * sx_radio_rx.h - the host-injectable radio-to-parser seam (design 03 section
 * 3.6). Pure C: no ESP-IDF and no hardware dependency.
 *
 * The radio task publishes one frame per received packet. Delivery is a
 * fixed-depth, single-producer/single-consumer queue: publish never blocks and
 * never allocates; if the queue is full the newest frame is dropped and counted.
 * The parser/sample-pipe side takes frames with sx4_radio_rx_take().
 *
 * Host tests inject a payload with sx4_radio_rx_publish() and observe it with
 * sx4_radio_rx_take(), without starting a radio or an RTOS task.
 */
#ifndef SX4_SX_RADIO_RX_H
#define SX4_SX_RADIO_RX_H

#include <stdbool.h>
#include <stdint.h>

#include "sx_radio_params.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SX4_RADIO_RX_QUEUE_DEPTH 4u
/* One slot is kept free so head == tail means empty without a separate count. */
#define SX4_RADIO_RX_CAPACITY (SX4_RADIO_RX_QUEUE_DEPTH - 1u)

typedef struct {
    int8_t rssi;
    int8_t snr;
    uint8_t length;
    uint8_t payload[SX4_RADIO_MAX_PAYLOAD];
} sx4_radio_packet_t;

/* Clear the queue and counters. Not thread-safe; call before the radio starts
 * or from host tests. */
void sx4_radio_rx_reset(void);

/* Copy one raw packet into the seam. Rejects NULL, an empty payload and any
 * length above SX4_RADIO_MAX_PAYLOAD. Returns false when rejected or when the
 * bounded queue is full (the newest frame is dropped). */
bool sx4_radio_rx_publish(const uint8_t *payload, uint8_t length, int8_t rssi,
                          int8_t snr);

/* Take the oldest packet, copying it into out. Returns false when empty. */
bool sx4_radio_rx_take(sx4_radio_packet_t *out);

uint32_t sx4_radio_rx_published_count(void);
uint32_t sx4_radio_rx_dropped_count(void);

#ifdef __cplusplus
}
#endif

#endif /* SX4_SX_RADIO_RX_H */
