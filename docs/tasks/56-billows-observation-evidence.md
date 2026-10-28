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
- [x] Attach a Billows to a real X4 with the air probe at room temperature; confirm `billows_attached` is non-zero.
- [x] Capture state packets at 225, 250, and 275 °F, changing the target on the Smoke X4 base between captures.
- [x] Record probe 4's `max` and `min` at each target.
- [x] Decide whether the target is `max`, `max − 25`, the midpoint, or another relation.
- [x] Detach the Billows; confirm `billows_attached` clears.
- [x] Commit the captures to `protocol/fixtures/lora/`.
- [x] Record the result in [`../billows-decision.md`](../billows-decision.md) and [`../hardware-verified.md`](../hardware-verified.md).

## Out of scope
- Any LoRa transmission, replay, or fuzzing — outside MVP; no task owns it. T68 is a receive-only post-MVP survey.
- Billows setpoint control (RF command or inline fan controller) — outside MVP; no task owns it. T68 does not add a control path.
- Firmware decode, capability bits and app surfaces (→ T57), and the milestone bench verification (→ T59).
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
- [x] Attached/detached is proven.
- [x] The target relation is either confirmed with two or more setpoints or explicitly marked unknown.
- [x] Captures are committed to `protocol/fixtures/lora/`.
- [x] The result is recorded in [`../billows-decision.md`](../billows-decision.md) and [`../hardware-verified.md`](../hardware-verified.md).
- [x] Hand-off below filled in.

## Hand-off

**Landed.** A passive capture on the already-flashed T55 release image
(`02E2E2B4…3340F61F6`, not reflashed) with a real Billows on a real X4. The
fixture is `protocol/fixtures/lora/x4-billows-225-250-275.loralog` with
`x4-billows-225-250-275.report.md` and a provenance row in that directory's
`README.md`. Raw serial evidence is
`artifacts/bench/T56/serial-t56.log`; the serial log → `loralog` converter is
`tools/bench/product_serial_to_loralog.py`.

**Result.** The target relation is **confirmed at three setpoints**: probe 4
`max` = the base target (225/250/275 °F), `min` = 0, `billows_attached` = 1. It
is not `max − 25` and not the midpoint. Detaching the Billows cleared the flag
to 0 and returned probe 4 to the non-fan defaults `max=160`, `min=32`. The
target is only meaningful while `billows_attached` is set.

**Deviations.**

- The product image already logs each accepted frame with payload and RSSI/SNR,
  so this sitting used a plain serial capture instead of flashing the T10
  capture probe. Nothing was transmitted; the existing X4 pairing was reused and
  no SYNC gesture or pairing ACK occurred in this session.
- The target was set to 250 °F first, then 225 °F, then 275 °F. All three are
  present with four or more frames each; the order has no bearing on the
  relation.
- Probe 4 briefly reported `state=3` on the frame immediately before the first
  attached frame (the channel-4 probe was disturbed while the Billows was
  plugged in). It returned to `state=0` and does not affect the target result.
- The trailing `new_alarm` field was `8` and header field 3 was `2` on the first
  frame after each menu-driven target change, then back to `0`/`1`. That is a
  menu/alarm edge, not target data.
- All captures are °F (`units=1`); °C conversion remains a T57/T59 check.

**For T57.** Encode `billows_target_f10` from probe 4's `max` **only when
`billows_attached` is true**; otherwise keep `0` (unknown). Do not subtract 25
and do not use `min`. The fixture has both attached and detached frames to test
the gate. `caps.billows_control` stays `0`.
