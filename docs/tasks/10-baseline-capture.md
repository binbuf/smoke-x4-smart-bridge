# T10 — Baseline capture

## Goal
Capture real Smoke X4 traffic on the bench — state frames for all four probes,
a detach/reattach, a °F/°C flip, an alarm edge, and the sync beacon/ACK — and
commit it as fixtures so the new parser can be replayed against reality.

## Context (read first)
- Design: [02 §2.9](../design/02-smoke-x-protocol.md)
- Verification: **B** (bench/board) · Board required: **yes**
- Depends on T09.
- This is a bench sitting, not a staged cook. Room-temperature probes are
  valid; the X4 broadcasts the same state whether it is cooking or sitting on
  the bench. No cook is required.

## Scope
With a real Smoke X4, on the bench (not during a live cook):

- [ ] Pair the reference/legacy firmware or a capture build.
- [ ] Record 30+ minutes of state traffic with all four probes.
- [ ] Include a detach/reattach in the capture.
- [ ] Include a °F/°C flip.
- [ ] Include an alarm edge if practical.
- [ ] Capture the sync beacon and the ACK.
- [ ] Commit the logs and a short report under `protocol/fixtures/lora/`.

## Out of scope
- Replaying the captures in a host test — the parser/harness side lands in
  T03/M1; this task supplies the fixtures.
- A staged cook or field cook — M6 / T38 field evidence.
- Billows-specific evidence — M5.
- Parser feature work beyond what the captures verify — M1.
- Changing the protocol contract — owned by T02.

## Design notes
- Bench-only: do not capture during a live cook.
- Room-temperature probes are acceptable; do not wait for a cook.
- The capture must include all four probes, a detach/reattach, a °F/°C flip,
  and (if practical) an alarm edge.
- The sync beacon and the ACK are required separate captures.
- Logs and a short report are committed together under
  `protocol/fixtures/lora/`, with provenance.
- Fixtures from T03 are the starting set; this task adds real, longer captures.
- Ongoing field evidence is gathered by T38; Billows-specific evidence is
  gathered in M5. This task neither replaces nor duplicates those.

## Done when
- [ ] The new parser can replay the captures in a host test.
- [ ] The logs and short report are committed under `protocol/fixtures/lora/`.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
