/* app_ui.c — GPIO, LEDC, i2c_master, event subscription, and the render
 * task (F11a.5, F11b.11).
 *
 * Everything decidable without a panel lives in app_ui_core.c /
 * app_ui_render.c / app_ui_input.c / app_ui_model.c / app_ui_led.c and is
 * host-tested; this file is the part that can only be proven on the board:
 * the pins, the PWM, and the snapshot it assembles from every other
 * component.
 *
 * ONE CORRECTION TO THE TASK TABLE. main/tasks.h's app_ui row reads
 * "4 Hz button sampling, 1 Hz OLED render". 07 §7.4 specifies 20 ms
 * sampling with a 30 ms debounce, and 25 Hz is what a 400 ms double-tap
 * window actually needs — 4 Hz cannot see one. The comment was wrong, not
 * the design; the task wakes every 20 ms for the button and renders only
 * when the snapshot changes.
 */
#include "app_ui.h"

#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/ledc.h"
#include "esp_app_desc.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "app_alarm.h"
#include "app_config_store.h"
#include "app_net.h"
#include "app_power.h"
#include "app_power_svc.h"
#include "app_ui_cook.h"
#include "app_ui_core.h"
#include "app_ui_input.h"
#include "app_ui_led.h"
#include "app_ui_model.h"
#include "app_ui_panel.h"
#include "bridge_event.h"
#include "cook_ring.h"
#include "cook_store.h"
#include "cook_store_core.h"
#include "smoke_x_ctrl.h"

static const char *TAG = "app_ui";

/* Mirrors the app_ui row of main/tasks.h — components cannot depend on
 * `main`, so the table stays the single source of truth and this is a
 * copy of one row. test_tasks_table.c pins the values so a change to the
 * table shows up as a failing test rather than a silent divergence. */
#define UI_TASK_NAME "app_ui"
#define UI_TASK_STACK 4096
#define UI_TASK_PRIO 3
#define UI_TASK_CORE 0

/* 01 §1.2 pin map. Vext is ACTIVE LOW (V1.4: rail on = GPIO36 LOW). */
#define PIN_OLED_SDA GPIO_NUM_17
#define PIN_OLED_SCL GPIO_NUM_18
#define PIN_OLED_RST GPIO_NUM_21
#define PIN_VEXT GPIO_NUM_36
#define PIN_BUTTON GPIO_NUM_0 /* PRG, active LOW */
#define PIN_LED GPIO_NUM_35   /* active HIGH, LEDC (V1.4) */

#define LED_TIMER LEDC_TIMER_0
#define LED_CHANNEL LEDC_CHANNEL_0

static i2c_master_bus_handle_t s_bus;
static i2c_master_dev_handle_t s_dev;
static app_ui_state_t s_state;
static app_ui_model_t s_model;
static app_ui_led_input_t s_led;
static SemaphoreHandle_t s_lock;
static TaskHandle_t s_task;
static uint32_t s_boot_ms;

/* ── the panel seam ───────────────────────────────────────────────── */

static int op_vext_power(void *ctx, bool on) {
    (void)ctx;
    /* Intent "on" → GPIO36 LOW. The polarity lives here and nowhere
     * else, so app_ui_panel stays a statement of order, not of wiring. */
    return gpio_set_level(PIN_VEXT, on ? 0 : 1) == ESP_OK ? 0 : -1;
}

static int op_reset_line(void *ctx, bool high) {
    (void)ctx;
    return gpio_set_level(PIN_OLED_RST, high ? 1 : 0) == ESP_OK ? 0 : -1;
}

static int op_bus_create(void *ctx) {
    (void)ctx;
    const i2c_master_bus_config_t bus_cfg = {
        .i2c_port = -1,
        .sda_io_num = PIN_OLED_SDA,
        .scl_io_num = PIN_OLED_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags = {.enable_internal_pullup = true},
    };
    if (i2c_new_master_bus(&bus_cfg, &s_bus) != ESP_OK) {
        return -1;
    }
    const i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = APP_UI_PANEL_ADDR,
        .scl_speed_hz = APP_UI_PANEL_I2C_HZ,
    };
    if (i2c_master_bus_add_device(s_bus, &dev_cfg, &s_dev) != ESP_OK) {
        (void)i2c_del_master_bus(s_bus);
        s_bus = NULL;
        return -1;
    }
    return 0;
}

