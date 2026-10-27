# T38 — Field observation: first normal cook on V0

## Goal
The V0 build is used for a normal cook with no staged changes, producing the first real field evidence on cadence, gaps, link behaviour, log continuity, battery, and UX friction. It is early dogfooding that feeds the roadmap and design assumptions, not the release acceptance cook.

## Context (read first)
- [10 §10.3 B5, §10.6](../design/10-test-and-release.md) — the field matrix and acceptance matrix.
- [02 §2.9](../design/02-smoke-x-protocol.md) — the validation corpus and capture expectations.
- [04 §4.6](../design/04-data-and-storage.md) — gaps and rotation: seq continuity is the source of truth, >90 s is missing time.
- [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) — the product states to observe in normal use.
- Design: [10 §10.3 B5, §10.6](../design/10-test-and-release.md), [02 §2.9](../design/02-smoke-x-protocol.md).
- Verify tier: **C**. Board: **yes**.
- Depends on T37.

## Scope
- [ ] Use the V0 build for a normal cook. Do not stage target changes, receiver button presses, probe detaches, or a special capture sequence.
- [ ] Pair once, let the bridge record, use the app as intended, and sync before and after the cook.
- [ ] Keep a firmware serial log if one is already running; it is optional.
- [ ] Record sample cadence, gaps, RSSI/SNR, and reconnect behaviour.
- [ ] Record firmware counters (valid/bad packets, queue drops, heap) if the build exposes them.
- [ ] Record ring-log continuity after the cook and after a power cycle.
- [ ] Record battery behaviour and any UX friction.
- [ ] Record anything that changes a design assumption.
- [ ] Commit a short field report plus screenshots (and the serial log if captured).
- [ ] Update `docs/hardware-verified.md` and the open-decisions table with what the data proves or changes.
- [ ] If a result retires or creates a risk, adjust the roadmap in the same change.
- [ ] Leave Billows unexercised; do not show or claim any Billows state while `caps.billows_observe = 0`.

## Out of scope
- Staged target changes, receiver button presses, probe detaches, and special capture sequences — deliberately excluded from this observation; protocol/Billows captures are bench-capable.
- Billows observation and validation → T56–T60 (M5); V0 hides the card while `caps.billows_observe = 0`, and Billows control is outside MVP with no owning task.
- The T63 release field cook → T63. This task and T63 are the only tasks that need an actual cook.
- The 24 h soak and full-field matrix → T61/T62.
- Wi-Fi/HTTP/OTA, cloud sync, accounts, or export — outside MVP; no task owns them.

## Design notes
- The point is to observe the product in normal use, not to run a test script. Do not introduce fixture states, lab modes, or staged protocol stimuli.
- Expected sample cadence is 30 s nominal; observed wobble during menu use is normal. A gap is a delta >90 s or a `seq` discontinuity; the report must distinguish device loss, bridge off, and app-away gaps where possible.
- `seq` continuity is the source of truth for completeness; a time delta alone does not prove a device gap.
- `unix_s = 0` / `clock_valid = 0` means the bridge clock was unknown; note estimated-time ranges rather than inventing exact times.
- Record the same fields the bench records: phone model, Android version, MTU, timings, and failure description, so the result is comparable with T37.
- Update the open-decisions table only with what the data proves; if an open unknown is untouched, leave it explicitly open rather than guessing.
- If the cook changes a design assumption or creates/retires a risk, the roadmap change belongs in the same commit.

## Done when
- [ ] The field report is committed, with screenshots and the serial log if captured.
- [ ] Each open unknown touched by the cook is advanced or explicitly left open.
- [ ] `docs/hardware-verified.md` and the open-decisions table reflect the result.
- [ ] The roadmap reflects any retired or newly created risk.
- [ ] Billows was not exercised, and no Billows state is claimed.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
