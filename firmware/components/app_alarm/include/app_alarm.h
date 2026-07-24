/* app_alarm.h — the ESP-IDF-facing half of the device-tier alarm engine
 * (F13.6; design 03 §3.1, 09 §9.1).
 *
 * The decisions are in app_alarm_core.h (rules, latching, hysteresis, lid
 * open) and app_alarm_svc.h (the wiring to config, radio, ring and
 * store), both of which are ESP-IDF-free and host-tested. This header is
 * only what `main` and the transports need.
 */
#ifndef APP_ALARM_H
#define APP_ALARM_H

#include <stdbool.h>
#include <stdint.h>

#include "app_alarm_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Subscribes to SAMPLE / SESSION / STORAGE / POWER, starts the app_alarm
 * task row and its 10 s tick, and checks for a coredump (system_fault).
 * Returns 0 on success. Not fatal to the boot (03 §3.4). */
int app_alarm_init(void);

/* Acknowledge — from the button, from HTTP, or from BLE op 11. Returns the
 * number silenced; 0 (unknown or already acked) is success, because three
 * transports can send the same ack. */
int app_alarm_ack(uint8_t id);
/* Everything raised at once: the OLED's "tap PRG to silence". */
int app_alarm_ack_all(void);

/* True while any alarm is raised and NOT acknowledged — the LED, the
 * buzzer, live_state.alarm_active and the OLED's warning glyph all read
 * this one function. */
bool app_alarm_unacked(void);

/* Raised and acked alarms, oldest first, for /status and the OLED. */
int app_alarm_list(const app_alarm_slot_t **out, int cap);

#ifdef __cplusplus
}
#endif

#endif /* APP_ALARM_H */
