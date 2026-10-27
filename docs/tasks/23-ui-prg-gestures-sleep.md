# T23 — ui: PRG gestures and deep sleep

## Goal
One GPIO0 button provides the complete MVP control surface: tap to advance pages, hold to power off with a cancel-on-release countdown, and hold-to-wake with a boot confirmation. Deep sleep turns off Vext, sleeps the SX1262, and drops BLE, with no hidden menu or on-device reset gesture.

## Context (read first)
- [07 §7.4](../design/07-display-and-controls.md) — button gestures, dialog selection, the gesture state machine, and deep-sleep wake.
- [07 §7.5](../design/07-display-and-controls.md) — display-state priority.
- [01 §1.4](../design/01-hardware.md) — on/off semantics, GPIO0 wake risk, and the 20/20 bench gate.
- [03 §3.10](../design/03-firmware-architecture.md) — UI task timing, display timeout, and power-off behavior.
- `firmware/components/ui/` — button scan, gesture state machine, and power path.
- **Verification:** H/B. **Board:** no for unit tests; B on hardware.
- Depends on T22 and T10.

## Scope
- [ ] Implement button sampling at **20 ms** with a **30 ms** debounce.
- [ ] Implement the tap/hold state machine:
  - press < 400 ms → tap → next page,
  - hold ≥ 1.5 s → power off,
  - countdown from ~400 ms; commit on **release**.
- [ ] A waking press is consumed: it wakes the display but does not also change the page.
- [ ] A tap during the power-off countdown does nothing; only releasing cancels.
- [ ] Releasing before the threshold cancels; releasing at/after 1.5 s commits.
- [ ] On commit: show `OFF` for ~300 ms, turn Vext off, sleep the SX1262, bring BLE down, enter deep sleep with GPIO0 as the wake source.
- [ ] Implement hold-to-wake: after reset, confirm the button is still held for ~1.5 s; an early release returns to sleep without starting BLE or the UI.
- [ ] Add unit tests for tap/hold/cancel and the boot confirmation.
- [ ] On the board, run 20/20 wake cycles with USB attached and detached.

## Out of scope
- Page rendering, overlays, and display timeout → T22.
- Battery measurement → T24.
- BLE-initiated `power_off` and connection teardown → Phase 3 BLE tasks (T27–T38); this task owns the local button path.
- App-driven factory reset, clear history, or any on-device reset gesture → M4 settings (T47–T55).
- A boot-time menu, button sequence, double-tap, or long-press ladder: outside MVP; no task owns it. The hold-to-wake confirmation is the only boot-time hold.
- Fallback hardware for the GPIO0 strap risk (RST wake or external latch) only if the 20/20 gate fails; that decision is a hardware escalation, not silent scope.
- Wi-Fi/HTTP/OTA: outside MVP; no task owns it.

## Design notes
- GPIO0 is active LOW and is a strapping pin. Read it as a user button only after boot; never treat a held button during a cold reset as an application command.
- Timing from [07 §7.4](../design/07-display-and-controls.md): sample 20 ms, debounce 30 ms, tap < 400 ms, hold ≥ 1.5 s, countdown starts ~400 ms.
- Gesture states: `IDLE → PRESSED → TAP` or `PRESSED → HOLD_CONFIRM → POWER OFF`; release below 1.5 s cancels.
- The input layer is modelled as `NEXT` (tap) and `SELECT` (hold), even though there is one button. The MVP has no multi-option menu.
- Display priority on power-off: power-off confirmation is above storage failure and the boot splash; passkey and reset/clear progress are above it.
- Power-off UI: `POWER OFF`, `keep holding N`, then `release to confirm`; `OFF` for ~300 ms before sleep.
- Deep sleep means Vext off, SX1262 asleep, BLE controller/host down, CPU in deep sleep, GPIO0 wake. "Off" is not zero current.
- Boot hold: the confirmation runs before BLE/UI start. An early release returns to sleep; it does not boot to a page.
- The GPIO0 ROM-strap risk is a hardware gate. If wake enters download mode, stop and record the evidence; do not ship an unreliable hold-to-wake.
- No hidden destructive gesture: a pocket press cannot erase a cook or reset the device.

## Done when
- [ ] Tap/hold/cancel unit tests pass, including the boot hold confirmation.
- [ ] On the board, 20/20 wake cycles work with USB attached and detached.
- [ ] An early release cancels the power-off countdown.
- [ ] A waking press does not change the page.
- [ ] Hold-to-wake boots to page 1; an early release returns to sleep without starting BLE or the UI.
- [ ] The deep-sleep path turns Vext off, sleeps the SX1262, and drops BLE.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] The 20/20 result and deep-sleep current are recorded in `docs/hardware-verified.md`.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
