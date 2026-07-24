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
#define BRIDGE_TASK_TABLE(X)                                                     \
    X(lora_rx, 4096, 6, 1)    /* poll SX1262, hand payloads to smoke_x_ctrl */   \
    X(smoke_x, 3072, 5, 0)    /* decode, pairing state machine, publish     */   \
    X(cook_store, 4096, 4, 0) /* drain queue → LittleFS append, retention   */ \
    X(app_ui, 4096, 3, 0) /* 20 ms button sampling — 07 §7.4, and 4 Hz \
                             cannot see a 400 ms double-tap — plus a \
                             DIRTY-DRIVEN render, not the reference's \
                             unconditional 1 Hz redraw (F11b.11)      */ \
    X(app_alarm, 3072, 4, 0) /* rules on each sample + 10 s tick           */    \
    X(app_net, 3072, 4, 0)   /* Wi-Fi state machine, retry backoff, mDNS   */    \
    X(app_power, 2560, 2, 0) /* battery ADC every 30 s, SoC filter         */    \
    X(ws_push, 4096, 4, 0)   /* serialize + fan out WebSocket frames; the \
                                 lwip send path runs on THIS stack (board- \
                                 found: 3072 overflowed)                   */ \
    X(ble_push, 4096, 4, 0)  /* build + fan out GATT notifications; NEVER \
                                 the event loop or the NimBLE host task \
                                 (F10.4 — the ws_push lesson, applied \
                                 before the board can teach it again)      */

typedef struct {
    const char *name;
    uint32_t stack_bytes;
    uint32_t priority;
    int core; /* 0 or 1 (task affinity) */
} bridge_task_def_t;

#define BRIDGE_TASK_DEF(name_, stack_, prio_, core_) \
    {#name_, (stack_), (prio_), (core_)},
static const bridge_task_def_t bridge_task_defs[]
    __attribute__((unused)) = {BRIDGE_TASK_TABLE(BRIDGE_TASK_DEF)};
#undef BRIDGE_TASK_DEF

#define BRIDGE_TASK_COUNT \
    (sizeof(bridge_task_defs) / sizeof(bridge_task_defs[0]))

/* Compile-time stack sum — checkable without running anything. */
#define BRIDGE_TASK_SUM(name_, stack_, prio_, core_) +(stack_)
enum { BRIDGE_TASK_STACK_TOTAL = 0 BRIDGE_TASK_TABLE(BRIDGE_TASK_SUM) };
#undef BRIDGE_TASK_SUM

/* 01 §1.4 budgets application task stacks; the assert holds the line so
 * growth is a deliberate design conversation, not drift.
 *
 * RENEGOTIATED IN M3 (F10.4): 28 KB → 32 KB. Adding the ble_push row took
 * the table from 27.5 KB to 31.5 KB and tripped the old assert — which is
 * the assert doing its job, so here is the argument rather than a bump.
 *
 *   §1.4's estimate was ~26 KB over seven tasks and ALREADY included a
 *   4 KB `ble_app` allowance, so ble_push is not new spending — it is the
 *   allowance finally being drawn. The extra ~5.5 KB over that estimate is
 *   two rows §1.4 never listed: app_power (2.5 KB) and ws_push (4 KB, a
 *   board-found M2 addition), less 1 KB that smoke_x came in under.
 *
 *   It is affordable on measured numbers, not on estimates: the M2 bench
 *   sitting recorded min_free_heap ≈ 180.7 KB with AP + httpd + both
 *   LittleFS mounts running (docs/hardware-verified.md). 5.5 KB against
 *   that is noise; the 35–45 KB NimBLE itself costs is not, and V3a.1
 *   re-measures the whole picture with the stack live before M4.
 *
 * ble_push gets the full 4 KB rather than 3 KB deliberately: ws_push is
 * the directly analogous row and it overflowed at 3072 on the board,
 * because the send path runs on the pushing task's stack. Paying 1 KB to
 * not repeat that during a bench sitting is the right trade. */
#define BRIDGE_TASK_STACK_BUDGET (32u * 1024u)
_Static_assert(BRIDGE_TASK_STACK_TOTAL <= BRIDGE_TASK_STACK_BUDGET,
               "task stacks exceed the 01 §1.4 RAM budget — renegotiate the "
               "budget, don't just bump it");

#ifdef __cplusplus
}
#endif

#endif /* TASKS_H */
