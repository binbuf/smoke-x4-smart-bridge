/* app_ui_model — which view is on the glass, the power-off hold, and when
 * the panel sleeps (design 07 §7.1, §7.2, §7.4).
 *
 * Pure C11 with an injected action seam, so a host test drives
 * level trace → gesture → view change without a GPIO and without a panel.
 *
 * THE DECISION WORTH KEEPING VISIBLE: the bridge is a PASSTHROUGH. Every
 * control — units, sessions, marks, pairing, network mode, battery saver,
 * factory reset — lives in the app, which already reaches the device over
 * HTTP and BLE. The device shows information and can be powered off. That
 * is the whole of its input surface, and it is why this file has one action
 * instead of nine.
 *
 * An alarm is DISPLAYED here and never silenced here: silencing belongs to
 * the Smoke X receiver or the app.
 */
#ifndef APP_UI_MODEL_H
#define APP_UI_MODEL_H

#include <stdbool.h>
#include <stdint.h>

#include "app_ui_core.h"
#include "app_ui_input.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The only action the button can commit. */
typedef enum {
    APP_UI_ACTION_NONE = 0,
    APP_UI_ACTION_POWER_OFF, /* hold PRG: deep sleep (07 §7.4) */
} app_ui_action_t;

/* The confirm copy the power-off hold shows (07 §7.3). */
const char *app_ui_action_prompt(app_ui_action_t a, const app_ui_state_t *st);

typedef struct {
    /* Performs a committed action. May be NULL. */
    void (*perform)(void *ctx, app_ui_action_t action);
    /* Panel power. The model owns WHEN; the panel layer owns HOW. */
    void (*panel_power)(void *ctx, bool on);
    void *ctx;
} app_ui_model_ops_t;

typedef struct {
    app_ui_input_t_state input;
    uint8_t page;
    bool awake;
    uint32_t last_activity_ms;
    /* The alarm overlay reverts after 60 s; the ALARM does not. Dismissing
     * it here is not silencing it — that is the receiver's or the app's. */
    bool alarm_overlay;
    uint32_t alarm_shown_ms;
} app_ui_model_t;

/* 07 §7.3: the overlay persists until dismissed or 60 s. */
#define APP_UI_ALARM_OVERLAY_MS 60000

void app_ui_model_init(app_ui_model_t *m, const app_ui_model_ops_t *ops);

/* One 20 ms tick. `pressed` is the debounced-input's raw level;
 * `timeout_s` is display_timeout_s (0 = never sleep). Mutates `st`'s
 * page/overlay/confirm fields in place — everything else in the snapshot
 * belongs to the glue. */
void app_ui_model_tick(app_ui_model_t *m, app_ui_state_t *st, bool pressed,
                       uint32_t now_ms, uint16_t timeout_s);

/* Wake sources other than the button (07 §7.1): any alarm, session
 * start/end, network state change, BLE connect. */
void app_ui_model_wake(app_ui_model_t *m, uint32_t now_ms);
/* An alarm was raised: wake, show the overlay, and reset to view 1. */
void app_ui_model_on_alarm(app_ui_model_t *m, app_ui_state_t *st,
                           uint32_t now_ms);
/* The alarm was silenced elsewhere (receiver, app, BLE). */
void app_ui_model_clear_alarm(app_ui_model_t *m, app_ui_state_t *st);

bool app_ui_model_awake(const app_ui_model_t *m);
uint8_t app_ui_model_page(const app_ui_model_t *m);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_MODEL_H */
