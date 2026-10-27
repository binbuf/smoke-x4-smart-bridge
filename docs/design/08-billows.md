# 08 — Billows

**Decision:** the MVP is **observation only**. Billows setpoint control is out of
scope. The signed record is [`../billows-decision.md`](../billows-decision.md).

## 8.1 What a Billows is

The ThermoWorks Billows is a 12 V variable-airflow fan used to hold a smoker at a
target temperature. It connects to a compatible ThermoWorks controller. On a
Smoke X4 it uses **channel 4**; the Smoke X4 interprets channel 4 as the pit/air
probe and runs its own fan-control loop.

From ThermoWorks' instructions:

- The fan is powered by 12 V through a fan adapter; the adapter plugs into the
  Smoke X4.
- The air probe must be in channel 4 or the fan will not run.
- The set temperature is adjusted **on the Smoke X4** with CH/SET/up/down.
- Fan mode automatically sets high/low alarms at ±25 °F around the setpoint, and
  those alarms cannot be adjusted in fan mode.
- The fan's actual on/off duty is not exposed as a number.

The Smoke X4 state broadcast exposes:

- `billows_attached` — trailing field, non-zero when a Billows is connected.
- Probe 4's `max`/`min` — the fan-mode setpoint relation is still unproven; one of
  them may carry the target, or the target may be derivable from them. This is a
  **decode** question, not a control question.

## 8.2 What the bridge can and cannot do

The bridge is a listener. It receives the same one-way state broadcast the stock
receiver receives. It transmits exactly one packet in its lifetime: the pairing
ACK. It has no channel to the Smoke X4's buttons, UI, or fan-control firmware.

| Claim | What it needs | MVP status |
|---|---|---|
| Show attached/status | Decode the broadcast | **Supported** |
| Show the target set on the Smoke X4 | Validate the probe-4 field relation | **Supported when validated; otherwise `—`** |
| Set the target from the app | A command path to the Smoke X4 | **Not possible with the documented product; out of scope** |
| Show fan duty/output | A telemetry field that does not exist today | **Not supported; post-MVP RF survey only** |

## 8.3 Why "set target" is not an MVP feature

