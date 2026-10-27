# T37 — Bench: V0 end-to-end

## Goal
The V0 build is exercised end to end on a factory-fresh install and a real board: advertising, pairing with the OLED code, four live temperatures, the last 15 minutes in the full History shell, disconnect/reconnect, offline cache, and a power cycle. This is the first deployable end-to-end proof and the human bench gate that absorbs every physical check deferred by the unattended run (T15/T16, T19, T22–T26, T27–T31, T32–T36).

## Context (read first)
- **Human checkpoint before this task.** T36 carries `hitl: true`, so the
  harness places `.stop` after T36 and pauses here. T37 starts only after a
  human removes the sentinel and confirms the phone/board bench setup.
- **Absorbs deferred physical proof:** real X4 pairing and stock receiver (T16),
  power-cut log recovery (T19/T25), OLED page walk/legibility and PRG/power
  (T22/T23/T26), battery reading (T24), real BLE bond/passkey/MTU (T27/T30), and
  the real-phone Setup/Live/History/time-sync checks (T32–T36). Currents,
  USB-detached 20/20 and 24 h runtime stay with T62.
- [10 §10.3 B2/B3](../design/10-test-and-release.md) — the BLE and app bench matrices this run executes.
- [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) — the setup and Live states to walk on the phone.
- [10 §10.6](../design/10-test-and-release.md) — the acceptance matrix: four probes, BLE health/reconnect, History, and the UI state matrix.
- [05 §5.12](../design/05-ble-contract.md) — first-connect and reconnect procedures.
- Design: [10 §10.3 B2/B3](../design/10-test-and-release.md).
- Verify tier: **P/B**. Board: **yes**.
- Depends on T30, T31, T35, and T36. The post-T36 sync-word/BLE/UI fixes are
  already in the tree and are part of this gate.

## Already verified on hardware (2026-10-27)
These are **partial evidence**, not a pass for the whole task. Keep the
remaining checks below open.

- [x] Advertising, public identity name `SmokeX4-8276`, and `info.device_id`
  agree; scan finds the Bridge.
- [x] First bond with the OLED passkey; the OLED wakes to show the code.
- [x] Four real X4 frames at ~30 s cadence are stored and synced.
- [x] `set_time` returns `result ok`; a 195-byte recent sync completes.
- [x] Live shows P1 79.4 °F, P2 78.9 °F, P3 79.5 °F, P4 79.3 °F with
  `updated 22s ago` and −35 dBm LoRa signal.
- [x] A stored bond reconnects without a new passkey prompt.
- **Open:** the new Live connection chain, probe range/change line and X4
  warning dialog render correctly on the real phone. They are built and
  widget-tested; the phone walk is still open (step 9/16).

