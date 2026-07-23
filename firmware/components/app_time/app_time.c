/* app_time — device glue for app_time_core (F6). SNTP wiring arrives with
 * app_net in M2; the phone path lands with the API/BLE glue.
 *
 * Clock acquisition is announced on the event bus; the cook_store drain
 * task owns the F6.2 back-patch (avoiding an app_time↔cook_store cycle). */
#include "app_time.h"

#include "app_time_core.h"
#include "bridge_event.h"
#include "esp_timer.h"

static uint64_t uptime_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

static void on_clock_acquired(void *ctx) {
    (void)ctx;
    bridge_evt_time_t evt = {0};
    switch (app_time_core_source()) {
        case APP_TIME_SNTP:
            evt.source = BRIDGE_TIME_SOURCE_SNTP;
            break;
        case APP_TIME_PHONE:
            evt.source = BRIDGE_TIME_SOURCE_PHONE;
            break;
        case APP_TIME_STALE:
            evt.source = BRIDGE_TIME_SOURCE_STALE;
            break;
        default:
            evt.source = BRIDGE_TIME_SOURCE_NONE;
            break;
    }
    (void)app_time_core_now(uptime_ms(), &evt.unix_ms);
    (void)bridge_event_post(BRIDGE_EVT_TIME, &evt, sizeof evt);
}

int app_time_init(void) {
    return app_time_core_init(uptime_ms(), on_clock_acquired, NULL);
}