ThermoWorks documents the limitation directly. From
[Signals vs Smoke X4](https://help.thermoworks.com/knowledge-base/signals-vs-smoke-x4/):

> While Smoke X includes control circuitry to run the optional Billows fan, you
> cannot change the temperature set points or the Billows fan via a Smoke X
> Receiver, as you can when you are using Signals with the ThermoWorks app.

The [Smoke X4 receiver instructions](https://www.manualslib.com/manual/1976553/Thermoworks-Smoke-X4.html)
confirm the receiver only has power/backlight, VOL, and SYNC controls; it displays
temperatures and alarm settings and updates every 30 s. It has no CH/SET/up/down.
The [Billows Smoke X setup guide](https://help.thermoworks.com/knowledge-base/billows-set-up-smoke-x/)
puts set-temperature entry on the Smoke X base itself.

The difference is product-level, not a firmware bug the bridge can bypass:

- **Signals** has Wi-Fi/Bluetooth and the ThermoWorks app, so the app can change
  the Billows set temperature remotely.
- **Smoke X4** is RF-only between base and receiver. Its receiver is a display,
  not a remote control.

The bridge is another display. Without a documented or observed command frame,
there is nothing to emulate. The existing G-Two reference and the real captures
show only the sync ACK as bridge→Smoke X4 traffic.

The control options remain documented in [§8.7](#87-deferred-control-options-post-mvp)
for a future decision, but the MVP does not implement them.

## 8.4 MVP behaviour: observation only

The MVP shall:

- Decode `billows_attached` and expose it in `live.flags`.
- Decode the candidate target field and expose `live.billows_target_f10` only
  when T56 has validated the relation; otherwise return `0` (unknown).
- Show a Billows card on Live and a page on the OLED **only when a Billows has
  been detected**; no zero or fake target when absent.
- Say "Set on the Smoke X4" wherever the target is shown.
- Never claim the fan is running, the duty cycle, or the bridge output.
- Advertise `caps.billows_observe = 1` and `caps.billows_control = 0`.
- Keep `set_billows_target` reserved and always answer `unsupported`.
- Keep the only LoRa TX path the pairing ACK. No Billows TX path exists.

The app and OLED must render from the capability bits, not from a build-time
assumption. A future control build may set `billows_control = 1`; this MVP app
must not offer a control affordance when it is `0`.

### Copy

| Context | Copy |
|---|---|
| Attached, target known | `Billows detected · Target 225 °F · Set on the Smoke X4` |
| Attached, target unknown | `Billows detected · Target — · Set on the Smoke X4` |
| Detected earlier, now missing | `Billows not detected` (one notice, not repeated per screen) |
| Never detected | No Billows card/page; no empty placeholder |

## 8.5 Target field validation (T56)

The target relation is captured passively; no setpoint is changed during a cook.

1. Attach a Billows to a real X4 with the air probe at room temperature and the
   fan unobstructed. No cook is required.
2. Capture state packets at 225, 250, and 275 °F, changing the target on the
   Smoke X4 base between captures.
3. Record probe 4's `max` and `min` at each target. Derive whether the target is
   `max`, `max − 25`, the midpoint, or another relation.
4. Detach the Billows and confirm `billows_attached` clears.
5. Store the captures in `protocol/fixtures/lora/` and record the result in
   [`../billows-decision.md`](../billows-decision.md) and
   [`../hardware-verified.md`](../hardware-verified.md).

If the relation is not confirmed, the target stays unknown. The attached flag is
independently useful and ships regardless.

There is no requirement to press receiver buttons or hunt for a command frame in
the MVP. That is post-MVP research ([§8.9](#89-post-mvp-passive-rf-survey)).

## 8.6 Contract

The BLE contract reserves the fields so observation can ship and control can be
added later without a wire break:

- `info.caps` b0 `billows_observe` (1), b1 `billows_control` (**0 in the MVP**).
- `live.flags` b2 `billows_attached`; b3 `billows_output` is **reserved and
  always 0** in the MVP.
- `live.billows_target_f10` — observed target, `0` = unknown.
- `config.billows_mode` and `config.billows_target_f10` — **reserved for a future
  control build**; the MVP writes neither and the app does not show a control UI.
- `control` op 6 `set_billows_target` — reserved; always returns `unsupported`
  while `caps.billows_control = 0`.

### Semantics

- `billows_attached` means the Smoke X4 reports a fan on channel 4. It does not
  mean the fan is currently blowing.
- `billows_target_f10` is the **observed** target set on the Smoke X4. Label the
  source as the Smoke X4; never present it as a bridge command.
- `billows_output` is always false in the MVP. The app must not interpret it as
  "fan off"; the Smoke X4's output is not observable.
- `billows_target_f10 = 0` means unknown. The UI shows `—`; it does not guess
  225 °F or `max`.
- `billows_mode` is not a user setting in the MVP. A write that requests
  `control` is refused with `unsupported`.

## 8.7 Deferred control options (post-MVP)

Nothing in this section is in the MVP. It is kept so a future decision does not
start from zero. Reopening it requires a new decision record, a real Billows, and
the safety/legal review below.

### A. A safe RF command exists

This requires a capture of a well-formed command that changes the Smoke X4
setpoint, with a repeatable before/after state change. Public documentation and
all captures so far show no such frame. If one is ever found:

- implement only the exact target-set operation, with a hard allow-list and
  range check;
- never transmit during a cook except that operation;
- re-verify the stock receiver and the Smoke X4's own fan mode;
- review legal/regulatory implications before shipping.

### B. Inline fan controller

The bridge drives the 12 V fan directly; the Smoke X4 fan adapter is
disconnected. This is a hardware product change, not a firmware checkbox. It
needs a fuse, high-side switch, flyback/snubber, keyed connector, separate
enclosure, thermal separation, and a fail-off controller. The ESP32 must never
see 12 V on a GPIO.

The control algorithm, if this path is ever chosen:

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

The 30 s Smoke X4 cadence is slow for tight control. Document a realistic
±10–15 °F band; do not promise ±1 °F.

### Safety requirements if A or B is ever reopened

1. **Fail off.** No valid pit reading for 120 s, invalid target, boot, crash, or
   brownout → fan output off.
2. **Never drive both controllers.** Disconnect the Smoke X4 fan adapter if the
   bridge drives the fan.
3. **Range check.** Target 32–572 °F; reject NaN/negative/out-of-range.
4. **No arbitrary transmit.** If A is implemented, only the validated frame, only
   on the paired frequency, only within 902–928 MHz.
5. **No control while unpaired.** The bridge must know the channel and be
   receiving valid probe-4 data.
6. **Visible state.** The OLED and app show control mode, target, and the bridge's
   own output when it has one. They never claim to know the Smoke X4's fan duty.
7. **Hardware protection.** Fuse, high-side switch, flyback/snubber, strain
   relief, and a connector keyed so 12 V cannot be plugged into the board.
8. **Bench first.** A real fan, a real smoker, and a supervised cook before an
   unattended one.

## 8.8 Test plan

### Observation (MVP)

Bench only; the air probe is at room temperature and the fan is left unobstructed.
No cook is required.

- [ ] Attach a Billows to a real Smoke X4; confirm `billows_attached` flips.
- [ ] Detach it; confirm the flag clears and the target becomes unknown.
- [ ] Set 225 °F on the Smoke X4; capture the state packet; confirm the target
      field and units.
- [ ] Change to 250 °F; confirm the field follows.
- [ ] Flip °F/°C; confirm the target converts correctly.
- [ ] Confirm the app and OLED show the target read-only when
      `caps.billows_control = 0`.
- [ ] Confirm no "fan running" or duty claim is made.
- [ ] Confirm the only LoRa TX path is the pairing ACK.

### Control (not in MVP)

Do not run these until A or B is separately approved.

- [ ] A: passive capture shows a repeatable command frame.
- [ ] A: decode target values across 200/225/250/275 °F.
- [ ] A: a host test asserts no other TX path.
- [ ] B: 12 V fan runs from the bridge's switch; no 12 V reaches the ESP32.
- [ ] B: fan is off at boot, on invalid probe, on target invalid, and on brownout.
- [ ] B: a supervised cook, then an unattended cook with the phone away.

## 8.9 Post-MVP passive RF survey

The useful follow-up is **receive-only**: learn whether the Smoke X4 broadcast,
the fan adapter, or the Billows emits anything else we can display.

Candidate questions:

- Does the state packet carry a distinct fan-mode flag or duty/status field?
- Does the target appear in more than one probe field, or in the trailing bytes?
- Does the fan adapter or Billows emit any RF at all, and on what frequency?
- Do base-side menu actions change the state packet beyond the known fields?
- Is there any receiver→base traffic in a passive capture? (Public docs say the
  receiver has no setpoint controls, so this is expected to be empty.)

Rules:

- Receive only. No transmitter, no replay, no fuzzing.
- Do not change setpoints mid-cook just to capture.
- Record captures and findings in `protocol/fixtures/lora/` and a short report.
- If no additional field exists, close the question and keep observation as-is.

## 8.10 Open questions

| # | Question | Needed for | Status |
|---|---|---|---|
| BQ1 | Does the receiver transmit anything besides the sync ACK? | Any future RF control | **Answered by product docs: no setpoint controls on the receiver. Passive confirmation is post-MVP.** |
| BQ2 | What changes in the state packet when the target changes? | Observation target | T56 passive capture |
| BQ3 | Is the target probe 4 `max`, `max − 25`, midpoint, or another field? | Observation target | T56 passive capture |
| BQ4 | Does the state packet expose fan duty or a fan-running flag? | Extra observation | Post-MVP passive survey |
| BQ5 | Does the fan adapter or Billows emit any RF telemetry? | Extra observation | Post-MVP passive survey |
| BQ6 | What is the fan's inrush/steady current? | Future inline controller | Deferred with option B |

Until BQ2/BQ3 are answered, the honest product statement is:

> **Billows:** the bridge shows whether a Billows is attached and, when the RF
> field is validated, the target set on the Smoke X4. Set the target on the
> Smoke X4. App control is not supported.
