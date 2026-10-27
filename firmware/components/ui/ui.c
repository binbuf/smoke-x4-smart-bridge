/*
 * ui.c - OLED lifecycle, render task and display sleep (design 03 section 3.10,
 * design 07 sections 7.1-7.5).
 *
 * Vext belongs to board_power_init(), which the boot sequence runs before this.
 * ui_init() creates the 400 kHz I2C bus, resets the panel and draws the boot
 * splash. The render task is a pure-snapshot consumer (ui_render.c) and only
 * touches the panel when the 1 KB framebuffer changes.
 */
#include "ui.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "ble_service.h"
#include "board.h"
#include "bridge_config.h"
#include "bridge_state.h"
#include "driver/i2c_master.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sample_log.h"
#include "ssd1306.h"
#include "sx_radio.h"
#include "ui_button.h"
#include "ui_render.h"
#include "ui_sleep.h"

#define UI_TASK_STACK 4096u
#define UI_TASK_PRIORITY 3u
#define UI_TASK_CORE 0
#define UI_BOOT_SPLASH_MS 300u
#define UI_POWER_OFF_SHOW_MS 300u /* the OFF frame before the rails drop */

static const char *TAG = "sx4.ui";

/* Cross-task dirty flag (T21 produces). */
static atomic_bool s_dirty;
static atomic_bool s_awake;
static atomic_bool s_wake_requested;

/* Display state, owned by the render task except for the short locked copies
 * used by the control API. */
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;
static ui_view_t s_view;
static uint8_t s_overlay_mask;
static char s_passkey[7];
static uint8_t s_power_countdown_s;
static bool s_storage_dismissed;
static bool s_panel_ok;
static bool s_panel_on; /* physical 0xAF/0xAE state, owned by the ui task */
static ui_button_t s_button;

static TaskHandle_t s_task;
static uint64_t s_boot_ms;
static uint64_t s_last_time_render_ms;
static bool s_have_frame;
static ui_framebuffer_t s_last_fb;

static i2c_master_bus_handle_t s_i2c_bus;
static i2c_master_dev_handle_t s_i2c_dev;

static uint64_t now_ms(void) { return (uint64_t)(esp_timer_get_time() / 1000); }

/* ---- SSD1306 I2C adapter ------------------------------------------------ */

static int panel_write(void *ctx, bool data, const uint8_t *buf, size_t len) {
    (void)ctx;
    if (s_i2c_dev == NULL || buf == NULL || len > SSD1306_WIDTH) {
        return -1;
    }
    /* One control byte plus at most one 128-byte page. */
    uint8_t tx[1u + SSD1306_WIDTH];
    tx[0] = data ? 0x40u : 0x00u;
    memcpy(tx + 1, buf, len);
    esp_err_t err = i2c_master_transmit(s_i2c_dev, tx, len + 1u, 100);
    return err == ESP_OK ? 0 : -1;
}

static const ssd1306_io_t s_panel_io = {.write = panel_write, .ctx = NULL};

static esp_err_t panel_bus_init(void) {
    i2c_master_bus_config_t bus_cfg = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_0,
        .scl_io_num = BOARD_PIN_I2C_SCL,
        .sda_io_num = BOARD_PIN_I2C_SDA,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    esp_err_t err = i2c_new_master_bus(&bus_cfg, &s_i2c_bus);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "i2c bus: %s", esp_err_to_name(err));
        return err;
    }

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = SSD1306_I2C_ADDRESS,
        .scl_speed_hz = SSD1306_I2C_HZ,
    };
    err = i2c_master_bus_add_device(s_i2c_bus, &dev_cfg, &s_i2c_dev);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "panel device: %s", esp_err_to_name(err));
        return err;
    }

    (void)board_oled_reset_pulse();
    if (ssd1306_init(&s_panel_io) != SSD1306_OK) {
        ESP_LOGE(TAG, "SSD1306 init failed at 0x%02x", SSD1306_I2C_ADDRESS);
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "SSD1306 128x64 at 0x%02x, %u Hz", SSD1306_I2C_ADDRESS,
             (unsigned)SSD1306_I2C_HZ);
    return ESP_OK;
}

/* ---- snapshot ----------------------------------------------------------- */

