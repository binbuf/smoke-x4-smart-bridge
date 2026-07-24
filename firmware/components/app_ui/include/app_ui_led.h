/* app_ui_led — the LED pattern engine and the buzzer mirror
 * (F11b.10; design 07 §7.5).
 *
 * A pure function of (state, time) → duty cycle. No LEDC, no timers: the
 * host test samples it at chosen instants across two full periods,
 * because a blink asserted at ONE instant is not a blink.
 *
 * `led_enabled` defaults to alarms-only, and the reason is in the design
 * doc rather than in a preference: a light blinking all night on a
 * bedside bridge is a reason to unplug the bridge.
 */
#ifndef APP_UI_LED_H
#define APP_UI_LED_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Highest precedence first — several of these are true at once during a
 * bad night, and the order is what decides what the user sees. */
typedef enum {
    APP_UI_LED_OFF = 0,
    APP_UI_LED_ALARM,     /* 2 Hz blink — unacknowledged alarm */
    APP_UI_LED_IDENTIFY,  /* 5 s rapid flash, from the app */
    APP_UI_LED_OTA,       /* slow breathe */
    APP_UI_LED_PAIRING,   /* solid */
    APP_UI_LED_BASE_LOST, /* double-blink every 2 s */
    APP_UI_LED_HEARTBEAT, /* one 20 ms flash per packet; off by default */
} app_ui_led_pattern_t;

typedef enum {
    APP_UI_LED_MODE_OFF = 0,
    APP_UI_LED_MODE_ALARMS_ONLY, /* the default (07 §7.5) */
    APP_UI_LED_MODE_ALL,
} app_ui_led_mode_t;

#define APP_UI_LED_IDENTIFY_MS 5000
#define APP_UI_LED_DUTY_MAX 255

typedef struct {
    bool alarm_unacked;
    bool pairing;
    bool base_lost;
    bool ota;
    bool packet_flash; /* set for one tick when a packet lands */
    uint32_t identify_until_ms;
    uint8_t mode; /* app_ui_led_mode_t */
    bool buzzer_enabled;
} app_ui_led_input_t;

/* Which pattern wins right now. */
app_ui_led_pattern_t app_ui_led_pattern(const app_ui_led_input_t *in,
                                        uint32_t now_ms);

/* 0..255 duty at this instant. `mode` gates it: OFF is zero in EVERY
 * state including alarm — the user asked for darkness and the API is
 * where an alarm still shouts. */
uint8_t app_ui_led_duty(const app_ui_led_input_t *in, uint32_t now_ms);

/* The optional piezo on GPIO7 mirrors the ALARM pattern only, and is a
 * no-op when unfitted (which is every board we have). */
bool app_ui_buzzer_on(const app_ui_led_input_t *in, uint32_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_LED_H */
