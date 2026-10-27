# T56 — Billows observation evidence (passive)

## Goal
A committed passive capture set proves whether a real Billows is reported by the Smoke X4 broadcast and whether probe 4 carries the target. The result is recorded in the decision and hardware records so firmware and app never guess a setpoint.

## Context (read first)
- Design: [08 §8.5](../design/08-billows.md); related behaviour in [08 §8.1](../design/08-billows.md) and [02 §2.6](../design/02-smoke-x-protocol.md).
- Original verification: **B** (bench) · **board:** yes.
- Depends on T09.
- Run this milestone after T55 (M4); M5 is not a V0–V4 dependency.
- This capture is **bench-only**: attach the Billows to a real X4 with the air probe at room temperature; the fan may run continuously because the probe is below target. Keep it unobstructed. A cook is not required. No setpoint is changed during a cook.
- This task is receive-only; do not press receiver buttons hunting for a command and do not transmit.

## Scope
- [ ] Attach a Billows to a real X4 with the air probe at room temperature; confirm `billows_attached` is non-zero.
- [ ] Capture state packets at 225, 250, and 275 °F, changing the target on the Smoke X4 base between captures.
- [ ] Record probe 4's `max` and `min` at each target.
- [ ] Decide whether the target is `max`, `max − 25`, the midpoint, or another relation.
- [ ] Detach the Billows; confirm `billows_attached` clears.
- [ ] Commit the captures to `protocol/fixtures/lora/`.
- [ ] Record the result in [`../billows-decision.md`](../billows-decision.md) and [`../hardware-verified.md`](../hardware-verified.md).

## Out of scope
- Any LoRa transmission, replay, or fuzzing — outside MVP; no task owns it. T68 is a receive-only post-MVP survey.
- Billows setpoint control (RF command or inline fan controller) — outside MVP; no task owns it. T68 does not add a control path.
- Firmware decode and capability bits (→ T57), app surfaces (→ T58), and the milestone bench verification (→ T59).
- A cook; none is required.
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- Receive only. Do not transmit, replay, or fuzz, and do not press receiver buttons hunting for a command.
- Change the setpoint only on the Smoke X4 base between captures, never during a cook.
- Candidate relations are `max`, `max − 25`, the midpoint, or another relation; record probe 4's `max` and `min` at each of 225, 250, and 275 °F.
- An unknown relation is acceptable and must be recorded as unknown; a guess is not. If unknown, T57 keeps `billows_target_f10 = 0` and the UI shows `—`.
- Keep the fan unobstructed; the probe stays at room temperature for the whole capture.
- Store raw captures in `protocol/fixtures/lora/` so T57 and later reviews can re-decode the same bytes.

## Done when
- [ ] Attached/detached is proven.
- [ ] The target relation is either confirmed with two or more setpoints or explicitly marked unknown.
- [ ] Captures are committed to `protocol/fixtures/lora/`.
- [ ] The result is recorded in [`../billows-decision.md`](../billows-decision.md) and [`../hardware-verified.md`](../hardware-verified.md).
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