static uint16_t timeout_from_config(void) {
    uint16_t timeout = BRIDGE_CONFIG_DEFAULT_TIMEOUT;
    if (bridge_config_get_display_timeout(&timeout) != BRIDGE_CONFIG_OK) {
        timeout = BRIDGE_CONFIG_DEFAULT_TIMEOUT;
    }
    switch (timeout) {
        case UI_TIMEOUT_NEVER:
        case UI_TIMEOUT_30S:
        case UI_TIMEOUT_60S:
        case UI_TIMEOUT_120S:
            return timeout;
        default:
            return UI_TIMEOUT_60S;
    }
}

static void build_snapshot(ui_snapshot_t *snapshot) {
    ui_snapshot_init(snapshot);

    bridge_state_live_t live;
    if (bridge_state_snapshot(&live) == BRIDGE_STATE_OK) {
        snapshot->seq = live.seq;
        snapshot->attached_mask = live.attached_mask;
        for (unsigned i = 0; i < 4u; i++) {
            snapshot->temp_f10[i] = live.temp_f10[i];
        }
        snapshot->battery_mv = live.battery_mv;
        snapshot->battery_pct = live.battery_pct;
        snapshot->smoke_paired =
            (live.flags & SX4_LIVE_FLAG_SMOKE_PAIRED) != 0;
        snapshot->x4_age_s = live.age_s;
        snapshot->rssi = live.rssi_lora;
        snapshot->billows_detected =
            (live.flags & SX4_LIVE_FLAG_BILLOWS_ATTACHED) != 0;
        snapshot->billows_target_valid = live.billows_target_valid;
        snapshot->billows_target_f10 = live.billows_target_f10;
    }
    /* BLE link state and paired-phone count arrive with T27; until then the
     * page correctly shows advertising and 0/4 rather than inventing a link. */
    snapshot->app_connected = false;
    snapshot->phones_paired = 0;
    snapshot->storage_ok = sample_log_storage_ok();

    bridge_config_pairing_t pairing;
    if (bridge_config_get_pairing(&pairing) == BRIDGE_CONFIG_OK) {
        snapshot->frequency_hz = pairing.frequency_hz;
    }
    bridge_config_device_t device;
    if (bridge_config_get_device(&device) == BRIDGE_CONFIG_OK) {
        memcpy(snapshot->name, device.device_name, sizeof(snapshot->name));
        snapshot->name[sizeof(snapshot->name) - 1u] = '\0';
    }

    log_ring_info_t info;
    if (sample_log_get_info(&info)) {
        const uint32_t capacity =
            info.sector_count * SAMPLE_LOG_RECORDS_PER_SECTOR;
        snapshot->readings_count = info.count;
        if (snapshot->storage_ok && capacity > info.count) {
            uint64_t remaining = (uint64_t)(capacity - info.count) *
                                 (uint64_t)SX4_SAMPLE_INTERVAL_S * 10u;
            uint64_t days_x10 = remaining / 86400u;
            snapshot->log_days_left_x10 =
                days_x10 > 0xFFFEu ? (uint16_t)0xFFFEu : (uint16_t)days_x10;
        }
    }

    snapshot->uptime_s = (uint32_t)(now_ms() / 1000u);
    snapshot->mem_free_kb = (uint32_t)(esp_get_free_heap_size() / 1024u);
    snapshot->mem_low_kb =
        (uint32_t)(esp_get_minimum_free_heap_size() / 1024u);

    taskENTER_CRITICAL(&s_lock);
    snapshot->overlay_mask = s_overlay_mask;
    memcpy(snapshot->passkey, s_passkey, sizeof(snapshot->passkey));
    snapshot->power_countdown_s = s_power_countdown_s;
    bool storage_dismissed = s_storage_dismissed;
    taskEXIT_CRITICAL(&s_lock);

    if (!snapshot->storage_ok && !storage_dismissed) {
        /* Persistent until the next boot; T23 may dismiss the overlay for this
         * boot while the status strip keeps this bit (design 07 7.3). */
        snapshot->overlay_mask |= UI_OVERLAY_MASK_STORAGE_FAILURE;
    }
}

static void render_once(ui_page_t page) {
    ui_snapshot_t snapshot;
    build_snapshot(&snapshot);

    ui_framebuffer_t fb;
    ui_render(&fb, page, &snapshot);
    if (s_have_frame && memcmp(&fb, &s_last_fb, sizeof(fb)) == 0) {
        return;
    }
    if (ssd1306_flush(&s_panel_io, fb.page) == SSD1306_OK) {
        s_last_fb = fb;
        s_have_frame = true;
    }
}

