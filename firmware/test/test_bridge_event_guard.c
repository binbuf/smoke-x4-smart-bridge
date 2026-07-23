/* test_bridge_event_guard.c — the ~5 ms handler-duration rule (F1.3).
 * A deliberately slow handler must trip the guard; a fast one must not.
 */
#include "bridge_event_guard.h"
#include "bridge_event_types.h"
#include "test_util.h"

static int g_violations = 0;
static uint64_t g_last_elapsed = 0;
static const char *g_last_name = NULL;

static void count_violation(const char *name, uint64_t elapsed_us) {
    g_violations++;
    g_last_elapsed = elapsed_us;
    g_last_name = name;
}

int main(void) {
    bridge_event_guard_set_violation_handler(count_violation);

    /* Within budget: no violation. */
    CHECK(bridge_event_guard_check("fast_handler", 1000, 1000 + 4999));
    CHECK_EQ_INT(g_violations, 0);

    /* Exactly at budget: still fine. */
    CHECK(bridge_event_guard_check("edge_handler", 0,
                                   BRIDGE_EVENT_GUARD_BUDGET_US));
    CHECK_EQ_INT(g_violations, 0);

    /* A deliberately slow handler (simulated 12 ms) trips the guard. */
    CHECK(!bridge_event_guard_check("slow_littlefs_gc", 5000, 17000));
    CHECK_EQ_INT(g_violations, 1);
    CHECK_EQ_INT((long long)g_last_elapsed, 12000);
    CHECK(g_last_name != NULL && strcmp(g_last_name, "slow_littlefs_gc") == 0);

    /* Clearing the handler must not crash on violation. */
    bridge_event_guard_set_violation_handler(NULL);
    CHECK(!bridge_event_guard_check("slow_again", 0, 60000));
    CHECK_EQ_INT(g_violations, 1);

    /* The twelve event IDs of 03 §3.2 exist and stay dense, plus M3's
     * additive BRIDGE_EVT_BLE (F10.5) at the end. */
    CHECK_EQ_INT(BRIDGE_EVT_SAMPLE, 0);
    CHECK_EQ_INT(BRIDGE_EVT_OTA, 11);
    CHECK_EQ_INT(BRIDGE_EVT_BLE, 12);
    CHECK_EQ_INT(BRIDGE_EVT_MAX, 13);

    return test_summary("test_bridge_event_guard");
}
