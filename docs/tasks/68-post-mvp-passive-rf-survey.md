# T68 — Post-MVP: passive RF survey for additional Billows data

## Goal
A receive-only survey documents whether the Smoke X4, fan adapter, or Billows emits any additional displayable telemetry. If nothing new exists, the question closes and observation stays as shipped, with no control path added.

## Context (read first)
- **Post-MVP only.** Do not run this task before T67 (final acceptance audit) completes; it does not gate the release.
- Design: [08 §8.9](../design/08-billows.md); open questions BQ4/BQ5 in [08 §8.10](../design/08-billows.md).
- Original verification: **B** (bench) · **board:** yes · **status:** post-MVP.
- Depends on T59, the exit gate for the T56–T59 observation group.
- This is a passive data survey, not a control investigation. There is no transmitter, replay, or fuzzing.

## Scope
- [ ] Survey for a fan-mode flag, duty, or fan-running status in the state packet.
- [ ] Check whether the target appears in another field or in the trailing bytes.
- [ ] Check whether the fan adapter or Billows emits any RF telemetry.
- [ ] Check whether base-side menu actions change the state packet beyond the known fields.
- [ ] Check whether any receiver→base traffic exists in a passive capture; public docs say the receiver has no setpoint controls, so expect none.
- [ ] Commit captures to `protocol/fixtures/lora/`.
- [ ] Write a short report recording what was found.
- [ ] If nothing new exists, close the question and keep observation as-is.

## Out of scope
- Billows setpoint control (RF command or inline fan controller) — outside MVP; no task owns it. This task adds no control path.
- Any transmitter, replay, or fuzzing — outside MVP; no task owns it.
- Changing setpoints mid-cook just to capture — outside MVP; no task owns it.
- Displaying any newly found field or shipping new Billows features — no task owns it; this task produces evidence and a report only.
- Re-running the T59 bench gate.
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- Receive only. No transmitter, no replay, no fuzzing.
- Do not change setpoints mid-cook just to capture.
- Keep the existing T56 evidence intact; add captures, do not rewrite the validated relation.
- Record captures and findings in `protocol/fixtures/lora/` and a short report, as required by [08 §8.9](../design/08-billows.md).
- If no additional field exists, close the question and keep observation as-is. That is a successful outcome.
- The honest product statement remains: the bridge shows whether a Billows is attached and, when the RF field is validated, the target set on the Smoke X4; set the target on the Smoke X4.

## Done when
- [ ] A short report records what was found.
- [ ] Captures are committed to `protocol/fixtures/lora/`.
- [ ] If nothing new exists, the question is closed and observation is unchanged.
- [ ] No control path, transmitter, replay, or fuzzing code is added.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