static int op_bus_destroy(void *ctx) {
    (void)ctx;
    if (s_dev != NULL) {
        (void)i2c_master_bus_rm_device(s_dev);
        s_dev = NULL;
    }
    if (s_bus != NULL) {
        (void)i2c_del_master_bus(s_bus);
        s_bus = NULL;
    }
    return 0;
}

static int op_tx(void *ctx, const uint8_t *buf, size_t len) {
    (void)ctx;
    return i2c_master_transmit(s_dev, buf, len, 100) == ESP_OK ? 0 : -1;
}

static void op_delay_ms(void *ctx, uint32_t ms) {
    (void)ctx;
    vTaskDelay(pdMS_TO_TICKS(ms));
}

static const app_ui_panel_ops_t k_panel_ops = {
    .vext_power = op_vext_power,
    .reset_line = op_reset_line,
    .bus_create = op_bus_create,
    .bus_destroy = op_bus_destroy,
    .tx = op_tx,
    .delay_ms = op_delay_ms,
};

/* ── the model seam ───────────────────────────────────────────────── */

static void op_panel_power(void *ctx, bool on) {
    (void)ctx;
    app_ui_panel_set_awake(on);
}

static void op_perform(void *ctx, app_ui_action_t action) {
    (void)ctx;
    /* ONE action. Everything the button used to do — units, sessions, marks,
     * pairing, network mode, battery saver, factory reset, alarm ack — moved
     * to the app, which already reaches this device over HTTP and BLE
     * (07 §7.4). The bridge is a passthrough; this is its only commit. */
    if (action != APP_UI_ACTION_POWER_OFF) {
        return;
    }
    /* Soft power off. Blank everything app_ui owns — the panel, its Vext
     * rail, and the LED — then hand the SoC to app_power, which arms the
     * GPIO0 wake and enters deep sleep. Does not return. */
    app_ui_panel_set_awake(false);    /* SSD1306 0xAE: pixels off */
    (void)op_vext_power(NULL, false); /* GPIO36 HIGH: cut the OLED rail */
    (void)ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL, 0);
    (void)ledc_update_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL);
    app_power_enter_deep_sleep();
}

static const app_ui_model_ops_t k_model_ops = {
    .perform = op_perform,
    .panel_power = op_panel_power,
};

/* ── the snapshot ─────────────────────────────────────────────────── */

static uint32_t now_ms(void) {
    return (uint32_t)((uint64_t)esp_timer_get_time() / 1000ull);
}

/* The config half of the snapshot, read from NVS. It lives in its own
 * struct and is read OUTSIDE s_lock (see ui_task), because s_lock MUST NEVER
 * wrap flash I/O: a bridge_event handler waiting on the lock runs on the
 * event loop under a 5 ms budget (F1.3), and a contended flash bus made
 * these 13 reads blow it and panic-loop the board (found 2026-07-23).
 * Anything added here must stay lock-free — keep flash out of s_lock. */
typedef struct {
    bool celsius;
    struct {
        char name[APP_UI_NAME_LEN + 1];
        int32_t target_f10;
        uint8_t role; /* raw app_config role; mapped in fill_snapshot */
    } probe[4];
} ui_cfg_read_t;

