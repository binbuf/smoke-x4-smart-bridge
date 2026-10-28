# T59 — Bench: Billows observation

## Goal
Bench evidence with a real Billows confirms attach/detach, target display (or `—`), unit conversion, app/OLED agreement, and that the bridge transmits only the pairing ACK.

## Context (read first)
- Design: [08 §8.8](../design/08-billows.md); the contract under test is [08 §8.4, §8.6](../design/08-billows.md) and [05 §5.4, §5.9](../design/05-ble-contract.md).
- Original verification: **P** (phone + board) · **board:** yes.
- Depends on T57.
- This is the **M5 exit gate**: Billows observation is verified with a real unit, the bridge shows attached/not attached and, when the probe-4 target relation is confirmed, the target set on the Smoke X4. `caps.billows_control = 0`; the app offers no target setter and the firmware has no Billows TX path. The decision is recorded in [`../billows-decision.md`](../billows-decision.md) as **Option C, observation only**, and no release claims "set target".
- Observation only; no cook is required.

## Scope
- [ ] Attach/detach the Billows; confirm the flag and UI change.
- [ ] Set 225, 250, and 275 °F on the Smoke X4 with the air probe at room temperature; confirm the displayed target follows the T56 relation, or shows `—` if unknown.
- [ ] Flip units; confirm the target converts.
- [ ] Confirm app and OLED agree, with no false "running" or duty claim.
- [ ] Confirm the stock receiver still works and the bridge transmits only the pairing ACK.

## Out of scope
- A cook or any setpoint change during a cook — not required for this gate.
- Billows setpoint control or any Billows transmit path — outside MVP; no task owns it. T68 does not add a control path.
- Re-deriving the target relation during the bench run; T56 owns that evidence.
- The post-MVP receive-only RF survey (→ T68).
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- Use a real Billows attached to a real Smoke X4; keep the air probe at room temperature and the fan unobstructed.
- The target must follow the T56-confirmed relation. If T56 marked the relation unknown, `—` is the correct result and still passes.
- App and OLED must both render from the capability bits; with `caps.billows_control = 0` there is no setter anywhere.
- Do not claim the fan is running, the duty cycle, or bridge output; `billows_output` is reserved and always 0.
- Capture the TX evidence for the pairing ACK only, not just an assertion.
- Record dated results in `docs/hardware-verified.md`.

## Done when
- [ ] Results are recorded in `docs/hardware-verified.md`.
- [ ] Release notes state "Billows observed only".
- [ ] `caps.billows_control = 0` and no app target setter or firmware Billows TX path is observed.
- [ ] The decision remains recorded as Option C, observation only, in [`../billows-decision.md`](../billows-decision.md).
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
