/*
 * test_board_battery.c - host coverage for the divider curve and power stats
 * (T24, design 01 section 1.3).
 *
 * The pure core is checked without an ADC: exact curve points, interpolation
 * between them, the clamps, the unknown sentinel and the stats accumulator.
 * The board ADC/calibration half is verified on hardware (T62 DMM row).
 */
#include <stdbool.h>
#include <stdint.h>

#include "board_battery.h"
#include "test_util.h"

static void test_sampling_contract(void) {
    CHECK_EQ_UINT(BOARD_BATTERY_SOC_UNKNOWN, 255u);
    CHECK_EQ_UINT(BOARD_BATTERY_DIVIDER_X100, 490u);
    CHECK_EQ_UINT(BOARD_BATTERY_ADC_SAMPLES, 32u);
    CHECK_EQ_UINT(BOARD_BATTERY_SETTLE_US, 200u);
}

/* The chosen Li-ion discharge points, high to low. A linear 3.3-4.2 V map
 * would put 3.75 V at ~50 %, but the flat middle is deliberately curved. */
static void test_curve_points(void) {
    static const struct {
        uint16_t mv;
        uint8_t pct;
    } points[] = {
        {4200u, 100u}, {4100u, 90u}, {4000u, 80u}, {3900u, 70u},
        {3850u, 65u},  {3800u, 60u}, {3750u, 50u}, {3700u, 40u},
        {3650u, 30u},  {3600u, 20u}, {3550u, 15u}, {3500u, 10u},
        {3450u, 7u},   {3400u, 5u},  {3350u, 2u},  {3300u, 0u},
    };
    for (size_t i = 0; i < sizeof(points) / sizeof(points[0]); i++) {
        CHECK_EQ_UINT(board_battery_soc(points[i].mv), points[i].pct);
    }
}

static void test_curve_interpolates_between_points(void) {
    CHECK_EQ_UINT(board_battery_soc(4150u), 95u); /* 4200/100, 4100/90 */
    CHECK_EQ_UINT(board_battery_soc(3950u), 75u); /* 4000/80, 3900/70 */
    CHECK_EQ_UINT(board_battery_soc(3825u), 63u); /* 3850/65, 3800/60 */
    CHECK_EQ_UINT(board_battery_soc(3725u), 45u); /* 3750/50, 3700/40 */
    CHECK_EQ_UINT(board_battery_soc(3575u), 18u); /* 3600/20, 3550/15 */
    CHECK_EQ_UINT(board_battery_soc(3475u), 9u);  /* 3500/10, 3450/7 */
    CHECK_EQ_UINT(board_battery_soc(3375u), 4u);  /* 3400/5, 3350/2 */
}

static void test_curve_clamps_and_unknown(void) {
    CHECK_EQ_UINT(board_battery_soc(4300u), 100u);
    CHECK_EQ_UINT(board_battery_soc(5000u), 100u);
    CHECK_EQ_UINT(board_battery_soc(3300u), 0u);
    CHECK_EQ_UINT(board_battery_soc(3000u), 0u);
    CHECK_EQ_UINT(board_battery_soc(100u), 0u);
    /* 0 mV is not a 0 % reading: it is no reading at all. */
    CHECK_EQ_UINT(board_battery_soc(0u), BOARD_BATTERY_SOC_UNKNOWN);
}

static void test_divider_scaling(void) {
    CHECK_EQ_UINT(board_battery_pack_mv(800u, 490u), 3920u);
    CHECK_EQ_UINT(board_battery_pack_mv(1000u, 490u), 4900u);
    CHECK_EQ_UINT(board_battery_pack_mv(823u, 490u), 4033u);
    CHECK_EQ_UINT(board_battery_pack_mv(820u, 500u), 4100u);
    CHECK_EQ_UINT(board_battery_pack_mv(820u, 100u), 820u);
    CHECK_EQ_UINT(board_battery_pack_mv(800u, 0u), 0u);
}

static void test_convert(void) {
    board_battery_reading_t r =
        board_battery_convert(800u, true, BOARD_BATTERY_DIVIDER_X100);
    CHECK(r.valid);
    CHECK_EQ_UINT(r.adc_mv, 800u);
    CHECK_EQ_UINT(r.pack_mv, 3920u);
    CHECK_EQ_UINT(r.percent, 72u);

    r = board_battery_convert(800u, false, BOARD_BATTERY_DIVIDER_X100);
    CHECK(!r.valid);
    CHECK_EQ_UINT(r.pack_mv, 0u);
    CHECK_EQ_UINT(r.percent, BOARD_BATTERY_SOC_UNKNOWN);

    /* A disconnected divider / absent pack reads 0 mV, not 0 %. */
    r = board_battery_convert(0u, true, BOARD_BATTERY_DIVIDER_X100);
    CHECK(!r.valid);
    CHECK_EQ_UINT(r.percent, BOARD_BATTERY_SOC_UNKNOWN);
}

static void test_stats_accumulate(void) {
    board_battery_stats_t stats;
    board_battery_stats_reset(&stats);
    CHECK(!stats.valid);
    CHECK_EQ_UINT(stats.percent, BOARD_BATTERY_SOC_UNKNOWN);
    CHECK_EQ_UINT(stats.millivolts, 0u);
    CHECK_EQ_UINT(stats.samples, 0u);
    CHECK_EQ_UINT(stats.failures, 0u);

    board_battery_reading_t good =
        board_battery_convert(800u, true, BOARD_BATTERY_DIVIDER_X100);
    board_battery_stats_apply(&stats, &good);
    CHECK(stats.valid);
    CHECK_EQ_UINT(stats.millivolts, 3920u);
    CHECK_EQ_UINT(stats.adc_millivolts, 800u);
    CHECK_EQ_UINT(stats.percent, 72u);
    CHECK_EQ_UINT(stats.samples, 1u);
    CHECK_EQ_UINT(stats.failures, 0u);

    /* A failed sample makes the published value unknown again. */
    board_battery_reading_t bad = board_battery_convert(0u, false, 490u);
    board_battery_stats_apply(&stats, &bad);
    CHECK(!stats.valid);
    CHECK_EQ_UINT(stats.millivolts, 0u);
    CHECK_EQ_UINT(stats.adc_millivolts, 0u);
    CHECK_EQ_UINT(stats.percent, BOARD_BATTERY_SOC_UNKNOWN);
    CHECK_EQ_UINT(stats.samples, 1u);
    CHECK_EQ_UINT(stats.failures, 1u);

    board_battery_stats_apply(&stats, &good);
    CHECK(stats.valid);
    CHECK_EQ_UINT(stats.samples, 2u);
    CHECK_EQ_UINT(stats.failures, 1u);
}

/* A 4.03 V pack on the default divider publishes a real percent, not unknown. */
static void test_plausible_pack_reading(void) {
    board_battery_reading_t r =
        board_battery_convert(823u, true, BOARD_BATTERY_DIVIDER_X100);
    CHECK(r.valid);
    CHECK(r.pack_mv >= 3900u && r.pack_mv <= 4100u);
    CHECK(r.percent >= 80u && r.percent <= 90u);
}

int main(void) {
    test_sampling_contract();
    test_curve_points();
    test_curve_interpolates_between_points();
    test_curve_clamps_and_unknown();
    test_divider_scaling();
    test_convert();
    test_stats_accumulate();
    test_plausible_pack_reading();
    return sx4_test_summary("board-battery");
}
