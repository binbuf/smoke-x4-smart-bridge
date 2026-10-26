# M5 — Billows

**Exit gate:** Billows observation is verified with a real unit. The bridge shows
attached/not attached and, when the probe-4 target relation is confirmed, the
target set on the Smoke X4. `caps.billows_control = 0`; the app offers no target
setter and the firmware has no Billows TX path. The decision is recorded in
[`../billows-decision.md`](../billows-decision.md) as **Option C, observation
only**. No release claims "set target".

**Design:** [08](../design/08-billows.md), [02 §2.6](../design/02-smoke-x-protocol.md)

**Run this milestone after M4.** It is not a V0–V4 dependency. The B5.0 capture is
**bench-only**: attach the Billows to a real X4 with the air probe at room
temperature; the fan may run continuously because the probe is below target. Keep
it unobstructed. A cook is not required. No setpoint is changed during a cook.

---

### B5.0 Billows observation evidence (passive)

- **blocked-by:** T0.9 · **verify:** B · **board:** yes
- **design:** [08 §8.5](../design/08-billows.md)

Confirm what the broadcast actually carries. This is a receive-only task; do not
press receiver buttons hunting for a command and do not transmit.

1. Attach a Billows to a real X4 with the air probe at room temperature; confirm
   `billows_attached` is non-zero.
2. Capture state packets at 225, 250, and 275 °F, changing the target on the
   Smoke X4 base between captures.
3. Record probe 4's `max` and `min` at each target. Decide whether the target is
   `max`, `max − 25`, the midpoint, or another relation.
4. Detach the Billows; confirm `billows_attached` clears.
5. Commit the captures to `protocol/fixtures/lora/` and record the result in
   [`../billows-decision.md`](../billows-decision.md) and
   [`../hardware-verified.md`](../hardware-verified.md).

**Done when.** Attached/detached is proven, and the target relation is either
confirmed with two or more setpoints or explicitly marked unknown. An unknown
relation is acceptable; a guess is not.

---

### B5.1 Firmware: Billows observation

- **blocked-by:** B5.0, F1.3, F2.2, F1.11 · **verify:** H/B · **board:** no / B
- **design:** [08 §8.4, §8.6](../design/08-billows.md), [05 §5.4, §5.9](../design/05-ble-contract.md)

Implement read-only observation:

- decode `billows_attached` into `live.flags`;
- decode the candidate target; return `billows_target_f10 = 0` until B5.0
  confirms the relation;
- set `caps.billows_observe = 1` and `caps.billows_control = 0`;
- keep `billows_output` reserved and always 0;
- keep `config.billows_mode` / `config.billows_target_f10` reserved and unwritten;
- answer `set_billows_target` with `unsupported`;
- keep the only LoRa TX path the pairing ACK.

**Done when.** Host tests cover the attached flag, unknown/known target encoding,
and an unsupported `set_billows_target`. The TX invariant test proves no Billows
transmit path exists.

---

### A5.1 App: Billows UI (observation only)

- **blocked-by:** B5.0, B5.1 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.5, §6.7](../design/06-app.md),
  [08 §8.4, §8.6](../design/08-billows.md)

Implement:

- a Live Billows card only when **detected**, with no “Connected” pill;
- target read-only when `billows_target_f10 != 0`, otherwise `—`;
- the source line “Set on the Smoke X4”;
- one `Billows disconnected` notice if it was detected earlier this session and
  is now missing;
- Settings > Bridge > Billows showing detection/last-seen only;
- no mode switch, no target editor, no Set target action, no fan-speed claim;
- no control UI even if a future firmware sets a control bit this build does not
  implement.

**Done when.** Fake and real states render correctly; no UI path can send
`set_billows_target`.

---

### V5.1 Bench: Billows observation

- **blocked-by:** B5.1, A5.1 · **verify:** P · **board:** yes
- **design:** [08 §8.8](../design/08-billows.md)

Observation only; no cook is required.

1. Attach/detach; the flag and UI change.
2. Set 225, 250, and 275 on the Smoke X4 with the air probe at room temperature;
   the displayed target follows the B5.0 relation, or shows `—` if unknown.
3. Flip units; the target converts.
4. App/OLED agree; no false "running" or duty claim.
5. Confirm the stock receiver still works and the bridge transmits only the
   pairing ACK.

**Done when.** Results are recorded in `docs/hardware-verified.md`; release notes
state "Billows observed only".

---

### B5.2 Post-MVP: passive RF survey for additional Billows data

- **blocked-by:** M5 exit · **verify:** B · **board:** yes · **status:** post-MVP
- **design:** [08 §8.9](../design/08-billows.md)

After the MVP ships, look for more **displayable** Billows/base telemetry using a
receive-only survey. No transmitter, replay, or fuzzing.

Candidate questions:

- Does the state packet expose a fan-mode flag, duty, or fan-running status?
- Does the target appear in another field or in the trailing bytes?
- Does the fan adapter or Billows emit any RF telemetry?
- Do base-side menu actions change the state packet beyond the known fields?
- Is there any receiver→base traffic in a passive capture? (Public docs say the
  receiver has no setpoint controls; expect none.)

**Done when.** A short report records what was found, with captures in
`protocol/fixtures/lora/`. If nothing new exists, close the question and keep
observation as-is. This task does not add a control path.

---

## Deferred (not in MVP)

Billows setpoint control (RF command or inline fan controller) is **not** in this
milestone and has no task here. If it is ever reopened, it needs a new decision
record, a real Billows, and the safety/legal review in
[08 §8.7](../design/08-billows.md#87-deferred-control-options-post-mvp).
