/* test_tasks_table.c — the 03 §3.3 task table invariants (F1.4).
 * The compile-time stack sum and budget assert live in tasks.h itself;
 * this test pins the values so a change is a conscious diff.
 */
#include "tasks.h"
#include "test_util.h"

int main(void) {
    /* The compile-time sum — checkable without running anything.
     *   lora_rx 4K · smoke_x 3K · cook_store 4K · app_ui 4K · app_alarm 3K
     *   · app_net 3K · app_power 2.5K · ws_push 4K · ble_push 4K
     * ws_push is 4 K, not 3 K: board-found in the M2 sitting, because the
     * lwip send path runs on that stack. ble_push is F10.4's row, and the
     * 28 KB → 32 KB budget move it forced is argued in tasks.h. */
    CHECK_EQ_INT(BRIDGE_TASK_STACK_TOTAL,
                 4096 + 3072 + 4096 + 4096 + 3072 + 3072 + 2560 + 4096 + 4096);
    CHECK(BRIDGE_TASK_STACK_TOTAL <= BRIDGE_TASK_STACK_BUDGET);
    CHECK_EQ_INT(BRIDGE_TASK_STACK_BUDGET, 32u * 1024u);
    CHECK_EQ_INT(BRIDGE_TASK_COUNT, 9);

    /* F10.4: notification fan-out gets its OWN row. If this disappears,
     * someone has moved it back onto the event loop or the NimBLE host
     * task — the exact mistake ws_push already paid for once. */
    int ble_push_seen = 0;
    for (size_t i = 0; i < BRIDGE_TASK_COUNT; i++) {
        if (strcmp(bridge_task_defs[i].name, "ble_push") == 0) {
            ble_push_seen = 1;
            CHECK_EQ_INT(bridge_task_defs[i].stack_bytes, 4096);
        }
    }
    CHECK(ble_push_seen);

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
