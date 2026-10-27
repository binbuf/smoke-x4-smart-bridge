# T37 — Bench: V0 end-to-end

## Goal
The V0 build is exercised end to end on a factory-fresh install and a real board: advertising, pairing with the OLED code, four live temperatures, the last 15 minutes in the full History shell, disconnect/reconnect, offline cache, and a power cycle. This is the first deployable end-to-end proof and the gate before any field use.

## Context (read first)
- **Human checkpoint before this task.** T36 carries `hitl: true`, so the
  harness places `.stop` after T36 and pauses here. T37 starts only after a
  human removes the sentinel and confirms the phone/board bench setup.
- [10 §10.3 B2/B3](../design/10-test-and-release.md) — the BLE and app bench matrices this run executes.
- [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) — the setup and Live states to walk on the phone.
- [10 §10.6](../design/10-test-and-release.md) — the acceptance matrix: four probes, BLE health/reconnect, History, and the UI state matrix.
- [05 §5.12](../design/05-ble-contract.md) — first-connect and reconnect procedures.
- Design: [10 §10.3 B2/B3](../design/10-test-and-release.md).
- Verify tier: **P**. Board: **yes**.
- Depends on T30, T31, T35, and T36.

## Scope
On a factory-fresh install and a real board:

- [ ] 1. Power on; confirm advertising and the OLED page.
- [ ] 2. Scan, pair with the OLED code, reach Live.
- [ ] 3. See four live temperatures update at ~30 s; probe tiles show sparklines and the approved footer (`1h · +3.8°F`, signed).
- [ ] 4. See the last 15 minutes in the full History shell.
- [ ] 5. Disconnect by walking away; confirm the stale/reconnect states and the offline-cache label.
- [ ] 6. Stop the Smoke X4 (or move it out of range); confirm the Bridge stays connected, Live says `No readings` / `Smoke X4 signal lost`, and the app does not show fake live data.
- [ ] 7. Power-cycle the bridge; confirm auto-reconnect and history.
- [ ] 8. Confirm the stock receiver still works.
- [ ] 9. Walk the setup and Live states in [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) on the phone; no prototype chrome is visible.
- [ ] Record the phone model, Android version, negotiated MTU, timings, and any failure.
- [ ] Commit the V0 evidence (logs, screenshots, and the recorded measurements) in the named evidence location.
- [ ] Confirm no `Sync now` on Live, no fixture/last-session values shown as current, and no BLE/GATT/MTU language on product screens.
- [ ] Confirm the Billows card is absent while `caps.billows_observe = 0`.

## Out of scope
- Full 24 h / full-ring history and resume → T46 (T46) and T61 (T61).
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
- No prototype chrome: no scenario lab, simulation timer, fixture badge, or fake OS prompt on any product screen.
- A failure is acceptable for the gate only when it has a named follow-up task; do not silently waive a step.

## Done when
- [ ] All nine steps pass, or every failure has a named follow-up task.
- [ ] Phone model, Android version, MTU, timings, and failures are recorded.
- [ ] V0 evidence is committed.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
