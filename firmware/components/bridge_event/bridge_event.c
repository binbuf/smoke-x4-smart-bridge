#include "bridge_event.h"

#include <assert.h>
#include <stdlib.h>

#include "esp_log.h"
#include "esp_timer.h"

#include "bridge_event_guard.h"

static const char *TAG = "bridge_event";

ESP_EVENT_DEFINE_BASE(BRIDGE_EVENT);

typedef struct {
    esp_event_handler_t handler;
    void *handler_arg;
    const char *name;
} guard_ctx_t;

/* Count of budget overruns since boot, exposed for diagnosis (a slow handler
 * must stay visible even though it no longer bricks the board). */
static uint32_t s_guard_violations;

uint32_t bridge_event_guard_violation_count(void) { return s_guard_violations; }

static void log_violation(const char *handler_name, uint64_t elapsed_us) {
    s_guard_violations++;
    ESP_LOGE(TAG, "handler %s ran %llu us (> %u us budget) [%lu total]",
             handler_name != NULL ? handler_name : "?",
             (unsigned long long)elapsed_us,
             (unsigned)BRIDGE_EVENT_GUARD_BUDGET_US,
             (unsigned long)s_guard_violations);
    /* BOARD-FOUND 2026-07-25: this used to `assert(false)` in debug builds. A
     * slow-but-completed handler is a perf bug, not a safety one — the guard
     * fires only AFTER the handler returns (a truly hung task is caught by the
     * task watchdog instead), so panicking here bricks a field device over a
     * transient blip. The real culprit is I²C/NVS flash-bus contention on the
     * event loop during AP startup: `app_ui.alarm` measured 17.3 ms and
     * crash-looped a live cook every time the Smoke X raised an alarm. The
     * loud ESP_LOGE + the counter keep it visible; the root-cause fix (all I²C
     * off the event loop, 13 §13.7.5 F17.2) is bench work. Degrade, don't die. */
}

static void guarded_trampoline(void *arg, esp_event_base_t base, int32_t id,
                               void *event_data) {
    guard_ctx_t *ctx = arg;
    const uint64_t start = (uint64_t)esp_timer_get_time();
    ctx->handler(ctx->handler_arg, base, id, event_data);
    bridge_event_guard_check(ctx->name, start, (uint64_t)esp_timer_get_time());
}

esp_err_t bridge_event_handler_register(bridge_event_id_t id,
                                        esp_event_handler_t handler,
                                        void *handler_arg, const char *name) {
    guard_ctx_t *ctx = calloc(1, sizeof(*ctx));
    if (ctx == NULL) {
        return ESP_ERR_NO_MEM;
    }
    ctx->handler = handler;
    ctx->handler_arg = handler_arg;
    ctx->name = name;
    /* BOARD-FOUND (M3 bring-up): every handler goes through the SAME
     * `guarded_trampoline` function pointer, and esp_event_handler_register
     * de-duplicates by (base, id, function) — so the second component to
     * subscribe to an event silently OVERWROTE the first, logging only
     * "handler already registered, overwriting". With app_ble subscribing
     * to SAMPLE/ALARM/NET, that would have displaced app_api's WebSocket
     * fan-out — the live push M2's F9.12 verified on the board.
     *
     * ..._instance_register is the API that permits the same function with
     * different args, which is precisely the trampoline pattern. We do not
     * keep the instance handle: nothing unregisters, and NULL is explicitly
     * allowed. */
    esp_err_t err = esp_event_handler_instance_register(
        BRIDGE_EVENT, (int32_t)id, guarded_trampoline, ctx, NULL);
    if (err != ESP_OK) {
        free(ctx);
    }
    return err;
}

esp_err_t bridge_event_post(bridge_event_id_t id, const void *payload,
                            size_t payload_size) {
    return esp_event_post(BRIDGE_EVENT, (int32_t)id, payload, payload_size, 0);
}

static void install_default_violation_handler(void)
    __attribute__((constructor));
static void install_default_violation_handler(void) {
    bridge_event_guard_set_violation_handler(log_violation);
}
