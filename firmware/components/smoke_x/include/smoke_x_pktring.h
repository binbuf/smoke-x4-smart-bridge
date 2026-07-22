/* smoke_x_pktring — the last 64 raw payloads with link quality and uptime
 * (F4.1, design 02 §2.7). Statically allocated; answers "what did it just
 * receive?" without a second SDR. Pure C11, host-testable. */
#ifndef SMOKE_X_PKTRING_H
#define SMOKE_X_PKTRING_H

#include <stddef.h>
#include <stdint.h>

#include "smoke_x_parser.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SMOKE_X_PKTRING_SIZE 64

typedef struct {
    char payload[SMOKE_X_PARSER_MAX_PAYLOAD];
    int8_t rssi;
    int8_t snr;
    uint64_t t_ms;
} smoke_x_pkt_t;

void smoke_x_pktring_reset(void);
void smoke_x_pktring_push(const char *payload, int8_t rssi, int8_t snr,
                          uint64_t t_ms);
size_t smoke_x_pktring_count(void);
/* idx 0 = newest, count-1 = oldest. NULL when out of range. */
const smoke_x_pkt_t *smoke_x_pktring_get(size_t idx);

#ifdef __cplusplus
}
#endif

#endif /* SMOKE_X_PKTRING_H */
