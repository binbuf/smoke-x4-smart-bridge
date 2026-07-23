/* cook_ring — the 240-sample (2 h) live ring (F5.6, design 04 §4.3).
 *
 * Serves /api/v1/live, the OLED sparkline, the alarm engine's rolling
 * windows, and the BLE history_preview — none of which may touch flash.
 * Pure C11, statically allocated (~3.8 KB).
 */
#ifndef COOK_RING_H
#define COOK_RING_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define COOK_RING_SIZE 240

typedef struct {
    uint32_t t; /* seconds since session start */
    int16_t temp[4];
    uint8_t flags;
    int8_t rssi;
} cook_ring_sample_t;

void cook_ring_reset(void);
void cook_ring_push(const cook_ring_sample_t *s);
int cook_ring_count(void);
/* idx 0 = newest. NULL when out of range. */
const cook_ring_sample_t *cook_ring_get(int idx);

/* OLS slope over the rolling 10-minute window (up to 20 samples), °F/hr —
 * the same contract as the app's rateOfChange (A2.2): returns false (no
 * value, "null") when fewer than 12 valid samples are present or the
 * window spans a gap > 2 min. */
bool cook_ring_slope_f_per_hr(int probe, float *out);

#ifdef __cplusplus
}
#endif

#endif /* COOK_RING_H */
