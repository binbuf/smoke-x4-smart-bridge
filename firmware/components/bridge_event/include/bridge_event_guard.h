/* bridge_event_guard.h — enforcement for the ~5 ms handler-duration rule
 * (design 03 §3.2). Pure C, host-testable; the IDF glue in bridge_event.c
 * wires it to esp_timer and, in debug builds, to an assert.
 *
 * At one packet per 30 s there is no throughput concern; the discipline
 * exists so a slow LittleFS GC pass or an OTA write can never stall the
 * decoder.
 */
#ifndef BRIDGE_EVENT_GUARD_H
#define BRIDGE_EVENT_GUARD_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Budget an event handler may spend before the guard fires. */
#define BRIDGE_EVENT_GUARD_BUDGET_US 5000u

typedef void (*bridge_event_guard_violation_fn)(const char *handler_name,
                                                uint64_t elapsed_us);

/* Installs the violation callback (debug builds install one that aborts).
 * NULL restores the default (no-op). */
void bridge_event_guard_set_violation_handler(
    bridge_event_guard_violation_fn fn);

/* Returns true when end - start is within budget; otherwise invokes the
 * violation handler and returns false. */
bool bridge_event_guard_check(const char *handler_name, uint64_t start_us,
                              uint64_t end_us);

#ifdef __cplusplus
}
#endif

#endif /* BRIDGE_EVENT_GUARD_H */
