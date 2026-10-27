# ADR 0032 — Battery sampling is a housekeeping seam over a pure Li-ion curve

**Status:** accepted (T24, 2026-10-26)

## Context

The board has no fuel gauge and no charge-detect line. The only battery input
is the GPIO37-gated divider on GPIO1/ADC1_CH0. The MCU must report integer
pack millivolts and an estimated percent without ever inventing a charging
state or collapsing "unknown" to 0 %. The sampling must not sit on the radio or
sample pipeline, where a ~3 ms analog read would delay a reading.

Design 01 §1.3 fixes the electrical procedure (GPIO37 HIGH, ~200 µs settle,
~32 calibrated samples at 12 dB, GPIO37 LOW, ratio ≈ ×4.9) but leaves the
software boundary open.

## Decision

1. **Pure core, thin adapter.** `board_battery.c` owns divider scaling, the
   piecewise-linear Li-ion curve and the power-stats accumulator as plain C11.
   `board_battery_esp.c` owns GPIO37, the oneshot ADC and the curve-fitting
   calibration. Host tests link only the pure core.
2. **One explicit sentinel.** `BOARD_BATTERY_SOC_UNKNOWN = 255` is used before
   the first valid sample, after a failed sample, and for a 0 mV divider read.
   `0` is a legitimate percent and is never used as "unknown".
3. **The curve is a table, not a formula.** Points run from 4200 mV/100 % to
   3300 mV/0 % with extra points through the flat 3.55–3.90 V region; values
   between points interpolate and the ends clamp. `BOARD_BATTERY_DIVIDER_X100`
   is the single calibration constant (default 490 = ×4.9).
4. **The divider is never left on.** Every sample path drives GPIO37 LOW after
   the reads, including a failed ADC read, before calibration conversion.
5. **Housekeeping owns the cadence.** A dedicated `housekeeping` task samples
   every 10 s, publishes `bridge_state_set_battery(mv, pct_or_unknown)` and
   calls `bridge_state_tick()`. `radio_rx`, `sample_pipe` and `log_writer` do
   not sample the battery. A failed sample publishes 0 mV/UNKNOWN, not stale
   or 0 %.
6. **Stats are a first-class source.** `board_battery_stats_t` exposes last
   millivolts, percent, divider millivolts and since-boot success/failure
   counts. The later BLE `stats` encoder reads the live snapshot; it does not
   need a second ADC path.

## Consequences

- Host tests can pin exact curve points and interpolation without an ADC; the
  board test (T62) only needs to compare the reported millivolts against a DMM
  and record the divider-on current.
- T62 replaces the calibration constant and records the DMM tolerance
  (±2 % of pack voltage) and the divider-enable current; no API change.
- The UI/app render 255 as `—`; 0 % remains a real empty-pack value.
- Charging/USB state stays unknowable. No task may infer it from voltage.
- A battery-init failure degrades to permanent UNKNOWN while Vext, the UI and
  the radio continue to boot.
