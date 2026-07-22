/* test_tasks_table.c — the 03 §3.3 task table invariants (F1.4).
 * The compile-time stack sum and budget assert live in tasks.h itself;
 * this test pins the values so a change is a conscious diff.
 */
#include "tasks.h"
#include "test_util.h"

int main(void)
{
    /* The compile-time sum — checkable without running anything. */
    CHECK_EQ_INT(BRIDGE_TASK_STACK_TOTAL,
                 4096 + 3072 + 4096 + 4096 + 3072 + 3072 + 2560 + 3072);
    CHECK(BRIDGE_TASK_STACK_TOTAL <= BRIDGE_TASK_STACK_BUDGET);
    CHECK_EQ_INT(BRIDGE_TASK_COUNT, 8);

    /* lora_rx is pinned to core 1, away from the Wi-Fi/BLE stacks; every
     * other application task lives on core 0 (03 §3.3). */
    int lora_seen = 0;
    for (size_t i = 0; i < BRIDGE_TASK_COUNT; i++) {
        const bridge_task_def_t *def = &bridge_task_defs[i];
        CHECK(def->stack_bytes >= 2048);
        if (strcmp(def->name, "lora_rx") == 0) {
            lora_seen = 1;
            CHECK_EQ_INT(def->core, 1);
            /* The polling radio loop outranks everything else. */
            CHECK_EQ_INT(def->priority, 6);
        } else {
            CHECK_EQ_INT(def->core, 0);
            CHECK(def->priority < 6);
        }
    }
    CHECK(lora_seen);

    return test_summary("test_tasks_table");
}
