/* app_ble_internal.h — what the three core translation units share.
 * Not installed in the component's public include set by intent: the glue
 * talks to app_ble_core.h, and nothing outside the component needs this.
 */
#ifndef APP_BLE_INTERNAL_H
#define APP_BLE_INTERNAL_H

#include "app_ble_core.h"
#include "app_time_core.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const app_ble_ops_t *g_ble_ops;

/* The one live snapshot both live_state (§5.7) and the advertising blob
 * (§2.3) are built from. */
typedef struct {
    bool paired;
    bool session_active;
    bool billows;
    bool alarm_active;
    bool clock_valid;
    int16_t temp[4];
    uint8_t soc_pct;
    int8_t rssi_lora;
    uint32_t session_t;
} app_ble_live_t;

void app_ble_live_snapshot(app_ble_live_t *out);

/* Builds and notifies a result frame (§5.9). `detail` may be NULL. */
int app_ble_answer(uint8_t op_echo, uint8_t status, const char *detail);

void app_ble_ctrl_reset(void);
void app_ble_adv_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_BLE_INTERNAL_H */
