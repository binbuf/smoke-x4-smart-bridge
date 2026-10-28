# T57 — Firmware and app: Billows observation (observation only)

## Goal
The firmware decodes Billows attachment and, only when T56 validated the relation, the target, while advertising observation-only caps and keeping no Billows transmit path. The app shows the approved status-only Billows surfaces on Live and in Settings, including honest offline and not-detected states, with no control affordance.

## Context (read first)
- Design: [08 §8.4, §8.6](../design/08-billows.md); contract details in [05 §5.4, §5.9](../design/05-ble-contract.md); app surfaces in [06 §6.5, §6.7](../design/06-app.md) and [13 §13.4](../design/13-ui-implementation-contract.md#live).
- Original verification: **H** (host) · **board:** no.
- Depends on T56, T14, T28, T22.
- T56 decides whether the candidate target relation is known. Until it is confirmed, the target is unknown; do not infer it from `max` or a default setpoint.
- The screen and states are fixed by [13](../design/13-ui-implementation-contract.md); the copy is fixed by the source bullets below. Implement against the contract, not a new mockup.
- **Post-T36 status:** the Live card, the lost-this-session notice and the
  Settings → Billows status-only screen already exist and are driven by
  `caps.billows_observe` plus the live flags. This task owns the real
  capability/target gate and the final widget states; do not add a mode switch
  or target editor.

## Scope
### Firmware
- [x] Decode `billows_attached` into `live.flags`.
- [x] Decode the target; T56 confirmed `max` = the base set temp, so return probe 4 `max` while attached and `billows_target_f10 = 0` when detached/unknown.
- [x] Set `caps.billows_observe = 1` and `caps.billows_control = 0`.
- [x] Keep `billows_output` reserved and always 0.
- [x] Keep `config.billows_mode` and `config.billows_target_f10` reserved and unwritten.
- [x] Answer `set_billows_target` with `unsupported`.
- [x] Keep the only LoRa TX path the pairing ACK.

### App
- [x] Add a Live Billows card only when **detected**, with no `Connected` pill and no `Read-only` label.
- [x] Show `Set temp` when `billows_target_f10 != 0`, otherwise `—`.
- [x] Show `Last detected` with an age (`12s ago`), not a bare `Detected`.
- [x] Show the source line `Set on the Smoke X4.`
- [x] Render the offline `Last observed state`, `Set temp (last known)` and a last-detected age.
- [x] Show one `Billows not detected` notice with `View connection log` if it was detected earlier this session and is now missing.
- [x] In Settings → Bridge → Billows, show status/last-seen only, with the focused connection log.
- [x] Provide no mode switch, no target editor, no Set target action, no fan-speed claim.
- [x] Provide no control UI even if a future firmware sets a control bit this build does not implement.

## Out of scope
- Any Billows control path, target write, or Billows transmit — outside MVP; no task owns it, and T68 is receive-only.
- Real-unit bench verification (→ T59).
- Any LoRa transmission other than the pairing ACK — outside MVP; no task owns it.
- Notifications or alarms — outside MVP; no task owns it.
- A UI redesign, new destination, or new prototype chrome — the contract is [13](../design/13-ui-implementation-contract.md).
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- `info.caps` b0 `billows_observe` is 1; b1 `billows_control` is **0 in the MVP**.
- `live.flags` b2 is `billows_attached`; b3 `billows_output` is reserved and always 0. Do not expose a fan-duty or fan-running claim.
- `live.billows_target_f10` is the observed target; `0` means unknown. Only encode a non-zero value after T56 has validated the relation with two or more setpoints.
- `config.billows_mode` and `config.billows_target_f10` are reserved for a future control build; the MVP writes neither.
- `control` op 6 `set_billows_target` always returns `unsupported` while `caps.billows_control = 0`.
- The only LoRa TX path is the pairing ACK; there is no Billows TX path. The invariant test must prove it, not merely assert it in review.
- The card is driven by the capability bits and the live model, not a build-time assumption. `BillowsView` null means never detected, so there is no card and no placeholder.
- `billowsLostThisSession` drives the single `Billows not detected` notice; do not repeat the notice per screen.
- `billows_target_f10 != 0` is the only condition for showing a numeric target. `0` means unknown and must render `—`, never a guessed 225 °F or `max`.
- The target is the value set on the Smoke X4; the source line is exactly `Set on the Smoke X4.`
- Age copy uses the approved relative format (`12s ago`), not a bare `Detected`.
- Settings → Bridge → Billows is status/last-seen only; the connection log is focused from this surface.
- No path in this build may send `set_billows_target`, regardless of advertised caps.

## Done when
- [x] Host tests cover the attached flag, unknown/known target encoding, and an unsupported `set_billows_target`.
- [x] The TX invariant test proves no Billows transmit path exists.
- [x] `caps.billows_observe = 1` and `caps.billows_control = 0` are observable in the host tests.
- [x] Fake and real states render correctly with the approved copy.
- [x] No UI path can send `set_billows_target`.
- [x] The card is absent when Billows has never been detected.
- [x] Widget tests cover detected, unknown target, known target, offline, and lost-this-session states.
- [x] Hand-off below filled in.

## Hand-off

**Landed.** The firmware parser now exposes probe 4 `max` as
`billows_target_deg` with `billows_target_valid = true` while
`billows_attached` is set (T56 relation: `max` = base set temp; `min` = 0).
`sample_pipe` converts the target to canonical °F tenths (including °C
packets), `bridge_state`/`ble_live` keep `0` for an unknown target, and
`caps.billows_control` remains 0. The existing single-TX-call-site test still
proves the pairing ACK is the only `LoRaSend` path.

The app now tracks the real last-detection and loss times from `live` instead
of the hardcoded 12-minute age, so `Last detected` and the connection log age
from the actual event. Settings → Bridge → Billows shows the offline
`Last observed state`, `Set temp (last known)` and the Billows-filtered
connection log. There is still no mode switch, target editor, Set target action,
fan-speed claim or control UI.

**Tests.** `firmware/test/test_sx_protocol.c` replays the T56 capture and
asserts `max` = 225/250/275 only while attached, with `min=0` and the detached
160/32 fields never becoming a target. `firmware/test/test_sample_pipe.c` covers
known target, detached/unknown target and °C conversion.
`app/test/billows_observation_test.dart` covers known target, unknown target,
offline last-known, lost-this-session age and the no-`set_billows_target` path.
The existing widget tests still cover the absent card and the single loss
notice.

**Deviations.** The app's fixture/default controller still seeds a 225 °F
Billows for the review shell, but real sessions clear it on launch/connect and
the card only renders from `live` data. The Billows-filtered log is shown inline
on the Billows screen; the full Bridge timeline remains in Bridge details.

**For T59.** Run the real bench matrix on the release image: attach/detach,
225/250/275 °F on the base, °F/°C flip, the app/OLED read-only target and the
absence of any Billows TX. T57 is host-verified only; the physical panel and
real-phone walk belong to T59.
