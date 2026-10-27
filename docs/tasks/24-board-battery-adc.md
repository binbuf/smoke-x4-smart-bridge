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
- [ ] Implement the GPIO37 enable/sample/disable sequence:
  - drive GPIO37 **HIGH** to enable the divider,
  - wait ~200 µs to settle,
  - oversample ADC1_CH0 (GPIO1) with 12 dB attenuation, ~32 samples, calibrated,
  - drive GPIO37 **LOW** to disconnect the divider and save quiescent current.
- [ ] Apply the divider calibration ratio (default `×4.9`; replace with the calibrated value).
- [ ] Implement the Li-ion discharge curve for percent; do not use a linear map.
- [ ] Return `SOC_UNKNOWN (255)` until the first valid sample or when the divider is disabled.
- [ ] Expose millivolts and percent in the live snapshot and stats.
- [ ] Keep the ADC/power sampling out of the radio and sample paths.
- [ ] Add a host test for the chosen curve points.
- [ ] On the board, compare the reading against a DMM within the agreed tolerance.
- [ ] Render unknown as `—` on the OLED and in the app (the UI owns the rendering; this task supplies the sentinel).

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
- [ ] The host curve test matches the chosen voltage/percent points.
- [ ] On the board, the reading tracks a DMM within the agreed tolerance.
- [ ] Unknown renders as `—`, never `0%`.
- [ ] GPIO37 is left LOW after each sample and the divider is not left enabled.
- [ ] The snapshot and stats expose mV/%/`SOC_UNKNOWN`.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] The DMM comparison and measured current are recorded in `docs/hardware-verified.md`.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
