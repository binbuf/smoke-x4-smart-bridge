/*
 * housekeeping.c - battery ADC sampling and clock persistence (T24).
 *
 * The task samples the pack every HOUSEKEEPING_BATTERY_PERIOD_MS and publishes
 * millivolts/percent (or the SOC_UNKNOWN sentinel) into the live snapshot. It
 * also owns the production bridge_state_tick() cadence; that call only writes
 * NVS when the ten-minute anchor is due.
 */
#include "housekeeping.h"

#include <stdbool.h>
#include <stdint.h>

#include "board.h"
#include "bridge_state.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "ui.h"

/* Mirrors the housekeeping row in firmware/main/tasks.h. */
#define HOUSEKEEPING_TASK_STACK_BYTES 3072u
#define HOUSEKEEPING_TASK_PRIORITY 2u
#define HOUSEKEEPING_TASK_CORE 0

static const char *TAG = "sx4.house";

static bool s_started;

static uint64_t now_ms(void) {
    return (uint64_t)(esp_timer_get_time() / 1000);
}

static void publish_battery(void) {
    board_battery_stats_t stats = board_battery_stats_get();
    if (stats.valid) {
        bridge_state_set_battery(stats.millivolts, stats.percent);
    } else {
        /* Never collapse a failed sample to 0 %: the UI/app render unknown. */
        bridge_state_set_battery(0u, BRIDGE_STATE_SOC_UNKNOWN);
    }
    /* Cheap when the panel is asleep; the renderer only flushes on a diff. */
    ui_mark_dirty();
}

static void housekeeping_task(void *argument) {
    (void)argument;
    ESP_LOGI(TAG, "housekeeping started: battery every %u ms",
             (unsigned)HOUSEKEEPING_BATTERY_PERIOD_MS);
    uint64_t next_battery_ms = 0u;

    for (;;) {
        uint64_t now = now_ms();
        if (now >= next_battery_ms) {
            board_battery_reading_t reading = board_battery_sample();
            publish_battery();
            if (reading.valid) {
                ESP_LOGI(TAG, "battery %u mV (%u%%)",
                         (unsigned)reading.pack_mv, (unsigned)reading.percent);
            }
            next_battery_ms = now + HOUSEKEEPING_BATTERY_PERIOD_MS;
        }

        (void)bridge_state_tick();
        vTaskDelay(pdMS_TO_TICKS(HOUSEKEEPING_TICK_MS));
    }
}

esp_err_t housekeeping_start(void) {
    if (s_started) {
        return ESP_OK;
    }
    BaseType_t created = xTaskCreatePinnedToCore(
        housekeeping_task, "housekeeping", HOUSEKEEPING_TASK_STACK_BYTES, NULL,
        HOUSEKEEPING_TASK_PRIORITY, NULL, HOUSEKEEPING_TASK_CORE);
    if (created != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    s_started = true;
    return ESP_OK;
}