static void read_ui_cfg(ui_cfg_read_t *c) {
    static const app_config_key_t name_keys[4] = {
        APP_CONFIG_PROBE1_NAME, APP_CONFIG_PROBE2_NAME,
        APP_CONFIG_PROBE3_NAME, APP_CONFIG_PROBE4_NAME};
    static const app_config_key_t role_keys[4] = {
        APP_CONFIG_PROBE1_ROLE, APP_CONFIG_PROBE2_ROLE,
        APP_CONFIG_PROBE3_ROLE, APP_CONFIG_PROBE4_ROLE};
    static const app_config_key_t target_keys[4] = {
        APP_CONFIG_PROBE1_TARGET, APP_CONFIG_PROBE2_TARGET,
        APP_CONFIG_PROBE3_TARGET, APP_CONFIG_PROBE4_TARGET};

    uint8_t units = 0;
    (void)app_config_store_get_u8(APP_CONFIG_DEV_UNITS, &units);
    c->celsius = units == APP_CONFIG_UNITS_C;
    for (int i = 0; i < 4; i++) {
        c->probe[i].name[0] = '\0';
        (void)app_config_store_get_str(name_keys[i], c->probe[i].name,
                                       sizeof c->probe[i].name);
        uint8_t role = APP_CONFIG_ROLE_UNUSED;
        (void)app_config_store_get_u8(role_keys[i], &role);
        c->probe[i].role = role;
        int32_t target = 0;
        (void)app_config_store_get_i32(target_keys[i], &target);
        c->probe[i].target_f10 = target;
    }
}

/* Populate the render snapshot. Everything here is in-memory — cook ring,
 * smoke_x, power, net — EXCEPT the config, which arrives pre-read in [cfg]
 * so this runs under s_lock without touching flash. */
