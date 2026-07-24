/* app_power_svc — the battery core wired to app_config, still without
 * ESP-IDF (F12.2, F12.5; design 01 §1.3, §1.6).
 *
 * The read side every other component uses. app_api's /status.power,
 * app_ble's live_state.soc_pct and the advertising blob's `soc` all come
 * through here rather than reaching into the core, so a build with no
 * app_power (or a bench image, or a host test) reports SOC_UNKNOWN and
 * never a plausible-looking lie.
 */
#ifndef APP_POWER_SVC_H
#define APP_POWER_SVC_H

#include <stdbool.h>
#include <stdint.h>

#include "app_power_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Loads vbat_cal_num/den from app_config (defaulting to V1.3's ×4.9) and
 * resets the filter. Safe to call again. */
int app_power_svc_init(void);

/* One raw ADC reading. Returns true when something an observer publishes
 * changed — the glue posts BRIDGE_EVT_POWER only then, so a steady pack
 * costs nothing on the event loop. */
bool app_power_svc_sample(uint16_t adc_mv, uint32_t now_s);

/* True once a real reading exists. device_info.caps b5 reads this: the
 * bit says whether a real value can EVER arrive (ble-gatt §5.1.1), which
 * is what lets the app tell "no battery data" from "a flat battery". */
bool app_power_svc_available(void);

uint16_t app_power_svc_mv(void);
uint8_t app_power_svc_soc(void); /* BRIDGE_SOC_UNKNOWN when unknown */
bool app_power_svc_charging(void);
/* The effective saver: the user's sticky app_config flag OR the automatic
 * one. Only the automatic half releases. */
bool app_power_svc_saver(void);

/* 01 §1.3's one-point command. Persists the solved ratio; refuses (−1) a
 * solution outside ±20 % of ×4.9. */
int app_power_svc_calibrate(uint16_t actual_mv);

#ifdef __cplusplus
}
#endif

#endif /* APP_POWER_SVC_H */
