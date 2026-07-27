#include "boot_seq.h"

#include <stddef.h>

static const char *const STEP_NAMES[BRIDGE_BOOT_STEP_COUNT] = {
    "nvs_flash_init", "boot_reason",   "app_config_init", "event_loop_create",
    "app_power_init", "app_ui_init",   "recovery_window", "cook_store_init",
    "smoke_x_init",   "smoke_x_start", "app_time_init",   "app_net_start",
    "app_api_start",  "app_ble_start", "app_alarm_start", "ota_health_gate",
    "app_mqtt_start",
};

const char *bridge_boot_step_name(int step) {
    if (step < 1 || step > BRIDGE_BOOT_STEP_COUNT) {
        return "?";
    }
    return STEP_NAMES[step - 1];
}

static bool step_is_fatal(int step) {
    /* Only NVS and the event loop are fatal (03 §3.4). Everything after
     * cook_store is individually failure-tolerant; so are the early UI and
     * power steps — a bridge with a dead OLED still records the cook. */
    return step == BRIDGE_BOOT_NVS || step == BRIDGE_BOOT_EVENT_LOOP;
}

bool bridge_boot_run(const bridge_boot_ops_t *ops, void *ctx,
                     bridge_boot_result_t *result) {
    bridge_boot_result_t res = {0};
    bool contiguous = true;

    for (int step = 1; step <= BRIDGE_BOOT_STEP_COUNT; step++) {
        const bridge_boot_step_fn fn = ops->steps[step - 1];
        const int rc = (fn != NULL) ? fn(ctx) : 0;
        if (rc == 0) {
            if (contiguous) {
                res.steps_completed = step;
            }
            continue;
        }
        if (step_is_fatal(step)) {
            res.fatal_step = step;
            if (result != NULL) {
                *result = res;
            }
            return false;
        }
        res.failed_mask |= (uint32_t)1u << (step - 1);
        contiguous = false;
    }

    if (result != NULL) {
        *result = res;
    }
    return true;
}
