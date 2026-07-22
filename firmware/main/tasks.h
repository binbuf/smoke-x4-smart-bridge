/* tasks.h — the single source of truth for every application task's stack,
 * priority, and core (design 03 §3.3), kept as one table so the 01 §1.4 RAM
 * budget stays auditable and the stack sum is a compile-time constant.
 *
 * lora_rx is pinned to core 1, away from the Wi-Fi/BLE stacks on core 0 —
 * the polling radio loop is the only truly latency-sensitive path.
 *
 * NimBLE host, httpd, and the default event loop tasks are created by their
 * stacks/frameworks and are accounted for in 01 §1.4 separately.
 */
#ifndef TASKS_H
#define TASKS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*                     name        stack  prio  core                         */
#define BRIDGE_TASK_TABLE(X)                                                  \
    X(lora_rx,    4096, 6, 1) /* poll SX1262, hand payloads to smoke_x_ctrl */\
    X(smoke_x,    3072, 5, 0) /* decode, pairing state machine, publish     */\
    X(cook_store, 4096, 4, 0) /* drain queue → LittleFS append, retention   */\
    X(app_ui,     4096, 3, 0) /* 4 Hz button sampling, 1 Hz OLED render     */\
    X(app_alarm,  3072, 4, 0) /* rules on each sample + 10 s tick           */\
    X(app_net,    3072, 4, 0) /* Wi-Fi state machine, retry backoff, mDNS   */\
    X(app_power,  2560, 2, 0) /* battery ADC every 30 s, SoC filter         */\
    X(ws_push,    3072, 4, 0) /* serialize + fan out WebSocket frames       */

typedef struct {
    const char *name;
    uint32_t stack_bytes;
    uint32_t priority;
    int core; /* 0 or 1 (task affinity) */
} bridge_task_def_t;

#define BRIDGE_TASK_DEF(name_, stack_, prio_, core_) \
    {#name_, (stack_), (prio_), (core_)},
static const bridge_task_def_t bridge_task_defs[] __attribute__((unused)) = {
    BRIDGE_TASK_TABLE(BRIDGE_TASK_DEF)
};
#undef BRIDGE_TASK_DEF

#define BRIDGE_TASK_COUNT \
    (sizeof(bridge_task_defs) / sizeof(bridge_task_defs[0]))

/* Compile-time stack sum — checkable without running anything. */
#define BRIDGE_TASK_SUM(name_, stack_, prio_, core_) +(stack_)
enum { BRIDGE_TASK_STACK_TOTAL = 0 BRIDGE_TASK_TABLE(BRIDGE_TASK_SUM) };
#undef BRIDGE_TASK_SUM

/* 01 §1.4 budgets ~26 KB for application task stacks; hold the line at 28 KB
 * so growth is a deliberate design conversation, not drift. */
#define BRIDGE_TASK_STACK_BUDGET (28u * 1024u)
_Static_assert(BRIDGE_TASK_STACK_TOTAL <= BRIDGE_TASK_STACK_BUDGET,
               "task stacks exceed the 01 §1.4 RAM budget — renegotiate the "
               "budget, don't just bump it");

#ifdef __cplusplus
}
#endif

#endif /* TASKS_H */
