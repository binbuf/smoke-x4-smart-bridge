/*
 * test_tasks.c - the task table and its stack budget (design 03 section 3.3).
 *
 * tasks.h already static-asserts the total against the budget at compile time.
 * This test proves the table agrees with that macro, pins the expected rows and
 * catches accidental duplicate names or unsupported core/priority values.
 */
#include "tasks.h"

#include <string.h>

#include "test_util.h"

static const char *const expected_names[] = {
    "radio_rx", "sample_pipe", "log_writer", "ble_tx", "ui", "housekeeping",
};

int main(void) {
    CHECK_EQ_UINT(SX4_TASK_STACK_BUDGET_BYTES, 24u * 1024u);
    CHECK_EQ_UINT(SX4_TASK_MIN_STACK_BYTES, 3072u);
    CHECK_EQ_UINT(SX4_TASK_TABLE_COUNT, 6u);
    CHECK_EQ_UINT(sx4_task_count, SX4_TASK_TABLE_COUNT);

    unsigned total = 0;
    for (size_t i = 0; i < sx4_task_count; i++) {
        const sx4_task_def_t *task = &sx4_tasks[i];
        CHECK(task->name != NULL);
        if (i < sizeof(expected_names) / sizeof(expected_names[0])) {
            CHECK_STR_EQ(task->name, expected_names[i]);
        }
        CHECK(task->stack_bytes >= SX4_TASK_MIN_STACK_BYTES);
        CHECK(task->priority >= 1 && task->priority <= 24);
        CHECK(task->core <= 1);
        CHECK_EQ_UINT(task->core, strcmp(task->name, "radio_rx") == 0 ? 1u : 0u);
        if (strcmp(task->name, "radio_rx") == 0) {
            /* Design 03 section 3.3 / SDK budget: 4096 bytes, priority 6,
             * core 1 (away from the BLE host). */
            CHECK_EQ_UINT(task->stack_bytes, 4096u);
            CHECK_EQ_UINT(task->priority, 6u);
            CHECK_EQ_UINT(task->core, 1u);
        }
        total += task->stack_bytes;

        for (size_t j = 0; j < i; j++) {
            CHECK(strcmp(sx4_tasks[j].name, task->name) != 0);
        }
    }

    CHECK_EQ_UINT(total, SX4_TASK_STACK_TOTAL);
    CHECK_EQ_UINT(total, 22528u);
    CHECK(total <= SX4_TASK_STACK_BUDGET_BYTES);
    CHECK_EQ_UINT(SX4_TASK_STACK_BUDGET_BYTES - total, 2048u);

    printf("task budget: %u/%u bytes across %u tasks\n", total,
           (unsigned)SX4_TASK_STACK_BUDGET_BYTES, (unsigned)sx4_task_count);
    return sx4_test_summary("task-budget");
}
