#include "bridge_event_guard.h"

#include <stddef.h>

static bridge_event_guard_violation_fn s_violation = NULL;

void bridge_event_guard_set_violation_handler(
    bridge_event_guard_violation_fn fn) {
    s_violation = fn;
}

bool bridge_event_guard_check(const char *handler_name, uint64_t start_us,
                              uint64_t end_us) {
    const uint64_t elapsed = end_us - start_us;
    if (elapsed <= BRIDGE_EVENT_GUARD_BUDGET_US) {
        return true;
    }
    if (s_violation != NULL) {
        s_violation(handler_name, elapsed);
    }
    return false;
}