/* ---- power-off path ----------------------------------------------------- */

static bool storage_notice_visible(void) {
    taskENTER_CRITICAL(&s_lock);
    bool dismissed = s_storage_dismissed;
    taskEXIT_CRITICAL(&s_lock);
    return !dismissed && !sample_log_storage_ok();
}

/*
 * A tap dismisses only the storage notice. Any other overlay (passkey, reset,
 * clearing, boot, power-off) is owned by another path, so a tap does nothing
 * there. Normal pages advance.
 */
static void handle_tap(void) {
    uint8_t mask;
    taskENTER_CRITICAL(&s_lock);
    mask = s_overlay_mask;
    taskEXIT_CRITICAL(&s_lock);

    if ((mask & (UI_OVERLAY_MASK_PASSKEY | UI_OVERLAY_MASK_CLEARING_LOG |
                 UI_OVERLAY_MASK_RESETTING | UI_OVERLAY_MASK_POWER_OFF |
                 UI_OVERLAY_MASK_OFF | UI_OVERLAY_MASK_BOOT)) != 0) {
        return;
    }
    if (storage_notice_visible()) {
        ui_dismiss_storage_failure();
        return;
    }
    (void)ui_page_next();
}

/* The panel is the caller's (ui task): draw OFF, hold it for ~300 ms, then
 * drop the rails in the order design 03 section 3.10 names. */
static void power_off_commit(void) {
    ui_page_t page;
    taskENTER_CRITICAL(&s_lock);
    s_power_countdown_s = 0;
    s_overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_POWER_OFF;
    s_overlay_mask |= UI_OVERLAY_MASK_OFF;
    page = s_view.page;
    taskEXIT_CRITICAL(&s_lock);

    render_once(page);
    vTaskDelay(pdMS_TO_TICKS(UI_POWER_OFF_SHOW_MS));
    ESP_LOGI(TAG, "power off: Vext off, radio asleep, BLE down, deep sleep");

    esp_err_t err = board_power_off_vext();
    (void)sx_radio_sleep();
    (void)ble_service_stop();
    err = board_enter_deep_sleep();
    if (err != ESP_OK) {
        /* Never claim to be off when the wake source could not be armed. */
        ESP_LOGE(TAG, "deep sleep failed (%s); staying on", esp_err_to_name(err));
        taskENTER_CRITICAL(&s_lock);
        s_overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_OFF;
        taskEXIT_CRITICAL(&s_lock);
        ui_mark_dirty();
    }
}

/* ---- render task -------------------------------------------------------- */

