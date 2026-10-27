/*
 * board_battery.h - battery divider sampling and Li-ion state of charge (T24).
 *
 * The pure-C half (this header + board_battery.c) owns the divider scaling,
 * the Li-ion discharge curve and the power-stats accumulator. It has no
 * ESP-IDF dependency and is exercised by firmware/test/test_board_battery.c.
 * board_battery_esp.c is the only part that touches GPIO37, the ADC and the
 * calibration scheme.
 *
 * Measurement procedure (design 01 section 1.3):
 *   GPIO37 HIGH -> ~200 us settle -> 32 calibrated ADC1_CH0 samples ->
 *   GPIO37 LOW. The divider is never left enabled.
 *
 * There is no fuel gauge and no charge-detect line. Percent is an estimate
 * from pack voltage; charging state is deliberately not reported.
 */
#ifndef SX4_BOARD_BATTERY_H
#define SX4_BOARD_BATTERY_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* First-class unknown sentinel shared with the BLE `live`/`stats` payloads. */
#define BOARD_BATTERY_SOC_UNKNOWN 255u

/*
 * Divider calibration, expressed as pack_mv = adc_mv * X100 / 100.
 * The board measures approximately x4.9 with the default divider. T62 owns
 * the DMM calibration; a measured ratio replaces this value (or is passed as
 * an override at build time with -DBOARD_BATTERY_DIVIDER_X100=...).
 */
#ifndef BOARD_BATTERY_DIVIDER_X100
#define BOARD_BATTERY_DIVIDER_X100 490u
#endif

/* Sampling contract. */
#define BOARD_BATTERY_ADC_SAMPLES 32u
#define BOARD_BATTERY_SETTLE_US 200u

/* A calibrated 0 mV read (divider disconnected, no pack) is not a reading. */
#define BOARD_BATTERY_MV_INVALID 0u

typedef struct {
    uint16_t adc_mv;   /* calibrated voltage at GPIO1/ADC1_CH0 */
    uint16_t pack_mv;  /* adc_mv scaled by the divider ratio */
    uint8_t percent;   /* 0..100, or BOARD_BATTERY_SOC_UNKNOWN */
    bool valid;        /* false: no usable sample; percent is UNKNOWN */
} board_battery_reading_t;

/*
 * Power stats for the housekeeping loop and the later BLE `stats` encoder.
 * `millivolts`/`percent` describe the last sample; when `valid` is false the
 * percent is the unknown sentinel, never 0.
 */
typedef struct {
    uint16_t millivolts;     /* last valid pack voltage; 0 when unknown */
    uint16_t adc_millivolts; /* last calibrated divider voltage */
    uint8_t percent;         /* 0..100 or BOARD_BATTERY_SOC_UNKNOWN */
    uint32_t samples;        /* successful samples since reset */
    uint32_t failures;       /* failed samples since reset */
    bool valid;
} board_battery_stats_t;

/* Scale one calibrated divider voltage by the divider ratio. */
uint16_t board_battery_pack_mv(uint16_t adc_mv, uint16_t divider_x100);

/*
 * Li-ion discharge curve, not a linear map. Returns 0..100 for a valid pack
 * voltage, clamped at the curve ends (4200 mV = 100 %, 3300 mV = 0 %), and
 * BOARD_BATTERY_SOC_UNKNOWN for pack_mv == 0.
 */
uint8_t board_battery_soc(uint16_t pack_mv);

/* Build one reading. `adc_ok == false` or a 0 mV pack yields UNKNOWN. */
board_battery_reading_t board_battery_convert(uint16_t adc_mv, bool adc_ok,
                                              uint16_t divider_x100);

/* Reset to "no sample yet": 0 mV and BOARD_BATTERY_SOC_UNKNOWN. */
void board_battery_stats_reset(board_battery_stats_t *stats);

/* Apply one reading: counters advance; a failed sample clears valid/percent. */
void board_battery_stats_apply(board_battery_stats_t *stats,
                               const board_battery_reading_t *reading);

#ifdef ESP_PLATFORM
#include "esp_err.h"

/* Configure GPIO37 LOW and the calibrated ADC1_CH0 oneshot unit. */
esp_err_t board_battery_init(void);

/* One enable/settle/oversample/disable cycle. Never leaves the divider on. */
board_battery_reading_t board_battery_sample(void);

/* Copy of the last sample and the since-boot counters. */
board_battery_stats_t board_battery_stats_get(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_BOARD_BATTERY_H */
