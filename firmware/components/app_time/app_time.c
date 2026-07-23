/* app_time — device glue for app_time_core (F6). SNTP wiring arrives with
 * app_net in M2; the phone path lands with the API/BLE glue. */
#include "app_time.h"

#include "app_time_core.h"
#include "cook_store.h"
#include "esp_timer.h"

static uint64_t uptime_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

/* F6.2: the moment a real clock lands, a clockless open session's header
 * becomes correctly dated — one 256 B rewrite, no sample rewrite. */
static void on_clock_acquired(void *ctx) {
    (void)ctx;
    if (!cook_session_is_open() || cook_session_clock_valid()) {
        return;
    }
    uint64_t started = 0;
    if (app_time_core_unix_at(
            (uint64_t)cook_session_started_uptime_s() * 1000u, uptime_ms(),
            &started)) {
        (void)cook_session_set_clock(started);
    }
}

int app_time_init(void) {
    return app_time_core_init(uptime_ms(), on_clock_acquired, NULL);
}
