# T52 — app: destructive actions

## Goal
Ship the approved destructive flows with exact cost-before-send copy: Forget this phone, Factory reset Bridge, Power off the Bridge and Clear history on the Bridge. Each action reports success only after the device's `result` or the expected disconnect, and phone history survives.

## Context (read first)
- [06 §6.7](../design/06-app.md) — Bridge actions and the destructive-action rules.
- [06 §6.8](../design/06-app.md) — error and empty states.
- [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations) — destructive-action, power-off, factory-reset and forget states.
- [12 §12.2](../design/12-copy-and-label-review.md) — exact loss copy for power off, factory reset and forget.
- [05 §5.12](../design/05-ble-contract.md) — forget/factory-reset/power-off procedure and disconnect as expected outcome.
- [05 §5.5](../design/05-ble-contract.md) — answer-first ordering for destructive ops.
- `app/lib/features/settings/bridge_details.dart` — entry point for the action rows.
- **Verify:** H/P · **Board:** no / phone
- Depends on T50 and T49.
- **Post-T36 status:** the four confirmation sheets, loss copy, Setup return and
  the local `forgetPhone`/`factoryReset` state changes already exist in
  `settings_details.dart`. They do not send control ops yet. T52 wires the real
  ops and the `result ok` / expected-disconnect outcome; do not change the copy.

## Scope
- [ ] **Forget this phone** — confirm with the exact loss copy; clear the saved connection and send a best-effort `forget_phone`; keep local history; explain if the Bridge may still hold the pairing; return to Setup with the `History on this phone` escape.
- [ ] **Factory reset Bridge** — open a cost sheet naming all paired phones, Bridge settings/screen preferences, saved readings and the clock; send `factory_reset`; treat the disconnect as success; clear the saved connection and return to Setup; keep local history and show the orphaned history entry.
- [ ] **Power off the Bridge** — confirm; send `power_off`; show the `Bridge is off` screen with the 1.5 s PRG wake instruction.
- [ ] **Clear history on the Bridge** — confirm; send `clear_history`; show the generation boundary outcome; keep phone history.
- [ ] Use the exact loss copy in 12 §12.2. Do not paraphrase the loss.
- [ ] Show exact loss, count and date range where applicable in the confirmation sheet.
- [ ] No action reports success before the device's `result` or the expected disconnect.
- [ ] After forget, clear the local bond on `result ok` or on the disconnect, whichever comes first.
- [ ] After factory reset, do not wait for a result that cannot arrive after the reboot; the expected disconnect after a sent request is success, but only after a `result ok` or a deliberate timeout with the link gone.
- [ ] After power off, never present the Bridge as reachable while it is off.
- [ ] Return to Setup after forget and factory reset, with saved `History on this phone` visible and an orphaned-history entry where the old Bridge identity is gone.
- [ ] Remove any `current cook` copy. There are no user-created cook sessions.
- [ ] Add widget tests for each sheet, the sending state, success, failure, expected disconnect and Setup return.

## Out of scope
- BLE control op implementation and status mapping → T48.
- Link teardown, re-advertising and power-cut state → T49.
- Settings root and Bridge details layout → T50; Bridge settings editors → T51.
- Local history deletion by 30/90/all and History & storage counts → T44.
- Units, theme and locale formatting on confirmations → T53.
- Full UI matrix, accessibility and copy-lint gate → T54.
- On-device factory reset gesture or boot-time button menu — outside MVP; no task owns it.
- Notifications — outside MVP; no task owns it.
- Billows control — M5 Billows (T56–T60); `caps.billows_control` is always 0.

## Design notes
- Exact copy (12 §12.2):
  - Forget: `Forget this phone?` — “This removes the Bluetooth pairing for this phone. The Bridge keeps recording.” Phone history is kept; other phones are not affected.
  - Factory reset: `Factory reset this Bridge?` — “The Bridge erases its pairings, settings, and saved readings, then restarts.” Bullets: all paired phones; settings and screen preferences; saved readings and clock; becomes available to pair as a new device. “History on this phone is kept.” Button: `Factory reset`.
  - Power off: `Power off the Bridge?` — “The Bridge stops recording until you turn it back on.” Supporting lines: “Recording stops while the Bridge is off”; “History on this phone is kept”; “Hold PRG for 1.5 seconds to turn the Bridge back on.”
  - Clear history: `Clear history on the Bridge…` and the sheet says history on this phone is kept.
