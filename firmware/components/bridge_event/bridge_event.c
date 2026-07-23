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

static void log_violation(const char *handler_name, uint64_t elapsed_us) {
    ESP_LOGE(TAG, "handler %s ran %llu us (> %u us budget)",
             handler_name != NULL ? handler_name : "?",
             (unsigned long long)elapsed_us,
             (unsigned)BRIDGE_EVENT_GUARD_BUDGET_US);
#ifndef NDEBUG
    /* A slow handler in a debug build is a bug, loudly (03 §3.2 rule 1). */
    assert(false && "bridge_event handler over 5 ms budget");
#endif
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
