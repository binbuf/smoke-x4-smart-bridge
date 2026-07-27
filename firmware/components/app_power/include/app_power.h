/* app_power.h — the ESP-IDF-facing half of battery measurement (F12.4;
 * design 01 §1.3, §1.6, 03 §3.1).
 *
 * The decisions are in app_power_core.h (curve, filter, charging
 * inference, plateau solver, saver hysteresis) and app_power_svc.h (the
 * calibration's persistence and the read side every transport uses), both
 * ESP-IDF-free and host-tested.
 */
#ifndef APP_POWER_H
#define APP_POWER_H

#ifdef __cplusplus
extern "C" {
#endif

/* Configures GPIO37 and ADC1_CH0, loads the stored calibration, and starts
 * the 30 s app_power task row. Returns 0 on success. Not fatal to the boot
 * (03 §3.4): a bridge that cannot read its battery still cooks, and says
 * SOC_UNKNOWN rather than inventing a percentage. */
int app_power_init(void);

/* Soft power off (07 §7.4): arm GPIO0 (PRG) as the deep-sleep wake source
 * and enter deep sleep. DOES NOT RETURN. Callers blank their own outputs
 * (panel, LED, rails) first — this owns only the power domain and the wake. */
void app_power_enter_deep_sleep(void);

/* Called first thing in app_main on every boot. If this boot is a GPIO0 wake
 * from app_power_enter_deep_sleep(), require the button held for
 * APP_POWER_WAKE_HOLD_MS (app_power_core.h) or go straight back to sleep, so a
 * pocket-press cannot power the bridge on. Returns immediately on a normal
 * boot. */
void app_power_wake_gate(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_POWER_H */