static void fill_snapshot(app_ui_state_t *st, const ui_cfg_read_t *cfg) {
    st->celsius = cfg->celsius;

    const cook_ring_sample_t *newest = cook_ring_get(0);
    const smoke_x_state_t *sx = smoke_x_ctrl_last_state();
    st->num_probes = sx != NULL ? sx->num_probes : 4;
    for (int i = 0; i < 4; i++) {
        app_ui_probe_t *p = &st->probe[i];
        snprintf(p->name, sizeof p->name, "%s", cfg->probe[i].name);
        const uint8_t role = cfg->probe[i].role;
        p->role = role == APP_CONFIG_ROLE_PIT     ? BRIDGE_PROBE_ROLE_PIT
                  : role == APP_CONFIG_ROLE_FOOD  ? BRIDGE_PROBE_ROLE_FOOD
                  : role == APP_CONFIG_ROLE_AMBIENT
                      ? BRIDGE_PROBE_ROLE_AMBIENT
                      : BRIDGE_PROBE_ROLE_UNUSED;
        p->target_f10 = cfg->probe[i].target_f10;
        p->temp_f10 =
            newest != NULL ? newest->temp[i] : (int16_t)BRIDGE_TEMP_DETACHED;
        if (sx != NULL && i < sx->num_probes && sx->probes[i].alarm_armed) {
            p->has_band = true;
            p->band_lo_f10 = (int16_t)(sx->probes[i].alarm_low * 10);
            p->band_hi_f10 = (int16_t)(sx->probes[i].alarm_high * 10);
        }
        float slope = 0.0f;
        p->slope_valid = cook_ring_slope_f_per_hr(i, &slope);
        p->slope_f10_per_hr = (int16_t)(slope * 10.0f);
    }

    /* status strip */
    const uint64_t ms = (uint64_t)esp_timer_get_time() / 1000ull;
    const uint64_t last = smoke_x_ctrl_last_valid_ms();
    st->base_ok = ms > last && (ms - last) < 60000ull;
    /* The ONLY elapsed time this device shows, and it comes from the app.
     * This used to be `newest->t` — seconds since the storage session
     * opened — which the bridge starts by itself the moment a probe warms
     * up, so the strip counted up whether or not a cook existed. */
    st->cook_elapsed_s = 0;
    st->cook_clock_set =
        app_ui_cook_get((uint32_t)(ms / 1000ull), &st->cook_elapsed_s);
    st->soc_pct = app_power_svc_soc();
    st->charging = app_power_svc_charging();
    st->saver = app_power_svc_saver();
    st->mv = app_power_svc_mv();
    st->alarm_unacked = app_alarm_unacked();

    app_net_status_t net;
    app_net_get_status(&net);
    st->net_mode = strcmp(net.mode, "ap") == 0    ? APP_UI_NET_AP
                   : strcmp(net.mode, "sta") == 0 ? APP_UI_NET_STA
                                                  : APP_UI_NET_OFF;
    st->net_state = strcmp(net.state, "up") == 0           ? APP_UI_NET_UP
                    : strcmp(net.state, "connecting") == 0 ? APP_UI_NET_CONNECTING
                    : strcmp(net.state, "failed") == 0     ? APP_UI_NET_FAILED
                                                           : APP_UI_NET_IDLE;
    snprintf(st->ssid, sizeof st->ssid, "%s", net.ssid);
    snprintf(st->ip, sizeof st->ip, "%s", net.ip);
    snprintf(st->host, sizeof st->host, "%s", net.host);
    st->wifi_rssi = net.rssi;
    st->ap_clients = (uint8_t)(net.ap_clients < 0 ? 0 : net.ap_clients);
    st->ap_client = st->ap_clients > 0;
    (void)app_config_store_get_str(APP_CONFIG_NET_AP_PSK, st->psk,
                                   sizeof st->psk);

    /* trends page — and note what is NOT here any more.
     *
     * The old cook page read the active session's 256 B header from
     * LittleFS on every fill, for a name and a mark count. fill_snapshot
     * runs UNDER s_lock, and the comment on ui_cfg_read_t above spells out
     * why that is a trap: NVS and LittleFS share the SPI-flash bus, a
     * contended read blocks ~17 ms, and s_lock is taken by three event-bus
     * handlers that have a 5 ms budget (F1.3). That is the same shape as
     * the panic-loop found on 2026-07-23; it survived here because the read
     * only ran while a session was open. Dropping the session from the glass
     * takes the last flash read out of s_lock with it.
     *
     * The sparkline reads the RAM ring and NEVER flash (04 §4.3). */
    int pit = 0;
    for (int i = 0; i < 4; i++) {
        if (st->probe[i].role == BRIDGE_PROBE_ROLE_PIT) {
            pit = i;
            break;
        }
    }
    const int have = cook_ring_count();
    const int want = have < APP_UI_SPARK_MAX ? have : APP_UI_SPARK_MAX;
    for (int i = 0; i < want; i++) {
        /* idx 0 is newest; the spark array runs oldest → newest. */
        const cook_ring_sample_t *s = cook_ring_get(want - 1 - i);
        st->spark[i] = s != NULL ? s->temp[pit] : (int16_t)BRIDGE_TEMP_DETACHED;
    }
    st->spark_n = (uint8_t)want;

    /* radio page */
    st->paired = smoke_x_ctrl_state() == SMOKE_X_CONFIRMED;
    if (sx != NULL) {
        snprintf(st->device_id, sizeof st->device_id, "%s", sx->device_id);
    }
    st->frequency_hz = smoke_x_ctrl_frequency_hz();
    const smoke_x_stats_t *stats = smoke_x_ctrl_stats();
    st->lora_rssi = stats->last_rssi;
    st->lora_snr = stats->last_snr;
    st->last_packet_s = (uint32_t)((ms > last ? ms - last : 0ull) / 1000ull);
    st->packets_ok = stats->valid;
    st->packets_bad = stats->parse_fail + stats->crc_fail +
                      stats->unknown_commas;
    st->interval_s10 = 300; /* the 02 Q1 nominal until a mean is tracked */

    /* system page */
    const esp_app_desc_t *desc = esp_app_get_description();
    snprintf(st->fw, sizeof st->fw, "v%.*s", (int)(sizeof st->fw - 2),
             desc != NULL ? desc->version : "?");
    st->uptime_s = (uint32_t)(ms / 1000ull);
    uint32_t total = 0;
    uint32_t used = 0;
    if (cook_store_fs_info(&total, &used) == 0) {
        st->storage_total_b = total;
        st->storage_used_b = used;
    }
    st->stored_files = (uint16_t)cook_store_index_count();
    st->heap_free = (uint32_t)esp_get_free_heap_size();
    st->heap_min = (uint32_t)esp_get_minimum_free_heap_size();
    app_ui_panel_counts(&st->i2c_ok, &st->i2c_err);
}

/* ── event handling ───────────────────────────────────────────────── */

