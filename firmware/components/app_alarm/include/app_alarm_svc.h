/* app_alarm_svc — the alarm engine wired to the rest of the firmware,
 * still without ESP-IDF (F13.6, F13.7; design 09 §9.2, 03 §3.1, §3.2).
 *
 * app_alarm.c (the IDF glue) does three things and no more: subscribe to
 * events, run a 10 s tick, and supply the four device facts below. This
 * file does the rest, and it does it against the same host-testable
 * modules the firmware runs — app_config_store for roles and targets,
 * smoke_x_ctrl for the base's own alarm bands, cook_ring for slopes,
 * cook_store for the session and its marks. That is the F9 pattern, for
 * the F9 reason: the interesting half closes without the board.
 *
 * THE 10 s TICK IS NOT A CONVENIENCE. base_lost fires on the ABSENCE of a
 * packet, so it can never be driven by one arriving.
 */
#ifndef APP_ALARM_SVC_H
#define APP_ALARM_SVC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_alarm_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The facts no pure module can know. Every one may be NULL, and a NULL op
 * degrades the rule that needs it to "abstain" rather than to a guess —
 * a build without app_power reports SOC_UNKNOWN and never a flat
 * battery. */
typedef struct {
    bool (*coredump_present)(void *ctx);
    /* false = storage usage not known yet; storage_low abstains. */
    bool (*storage_free_pct)(void *ctx, uint8_t *pct);
    /* BRIDGE_SOC_UNKNOWN until F12's app_power has a reading. */
    uint8_t (*soc_pct)(void *ctx);
    /* One call per transition. The glue turns this into BRIDGE_EVT_ALARM;
     * tests record it. */
    void (*publish)(void *ctx, const app_alarm_evt_t *e);
    void *ctx;
} app_alarm_ops_t;

/* Binds the ops and loads the persisted rule configuration (or the §9.2
 * defaults when none was ever written). Safe to call again — a host test
 * drives many scenarios in one process. */
int app_alarm_svc_init(const app_alarm_ops_t *ops);

/* A decoded state message has just been accepted. Advances the lid
 * detector, evaluates every rule, publishes transitions, and writes the
 * §9.2 kind-5 / §9.4 kind-2 marks. */
void app_alarm_svc_on_sample(uint32_t now_s);

/* The 10 s tick: the time-based rules, with no new pit sample fed to the
 * lid detector. `since_last_packet_s` is what base_lost reads. */
void app_alarm_svc_tick(uint32_t now_s, uint32_t since_last_packet_s);

/* Acknowledge. Returns the number of alarms silenced: 0 means the id was
 * unknown or already acked, which every transport treats as success
 * because three of them can send the same ack. */
int app_alarm_svc_ack(uint8_t id);
int app_alarm_svc_ack_all(void);

/* Session lifecycle. Ending one clears the session-scoped rules and
 * leaves battery/storage/base/fault alone. */
void app_alarm_svc_session_started(void);
void app_alarm_svc_session_ended(void);

/* Read side, for /status, live_state, the OLED, and the LED. */
int app_alarm_svc_list(const app_alarm_slot_t **out, int cap);
bool app_alarm_svc_unacked(void);
const app_alarm_slot_t *app_alarm_svc_find(uint8_t id);

/* Configuration, persisted through app_config_store's 64 B blob. */
const app_alarm_cfg_t *app_alarm_svc_cfg(void);
int app_alarm_svc_set_cfg(const app_alarm_cfg_t *cfg);

#ifdef __cplusplus
}
#endif

#endif /* APP_ALARM_SVC_H */
