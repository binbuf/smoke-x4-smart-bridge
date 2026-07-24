/* app_ui_led.c — the 07 §7.5 pattern table (F11b.10). */
#include "app_ui_led.h"

app_ui_led_pattern_t app_ui_led_pattern(const app_ui_led_input_t *in,
                                        uint32_t now_ms) {
    if (in == NULL) {
        return APP_UI_LED_OFF;
    }
    /* Precedence, and the order is the argument: an unacknowledged alarm
     * outranks everything, because it is the only pattern that means
     * "come outside". Identify beats the ambient patterns because its
     * whole job is telling two bridges apart on demand. */
    if (in->alarm_unacked) {
        return APP_UI_LED_ALARM;
    }
    if (in->identify_until_ms != 0 && now_ms < in->identify_until_ms) {
        return APP_UI_LED_IDENTIFY;
    }
    if (in->ota) {
        return APP_UI_LED_OTA;
    }
    if (in->pairing) {
        return APP_UI_LED_PAIRING;
    }
    if (in->base_lost) {
        return APP_UI_LED_BASE_LOST;
    }
    if (in->packet_flash) {
        return APP_UI_LED_HEARTBEAT;
    }
    return APP_UI_LED_OFF;
}

uint8_t app_ui_led_duty(const app_ui_led_input_t *in, uint32_t now_ms) {
    if (in == NULL || in->mode == APP_UI_LED_MODE_OFF) {
        /* OFF is zero in EVERY state, including alarm. The user asked for
         * darkness; the API, the app and the buzzer are where an alarm
         * still shouts. */
        return 0;
    }
    const app_ui_led_pattern_t p = app_ui_led_pattern(in, now_ms);
    if (in->mode == APP_UI_LED_MODE_ALARMS_ONLY && p != APP_UI_LED_ALARM &&
        p != APP_UI_LED_IDENTIFY) {
        /* The default. Identify survives because the user just asked for
         * it from the app, deliberately, seconds ago. */
        return 0;
    }

    switch (p) {
    case APP_UI_LED_ALARM:
        /* 2 Hz: 250 ms on, 250 ms off. */
        return (now_ms % 500u) < 250u ? APP_UI_LED_DUTY_MAX : 0;
    case APP_UI_LED_IDENTIFY:
        /* Rapid — 10 Hz, unmistakably not the alarm. */
        return (now_ms % 100u) < 50u ? APP_UI_LED_DUTY_MAX : 0;
    case APP_UI_LED_OTA: {
        /* Slow breathe over 4 s, triangular so it is smooth at 8 bits. */
        const uint32_t t = now_ms % 4000u;
        const uint32_t up = t < 2000u ? t : 4000u - t;
        return (uint8_t)((up * APP_UI_LED_DUTY_MAX) / 2000u);
    }
    case APP_UI_LED_PAIRING:
        return APP_UI_LED_DUTY_MAX;
    case APP_UI_LED_BASE_LOST: {
        /* Double-blink every 2 s: on 0-80, off 80-240, on 240-320. */
        const uint32_t t = now_ms % 2000u;
        return (t < 80u || (t >= 240u && t < 320u)) ? APP_UI_LED_DUTY_MAX : 0;
    }
    case APP_UI_LED_HEARTBEAT:
        return APP_UI_LED_DUTY_MAX;
    default:
        return 0;
    }
}

bool app_ui_buzzer_on(const app_ui_led_input_t *in, uint32_t now_ms) {
    if (in == NULL || !in->buzzer_enabled || !in->alarm_unacked) {
        return false;
    }
    /* Mirrors the alarm pattern exactly, and nothing else — a piezo that
     * chirps for a heartbeat is a piezo that gets removed. */
    return (now_ms % 500u) < 250u;
}
