#include "double_reset.h"

bool bridge_double_reset_check(bridge_drt_token_t *tok, uint64_t now_ms) {
    const bool armed = tok->magic == BRIDGE_DRT_MAGIC;
    const bool fresh = armed && now_ms >= tok->armed_at_ms &&
                       (now_ms - tok->armed_at_ms) < BRIDGE_DRT_WINDOW_MS;
    /* Consume unconditionally: a stale or corrupt token must not linger. */
    tok->magic = 0;
    tok->armed_at_ms = 0;
    return fresh;
}

void bridge_double_reset_arm(bridge_drt_token_t *tok, uint64_t now_ms) {
    tok->magic = BRIDGE_DRT_MAGIC;
    tok->armed_at_ms = now_ms;
}

void bridge_double_reset_disarm(bridge_drt_token_t *tok) {
    tok->magic = 0;
    tok->armed_at_ms = 0;
}
