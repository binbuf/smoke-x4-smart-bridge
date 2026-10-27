# T58 — App: Billows UI (observation only)

## Goal
The app shows the approved status-only Billows surfaces on Live and in Settings, including honest offline and not-detected states, with no control affordance.

## Context (read first)
- Design: [06 §6.5, §6.7](../design/06-app.md), [08 §8.4, §8.6](../design/08-billows.md), [13 §13.4](../design/13-ui-implementation-contract.md#live).
- Original verification: **H/P** · **board:** no / phone.
- Depends on T56, T57.
- The screen and states are fixed by [13](../design/13-ui-implementation-contract.md); the copy is fixed by the source bullets below. Implement against the contract, not a new mockup.
- **Post-T36 status:** the Live card, the lost-this-session notice and the
  Settings → Billows status-only screen already exist and are driven by
  `caps.billows_observe` plus the live flags. T58 still owns the real
  capability/target gate and the final widget states; do not add a mode switch
  or target editor.

## Scope
- [ ] Add a Live Billows card only when **detected**, with no `Connected` pill and no `Read-only` label.
- [ ] Show `Set temp` when `billows_target_f10 != 0`, otherwise `—`.
- [ ] Show `Last detected` with an age (`12s ago`), not a bare `Detected`.
- [ ] Show the source line `Set on the Smoke X4.`
- [ ] Render the offline `Last observed state`, `Set temp (last known)` and a last-detected age.
- [ ] Show one `Billows not detected` notice with `View connection log` if it was detected earlier this session and is now missing.
- [ ] In Settings → Bridge → Billows, show status/last-seen only, with the focused connection log.
- [ ] Provide no mode switch, no target editor, no Set target action, no fan-speed claim.
- [ ] Provide no control UI even if a future firmware sets a control bit this build does not implement.

## Out of scope
- Billows setpoint control, mode selection, or a target editor — outside MVP; no task owns it. T68 does not add a control path.
- Firmware decode and capability bits (→ T57).
- Real-unit bench verification (→ T59).
- Notifications or alarms — outside MVP; no task owns it.
- Wi-Fi/HTTP/OTA, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.
- A UI redesign, new destination, or new prototype chrome — the contract is [13](../design/13-ui-implementation-contract.md).

## Design notes
- The card is driven by the capability bits and the live model, not a build-time assumption. `BillowsView` null means never detected, so there is no card and no placeholder.
- `billowsLostThisSession` drives the single `Billows not detected` notice; do not repeat the notice per screen.
- `billows_target_f10 != 0` is the only condition for showing a numeric target. `0` means unknown and must render `—`, never a guessed 225 °F or `max`.
- The target is the value set on the Smoke X4; the source line is exactly `Set on the Smoke X4.`
- Age copy uses the approved relative format (`12s ago`), not a bare `Detected`.
- Settings → Bridge → Billows is status/last-seen only; the connection log is focused from this surface.
- No path in this build may send `set_billows_target`, regardless of advertised caps.

## Done when
- [ ] Fake and real states render correctly with the approved copy.
- [ ] No UI path can send `set_billows_target`.
- [ ] The card is absent when Billows has never been detected.
- [ ] Widget tests cover detected, unknown target, known target, offline, and lost-this-session states.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
