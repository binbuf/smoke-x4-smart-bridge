# 08 — Billows

## 8.1 What a Billows is

The ThermoWorks Billows is a 12 V variable-airflow fan used to hold a smoker at a
target temperature. It connects to a compatible ThermoWorks controller. On a
Smoke X4 it uses **channel 4**; the Smoke X4's fan mode interprets channel 4 as
the pit/air probe and runs its own control loop.

From the ThermoWorks instructions:

- The fan is powered by 12 V through a fan adapter; the adapter plugs into the
  Smoke X4.
- The air probe must be in channel 4 or the fan will not run.
- The set temperature is adjusted **on the Smoke X4** with CH/SET/up/down.
- Fan mode automatically sets high/low alarms at ±25 °F around the setpoint.
- The fan's actual on/off duty is not exposed as a number.

The Smoke X4 state broadcast exposes:

- `billows_attached` — trailing field, non-zero when a Billows is connected.
- Probe 4's `max`/`min` — alarm setpoints; one of them may carry the fan target
  in fan mode, but the relation is unproven.

The ±25 °F alarm behavior makes the naive "target = max" reading suspect:
if `max` is the high alarm it is `target + 25`, and if `max` is the target then
the ±25 alarms are not in the packet. B5.0 must capture both setpoints at two
targets and derive the relation. See [02 §2.6](02-smoke-x-protocol.md) and
Q4/Q5 in [02 §2.10](02-smoke-x-protocol.md).

## 8.2 The requirement

The brief says:

> Support ThermoWorks Billows
> - Set target temp
> - Be able to tell its connected, status, etc

Those are two different claims:

| Claim | What it needs | Confidence today |
|---|---|---|
| Show attached/status | Decode the broadcast | High for attached; target needs validation |
| Set target | A control path to the fan/base | **Unknown; no proven path** |

The design does not pretend the second exists. It defines a gate, two candidate
implementations, and a scope decision if neither is safe.

## 8.3 Why the obvious RF approach may not exist

The bridge is a listener. The only LoRa packet it has ever sent is the pairing
ACK. The Smoke X4 base has a receiver (it hears that ACK during sync), but no
capture has shown a **command** from the handheld receiver to the base. In the
standard product the setpoint is entered on the base's own buttons and the base
drives the fan through the wired adapter. The handheld receiver may be
display-only.

If that is true, there is no RF command to emulate, and any claim that the app
"sets the target over LoRa" would be fiction. A passive capture campaign is
therefore the first task, not an implementation detail.

## 8.4 The decision gate (B5.0)

**B5.0 must run before any "set target" code is written.** Its result is recorded
in [`docs/billows-decision.md`](../billows-decision.md). It has three outcomes:

### A. A safe RF command exists

Evidence: a capture of the receiver or another controller transmitting a
well-formed command that changes the Smoke X4 setpoint, with a repeatable
before/after state change.

Work:

0. With a Billows attached, capture the state packets at setpoints 225, 250, and
   275 °F. Record probe 4's `max` and `min` at each. Derive whether the target is
   `max`, `max - 25`, the midpoint, or something else. Do this before any
   observation UI promises a target. Never change a setpoint mid-cook just to
   capture; this is part of the M5 bench sitting. No cook is required, and the
   fan should be left unobstructed.
1. Capture with an SX1262 or SDR on the operating frequency while pressing every
   receiver button (CH, SET, up/down, alarm, mute) and while changing the target
   on the base.
2. Diff the packets. If the receiver transmits nothing, option A is dead.
3. If a command exists, decode the target opcode and value; confirm it is not a
   general-purpose arbitrary-transmit protocol.
4. Implement only the target-set operation, with a hard allow-list and range
   check. Never transmit during a cook except this exact operation.
5. Re-verify that the stock receiver and the Smoke X4's own fan mode still work.
6. Review legal/regulatory implications (ISM band, duty cycle, product
   certification) before shipping.

This is the cleanest user experience if it exists: the Smoke X4 keeps owning the
fan loop and its ±25 °F alarms.

### B. No RF command; an inline fan controller is acceptable

The bridge controls the fan directly:

- The Smoke X4 fan adapter is **disconnected** from the fan. The bridge's
  controller is the only thing driving the 12 V fan.
- The bridge uses probe 4 (channel 4) as the pit sensor and runs a closed-loop
  controller.
- The app sets the target over BLE.
- The Smoke X4 still broadcasts temperatures; its own fan mode is not used.

This is feasible with a small high-side switch, but it is a **hardware product
change**, not a firmware checkbox:

- 12 V load, fuse, high-side MOSFET, gate drive, flyback/snubber, connectors,
  enclosure, and thermal separation from the smoker.
