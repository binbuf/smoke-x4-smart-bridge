/*
 * board_battery.c - pure divider scaling, Li-ion curve and power stats (T24).
 *
 * Plain C11: no ESP-IDF headers, no heap. Host tests exercise exactly these
 * functions; the firmware adapter adds the GPIO/ADC/calibration half in
 * board_battery_esp.c.
 *
 * The curve is a piecewise-linear approximation of a Li-ion discharge at a
 * light load, with more points in the flat 3.6-3.9 V region where a linear map
 * would be most wrong. It is an estimate, not a fuel gauge. Charging state is
 * never inferred.
 */
#include "board_battery.h"

#include <stddef.h>

typedef struct {
    uint16_t millivolts;
    uint8_t percent;
} soc_point_t;

/* Descending pack voltage. 4200 mV = full, 3300 mV = empty. */
static const soc_point_t s_curve[] = {
    {4200u, 100u}, {4100u, 90u}, {4000u, 80u}, {3900u, 70u},
    {3850u, 65u},  {3800u, 60u}, {3750u, 50u}, {3700u, 40u},
    {3650u, 30u},  {3600u, 20u}, {3550u, 15u}, {3500u, 10u},
    {3450u, 7u},   {3400u, 5u},  {3350u, 2u},  {3300u, 0u},
};

#define CURVE_POINTS (sizeof(s_curve) / sizeof(s_curve[0]))

uint16_t board_battery_pack_mv(uint16_t adc_mv, uint16_t divider_x100) {
    uint32_t scaled = (uint32_t)adc_mv * (uint32_t)divider_x100;
    uint32_t mv = (scaled + 50u) / 100u; /* nearest millivolt */
    return mv > UINT16_MAX ? UINT16_MAX : (uint16_t)mv;
}

uint8_t board_battery_soc(uint16_t pack_mv) {
    if (pack_mv == BOARD_BATTERY_MV_INVALID) {
        return BOARD_BATTERY_SOC_UNKNOWN;
    }

    const soc_point_t *high = &s_curve[0];
    if (pack_mv >= high->millivolts) {
        return high->percent;
    }
    const soc_point_t *low = &s_curve[CURVE_POINTS - 1u];
    if (pack_mv <= low->millivolts) {
        return low->percent;
    }

    for (size_t i = 0; i + 1u < CURVE_POINTS; i++) {
        high = &s_curve[i];
        low = &s_curve[i + 1u];
        if (pack_mv <= high->millivolts && pack_mv >= low->millivolts) {
            uint32_t span_mv = (uint32_t)high->millivolts - low->millivolts;
            uint32_t above_mv = (uint32_t)pack_mv - low->millivolts;
            uint32_t span_pct = (uint32_t)high->percent - low->percent;
            /* Both ends are on the same monotonic segment, so low.percent is
             * the smaller value. Round to the nearest percent. */
            uint32_t delta = (above_mv * span_pct + span_mv / 2u) / span_mv;
            return (uint8_t)(low->percent + delta);
        }
    }

    /* Unreachable for a monotonic table; keep the value first-class. */
    return BOARD_BATTERY_SOC_UNKNOWN;
}

board_battery_reading_t board_battery_convert(uint16_t adc_mv, bool adc_ok,
                                              uint16_t divider_x100) {
    board_battery_reading_t reading = {
        .adc_mv = 0u,
        .pack_mv = 0u,
        .percent = BOARD_BATTERY_SOC_UNKNOWN,
        .valid = false,
    };
    if (!adc_ok) {
        return reading;
    }

    uint16_t pack_mv = board_battery_pack_mv(adc_mv, divider_x100);
    if (pack_mv == BOARD_BATTERY_MV_INVALID) {
        return reading;
    }

    reading.adc_mv = adc_mv;
    reading.pack_mv = pack_mv;
    reading.percent = board_battery_soc(pack_mv);
    reading.valid = true;
    return reading;
}

void board_battery_stats_reset(board_battery_stats_t *stats) {
    if (stats == NULL) {
        return;
    }
    *stats = (board_battery_stats_t){
        .millivolts = 0u,
        .adc_millivolts = 0u,
        .percent = BOARD_BATTERY_SOC_UNKNOWN,
        .samples = 0u,
        .failures = 0u,
        .valid = false,
    };
}

void board_battery_stats_apply(board_battery_stats_t *stats,
                               const board_battery_reading_t *reading) {
    if (stats == NULL) {
        return;
    }
    if (reading == NULL || !reading->valid) {
        stats->millivolts = 0u;
        stats->adc_millivolts = 0u;
        stats->percent = BOARD_BATTERY_SOC_UNKNOWN;
        stats->valid = false;
        stats->failures++;
        return;
    }

    stats->millivolts = reading->pack_mv;
    stats->adc_millivolts = reading->adc_mv;
    stats->percent = reading->percent;
    stats->valid = true;
    stats->samples++;
}
