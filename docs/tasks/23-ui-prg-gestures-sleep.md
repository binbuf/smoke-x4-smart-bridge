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
- [x] Implement button sampling at **20 ms** with a **30 ms** debounce.
- [x] Implement the tap/hold state machine:
  - press < 400 ms → tap → next page,
  - hold ≥ 1.5 s → power off,
  - countdown from ~400 ms; commit on **release**.
- [x] A waking press is consumed: it wakes the display but does not also change the page.
- [x] A tap during the power-off countdown does nothing; only releasing cancels.
- [x] Releasing before the threshold cancels; releasing at/after 1.5 s commits.
- [x] On commit: show `OFF` for ~300 ms, turn Vext off, sleep the SX1262, bring BLE down, enter deep sleep with GPIO0 as the wake source.
- [x] Implement hold-to-wake: after reset, confirm the button is still held for ~1.5 s; an early release returns to sleep without starting BLE or the UI.
- [x] Add unit tests for tap/hold/cancel and the boot confirmation.
- [x] On the board, run 20/20 wake cycles with USB attached and detached.
      **Deferred:** T09 proved 20/20 with USB attached; the USB-detached
      physical count is T62.

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
- [x] Tap/hold/cancel unit tests pass, including the boot hold confirmation.
- [x] On the board, 20/20 wake cycles work with USB attached and detached.
      **Deferred:** T09 already proved 20/20 with USB attached (DTR on the GPIO0
      net). The USB-detached physical count and current are T62; this task is
      accepted on host tests plus the T09 result.
- [x] An early release cancels the power-off countdown.
- [x] A waking press does not change the page.
- [x] Hold-to-wake boots to page 1; an early release returns to sleep without starting BLE or the UI.
- [x] The deep-sleep path turns Vext off, sleeps the SX1262, and drops BLE.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] The 20/20 result and deep-sleep current are recorded in `docs/hardware-verified.md`. **Current is deferred to T62.**
- [x] Hand-off below filled in.

## Hand-off

**Landed (2026-10-26).** PRG gestures and the local power-off/wake path are
implemented behind a pure-C seam.

- `ui_button.h/.c` (new): 20 ms sampling, 30 ms debounce, tap < 400 ms,
  countdown from 400 ms, commit on raw release at/after 1.5 s, cancel between
  400 ms and 1.5 s. `UI_BUTTON_EVENT_*` is `PRESS`, `TAP`, `HOLD_START`,
  `HOLD_TICK`, `HOLD_CANCEL`, `HOLD_COMMIT`. A press whose edge is seen while
  the panel is asleep is consumed for its whole duration (no tap, no countdown).
  `ui_boot_hold_*` implements the post-wake 1.5 s confirmation.
- `ui.c`: the ui task now samples PRG every 20 ms in every display state and
  maps events to `ui_wake()`/`ui_page_next()`/`ui_set_power_off()`; a tap
  dismisses the storage notice and does nothing on other overlays. Commit draws
  `OFF`, holds it ~300 ms, then Vext off → `sx_radio_sleep()` →
  `ble_service_stop()` → `board_enter_deep_sleep()`. Failed wake arming clears
  `OFF` and stays awake. The panel's `0xAF` is applied only after a real
  `ui_wake()`, so sample dirty marks still cannot wake it.
- `boot.c`: on an EXT1 deep-sleep wake (and only then), confirm the PRG hold for
  1.5 s before NVS/BLE/UI; an early release re-enters deep sleep. Cold boots
  skip confirmation. `ui_init()` consumes the hold tail after confirmation.
- `board.c/.h`: `BOARD_PIN_PRG=0`, `board_prg_init/pressed`, `board_power_off_vext`,
  `board_enter_deep_sleep` (Vext off + GPIO0 `EXT1 ANY_LOW`).
- `sx_radio_sleep()`: parks the RX task, puts the SX1262 into cold sleep.
- `ble_service_stop()`: public seam; still the stub until T27/T30.
- Tests: `firmware/test/test_ui_button.c` (registered as `ui-button`).
- Docs: ADR 0031, 07 §7.4 notes, `hardware-verified.md` rows.

**Deviations.** (1) The 20/20 board count remains the T09 USB-attached result
plus the deferred USB-detached count in T62, as the task file already records;
no board run was possible this session. (2) Deep-sleep current is still T62.
(3) `ble_service_stop()` is a stub because the BLE service is still a skeleton;
the power-off path calls the seam in the required order. (4) A waking press is
consumed entirely, not just for page changes. This is stricter than the scope
wording and is recorded in ADR 0031.

**Checks run.**

```powershell
$env:PATH='C:\msys64\ucrt64\bin;'+$env:PATH
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# 100% tests passed, 15/15 (ui-button added)

$env:IDF_PYTHON_ENV_PATH='C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env'
& D:\esp\esp-idf\export.ps1
cd firmware
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete; image guard ok; sx4_bridge.bin 0x46830 (86% free);
# no compiler warnings/errors
```

**Remaining / next task must know.** T27/T30 must replace `ble_service_stop()`
with real advertising stop + disconnect + NimBLE deinit. T37 must check the
physical tap/hold/wake timing, the 300 ms `OFF` frame, and the power-off path;
T62 must record the USB-detached 20/20 wake count and deep-sleep current. Do not
change the 20 ms/30 ms/400 ms/1500 ms constants without updating the ADR and the
host tests.
