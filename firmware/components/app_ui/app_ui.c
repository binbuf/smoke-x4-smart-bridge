/* app_ui.c — GPIO, i2c_master, event subscription, and the render task
 * (F11a.5). Everything decidable without a panel lives in app_ui_core.c /
 * app_ui_panel.c and is host-tested; this file is the part that can only
 * be proven on the board.
 */
#include "app_ui.h"

#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "app_ui_core.h"
#include "app_ui_panel.h"
#include "bridge_event.h"

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

static i2c_master_bus_handle_t s_bus;
static i2c_master_dev_handle_t s_dev;
static app_ui_state_t s_state;
static SemaphoreHandle_t s_lock;
static TaskHandle_t s_task;

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

static const app_ui_panel_ops_t k_ops = {
    .vext_power = op_vext_power,
    .reset_line = op_reset_line,
    .bus_create = op_bus_create,
    .bus_destroy = op_bus_destroy,
    .tx = op_tx,
    .delay_ms = op_delay_ms,
};

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
        s_state.passkey_active = true;
        snprintf(s_state.passkey, sizeof s_state.passkey, "%06u",
                 (unsigned)(e->passkey % 1000000u));
        break;
    case BRIDGE_BLE_PASSKEY_CLEAR:
    case BRIDGE_BLE_BONDED:
    case BRIDGE_BLE_DISCONNECTED:
        s_state.passkey_active = false;
        memset(s_state.passkey, 0, sizeof s_state.passkey);
        break;
    default:
        break;
    }
    xSemaphoreGive(s_lock);
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

/* ── the render task row ──────────────────────────────────────────── */

static void ui_task(void *arg) {
    (void)arg;
    for (;;) {
        /* Wake on state change, not on a timer: 07 §7.6's "render only
         * when dirty". The 1 s backstop exists only so a missed
         * notification cannot leave the glass permanently stale — it
         * costs nothing, because app_ui_panel_render() compares the
         * snapshot and returns without touching I²C when it is equal.
         *
         * The 1 Hz clock tick the reference redraws for arrives with
         * F11b's status strip (M5); M3 has no time-varying field. */
        (void)ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(1000));
        app_ui_state_t snapshot;
        xSemaphoreTake(s_lock, portMAX_DELAY);
        snapshot = s_state;
        xSemaphoreGive(s_lock);
        (void)app_ui_panel_render(&snapshot);
    }
}

int app_ui_init(void) {
    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) {
        return -1;
    }
    memset(&s_state, 0, sizeof s_state);

    const gpio_config_t out = {
        .pin_bit_mask = (1ULL << PIN_VEXT) | (1ULL << PIN_OLED_RST),
        .mode = GPIO_MODE_OUTPUT,
    };
    if (gpio_config(&out) != ESP_OK) {
        return -1;
    }

    app_ui_panel_init(&k_ops, NULL);
    const int rc = app_ui_panel_bringup();
    if (rc != 0) {
        ESP_LOGE(TAG, "panel bring-up failed (%d) — continuing headless", rc);
        return -1;
    }

    if (bridge_event_handler_register(BRIDGE_EVT_BLE, on_ble_event, NULL,
                                      "app_ui.ble") != ESP_OK) {
        return -1;
    }

    if (xTaskCreatePinnedToCore(ui_task, UI_TASK_NAME, UI_TASK_STACK, NULL,
                                UI_TASK_PRIO, &s_task,
                                UI_TASK_CORE) != pdPASS) {
        return -1;
    }
    ESP_LOGI(TAG, "display up: SSD1306 @400 kHz, passkey overlay only (M3)");
    return 0;
}
