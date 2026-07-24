/* power_svc.c — the battery core plus persistence (F12.2, F12.5). */
#include "app_power_svc.h"

#include "app_config_store.h"

static app_power_t s_p;
static bool s_inited;

static void store_cal(void) {
    (void)app_config_store_set_u16(APP_CONFIG_DEV_VBAT_CAL_NUM, s_p.cal_num);
    (void)app_config_store_set_u16(APP_CONFIG_DEV_VBAT_CAL_DEN, s_p.cal_den);
}

int app_power_svc_init(void) {
    uint16_t num = 0;
    uint16_t den = 0;
    (void)app_config_store_get_u16(APP_CONFIG_DEV_VBAT_CAL_NUM, &num);
    (void)app_config_store_get_u16(APP_CONFIG_DEV_VBAT_CAL_DEN, &den);
    /* The schema default for both is 0, which means "never calibrated" —
     * the core substitutes V1.3's ×4.9 rather than dividing by zero. */
    app_power_core_reset(&s_p, num, den);
    /* A stored calibration is a decision someone made (a DMM point, or a
     * converged plateau); the solver does not get to re-open it every
     * boot. */
    s_p.cal_manual = num != 0 && den != 0;
    s_inited = true;
    return 0;
}

bool app_power_svc_sample(uint16_t adc_mv, uint32_t now_s) {
    if (!s_inited) {
        return false;
    }
    const uint16_t before_num = s_p.cal_num;
    const uint16_t before_den = s_p.cal_den;
    const bool changed = app_power_core_sample(&s_p, adc_mv, now_s);
    if (s_p.cal_num != before_num || s_p.cal_den != before_den) {
        store_cal(); /* the plateau solver converged; persist it once */
    }
    return changed;
}

bool app_power_svc_available(void) { return s_inited && s_p.have; }

uint16_t app_power_svc_mv(void) { return s_inited ? s_p.pack_mv : 0; }

uint8_t app_power_svc_soc(void) {
    return s_inited ? s_p.soc_pct : (uint8_t)BRIDGE_SOC_UNKNOWN;
}

bool app_power_svc_charging(void) { return s_inited && s_p.charging; }

bool app_power_svc_saver(void) {
    uint8_t user = 0;
    (void)app_config_store_get_u8(APP_CONFIG_DEV_BATTERY_SAVER, &user);
    return app_power_core_saver(s_inited ? &s_p : NULL, user != 0);
}

int app_power_svc_calibrate(uint16_t actual_mv) {
    if (!s_inited || app_power_core_calibrate(&s_p, actual_mv) != 0) {
        return -1;
    }
    store_cal();
    return 0;
}
