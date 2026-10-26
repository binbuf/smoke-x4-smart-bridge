# M5 — Billows

**Exit gate:** Billows observation is verified with a real unit. The setpoint
question has a **signed** decision in `docs/billows-decision.md`: a validated RF
path, an approved inline fan controller, or an explicit observation-only scope
reduction accepted by the owner. No release claims "set target" unless the
capability bit is set and the path was tested. Option C without a signature
means M5 is not complete.

**Design:** [08](../design/08-billows.md), [02 §2.6](../design/02-smoke-x-protocol.md)

**Run this milestone after M4.** Billows is the one area with an open
control-path question; the core bridge/app must be usable first. V0–V4 do not
depend on it. The spike is cheap, and its answer changes B5.2/A5.1.

The B5.0 capture is **bench-only**: attach the Billows to a real X4 with the air
probe at room temperature; the fan may run continuously because the probe is
below target. Keep it unobstructed. A cook is not required. Only the B5.2
inline-controller safety run needs a supervised cook.

---

### B5.0 Billows control-path feasibility

- **blocked-by:** T0.9 · **verify:** B · **board:** yes
- **design:** [08 §8.3, §8.4](../design/08-billows.md)

Work from the M5 captures: the attached flag and probe 4's `max`/`min` at a
known setpoint can be evaluated immediately, and a single known target separates
`max = target` from `max = target + 25`. The controlled steps must run before
the decision is signed. This is a bench capture; no smoker or cook is required.
Keep the fan intake and outlet clear.

Capture campaign:

1. With a Billows attached, capture the X4 state at 225, 250, and 275 °F. Record
   probe 4's `max` and `min` at each; derive whether the target is `max`,
   `max - 25`, the midpoint, or another relation.
2. Press every receiver button (CH, SET, up/down, alarm/mute) while capturing
   the operating frequency. Does the receiver transmit at all?
3. Change target on the base while capturing; is there any command packet?
4. Scope the fan adapter's control line if a safe probe point exists; identify
   on/off vs PWM vs analog. Do not load the line or connect 12 V to the board.
5. Write a decision record: **A** RF command, **B** inline controller, or **C**
   observation only.

**Done when.** The captures and decision are committed in
`protocol/fixtures/lora/` and `docs/billows-decision.md`, with the product
owner's sign-off. If A, include the exact command bytes and the safety/legal
review notes. If C, state the scope reduction explicitly and sign it; an unsigned
"TBD" does not close the gate.

---

### B5.1 Firmware/app: Billows observation

- **blocked-by:** T0.9, F1.3, F2.2, F1.11, A2.3 · **verify:** H/B · **board:** no / B
- **design:** [08 §8.6](../design/08-billows.md), [05 §5.4, §5.9](../design/05-ble-contract.md)

Read-only observation does not need the `config` characteristic. The
`billows_mode`/target config lands with F4.1; do not hold the attached flag,
live target, OLED page, or app card behind M4.

Implement observation independent of the control decision:

- decode `billows_attached` and the target field,
- flags and live target in `live`,
- config `billows_mode`/target with validation,
- `caps.billows_observe`,
- OLED Billows page,
- app Billows card and read-only target when control is absent.

If the target field is not validated by B5.0, return 0/unknown and show `—`.

**Done when.** On the bench, Billows attach/detach and target changes appear in
the app and OLED; detached shows "not attached"; no "fan running" is invented.

---

### B5.2 Firmware/hardware: Billows setpoint (only if A or B)

- **blocked-by:** B5.0, B5.1, F4.2 · **verify:** H/B · **board:** yes
- **design:** [08 §8.4, §8.7, §8.8](../design/08-billows.md)

**If A (RF command):**

- implement only the target-set frame, allow-listed and range-checked,
- set `caps.billows_control`,
- host test that no other TX path exists,
- re-verify the stock receiver and the Smoke X4 fan mode.

**If B (inline controller):**

- build the high-side switch harness (fuse, MOSFET, gate drive, flyback,
  connector) and a separate enclosure,
- implement fail-off control from probe 4, target validation, and visible
  output state,
- disconnect the Smoke X4 fan control path; never drive both,
- set `caps.billows_control`,
- add the safety tests in 08 §8.7.

**If C:** do not implement this task; record the scope decision and keep the
capability bit clear.

**Done when.** The chosen path passes its host and bench tests; the app can set a
target and read it back; the safety behavior is demonstrated.

---

### A5.1 App: Billows UI

- **blocked-by:** B5.0, B5.1 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.5, §6.7](../design/06-app.md),
  [08 §8.6](../design/08-billows.md)

Implement:

- Live Billows card: attached/not attached, target, source (observed/controlled),
- Settings Billows mode and target,
- target setter only when `caps.billows_control` and mode = control; under
  option C there is no setter at all,
- "observe only" explanation when unsupported,
- no fan-speed claim.

The UI may be built before B5.2, but it must be capability-gated and must not
write a target until a validated control path exists.

**Done when.** Fake and real states render correctly; an unsupported target
write cannot be attempted from the UI.

---

### V5.1 Bench: Billows

- **blocked-by:** B5.1, A5.1 · **verify:** P · **board:** yes
- **design:** [08 §8.8](../design/08-billows.md)

Observation runs even if B5.2 is skipped (option C). The control/safety rows
run only when B5.2 landed.

Observation and the B5.0 capture are bench-only; no cook is required. Only the
B5.2 inline-controller rows that exercise the fan under load need a supervised
cook.

Run the observation checklist and, if control is implemented, the control/safety
checklist. At minimum:

1. Attach/detach; flag changes.
2. Set 225, 250, and 275 on the Smoke X4 with the air probe at room temperature;
   the derived target follows the validated relation (not necessarily raw
   `max`).
3. Flip units; target converts.
4. App/OLED agree; no false "running".
5. If control: set from the app, read back, fail-off tests, supervised cook.

**Done when.** The result is recorded; release notes state observe vs control
accurately.
