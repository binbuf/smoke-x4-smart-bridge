/* app_time_core — clock source arbitration, back-patch primitive, and the
 * monotonic floor (F6.1–F6.3, design 04 §4.4).
 *
 * The board has no battery-backed RTC. Samples never touch this module —
 * they store seconds-since-session-start from esp_timer, monotonic and
 * never adjusted. Wall clock is a session-level property, and this module
 * owns it: SNTP > phone > stale-floor > nothing.
 *
 * Pure C11 over app_config_store and a caller-supplied uptime; fully
 * host-testable.
 */
#ifndef APP_TIME_CORE_H
#define APP_TIME_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    APP_TIME_NONE = 0, /* only monotonic uptime exists */
    APP_TIME_SNTP = 1,
    APP_TIME_PHONE = 2,
    APP_TIME_STALE = 3, /* restored floor after a reboot; approximate */
} app_time_source_t;

/* Persist the floor about every 10 minutes (04 §4.4). */
#define APP_TIME_PERSIST_INTERVAL_MS (10u * 60u * 1000u)

/* Called on the transition from no-real-clock (NONE/STALE) to a real
 * source — the hook the F6.2 glue uses to back-patch an open session's
 * header via cook_session_set_clock. */
typedef void (*app_time_acquired_cb_t)(void *ctx);

/* Loads time/last_epoch_ms from config; a non-zero floor makes the clock
 * start there as STALE, so timestamps never go backwards. */
int app_time_core_init(uint64_t uptime_ms, app_time_acquired_cb_t cb,
                       void *cb_ctx);

/* Offers a clock. Precedence is enforced HERE: SNTP always wins, phone
 * never overrides SNTP, and stale/none lose to anything real. Returns
 * true when adopted. */
bool app_time_core_set(app_time_source_t source, uint64_t unix_ms,
                       uint64_t uptime_ms);

app_time_source_t app_time_core_source(void);

/* Wall clock now. False when no source of any kind exists. Never returns
 * a value below the persisted floor, and never goes backwards. */
bool app_time_core_now(uint64_t uptime_ms, uint64_t *unix_ms);

/* Wall clock at a PAST uptime — the back-patch primitive: what
 * started_unix_ms was, computed after the fact (04 §4.4). */
bool app_time_core_unix_at(uint64_t past_uptime_ms, uint64_t now_uptime_ms,
                           uint64_t *unix_ms);

/* Call ~once a minute: persists the floor every 10 minutes. */
void app_time_core_tick(uint64_t uptime_ms);

#ifdef __cplusplus
}
#endif

#endif /* APP_TIME_CORE_H */
