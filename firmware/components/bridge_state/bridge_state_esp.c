/*
 * bridge_state_esp.c - ESP-IDF adapter for bridge_state (T20).
 *
 * Installs the monotonic microsecond timer and restores the persisted clock
 * anchor. Deep-sleep off-time is not known to this build (the ESP timer is
 * reset on boot), so the restored anchor stays estimated and advances from the
 * reboot point; a source that survives sleep can pass elapsed_sleep_s later.
 */
#include "bridge_state.h"

#include "esp_err.h"
#include "esp_timer.h"

static uint64_t esp_uptime_ms(void *ctx) {
    (void)ctx;
    int64_t us = esp_timer_get_time();
    return us > 0 ? (uint64_t)us / 1000u : 0;
}

esp_err_t bridge_state_init(void) {
    bridge_state_time_source_t source = {
        .uptime_ms = esp_uptime_ms,
        .ctx = NULL,
    };
    bridge_state_result_t rc = bridge_state_core_init(&source, 0);
    return rc == BRIDGE_STATE_OK ? ESP_OK : ESP_ERR_INVALID_STATE;
}
