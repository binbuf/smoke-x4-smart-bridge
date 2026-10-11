/* app_ui — the ESP-IDF glue for the display (F11a.5; design 07 §7.1,
 * 03 §3.1). The pixels live in app_ui_core.h, the panel sequencing in
 * app_ui_panel.h; this file only owns GPIO, the i2c_master bus, the event
 * subscription, and the app_ui task row.
 *
 * M3 scope: the panel shows the F10.5 passkey overlay and is otherwise
 * dark. Pages, gestures, the LED, and the sleep policy are F11b (M5).
 */
#ifndef APP_UI_H
#define APP_UI_H

#ifdef __cplusplus
extern "C" {
#endif

/* Brings the rail, bus, and panel up, subscribes to BRIDGE_EVT_BLE, and
 * starts the app_ui task row. Returns 0 on success. A failure here is not
 * fatal to the boot: a bridge with a dead panel still cooks (03 §3.4). */
int app_ui_init(void);

/* Open the on-device factory-reset flow now. Called by main after a double
 * reset (< 10 s) and by the task itself when PRG is held through the boot
 * splash. The flow is hold-to-confirm: hold ~3 s, release to wipe, release
 * early to cancel. */
void app_ui_request_recovery(void);

/* What the recovery flow runs when the user confirms. main registers this so
 * app_ui does not have to depend on app_ble/app_config/cook_store (which
 * would be a component cycle). It must not return — it wipes bonds + config
 * + recorded cooks and reboots. If none is set, app_ui just reboots. */
typedef void (*app_ui_recovery_fn)(void);
void app_ui_set_recovery_hook(app_ui_recovery_fn fn);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_H */
