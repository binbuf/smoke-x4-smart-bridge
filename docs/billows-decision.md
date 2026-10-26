# Billows Control-Path Decision

**Status:** open · **Owner:** TBD · **Decision date:** TBD

This record closes [08 §8.4](design/08-billows.md#84-the-decision-gate-b50)
and [B5.0](tasks/M5-billows.md). Do not implement "set target" until this is
filled in.

## Evidence collected

Evidence from the M5 bench work can open the decision; the controlled captures
close it. A live cook is never steered just to capture.

| Capture | What it shows | Artifact |
|---|---|---|
| M5 bench capture (no cook; fan unobstructed) | attached flag, raw `max`/`min` at the displayed setpoint; provisional only | |
| Controlled: attached at 225 °F | raw `max`/`min`; target relation candidate | |
| Controlled: attached at 250 °F | raw `max`/`min`; relation follows | |
| Controlled: attached at 275 °F | confirms `max`, `max−25`, midpoint, or other | |
| Billows detached | attached flag clears | |
| Receiver buttons pressed | any receiver→base transmission? | |
| Base target changed | any command packet or wired control signal? | |
| Fan adapter control line scoped | on/off, PWM, analog, or unknown | |

## Options

| Option | Description | Cost | Risk | Decision |
|---|---|---|---|---|
| **A — RF command** | Emulate the validated target-set frame | Firmware + capture only | Regulatory/safety review; must not disturb the stock receiver | ☐ |
| **B — Inline controller** | Bridge drives the 12 V fan directly; Smoke X4 fan control disconnected | Hardware, enclosure, PID, safety | Fire/safety, 12 V wiring, extra product | ☐ |
| **C — Observation only** | Show attached/target; no setpoint | None | Does not meet the "set target" line; requires owner sign-off | ☐ |

## Decision

- Chosen option: **TBD**
- Why: **TBD**
- Target derivation if observe-only: **TBD (e.g. `max − 25`, midpoint, or unknown)**
- What changes in the app/OLED: **TBD**
- What `caps.billows_control` will be: **TBD**
- Release-note wording: **TBD**

## Sign-off

- Product owner: **TBD**
- Firmware owner: **TBD**
- Safety/hardware reviewer (required for B): **TBD**

## If C is chosen

Record the explicit scope reduction here. The release notes and README must say
"Billows observed only; set the target on the Smoke X4." The `set target` feature
is not complete until the owner accepts this cut.