Evidence: [`hardware-verified.md`](../hardware-verified.md#lora-receive-root-cause-and-re-check-2026-10-27),
[`T37/lora-rx-after-syncword-fix.log`](../../artifacts/bench/T37/lora-rx-after-syncword-fix.log),
[`T37/lora-rx-ble-sync-after-fix.log`](../../artifacts/bench/T37/lora-rx-ble-sync-after-fix.log).

## Scope
On a factory-fresh install and a real board:

- [x] 1. Power on; confirm advertising and the OLED page.
- [x] 2. Scan, pair with the OLED code, reach Live.
- [ ] 3. See four live temperatures update at ~30 s; probe tiles show
      sparklines, the Min/Max range line, and the signed change over the
      selected **Live change window** (default `5m · +0.4°F`). The old fixed
      `1h · +3.8°F` footer is superseded by [06 §6.5](../design/06-app.md).
- [ ] 4. See the last 15 minutes in the full History shell.
- [ ] 5. Disconnect by walking away; confirm the stale/reconnect states and the offline-cache label. A cold app relaunch is T43/T46, not this gate.
- [ ] 6. Stop the Smoke X4 (or move it out of range); confirm the Bridge stays connected, the X4 node shows one amber warning, tapping it opens the pairing dialog, Live says `No readings` / `Smoke X4 signal lost`, and the app does not show fake live data.
- [ ] 7. Power-cycle the bridge; confirm auto-reconnect and history.
- [ ] 8. Confirm the stock receiver still works.
- [ ] 9. Walk the setup and Live states in [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) on the phone; no prototype chrome is visible.
- [ ] 10. Confirm a real X4 pair and that the stock receiver keeps updating;
      record the exact sync gesture.
- [ ] 11. Start recording, pull USB power mid-recording, reboot, and confirm
      earlier records survive and the log resumes.
- [ ] 12. Detach and reattach one probe; confirm `---`/`—` and the sentinel;
      flip °F/°C and confirm canonical °F storage.
- [ ] 13. Walk all OLED pages through the case window, including the blinking
      `BT` discovery indicator, display sleep/wake, passkey wake, and PRG power
      off/on with the hold countdown and early-release cancel.
- [ ] 14. Confirm the battery reading is plausible and unknown renders as `—`.
- [ ] 15. Reject a wrong passkey, confirm the bond survives reboot with no new
      prompt, and record the negotiated MTU.
- [ ] 16. Confirm the quiet 30 s forward sync keeps History current and never
      duplicates the newest sequence after a live notification.
- [ ] Record the phone model, Android version, negotiated MTU, timings, and any failure.
- [ ] Commit the V0 evidence (logs, screenshots, and the recorded measurements) in the named evidence location.
- [ ] Confirm no `Sync now` on Live, no fixture/last-session values shown as current, and no BLE/GATT/MTU language on product screens.
- [ ] Confirm the Billows card is absent while `caps.billows_observe = 0`.

## Out of scope
- Full 24 h / full-ring history and resume → T46 (T46) and T61 (T61).
- Cold-launch saved-Bridge auto-connect and archive-backed offline cache → T43;
  the phone proof is T46.
- Billows observation on a real unit → T56–T60 (M5); this gate does not depend on it, and Billows stays hidden while `caps.billows_observe = 0`.
- Settings, actions, and the full UI/a11y/copy gate → T55 (T55).
- The first real cook → T38; the release field cook → T63 (T63).
- Firmware release packaging and the app release build → T64/T65.
- Wi-Fi/HTTP/OTA — outside MVP; no task owns it.

## Design notes
- This is a **P** run: real phone + real board. Record the test phone model and Android version; they belong in the release notes (06 §6.9).
- Expected cadence is 30 s nominal. The observed cadence can wobble during Smoke X4 menu use; 90 s is the gap threshold, not a pass/fail timing target.
- At MTU 23 sync works but is slow; record the negotiated MTU rather than assuming 247. A low MTU is not a failure by itself.
- "Stale" means the bridge is still connected but the X4 is quiet (90 s–10 min); after 10 min it is `Smoke X4 signal lost`. Do not conflate BLE disconnection with X4 silence.
- The offline-cache state must show `Showing saved readings · last reading 20 min ago` (with the actual age) and must not present cache as live.
- The post-T36 connection card shows one signal meter per radio link: phone→Bridge (BLE RSSI) and Bridge→X4 (LoRa RSSI). The old single `Bridge connected · 2h 14m` line is superseded; durations sit under each link.
- The X4 warning is a single amber icon on the X4 node, not an inline notice. Tapping it opens the SYNC-mode pairing dialog; the healthy screen stays quiet.
- A cold launch still enters Setup until T43. Do not count that as a T37 failure; record the manual-setup friction as field evidence for T38/T43.
- No prototype chrome: no scenario lab, simulation timer, fixture badge, or fake OS prompt on any product screen.
- A failure is acceptable for the gate only when it has a named follow-up task; do not silently waive a step.

## Done when
- [ ] Every remaining step passes, or every failure has a named follow-up task.
- [ ] Phone model, Android version, MTU, timings, and failures are recorded.
- [ ] V0 evidence is committed.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
