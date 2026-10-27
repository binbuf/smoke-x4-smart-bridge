#include "tasks.h"

#define SX4_TASK_ROW(name, stack, prio, core) \
    { #name, (stack), (prio), (core) },

const sx4_task_def_t sx4_tasks[] = {
    SX4_TASK_LIST(SX4_TASK_ROW)
};

const size_t sx4_task_count = sizeof(sx4_tasks) / sizeof(sx4_tasks[0]);
