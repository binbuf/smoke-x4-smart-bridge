#include "ui.h"

#include <stdatomic.h>
#include <stdbool.h>

#include "esp_log.h"

static const char *TAG = "sx4.ui";

/* Set by the sample pipeline, consumed by the T22 renderer. */
static atomic_bool s_dirty;

esp_err_t ui_init(void) {
    atomic_store(&s_dirty, false);
    ESP_LOGD(TAG, "stub init");
    return ESP_OK;
}

esp_err_t ui_start(void) {
    ESP_LOGD(TAG, "stub start");
    return ESP_OK;
}

void ui_mark_dirty(void) {
    atomic_store_explicit(&s_dirty, true, memory_order_release);
}

bool ui_dirty_take(void) {
    return atomic_exchange_explicit(&s_dirty, false, memory_order_acq_rel);
}

bool ui_dirty_pending(void) {
    return atomic_load_explicit(&s_dirty, memory_order_acquire);
}
