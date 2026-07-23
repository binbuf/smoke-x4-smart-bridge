/* app_lora_core — radio parameters, the unpaired frequency scanner, and
 * the TX guard (F2.2, F2.3, F2.5; design 01 §1.5, 02 §2.4–2.5).
 *
 * Pure C11: the schedule and the guard are the parts worth testing, so
 * they live outside the driver glue.
 */
#ifndef APP_LORA_CORE_H
#define APP_LORA_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The §1.5 table, inherited from the reference verbatim. The bandwidth is
 * an INDEX (4 = 125 kHz) — the SX126x driver takes indices, not Hz, unlike
 * the SX1276 path; passing 125000 here would silently misconfigure. */
typedef struct {
    uint8_t spreading_factor; /* 9 */
    uint8_t bandwidth_index;  /* 4 = 125 kHz */
    uint8_t coding_rate;      /* 1 = 4/5 */
    uint16_t preamble_len;    /* 10 symbols */
    uint8_t sync_word;        /* 0x12, private network */
    bool crc_on;
    int8_t tx_power_dbm; /* 22 — only ever used for the pairing ACK */
    float tcxo_volts;    /* 3.3, LDO regulator */
    bool use_ldo;
} app_lora_params_t;

const app_lora_params_t *app_lora_params(void);

/* ── Unpaired scanner (F2.5) ──
 * Alternate the two sync channels every 3.3 s while the base beacons every
 * 3 s — deliberately offset so the two never lock into a beat pattern that
 * starves one channel (02 §2.4). */
#define APP_LORA_SCAN_DWELL_MS 3300u
#define APP_LORA_SCAN_FREQ_X4 915000000u /* X4 syncs here */
#define APP_LORA_SCAN_FREQ_X2 920000000u /* X2 syncs here */

uint32_t app_lora_scan_freq_at(uint64_t now_ms, uint64_t scan_started_ms);

/* ── TX guard (F2.3, 02 §2.5 invariant 1) ──
 * The bridge transmits exactly one packet per pairing: the sync ACK. The
 * window is open only inside the sync handler's transmit op; any other
 * call path reaching TX is refused, as is any out-of-band frequency. */
#define APP_LORA_RF_MIN_HZ 902000000u
#define APP_LORA_RF_MAX_HZ 928000000u

void app_lora_guard_reset(void);
void app_lora_guard_open_sync_window(void);
void app_lora_guard_close_sync_window(void);
/* True only when the window is open AND the frequency is in band. */
bool app_lora_guard_tx_allowed(uint32_t freq_hz);

#ifdef __cplusplus
}
#endif

#endif /* APP_LORA_CORE_H */
