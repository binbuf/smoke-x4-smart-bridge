# T62 — Power, deep sleep, and runtime

## Goal
A committed current and runtime table, plus 20/20 hold-PRG wake evidence, lets the release state battery life honestly and proves the sleep/wake path on real hardware.

## Context (read first)
- Design: [01 §1.4, §1.9](../design/01-hardware.md); bench row B0 in [10 §10.3](../design/10-test-and-release.md).
- Original verification: **B** (bench) · **board:** yes.
- Depends on T23, T24.
- The board is the real bridge with the 3000 mAh pack and the fitted antenna.

## Scope
- [ ] Measure current with the bridge on + advertising + OLED asleep.
- [ ] Measure current with the bridge on + connected + OLED awake.
- [ ] Measure current in deep sleep.
- [ ] Run 24 h on the 3000 mAh pack (advertising, OLED asleep).
- [ ] Confirm hold-PRG wake 20/20 with USB attached.
- [ ] Confirm hold-PRG wake 20/20 with USB detached.
- [ ] Record the fallback if the strap issue appears.
- [ ] Commit the runtime and current table.

## Out of scope
- The 24-hour soak with BLE/sync traffic and its memory criteria (→ T61).
- The field cook (→ T63).
- App release build (→ T64) and firmware release build (→ T65).
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, multi-bridge, and Billows setpoint control — outside MVP; no task owns them.

## Design notes
- Report the four measurement states separately; do not collapse advertising and connected current into one number.
- The 24 h runtime run is advertising + OLED asleep on the 3000 mAh pack.
- Hold-PRG wake must be 20/20 in both USB states; record any strap-issue fallback rather than omitting the failure.
- If the 24 h target is missed, the release note states the measured value honestly; do not change the target.
- Keep the measurement method and instrument in the table so the result is repeatable.

## Done when
- [ ] The runtime and current table is committed.
- [ ] Hold-PRG wake is recorded as 20/20 with USB attached and 20/20 with USB detached.
- [ ] Any strap fallback is recorded.
- [ ] The 24 h target is passed, or the release note states the measured value honestly.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
