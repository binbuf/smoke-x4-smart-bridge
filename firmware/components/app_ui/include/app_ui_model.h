/* app_ui_model — what a gesture MEANS, and when the panel sleeps
 * (F11b.8, F11b.9; design 07 §7.2, §7.4, §7.1).
 *
 * Pure C11 with an injected action seam, so a host test drives
 * level trace → gesture → action → snapshot change without a GPIO and
 * without a panel.
 *
 * The design decision worth keeping visible: the AP↔STA switch is a
 * CONTEXT ACTION on the Network page, not a global long-press. 07 opens
 * by answering that question — requiring the user to navigate to the page
 * first means the screen already shows what they are switching *from* and
 * *to*, and a blind global toggle is one pocket-press away from taking a
 * bridge off the network 12 hours into a cook.
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

/* One per page, plus the two global ones. */
typedef enum {
    APP_UI_ACTION_NONE = 0,
    APP_UI_ACTION_TOGGLE_UNITS,   /* page 1 */
    APP_UI_ACTION_SESSION_TOGGLE, /* page 2 */
    APP_UI_ACTION_NET_TOGGLE,     /* page 3 */
    APP_UI_ACTION_RADIO_TOGGLE,   /* page 4: unpair, or re-scan */
    APP_UI_ACTION_SAVER_TOGGLE,   /* page 5 */
    APP_UI_ACTION_ADD_MARK,       /* double-tap, any page */
    APP_UI_ACTION_ACK_ALARM,      /* tap on the alarm overlay */
    APP_UI_ACTION_FACTORY_RESET,
} app_ui_action_t;

/* The confirm copy each hold action shows (07 §7.3). */
const char *app_ui_action_prompt(app_ui_action_t a, const app_ui_state_t *st);

typedef struct {
    /* Performs a committed action. May be NULL. */
    void (*perform)(void *ctx, app_ui_action_t action);
    /* Panel power. The model owns WHEN; the panel layer owns HOW. */
    void (*panel_power)(void *ctx, bool on);
    void *ctx;
} app_ui_model_ops_t;

/* 07 §7.4: factory reset counts down from 5 with three separate
 * KEEP HOLDING prompts. */
#define APP_UI_FACTORY_CONFIRMS 3

typedef struct {
    app_ui_input_t_state input;
    uint8_t page;
    bool awake;
    uint32_t last_activity_ms;
    /* A hold in progress: which action, and how far into the countdown. */
    app_ui_action_t pending;
    uint8_t factory_confirms;
    /* The alarm overlay reverts after 60 s; the ALARM does not. */
    bool alarm_overlay;
    uint32_t alarm_shown_ms;
    uint8_t mark_seq;
} app_ui_model_t;

/* 07 §7.3: the overlay persists until acknowledged or 60 s. */
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
/* An alarm was raised: wake, show the overlay, and reset to page 1. */
void app_ui_model_on_alarm(app_ui_model_t *m, app_ui_state_t *st,
                           uint32_t now_ms);
/* The alarm was acknowledged or cleared elsewhere (app, BLE). */
void app_ui_model_clear_alarm(app_ui_model_t *m, app_ui_state_t *st);

bool app_ui_model_awake(const app_ui_model_t *m);
uint8_t app_ui_model_page(const app_ui_model_t *m);

#ifdef __cplusplus
}
#endif

#endif /* APP_UI_MODEL_H */