- The ESP32 must be isolated from the 12 V rail; never connect 12 V to a GPIO.
- A fan stuck on is a fire/safety risk. The controller must fail off.
- The fan's own electronics may not accept slow PWM on the 12 V rail; the
  conservative implementation is on/off switching with a duty window, not a
  high-frequency PWM.

The control algorithm, if this path is chosen:

```
every 1 s:
  t = latest valid probe-4 temperature
  if t is invalid or older than 120 s: fan OFF; alarm state
  if target invalid or outside 32..572 °F: fan OFF
  error = target - t
  if error > +15 °F: duty = 100%
  else if error < -10 °F: duty = 0%
  else: PI with anti-windup, duty clamped 0..100%
  apply duty over a 10 s window (on/off, minimum 1 s on)
```

The 30 s Smoke X4 cadence is slow for tight control. The fan's own thermal mass
and the smoker's inertia make a 30 s sensor update usable but not precise.
Document the expected ±10–15 °F band; do not promise ±1 °F.

### C. Neither is safe/available: observation only

If A does not exist and B is not approved (cost, enclosure, safety, or schedule),
the MVP ships:

- attached/not attached,
- observed target (if validated),
- no setpoint control.

The app shows the target read-only and says why. This is a **scope reduction
that must be explicitly accepted**; it is not silently shipped as if the feature
exists. The task plan marks the setpoint acceptance line as blocked until this
decision is recorded.

## 8.5 Recommendation

1. Run **B5.0** in M5, after the core bridge/app is usable. It is not a V0–V4
   dependency; it is cheap and settles the question.
2. Implement **observation** regardless of the outcome; it is useful and does
   not depend on the control path.
3. If A exists, implement A. It preserves the Smoke X4's own control loop and
   avoids new power hardware.
4. If A does not exist, do not smuggle in a half-working RF guess. Decide
   whether B is in the MVP. If it is, treat it as a hardware milestone with its
   own enclosure and safety review. If not, ship C with a named decision.

The project should not claim "set target" in release notes until one of these is
true and tested on a real fan.

## 8.6 Contract

The BLE contract reserves the fields now so observation can ship and control can
be added without a wire break:

- `info.caps` b0 `billows_observe`, b1 `billows_control`.
- `live.flags` b2 `billows_attached`, b3 `billows_output`.
- `live.billows_target_f10`.
- `config.billows_mode` (observe/control/disabled) and
  `config.billows_target_f10`.
- `control` op 6 `set_billows_target`, refused with `unsupported` when
  `caps.billows_control = 0`.

The app must render from the capabilities, not from a build-time assumption.

### Semantics

- `billows_attached` means the Smoke X4 reports a fan on channel 4. It does not
  mean the fan is currently blowing. In inline-control mode the Smoke X4 fan
  adapter is disconnected, so this bit may be false even while the bridge drives
  the fan; the UI must show the control mode as the primary truth.
- `billows_output` is only set when the **bridge** is driving an output. In
  observe mode or RF-control mode it is false, and the app must not interpret
  false as "fan off" — the Smoke X4's output is not observable.
- `billows_target_f10` is the **derived** observed target in observe mode, or
  the bridge's commanded target in control mode. Label the source in the UI.
- `billows_mode = control` is refused if the firmware has no control path.
- If the target relation is not validated, `billows_target_f10 = 0` and the UI
  shows `—`; it does not guess 225 °F or `max`.

## 8.7 Safety requirements for any control path

These apply to A and B, with B carrying the electrical ones:

1. **Fail off.** No valid pit reading for 120 s, invalid target, boot, crash, or
   brownout → fan output off.
2. **Never drive both controllers.** If the bridge controls the fan, the Smoke
   X4 fan adapter's control path must be disconnected. Two control loops
   fighting over one fan is not a supported configuration.
3. **Range check.** Target 32–572 °F; reject NaN/negative/out-of-range.
4. **No arbitrary transmit.** If A is implemented, only the exact target-set
   frame, only on the paired operating frequency, only within 902–928 MHz.
5. **No control while unpaired.** The bridge must know the Smoke X4 channel and
   be receiving valid probe 4 data.
6. **Visible state.** The OLED and app show `control`, target, and the bridge's
   own output when it has one. They never claim to know the Smoke X4's fan duty.
   A silent controller is not acceptable.
7. **Hardware protection.** Fuse, high-side switch, flyback/snubber, strain
   relief, and a connector keyed so 12 V cannot be plugged into the board.
8. **Bench first.** A real fan, a real smoker, and a supervised cook before an
   unattended one.

## 8.8 Test plan

### Observation (no control)

