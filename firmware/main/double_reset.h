/* double_reset.h — the RTC-SRAM double-reset token (design 03 §3.4.1).
 *
 * A token in RTC SRAM survives a reset but not a power cycle. Two resets
 * within 10 s force AP mode for that boot — the recovery path that works
 * with a dead OLED, replacing the physically impossible "hold PRG through
 * reset" idiom (GPIO0 is the boot strapping pin).
 *
 * Pure logic over an injected token + clock so host tests can simulate
 * reset (token survives) vs power cycle (token zeroed).
 */
#ifndef DOUBLE_RESET_H
#define DOUBLE_RESET_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BRIDGE_DRT_MAGIC 0x44525354u /* "DRST" */
#define BRIDGE_DRT_WINDOW_MS 10000u

typedef struct {
    uint32_t magic;
    uint64_t armed_at_ms; /* RTC-clock time the token was armed */
} bridge_drt_token_t;

/* Call first thing on boot with the RTC-clock now. Returns true when a valid
 * token younger than the window is present — a double reset; the token is
 * consumed either way so a third reset starts fresh. */
bool bridge_double_reset_check(bridge_drt_token_t *tok, uint64_t now_ms);

/* Arm the token for this boot. Call after check() returned false. */
void bridge_double_reset_arm(bridge_drt_token_t *tok, uint64_t now_ms);

/* Clear the token once the boot is considered stable (~10 s of uptime). */
void bridge_double_reset_disarm(bridge_drt_token_t *tok);

#ifdef __cplusplus
}
#endif

#endif /* DOUBLE_RESET_H */