static void ui_task(void *arg) {
    (void)arg;
    for (;;) {
        uint64_t now = now_ms();
        bool asleep;
        bool went_to_sleep = false;
        ui_page_t page;

        /* ui_wake() updates the view and sets the flag; the panel's 0xAF is
         * applied here so every wake source (PRG, BLE, app) goes through one
         * path and a sample dirty mark can never power the panel on. */
        if (atomic_exchange(&s_wake_requested, false) && !s_panel_on) {
            (void)ssd1306_set_power(&s_panel_io, true); /* 0xAF */
            bridge_state_set_display_on(true);
            s_panel_on = true;
            ESP_LOGD(TAG, "panel awake, page unchanged");
        }

        taskENTER_CRITICAL(&s_lock);
        if (!s_view.asleep && ui_view_tick(&s_view, now)) {
            went_to_sleep = true;
        }
        asleep = s_view.asleep;
        page = s_view.page;
        taskEXIT_CRITICAL(&s_lock);

        if (went_to_sleep) {
            atomic_store(&s_awake, false);
            (void)ssd1306_set_power(&s_panel_io, false); /* 0xAE */
            bridge_state_set_display_on(false);
            s_panel_on = false;
            ESP_LOGD(TAG, "panel asleep");
        }

        /* PRG is sampled every 20 ms in all states. A press that arrives while
         * the panel is asleep is consumed by the machine: it wakes the panel
         * but produces no tap and no power-off countdown. */
        ui_button_event_t event = ui_button_sample(
            &s_button, board_prg_pressed(), now, asleep);
        switch (event) {
            case UI_BUTTON_EVENT_PRESS:
                /* ui_wake() also handles the awake case by restarting the
                 * display timeout; it never changes the page. */
                ui_display_activity();
                break;
            case UI_BUTTON_EVENT_TAP:
                handle_tap();
                break;
            case UI_BUTTON_EVENT_HOLD_START:
            case UI_BUTTON_EVENT_HOLD_TICK:
                ui_display_activity();
                ui_set_power_off(ui_button_countdown_s(&s_button, now), true);
                break;
            case UI_BUTTON_EVENT_HOLD_CANCEL:
                ui_set_power_off(0, false);
                break;
            case UI_BUTTON_EVENT_HOLD_COMMIT:
                power_off_commit();
                break;
            case UI_BUTTON_EVENT_NONE:
            default:
                break;
        }

        taskENTER_CRITICAL(&s_lock);
        asleep = s_view.asleep;
        page = s_view.page;
        taskEXIT_CRITICAL(&s_lock);

        if (!asleep && !s_panel_on) {
            (void)ssd1306_set_power(&s_panel_io, true); /* 0xAF */
            bridge_state_set_display_on(true);
            s_panel_on = true;
            ESP_LOGD(TAG, "panel awake, page unchanged");
        }

        if (!asleep && !went_to_sleep) {
            bool dirty = ui_dirty_take();
            bool time_tick = false;
            if ((page == UI_PAGE_BRIDGE || page == UI_PAGE_CONNECTION) &&
                now - s_last_time_render_ms >= 1000u) {
                time_tick = true;
            }
            if (dirty || time_tick || !s_have_frame) {
                render_once(page);
                s_last_time_render_ms = now;
            }
        }

        uint64_t wait_ms = UI_BUTTON_SAMPLE_MS;
        if (!asleep) {
            uint64_t view_wait;
            taskENTER_CRITICAL(&s_lock);
            view_wait = ui_view_next_tick_ms(&s_view, now);
            taskEXIT_CRITICAL(&s_lock);
            if ((page == UI_PAGE_BRIDGE || page == UI_PAGE_CONNECTION) &&
                view_wait > 1000u) {
                view_wait = 1000u;
            }
            if (view_wait < wait_ms) {
                wait_ms = view_wait;
            }
        }
        TickType_t ticks = pdMS_TO_TICKS(wait_ms);
        if (ticks == 0) {
            ticks = 1;
        }
        (void)ulTaskNotifyTake(pdTRUE, ticks);
    }
}

/* ---- lifecycle ---------------------------------------------------------- */

esp_err_t ui_init(void) {
    atomic_store(&s_dirty, false);
    atomic_store(&s_awake, true);
    atomic_store(&s_wake_requested, false);
    uint64_t start = now_ms();
    s_boot_ms = start;
    uint16_t timeout = timeout_from_config();
    ui_view_init(&s_view, UI_PAGE_PROBES, timeout, start);
    s_overlay_mask = UI_OVERLAY_MASK_BOOT;
    s_passkey[0] = '\0';
    s_power_countdown_s = 0;
    s_storage_dismissed = false;
    s_have_frame = false;
    s_panel_on = false;

    (void)board_prg_init();
    /* An in-progress hold at boot is the tail of hold-to-wake (or a reset with
     * the button down). Consume it so releasing does not fire a tap. */
    ui_button_init(&s_button, board_prg_pressed(), start, true);

    esp_err_t err = panel_bus_init();
    if (err != ESP_OK) {
        s_panel_ok = false;
        return err;
    }
    s_panel_ok = true;
    s_panel_on = true; /* ssd1306_init() ends with 0xAF */
    bridge_state_set_display_on(true);
    render_once(UI_PAGE_PROBES); /* boot overlay wins inside ui_render() */
    /* The 300 ms splash window starts when the frame actually reaches the
     * panel, not when init began. */
    s_boot_ms = now_ms();
    return ESP_OK;
}

esp_err_t ui_start(void) {
    if (!s_panel_ok) {
        ESP_LOGW(TAG, "panel unavailable; render task not started");
        return ESP_OK;
    }

    uint64_t elapsed = now_ms() - s_boot_ms;
    if (elapsed < UI_BOOT_SPLASH_MS) {
        vTaskDelay(pdMS_TO_TICKS(UI_BOOT_SPLASH_MS - elapsed));
    }
    taskENTER_CRITICAL(&s_lock);
    s_overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_BOOT;
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();

    BaseType_t created = xTaskCreatePinnedToCore(
        ui_task, "ui", UI_TASK_STACK, NULL, UI_TASK_PRIORITY, &s_task,
        UI_TASK_CORE);
    if (created != pdPASS) {
        s_task = NULL;
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "ui task started (page %d, timeout %u s)", (int)ui_page(),
             (unsigned)timeout_from_config());
    return ESP_OK;
}

