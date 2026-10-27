/*
 * tasks.h - the single task table and stack budget (design 03 section 3.3).
 *
 * Pure C11: this header is included by the firmware and by the host test suite,
 * so it must not include an ESP-IDF header. The table lists application-owned
 * tasks only; the NimBLE host/controller task is created by the BLE stack and
 * its stack is accounted for separately in the heap budget.
 *
 * Adding a task means editing SX4_TASK_LIST. The static asserts below then fail
 * unless the 24 KB application-stack budget is deliberately revisited.
 */
#ifndef SX4_TASKS_H
#define SX4_TASKS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SX4_TASK_LIST(X)          \
    X(radio_rx, 4096, 6, 1)       \
    X(sample_pipe, 4096, 5, 0)    \
    X(log_writer, 4096, 4, 0)     \
    X(ble_tx, 3072, 4, 0)         \
    X(ui, 4096, 3, 0)             \
    X(housekeeping, 3072, 2, 0)

typedef struct {
    const char *name;
    uint32_t stack_bytes;
    uint8_t priority;
    uint8_t core;
} sx4_task_def_t;

extern const sx4_task_def_t sx4_tasks[];
extern const size_t sx4_task_count;

#define SX4_TASK_ADD_STACK(name, stack, prio, core) + (stack)
#define SX4_TASK_ADD_COUNT(name, stack, prio, core) + 1

/* Declared total and row count, derived from the same list as the table. */
#define SX4_TASK_STACK_TOTAL (0 SX4_TASK_LIST(SX4_TASK_ADD_STACK))
#define SX4_TASK_TABLE_COUNT (0 SX4_TASK_LIST(SX4_TASK_ADD_COUNT))

/* Application stacks only. 22 KiB declared + 2 KiB headroom under 24 KiB. */
#define SX4_TASK_STACK_BUDGET_BYTES (24 * 1024)
#define SX4_TASK_MIN_STACK_BYTES 3072

_Static_assert(SX4_TASK_STACK_TOTAL == 22528,
               "task stack total changed; update the budget in tasks.h and "
               "design 03 section 3.3 deliberately");
_Static_assert(SX4_TASK_STACK_TOTAL <= SX4_TASK_STACK_BUDGET_BYTES,
               "application task stacks exceed SX4_TASK_STACK_BUDGET_BYTES");
_Static_assert(SX4_TASK_TABLE_COUNT == 6,
               "task table row count changed; update the budget/design");

#ifdef __cplusplus
}
#endif

#endif /* SX4_TASKS_H */
