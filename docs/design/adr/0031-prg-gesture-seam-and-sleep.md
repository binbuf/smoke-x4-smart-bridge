# ADR 0031 — PRG gestures are a pure-C FSM; a waking press is fully consumed

**Status:** accepted (T23, 2026-10-26)

## Context

One GPIO0/PRG button is the whole MVP control surface: tap = next page,
hold = power off with a cancel-on-release countdown, and hold-to-wake with a
post-reset confirmation. The firmware samples it every 20 ms with a 30 ms
debounce (07 §7.4). The same behaviour must be host-testable without ESP-IDF or
a board, and the deep-sleep path must not start BLE or the UI on an unconfirmed
wake.

## Decision

- **`ui_button` is a pure-C seam.** `ui_button_sample(button, raw_pressed,
  now_ms, consume_press)` owns debounce, tap/hold/cancel/commit, and the
  countdown digit. Time and the raw GPIO level are injected. `ui.c` only maps
  events to UI actions; `board.c` owns the pin and the sleep call.
- **A press that starts while the display is asleep is consumed for its whole
  duration.** It wakes the panel (via `ui_display_activity()`), but produces no
  tap, no page change, and no power-off countdown. This is stricter than "wake
  does not also change the page" and removes the pocket-press power-off path.
- **The hold threshold is judged on the raw release edge.** A release below
  1.5 s emits `HOLD_CANCEL`; at/after 1.5 s it emits `HOLD_COMMIT`. The 30 ms
  debounce applies to the press/release level, not to the threshold decision.
- **Boot confirmation runs only on an EXT1 deep-sleep wake.** Cold boots (USB,
  EN reset) never ask for a hold, so development and first power-on still work.
  On a wake, the boot path confirms 1.5 s of continuous hold before NVS, BLE or
  the UI start. Any release returns to deep sleep. `ui_init()` consumes the tail
  of that hold so the user can keep holding without triggering power-off. The
  1.5 s window starts at `app_main`, so the physical hold also includes the
  bootloader time (roughly 0.2–0.4 s on this board); T37 should time the real
  button to confirm it still feels like "hold to turn on".
- **Power-off order is OFF frame (300 ms) → Vext off → SX1262 cold sleep → BLE
  stop → deep sleep with GPIO0 `EXT1 ANY_LOW`.** If arming the wake source
  fails, the device clears `OFF` and stays awake rather than claiming to be off.
  `ble_service_stop()` is a stub seam now; T27/T30 fill in the real teardown.

## Consequences

- Host tests can drive exact millisecond boundaries (399/400 ms,
  1499/1500 ms) and the boot confirmation without hardware.
- The UI task now polls every 20 ms in every display state, including display
  sleep. The panel itself stays in `0xAE`; there is no I2C traffic while asleep.
- A waking long press cannot power the device off. The user must wake, release,
  then hold to power off. This is deliberate and should not be "fixed" without
  revisiting the pocket-press defense.
- T27/T30 must implement `ble_service_stop()` (advertising stop, disconnect,
  host/controller deinit) so the documented order remains true.
- The GPIO0 ROM-strap gate and the USB-detached 20/20 count remain hardware
  evidence owned by T09/T62; this ADR only defines the software contract.