- 05 §5.12 supplies the longer contract wording if a sheet needs the full consequence; keep it consistent with the 12 §12.2 labels above.
- Destructive ordering (05 §5.5): the app sends the op, the bridge answers `result ok`, then the bridge acts after ≈250 ms. The app must tolerate either the notification or the disconnect arriving first.
- Forget is local-first plus best-effort network. If the write fails because the link is already gone, still clear the local saved connection and explain that the Bridge may still hold the pairing.
- Factory reset is not reversible from the app. The sheet must name every category of loss, and the app must keep phone history and show the orphaned entry rather than implying the phone was wiped.
- Power off is not a factory reset: it stops recording and advertising until PRG is held for 1.5 s. The `Bridge is off` screen must not claim the Bridge is reachable.
- Clear history changes the bridge generation only. It does not clear phone history, pairing or config.
- Use `readings` in user copy, never `records`, `points` or `samples`. The ESP32 device is always the `Bridge`, including in destructive copy.
- No action may show a success banner before the `result` or the expected disconnect. A failed send leaves the local state unchanged where possible.
- Design: [06 §6.7](../design/06-app.md), [06 §6.8](../design/06-app.md), [13 §13.4](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations), [12 §12.2](../design/12-copy-and-label-review.md).

## Done when
- [ ] Each action works on the real bridge: forget, factory reset, power off and clear history.
- [ ] Each confirmation sheet names the exact loss, with counts and date range where applicable.
- [ ] Setup shows saved `History on this phone` after forget or reset, including the orphaned history entry.
- [ ] No `current cook` copy remains anywhere in the flows.
- [ ] `flutter analyze` is clean and `flutter test` passes, including widget tests for every sheet and outcome.
- [ ] Hand-off below filled in.

## Hand-off

**Landed.** The four actions now send real control ops and report success only
from the device. `BridgeLink.attemptControl()` records whether the write reached
the Bridge, so `factory_reset`/`forget_phone`/`power_off` can treat the
subsequent disconnect as the expected outcome while `clear_history` still needs
`result ok`. `BridgeController.forgetPhone/factoryReset/powerOff/
clearBridgeHistory` own the local outcome: bond and saved-connection clearing for
forget and reset, `bridgeOff` for power off, and Bridge-figure zeroing plus the
`History on the Bridge cleared` result for clear history. Setup shows orphaned
`History on this phone` (`· from your previous Bridge.`) and a `Pairing not
confirmed` notice after an unconfirmed forget. The approved 12 §12.2 copy is
unchanged, and no `current cook` copy appears in any sheet.

**Tests.** `app/test/settings_destructive_test.dart` (17) covers the exact copy
and no-send-on-open for each sheet, the neutral sending state, success only on
`ok`, refusal and timeout, the expected-disconnect branches for factory reset
and forget (online and offline), the `Bridge is off` screen, and Setup return
with orphaned history. Four scripted-bridge tests assert the wire ops and bond
removal. `flutter analyze` clean, `flutter test` 262/262, host verify 25/25.

**Deviated / deferred.** The destructive board walk is deferred to T55 with an
NVS/samples backup and a re-pair plan, matching T48/T49; no destructive op was
sent to the shared bench board. The real-phone/OLED evidence and the new
generation boundary stay open in `docs/hardware-verified.md`.

**Next task must know.** `clear_history` must not treat a disconnect as success;
only `factory_reset`, `forget_phone` and `power_off` do. Forget is local-first,
so it always returns to Setup and keeps phone history; the notice is the only
difference when the pairing is unconfirmed. `clearBridgeHistory()` only zeroes
the displayed figures — the new epoch arrives on the next stats read (T49
firmware). T53 owns units/theme formatting inside these sheets, T54 their
state-matrix/a11y/copy gate, and T55 the real-board walk.