Bench only; the air probe is at room temperature and the fan is left
unobstructed. No cook is required.

- [ ] Attach a Billows to a real Smoke X4; confirm `billows_attached` flips.
- [ ] Detach it; confirm the flag clears and the target becomes unknown.
- [ ] Set 225 °F on the Smoke X4; capture the state packet; confirm the target
      field and units.
- [ ] Change to 250 °F; confirm the field follows.
- [ ] Flip °F/°C; confirm the target converts correctly.
- [ ] Confirm the app and OLED show the target read-only when
      `caps.billows_control = 0`.
- [ ] Confirm no "fan running" claim is made.

### RF control (only if A)

- [ ] Passive capture shows a repeatable command frame.
- [ ] Decode target values across 200/225/250/275 °F.
- [ ] The bridge sends only that frame; a host test asserts no other TX path.
- [ ] The stock receiver and the Smoke X4's own fan mode still work.
- [ ] The target survives a bridge reboot; the app reads it back.
- [ ] A malformed/out-of-range target is refused without transmitting.

### Inline controller (only if B)

- [ ] 12 V fan runs from the bridge's switch; no 12 V reaches the ESP32.
- [ ] Fan is off at boot, on invalid probe, on target invalid, and on brownout.
- [ ] Target holds within ±15 °F over a 2 h bench run with a real probe.
- [ ] A disconnected probe turns the fan off within 120 s.
- [ ] The switch and wiring stay below their thermal ratings.
- [ ] The enclosure keeps mains/12 V separated from the board and the user.
- [ ] A supervised cook, then an unattended cook with the phone away.

## 8.9 If B is chosen: inline controller reference design

This is a reference, not a build instruction. It exists so the cost and safety
work are visible before someone approves "set target" as a firmware task.

### Minimum bill of materials

| Part | Requirement |
|---|---|
| High-side or low-side switch | Logic-level MOSFET / load switch rated for 12 V and the fan's inrush; gate pulled to the off state |
| Fuse | Inline on the 12 V feed, sized above steady current and below wiring rating |
| Flyback/snubber | Across the fan/load if the fan is inductive or generates back-EMF |
| 12 V input | The existing Billows 12 V adapter or battery bank; do not derive 12 V from the ESP32 |
| Fan connector | Keyed/relieved; cannot be plugged into the board |
| Enclosure | Separate from the bridge or a new case; keeps 12 V and mains away from the user and the ESP32 |
| Grounding | ESP32 ground and 12 V return meet only at the intended switch point; no 12 V on GPIO |

### Wiring concept (low-side example)

```
12V+ ── fuse ──────────────► Billows fan +
12V- ──────────────► MOSFET drain
                         MOSFET source ──► 12V- / ground
ESP32 GPIO ── 10k pulldown ──► MOSFET gate
ESP32 GND ──────────────────── 12V- (common)
```

A high-side switch is preferable if the fan's USB-C shell/ground must stay at
0 V; it needs a gate driver or a P-channel + NPN level shifter. The chosen
topology must be reviewed against the fan's actual input before connection.

### Control behavior

- On/off only; do not PWM the 12 V rail unless the fan is proven to accept it.
- 1 s control tick; a 10 s duty window with a minimum 1 s on-time.
- PI or bang-bang with a deadband; the exact loop is tuned on a real smoker.
- The app's target is the setpoint; probe 4 is the feedback.
- The OLED/app show `control`, target, and output state.
- Fail-off rules in §8.7 are mandatory.

### What this changes about the product

The bridge is no longer only a gateway for Billows; it becomes the fan
controller. The Smoke X4's own fan mode is not used. This must be stated in the
UI, the README, and the release notes. It is a legitimate MVP choice only if the
owner accepts the extra hardware and safety work.

## 8.10 Open questions

| # | Question | Needed for |
|---|---|---|
| BQ1 | Does the receiver transmit anything besides the sync ACK? | Option A |
| BQ2 | What changes in the state packet when the target changes? | Observation target |
| BQ3 | Is the target probe 4 `max` on an X4? | Observation target |
| BQ4 | Is the fan adapter's control input a simple PWM/analog/on-off signal? | Option B |
| BQ5 | What is the fan's inrush/steady current? | Option B hardware |
| BQ6 | Can the bridge control the fan while the Smoke X4 remains connected to the adapter? | Option B wiring |
| BQ7 | Does the Smoke X4 re-assert its own target and fight the bridge? | Option B control |
| BQ8 | Does a target change require the Smoke X4 to be in fan mode? | A and B |

Until these are answered, the honest product statement is:

> **Billows:** attached/status and observed target are supported. App setpoint
> control is available only on builds where the control path has been validated
> and the capability bit is set.
