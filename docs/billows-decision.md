# Billows Control-Path Decision

**Status:** decided — **Option C, observation only** · **Decision date:** 2026-10-26

This record closes the control-path question in
[08 §8.3](design/08-billows.md#83-why-set-target-is-not-an-mvp-feature). The MVP
does not implement "set target" and does not transmit to a Billows or to the
Smoke X4 outside the pairing ACK.
[T56](tasks/56-billows-observation-evidence.md) remains open: it is the passive
capture that validates the target **relation**, which is a decode question, not
a control decision.

## Evidence

Public ThermoWorks material settles the control question without a bench capture:

| Source | What it says |
|---|---|
| [Signals vs Smoke X4](https://help.thermoworks.com/knowledge-base/signals-vs-smoke-x4/) | "While Smoke X includes control circuitry to run the optional Billows fan, you cannot change the temperature set points or the Billows fan via a Smoke X Receiver, as you can when you are using Signals with the ThermoWorks app." |
| [Billows Set Up: Smoke X](https://help.thermoworks.com/knowledge-base/billows-set-up-smoke-x/) | The Billows target is the Channel 4 set temperature on an X4 (Channel 2 on an X2). It is adjusted **on the Smoke X** with CH/SET/up/down. Fan mode fixes the high/low alarms at ±25 °F and they "cannot be adjusted in fan mode." |
| [Smoke X4 receiver instructions](https://www.manualslib.com/manual/1976553/Thermoworks-Smoke-X4.html) | The receiver has power/backlight, VOL, and SYNC controls only. It displays temperatures, high/low alarm settings, and alarm state; it updates every 30 s. It has no CH/SET/up/down and no setpoint control. |
| [Smoke X4 product page](https://www.thermoworks.com/products/smoke-x) | RF-only between base and receiver: no Wi-Fi, Bluetooth, or app. |
| [Signals product page](https://www.thermoworks.com/Signals) | Signals adds Wi-Fi/Bluetooth and the ThermoWorks app, which can change the Billows set temperature remotely. This is the product difference, not a Smoke X4 firmware bug that a listener can work around. |
| Existing RF captures and the G-Two reference | The only known bridge→Smoke X4 transmission is the pairing ACK. No command frame has been observed. |

A receiver-side control path therefore does not exist to emulate. The bridge is a
listener; without a command path it cannot set a Smoke X4 setpoint over LoRa.
The remaining control options (an inline 12 V fan controller, or a future RF
command if one is ever discovered) are hardware/post-MVP work, not MVP firmware.

## Options

| Option | Description | Cost | Risk | Decision |
|---|---|---|---|---|
| **A — RF command** | Emulate a target-set frame | Firmware + captures | No documented or observed frame; regulatory/safety review if one appears | **Deferred, post-MVP research only** |
| **B — Inline controller** | Bridge drives the 12 V fan directly; Smoke X4 fan control disconnected | Hardware, enclosure, PID, safety | Fire/safety, 12 V wiring, extra product | **Deferred, not in MVP** |
| **C — Observation only** | Show attached and the target the Smoke X4 broadcasts; no setpoint | None | Does not meet the original "set target" line; owner accepts the cut | **Chosen** ☑ |

## Decision

- **Chosen option:** **C — observation only.**
- **Why:** ThermoWorks documents that the Smoke X4 receiver cannot change set
  points or the Billows; only the base can. The bridge sees the same one-way
  broadcast as the receiver. There is no command path to emulate, and inventing
  one is unsafe and unsupported.
- **Target derivation:** the observed target remains a **decode question**, not a
  control question. The candidate is Channel 4's `max`/`min` field in fan mode.
  T56 captures 225/250/275 °F passively and records whether the target is
  `max`, `max − 25`, the midpoint, or another relation. Until that is confirmed,
  the firmware returns `billows_target_f10 = 0` and the UI shows `—`; it never
  guesses.
- **What changes in the app/OLED:** Billows is a read-only card/page shown when a
  Billows is detected. It shows attached/not attached and a validated target when
  available. Copy says "Set on the Smoke X4." There is no mode switch, target
  editor, or Set target action.
- **What `caps.billows_control` will be:** **0 in the MVP.** The reserved bit and
  `set_billows_target` op stay in the contract so a future build can add control
  without a wire break; the MVP app never sends the op and the firmware always
  answers `unsupported`.
- **Release-note wording:** "Billows observed only. The bridge shows whether a
  Billows is attached and, when the RF field is validated, the target set on the
  Smoke X4. Set the target on the Smoke X4."
- **Post-MVP:** a passive RF survey may look for additional Billows/base
  telemetry (duty, status, or a target field) to display. It is receive-only and
  cannot transmit. See [T68](tasks/68-post-mvp-passive-rf-survey.md).

## Sign-off

- Product owner: **scope directed 2026-10-26 — observation only for MVP**
- Firmware owner: **not required for C** (no control path implemented)
- Safety/hardware reviewer: **not required for C** (no fan output, no new 12 V hardware)

If A or B is ever reopened, it needs a new decision record, a real Billows, and
the safety/legal review in [08 §8.7](design/08-billows.md#87-deferred-control-options-post-mvp).

## If C is chosen

Record the explicit scope reduction here. The release notes and README must say
"Billows observed only; set the target on the Smoke X4." The `set target` feature
is not complete until the owner accepts this cut — this record is that
acceptance for the MVP.