/* ---- cross-task API ----------------------------------------------------- */

void ui_mark_dirty(void) {
    atomic_store_explicit(&s_dirty, true, memory_order_release);
    if (atomic_load_explicit(&s_awake, memory_order_acquire) && s_task != NULL) {
        (void)xTaskNotifyGive(s_task);
    }
}

bool ui_dirty_take(void) {
    return atomic_exchange_explicit(&s_dirty, false, memory_order_acq_rel);
}

bool ui_dirty_pending(void) {
    return atomic_load_explicit(&s_dirty, memory_order_acquire);
}

bool ui_display_asleep(void) {
    return !atomic_load_explicit(&s_awake, memory_order_acquire);
}

bool ui_wake(void) {
    uint64_t now = now_ms();
    taskENTER_CRITICAL(&s_lock);
    bool was_asleep = ui_view_wake(&s_view, now);
    taskEXIT_CRITICAL(&s_lock);
    atomic_store(&s_awake, true);
    atomic_store(&s_dirty, true);
    if (was_asleep) {
        atomic_store(&s_wake_requested, true);
    }
    if (s_task != NULL) {
        (void)xTaskNotifyGive(s_task);
    }
    return was_asleep;
}

void ui_display_activity(void) {
    (void)ui_wake();
}

void ui_set_display_timeout(uint16_t timeout_s) {
    if (timeout_s != UI_TIMEOUT_NEVER && timeout_s != UI_TIMEOUT_30S &&
        timeout_s != UI_TIMEOUT_60S && timeout_s != UI_TIMEOUT_120S) {
        return;
    }
    taskENTER_CRITICAL(&s_lock);
    s_view.timeout_s = timeout_s;
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
}

ui_page_t ui_page(void) {
    taskENTER_CRITICAL(&s_lock);
    ui_page_t page = s_view.page;
    taskEXIT_CRITICAL(&s_lock);
    return page;
}

void ui_set_page(ui_page_t page) {
    taskENTER_CRITICAL(&s_lock);
    ui_view_set_page(&s_view, page);
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
}

ui_page_t ui_page_next(void) {
    bridge_state_live_t live;
    bool billows = false;
    if (bridge_state_snapshot(&live) == BRIDGE_STATE_OK) {
        billows = (live.flags & SX4_LIVE_FLAG_BILLOWS_ATTACHED) != 0;
    }
    taskENTER_CRITICAL(&s_lock);
    ui_page_t page = ui_view_next_page(&s_view, billows);
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
    return page;
}

void ui_set_overlay_mask(uint8_t mask) {
    taskENTER_CRITICAL(&s_lock);
    s_overlay_mask = mask;
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
}

void ui_set_passkey(const char *digits) {
    taskENTER_CRITICAL(&s_lock);
    if (digits == NULL) {
        s_passkey[0] = '\0';
        s_overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_PASSKEY;
    } else {
        size_t i = 0;
        for (; i < 6u && digits[i] >= '0' && digits[i] <= '9'; i++) {
            s_passkey[i] = digits[i];
        }
        s_passkey[i] = '\0';
        if (i == 6u) {
            s_overlay_mask |= UI_OVERLAY_MASK_PASSKEY;
        } else {
            s_passkey[0] = '\0';
            s_overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_PASSKEY;
        }
    }
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
}

void ui_set_power_off(uint8_t countdown_s, bool visible) {
    taskENTER_CRITICAL(&s_lock);
    s_power_countdown_s = countdown_s;
    if (visible) {
        s_overlay_mask |= UI_OVERLAY_MASK_POWER_OFF;
    } else {
        s_overlay_mask &= (uint8_t)~UI_OVERLAY_MASK_POWER_OFF;
    }
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
}

void ui_dismiss_storage_failure(void) {
    taskENTER_CRITICAL(&s_lock);
    s_storage_dismissed = true;
    taskEXIT_CRITICAL(&s_lock);
    ui_mark_dirty();
}
