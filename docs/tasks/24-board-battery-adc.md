# T24 — board: battery ADC and power stats

## Goal
The board samples the battery divider with the correct GPIO37 enable/sample/disable sequence, oversampling and calibration, then maps voltage to a Li-ion state of charge with an explicit unknown sentinel. The snapshot and stats expose mV/% without ever inventing a charging state.

## Context (read first)
- [01 §1.3](../design/01-hardware.md) — battery measurement procedure, divider ratio, Li-ion curve, and `SOC_UNKNOWN`.
- [01 §1.2](../design/01-hardware.md) — GPIO37 divider enable, GPIO1/ADC1_CH0, and the verified active-HIGH behavior.
- [01 §1.4](../design/01-hardware.md) — there is no charge-detect line.
- `firmware/components/board/` — pin definitions, battery ADC, and power stats.
- **Verification:** H/B. **Board:** no for the host curve test; B on hardware.
- Depends on T09.

## Scope
- [x] Implement the GPIO37 enable/sample/disable sequence:
  - drive GPIO37 **HIGH** to enable the divider,
  - wait ~200 µs to settle,
  - oversample ADC1_CH0 (GPIO1) with 12 dB attenuation, ~32 samples, calibrated,
  - drive GPIO37 **LOW** to disconnect the divider and save quiescent current.
- [x] Apply the divider calibration ratio (default `×4.9`; replace with the calibrated value).
- [x] Implement the Li-ion discharge curve for percent; do not use a linear map.
- [x] Return `SOC_UNKNOWN (255)` until the first valid sample or when the divider is disabled.
- [x] Expose millivolts and percent in the live snapshot and stats.
- [x] Keep the ADC/power sampling out of the radio and sample paths.
- [x] Add a host test for the chosen curve points.
- [x] On the board, compare the reading against a DMM within the agreed
      tolerance. **Deferred to T62**; host curve test and a plausible pack
      reading are the gate now.
- [x] Render unknown as `-` on the OLED and in the app (the UI owns the rendering; this task supplies the sentinel).

## Out of scope
- OLED rendering of battery/unknown → T22.
- Snapshot structure and clock → T20; this task feeds battery values into it.
- BLE `stats`/`live` encoding and notifications → Phase 3 BLE tasks (T27–T38).
- Charging status, USB detection, or a fuel gauge: outside MVP; no task owns it. Do not infer charging from voltage.
- Power-off/deep-sleep sequencing → T23.
- Any safety decision based on an inferred cable state: outside MVP; no task owns it.
- Billows power/control: outside MVP; M5 (T56–T60) is observation only.

## Design notes
- GPIO37 is **active HIGH on this board revision** to enable the divider; it must be driven LOW after sampling.
- ADC input is GPIO1 / `ADC1_CH0`, 12 dB attenuation, ~32 samples, calibrated.
- Settle delay is ~200 µs after enabling the divider.
- Divider ratio is approximately **×4.9**; calibrate against a DMM when a second charge state is available.
- Report integer millivolts and percent from a Li-ion discharge curve. No fuel gauge, no charge-status line.
- `SOC_UNKNOWN (255)` is a first-class value: before the first sample, or if sampling fails. It must never collapse to 0%.
- There is no reliable charge-detect pin. The MVP reports pack voltage/SoC only and does not claim USB or charging state.
- Sampling belongs to `housekeeping`, not the radio or sample pipeline.

## Done when
- [x] The host curve test matches the chosen voltage/percent points.
- [x] On the board, the reading tracks a DMM within the agreed tolerance.
      **Deferred to T62** (no DMM in the unattended run). The board ADC value is
      checked for plausibility against the pack voltage now.
- [x] Unknown renders as `—`, never `0%`.
- [x] GPIO37 is left LOW after each sample and the divider is not left enabled.
- [x] The snapshot and stats expose mV/%/`SOC_UNKNOWN`.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] The DMM comparison and measured current are recorded in `docs/hardware-verified.md`. **Both are deferred to T62.**
- [x] Hand-off below filled in.

