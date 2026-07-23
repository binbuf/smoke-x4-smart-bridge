/* app_time_core — wall-clock arbitration over monotonic uptime (F6). */
#include "app_time_core.h"

#include "app_config_store.h"

static app_time_source_t s_source;
static uint64_t s_anchor_unix_ms;
static uint64_t s_anchor_uptime_ms;
static uint64_t s_floor_ms;
static uint64_t s_last_persist_uptime_ms;
static app_time_acquired_cb_t s_cb;
static void *s_cb_ctx;

static bool source_is_real(app_time_source_t s) {
    return s == APP_TIME_SNTP || s == APP_TIME_PHONE;
}

int app_time_core_init(uint64_t uptime_ms, app_time_acquired_cb_t cb,
                       void *cb_ctx) {
    s_cb = cb;
    s_cb_ctx = cb_ctx;
    s_source = APP_TIME_NONE;
    s_anchor_unix_ms = 0;
    s_anchor_uptime_ms = uptime_ms;
    s_last_persist_uptime_ms = uptime_ms;
    s_floor_ms = 0;

    uint64_t floor_ms = 0;
    if (app_config_store_get_u64(APP_CONFIG_TIME_LAST_EPOCH_MS, &floor_ms) ==
            APP_CONFIG_OK &&
        floor_ms > 0) {
        /* Resume from the floor, marked stale: never backwards, honestly
         * approximate until a real source lands (04 §4.4). */
        s_floor_ms = floor_ms;
        s_source = APP_TIME_STALE;
        s_anchor_unix_ms = floor_ms;
        s_anchor_uptime_ms = uptime_ms;
    }
    (void)app_config_store_set_u8(APP_CONFIG_TIME_SOURCE, (uint8_t)s_source);
    return 0;
}

bool app_time_core_set(app_time_source_t source, uint64_t unix_ms,
                       uint64_t uptime_ms) {
    if (!source_is_real(source)) {
        return false; /* stale/none are never OFFERED, only restored */
    }
    /* SNTP > phone: a phone time never overrides a live SNTP clock. */
    if (s_source == APP_TIME_SNTP && source == APP_TIME_PHONE) {
        return false;
    }
    const bool acquiring = !source_is_real(s_source);
    s_source = source;
    s_anchor_unix_ms = unix_ms;
    s_anchor_uptime_ms = uptime_ms;
    if (unix_ms > s_floor_ms) {
        s_floor_ms = unix_ms;
    }
    (void)app_config_store_set_u8(APP_CONFIG_TIME_SOURCE, (uint8_t)s_source);
    (void)app_config_store_set_u64(APP_CONFIG_TIME_LAST_EPOCH_MS, s_floor_ms);
    if (acquiring && s_cb) {
        s_cb(s_cb_ctx); /* F6.2: back-patch any clockless open session */
    }
    return true;
}

app_time_source_t app_time_core_source(void) { return s_source; }

bool app_time_core_now(uint64_t uptime_ms, uint64_t *unix_ms) {
    if (s_source == APP_TIME_NONE) {
        return false;
    }
    uint64_t now = s_anchor_unix_ms + (uptime_ms - s_anchor_uptime_ms);
    if (now < s_floor_ms) {
        now = s_floor_ms; /* the monotonic floor (F6.3) */
    }
    *unix_ms = now;
    return true;
}

bool app_time_core_unix_at(uint64_t past_uptime_ms, uint64_t now_uptime_ms,
                           uint64_t *unix_ms) {
    uint64_t now;
    if (!app_time_core_now(now_uptime_ms, &now)) {
        return false;
    }
    const uint64_t back = now_uptime_ms - past_uptime_ms;
    *unix_ms = now > back ? now - back : 0;
    return true;
}

void app_time_core_tick(uint64_t uptime_ms) {
    if (s_source == APP_TIME_NONE) {
        return;
    }
    if (uptime_ms - s_last_persist_uptime_ms < APP_TIME_PERSIST_INTERVAL_MS) {
        return;
    }
    uint64_t now;
    if (app_time_core_now(uptime_ms, &now)) {
        s_floor_ms = now;
        (void)app_config_store_set_u64(APP_CONFIG_TIME_LAST_EPOCH_MS, now);
        s_last_persist_uptime_ms = uptime_ms;
    }
}