static void on_ble_event(void *arg, esp_event_base_t base, int32_t id,
                         void *data) {
    (void)arg;
    (void)base;
    (void)id;
    const bridge_evt_ble_t *e = data;
    if (e == NULL) {
        return;
    }
    /* The handler only mutates the snapshot — the I²C write happens on the
     * app_ui task, never on the event loop (03 §3.2's duration guard). */
    xSemaphoreTake(s_lock, portMAX_DELAY);
    switch (e->action) {
    case BRIDGE_BLE_PASSKEY_SHOW:
        s_state.overlay = APP_UI_OVERLAY_PASSKEY;
        snprintf(s_state.passkey, sizeof s_state.passkey, "%06u",
                 (unsigned)(e->passkey % 1000000u));
        app_ui_model_wake(&s_model, now_ms());
        break;
    case BRIDGE_BLE_PASSKEY_CLEAR:
    case BRIDGE_BLE_BONDED:
    case BRIDGE_BLE_DISCONNECTED:
        if (s_state.overlay == APP_UI_OVERLAY_PASSKEY) {
            s_state.overlay = APP_UI_OVERLAY_NONE;
        }
        memset(s_state.passkey, 0, sizeof s_state.passkey);
        break;
    case BRIDGE_BLE_CONNECTED:
        app_ui_model_wake(&s_model, now_ms());
        break;
    default:
        break;
    }
    s_state.ble_conns = e->conns;
    s_state.ble_bonds = e->bonds;
    xSemaphoreGive(s_lock);
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

static void on_alarm_event(void *arg, esp_event_base_t base, int32_t id,
                           void *data) {
    (void)arg;
    (void)base;
    (void)id;
    const bridge_evt_alarm_t *e = data;
    if (e == NULL) {
        return;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (e->action == BRIDGE_ALARM_RAISED) {
        s_state.alarm_rule = e->rule;
        s_state.alarm_probe = e->probe;
        s_state.alarm_value_f10 = e->value_f10;
        app_ui_model_on_alarm(&s_model, &s_state, now_ms());
    } else {
        app_ui_model_clear_alarm(&s_model, &s_state);
    }
    xSemaphoreGive(s_lock);
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

static void on_wake_event(void *arg, esp_event_base_t base, int32_t id,
                          void *data) {
    (void)arg;
    (void)base;
    (void)id;
    (void)data;
    /* 07 §7.1's wake list, minus one. Storage session start/end used to
     * light the panel; it no longer does, because nothing on the glass
     * changes when it happens. Waking a battery-powered display for an
     * invisible event is a cost with no reader. */
    xSemaphoreTake(s_lock, portMAX_DELAY);
    app_ui_model_wake(&s_model, now_ms());
    xSemaphoreGive(s_lock);
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

/* ── the render task row ──────────────────────────────────────────── */

static void ui_task(void *arg) {
    (void)arg;
    for (;;) {
        /* 20 ms: 07 §7.4's sampling rate, which is what a 400 ms
         * double-tap window needs. Rendering is still dirty-driven —
         * app_ui_panel_render() compares the snapshot and returns without
         * touching I²C when it is equal, so 25 Hz of ticks costs 25 Hz of
         * memcmp and no I²C at all. */
        (void)ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(APP_UI_SAMPLE_MS));
        const uint32_t t = now_ms();
        const bool pressed = gpio_get_level(PIN_BUTTON) == 0; /* active LOW */

        uint16_t timeout_s = 60;
        (void)app_config_store_get_u16(APP_CONFIG_DEV_DISPLAY_TIMEOUT_S,
                                       &timeout_s);
        if (app_power_svc_saver() && timeout_s > 30) {
            timeout_s = 30; /* 01 §1.6's saver profile */
        }

        /* ALL config/NVS reads happen BEFORE s_lock. NVS shares the SPI-flash
         * bus with LittleFS (cook + power log): under write contention a read
         * blocks ~17 ms. Holding s_lock across that stalls the event-bus
         * handlers (on_alarm/on_ble/on_wake all take this lock), and a handler
         * over 5 ms trips the F1.3 guard — board-found as an `app_ui.alarm`
         * panic that looped the board. The lock wraps only in-memory work. */
        uint8_t led_mode = 1;
        (void)app_config_store_get_u8(APP_CONFIG_DEV_LED_ENABLED, &led_mode);
        uint8_t buzzer = 0;
        (void)app_config_store_get_u8(APP_CONFIG_DEV_BUZZER_ENABLED, &buzzer);
        ui_cfg_read_t cfg;
        read_ui_cfg(&cfg); /* the 13 probe/units reads — lock-free */

        app_ui_state_t snapshot;
        xSemaphoreTake(s_lock, portMAX_DELAY);
        /* The boot splash owns the glass for the 3 s recovery window
         * (03 §3.4.1) and then gets out of the way. */
        if (s_state.overlay == APP_UI_OVERLAY_SPLASH) {
            const uint32_t age = t - s_boot_ms;
            if (age >= 3000u) {
                s_state.overlay = APP_UI_OVERLAY_NONE;
            } else {
                s_state.confirm_count = (uint8_t)(3u - age / 1000u);
            }
        }
        fill_snapshot(&s_state, &cfg);
        app_ui_model_tick(&s_model, &s_state, pressed, t, timeout_s);
        snapshot = s_state;

        s_led.alarm_unacked = snapshot.alarm_unacked;
        s_led.pairing = !snapshot.paired;
        s_led.base_lost = !snapshot.base_ok;
        s_led.mode = led_mode > 2 ? APP_UI_LED_MODE_ALARMS_ONLY : led_mode;
        s_led.buzzer_enabled = buzzer != 0;
        const uint8_t duty = app_ui_led_duty(&s_led, t);
        xSemaphoreGive(s_lock);

        (void)ledc_set_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL, duty);
        (void)ledc_update_duty(LEDC_LOW_SPEED_MODE, LED_CHANNEL);
        (void)app_ui_panel_render(&snapshot);
    }
}

int app_ui_init(void) {
    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) {
        return -1;
    }
    memset(&s_state, 0, sizeof s_state);
    s_boot_ms = now_ms();
    s_state.overlay = APP_UI_OVERLAY_SPLASH;
    s_state.soc_pct = BRIDGE_SOC_UNKNOWN;

    const gpio_config_t out = {
        .pin_bit_mask = (1ULL << PIN_VEXT) | (1ULL << PIN_OLED_RST),
        .mode = GPIO_MODE_OUTPUT,
    };
    if (gpio_config(&out) != ESP_OK) {
        return -1;
    }
    const gpio_config_t btn = {
        .pin_bit_mask = 1ULL << PIN_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    if (gpio_config(&btn) != ESP_OK) {
        return -1;
    }

    /* GPIO35, active HIGH, under LEDC (V1.4 confirmed it dims). */
    const ledc_timer_config_t ledt = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_8_BIT,
        .timer_num = LED_TIMER,
        .freq_hz = 1000,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    (void)ledc_timer_config(&ledt);
    const ledc_channel_config_t ledc = {
        .gpio_num = PIN_LED,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LED_CHANNEL,
        .timer_sel = LED_TIMER,
        .duty = 0,
        .hpoint = 0,
    };
    (void)ledc_channel_config(&ledc);

    app_ui_panel_init(&k_panel_ops, NULL);
    const int rc = app_ui_panel_bringup();
    if (rc != 0) {
        /* A bridge with a dead panel still cooks (03 §3.4). */
        ESP_LOGE(TAG, "panel bring-up failed (%d) — continuing headless", rc);
        return -1;
    }
    app_ui_model_init(&s_model, &k_model_ops);

    if (bridge_event_handler_register(BRIDGE_EVT_BLE, on_ble_event, NULL,
                                      "app_ui.ble") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_ALARM, on_alarm_event, NULL,
                                      "app_ui.alarm") != ESP_OK ||
        bridge_event_handler_register(BRIDGE_EVT_NET, on_wake_event, NULL,
                                      "app_ui.net") != ESP_OK) {
        return -1;
    }

    if (xTaskCreatePinnedToCore(ui_task, UI_TASK_NAME, UI_TASK_STACK, NULL,
                                UI_TASK_PRIO, &s_task,
                                UI_TASK_CORE) != pdPASS) {
        return -1;
    }
    ESP_LOGI(TAG,
             "display up: SSD1306 @400 kHz, 5 pages, 20 ms button, LED on "
             "GPIO35");
    return 0;
}