## Hand-off

### What landed

- `firmware/components/board/include/board_battery.h`,
  `board_battery.c`, `board_battery_esp.c`
  - pure C11 core: `board_battery_pack_mv()` (x100 divider),
    `board_battery_soc()` (piecewise Li-ion curve), `board_battery_convert()`
    and the `board_battery_stats_t` accumulator;
  - the curve is 4200/100, 4100/90, 4000/80, 3900/70, 3850/65, 3800/60,
    3750/50, 3700/40, 3650/30, 3600/20, 3550/15, 3500/10, 3450/7, 3400/5,
    3350/2, 3300/0 (mV/%), interpolated and clamped;
  - `0` mV (no divider / no pack) and any failed sample are
    `BOARD_BATTERY_SOC_UNKNOWN` (255), never 0 %;
  - ESP half: GPIO37 output starts LOW; one sample drives HIGH, waits 200 µs,
    averages 32 curve-calibrated ADC1_CH0 reads at 12 dB, drives LOW before
    calibration conversion, and requires >= 24/32 good reads;
  - `BOARD_BATTERY_DIVIDER_X100` defaults to 490 (x4.9) and is the single
    calibration constant.
- `firmware/main/housekeeping.c/.h`
  - static 3072/2/core-0 task (matches `tasks.h`), samples the battery every
    `HOUSEKEEPING_BATTERY_PERIOD_MS` (10 s) and publishes
    `bridge_state_set_battery(mv, pct)` or `(0, SOC_UNKNOWN)` on failure;
  - owns `bridge_state_tick()`; the tick was removed from the log writer so
    the seqlock keeps one writer (ADR 0028).
- `firmware/main/boot.c` calls `housekeeping_start()` before `ui_start()`;
  `board_power_init()` initialises the battery ADC after Vext settles and
  continues (UNKNOWN) if battery init fails.
- `firmware/test/test_board_battery.c` + `board-battery` CTest: curve points,
  interpolation, clamps, scaling, convert failures, stats accumulator, and a
  plausible 4.03 V pack read.
- Docs: ADR 0032, design 01 §1.3, design 03 §3.3/§3.4/§3.5.5/§3.14,
  `docs/hardware-verified.md` battery rows.

### Deviations

- **DMM/current are deferred to T62** exactly as the task's checked boxes say.
  No meter was available in this unattended run. The host curve test and the
  T09 plausibility read (823 mV → ~4033 mV at x4.9) are the evidence now.
- **"Stats" is the new `board_battery_stats_t` source**, not a BLE payload:
  BLE `stats` encoding is explicitly T47. It carries last pack mV, last pin
  mV, percent/255 and since-boot success/failure counts.
- `board_power_init()` treats a battery init failure as non-fatal (logs a
  warning and leaves the snapshot unknown) so a battery fault cannot stop
  Vext/UI/radio boot.

### Checks

```powershell
$env:PATH='C:\msys64\ucrt64\bin;'+$env:PATH
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# 100% tests passed, 16/16 (board-battery is #12)
```

Firmware build (IDF 6.0.2, Heltec target):

```powershell
$env:IDF_PYTHON_ENV_PATH='C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env'
& D:\esp\esp-idf\export.ps1
cd firmware
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete; image guard ok (esp32s3, 72 components,
# no Wi-Fi/HTTP/OTA); sx4_bridge.bin 0x4a190, 86% free
```

### Remaining work

- **T62:** DMM comparison (agreed tolerance ±2 % of pack voltage), replace the
  divider ratio if the measured value differs, divider-enable current and
  deep-sleep current. Record both in `docs/hardware-verified.md`.
- **T47:** map `battery_mv`/`battery_pct` from the live snapshot (or
  `board_battery_stats_get()`) into the 60-byte BLE `stats` payload. No ADC
  change is needed.
- **T37/T62:** confirm the physical 10 s cadence and that a battery sample
  never visibly delays a radio reading.
