/* app_lora_core — params, scanner schedule, TX guard (F2). */
#include "app_lora_core.h"

static const app_lora_params_t k_params = {
    .spreading_factor = 9,
    .bandwidth_index = 4, /* 125 kHz, as an index */
    .coding_rate = 1,     /* 4/5 */
    .preamble_len = 10,
    .sync_word = 0x12,
    .crc_on = true,
    .tx_power_dbm = 22,
    .tcxo_volts = 3.3f,
    .use_ldo = true,
};

const app_lora_params_t *app_lora_params(void) { return &k_params; }

uint32_t app_lora_scan_freq_at(uint64_t now_ms, uint64_t scan_started_ms) {
    const uint64_t elapsed = now_ms - scan_started_ms;
    const uint64_t slot = elapsed / APP_LORA_SCAN_DWELL_MS;
    return (slot % 2 == 0) ? APP_LORA_SCAN_FREQ_X4 : APP_LORA_SCAN_FREQ_X2;
}

static bool s_sync_window_open;

void app_lora_guard_reset(void) { s_sync_window_open = false; }

void app_lora_guard_open_sync_window(void) { s_sync_window_open = true; }

void app_lora_guard_close_sync_window(void) { s_sync_window_open = false; }

bool app_lora_guard_tx_allowed(uint32_t freq_hz) {
    if (!s_sync_window_open) {
        return false;
    }
    return freq_hz >= APP_LORA_RF_MIN_HZ && freq_hz <= APP_LORA_RF_MAX_HZ;
}
