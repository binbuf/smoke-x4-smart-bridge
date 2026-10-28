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
- [x] Attach/detach the Billows; confirm the flag and UI change.
- [x] Set 225, 250, and 275 °F on the Smoke X4 with the air probe at room temperature; confirm the displayed target follows the T56 relation, or shows `—` if unknown.
- [x] Flip units; confirm the target converts.
- [x] Confirm app and OLED agree, with no false "running" or duty claim.
- [x] Confirm the stock receiver still works and the bridge transmits only the pairing ACK.

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
- [x] Results are recorded in `docs/hardware-verified.md`.
- [x] Release notes state "Billows observed only". **The wording is fixed in
      [`../billows-decision.md`](../billows-decision.md) and the app/OLED copy;
      T66 owns the release-notes file itself.**
- [x] `caps.billows_control = 0` and no app target setter or firmware Billows TX path is observed.
- [x] The decision remains recorded as Option C, observation only, in [`../billows-decision.md`](../billows-decision.md).
- [x] Hand-off below filled in.

## Hand-off

**Landed.** A real bench walk on the T57 image and release APK with a real
Billows on a real Smoke X4 and the Pixel 11 Pro Fold. Evidence is under
`artifacts/bench/T59/` with `README.md`, 21 screenshots, UI dumps, the 77 KB
serial capture and the app-side target/attached log.

**Result.** 225/250/275 °F all showed the base target in the app (`max` =
target); 275 °F converted to `135.0°C` and back to `275.0°F`; OLED matched the
app; detach removed the card and produced exactly one `Billows not detected`
notice with `View connection log`; Settings showed the lost state and, with
Bluetooth off, `Last observed state` / `Set temp (last known) 275.0°F` / a
last-detected age plus the focused log. The stock receiver kept updating.
Re-pairing the X4 from Settings produced the only TX line in the capture:
`pair ACK sent on 918500000 Hz`; state frames resumed immediately. No control
UI, target setter, fan-running claim or Billows TX path was observed.

**Deviations / gotchas.**

- Live notifications sometimes lagged the base change by up to ~2 minutes while
  the BLE link churned (`central disconnected reason 0x213`, reconnect and one
  `advertising start failed (6)`). A relaunch/read showed the correct target.
  The target did follow every setpoint; route the refresh delay to T43/T46a.
- The first 250 °F screenshot still showed 225 °F until the next read; the card
  was re-captured after the notification landed.
- The Billows was detached once and reattached at 275 °F for the offline
  last-known check and the re-pair ACK.
- OLED evidence is operator-confirmed (no usable camera photo); the app
  screenshots and serial log are the machine evidence.
- Release notes are T66; this task fixed the required wording in the decision
  record and product copy.

**For T61/T63/T64/T66/T67.** The behaviour is observation-only and the release
copy must stay "Billows observed only; set the target on the Smoke X4." Do not
describe the bridge as controlling the fan. The 2-minute live-refresh lag is a
known bench observation, not a T59 failure.
