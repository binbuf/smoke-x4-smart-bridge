# T09 — Board identity, bench rig, and deep-sleep gate

## Goal
Confirm on the bench that the board is the expected Heltec V3 and answer the
GPIO0/hold-PRG deep-sleep wake question with recorded evidence. The result
unblocks all firmware power work and the real-capture tasks.

## Context (read first)
- Design: [01 §1.4, §1.9](../design/01-hardware.md),
  [07 §7.7](../design/07-display-and-controls.md)
- Verification: **B** (bench/board) · Board required: **yes**
- Depends on T04.
- This answers open decision Q1 (exact board is Heltec V3) and Q3 (GPIO0
  deep-sleep wake works) from [README](README.md#open-decisions-that-block-tasks).
- Bench sitting, one session; board time is serialized, so batch with other
  board tasks where possible.

## Scope
One bench sitting:

- [ ] Confirm the board is the Heltec WiFi LoRa 32 V3, 8 MB flash, SX1262,
      SSD1306.
- [ ] Fit the antenna; verify Vext/OLED, PRG, battery divider.
- [ ] Flash a **bare BLE advertising + deep-sleep test image** (an IDF example,
      not the product service) and confirm advertising, then sleep.
- [ ] Test hold-PRG wake 20 times with USB attached and detached.
- [ ] Measure on/advertising/sleep current; run the pack for 24 h if time
      allows.
- [ ] Record every result in `docs/hardware-verified.md`.

## Out of scope
- Building the product BLE service or firmware features — M1/M2.
- The power decision record and fallback selection — owned by T11.
- Real X4 traffic capture — owned by T10.
- Deep-sleep/power feature implementation — M1/M4, gated on T11.
- Wi-Fi/HTTP/OTA test images as product code — no task; outside MVP (the IDF
  example is a bench probe only).

## Design notes
- The test image is an **IDF example**: bare BLE advertising plus deep sleep,
  explicitly not the product service. Do not let it become product code.
- Test with the antenna fitted; verify Vext/OLED, PRG, and the battery divider
  as part of the same sitting.
- Hold-PRG wake is tested 20 times in each condition: USB attached and USB
  detached. Record successes/failures, not just a verdict.
- Measure current in three states: on, advertising, sleep. The 24 h pack run is
  time-permitting but should be attempted.
- Every result goes in `docs/hardware-verified.md` — no verbal-only findings.
- If wake enters ROM download, record the fallback decision **before** any
  power-feature work; T11 writes the formal decision.
- GPIO0 wake behaviour is Q3; board identity is Q1. Do not silently pick an
  alternative board or wake mechanism.

## Done when
- [ ] The board identity is written down in `docs/hardware-verified.md`.
- [ ] The GPIO0 wake answer is written down in `docs/hardware-verified.md`.
- [ ] If wake enters ROM download, the fallback decision is recorded before any
      power-feature work.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
