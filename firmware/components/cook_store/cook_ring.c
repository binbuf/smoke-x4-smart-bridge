/* cook_ring — live ring + rolling slope (F5.6). */
#include "cook_ring.h"

#include <string.h>

#include "record_gen.h"

static cook_ring_sample_t s_ring[COOK_RING_SIZE];
static int s_next;
static int s_count;

void cook_ring_reset(void) {
    s_next = 0;
    s_count = 0;
}

void cook_ring_push(const cook_ring_sample_t *s) {
    s_ring[s_next] = *s;
    s_next = (s_next + 1) % COOK_RING_SIZE;
    if (s_count < COOK_RING_SIZE) {
        s_count++;
    }
}

int cook_ring_count(void) { return s_count; }

const cook_ring_sample_t *cook_ring_get(int idx) {
    if (idx < 0 || idx >= s_count) {
        return NULL;
    }
    return &s_ring[(s_next + COOK_RING_SIZE - 1 - idx) % COOK_RING_SIZE];
}

bool cook_ring_slope_f_per_hr(int probe, float *out) {
    if (probe < 0 || probe > 3 || s_count == 0) {
        return false;
    }
    /* The window: newest sample back 10 minutes, at most 20 samples. */
    const uint32_t newest_t = cook_ring_get(0)->t;
    const uint32_t window_start = newest_t >= 600 ? newest_t - 600 : 0;

    float xs[20], ys[20];
    int n = 0;
    uint32_t prev_t = 0;
    bool have_prev = false;
    /* Walk oldest→newest inside the window so the gap check is ordered. */
    for (int idx = (s_count < 20 ? s_count : 20) - 1; idx >= 0; idx--) {
        const cook_ring_sample_t *s = cook_ring_get(idx);
        if (s->t < window_start) {
            continue;
        }
        /* A2.2: a gap > 2 min inside the window voids the slope — the
         * window no longer represents 10 contiguous minutes. */
        if (have_prev && s->t - prev_t > 120) {
            return false;
        }
        prev_t = s->t;
        have_prev = true;
        const int16_t v = s->temp[probe];
        if (v == BRIDGE_TEMP_DETACHED || v == BRIDGE_TEMP_INVALID) {
            continue;
        }
        xs[n] = (float)s->t;
        ys[n] = (float)v / 10.0f; /* tenths → °F */
        n++;
    }
    if (n < 12) {
        return false;
    }
    float sx = 0, sy = 0;
    for (int i = 0; i < n; i++) {
        sx += xs[i];
        sy += ys[i];
    }
    const float mx = sx / (float)n, my = sy / (float)n;
    float num = 0, den = 0;
    for (int i = 0; i < n; i++) {
        num += (xs[i] - mx) * (ys[i] - my);
        den += (xs[i] - mx) * (xs[i] - mx);
    }
    if (den == 0) {
        return false;
    }
    *out = (num / den) * 3600.0f; /* °F/s → °F/hr */
    return true;
}
