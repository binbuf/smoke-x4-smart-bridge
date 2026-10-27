# T25 — Bench prep: pair, stock receiver, power cut

## Goal
Prepare and automate the T25 bench procedure so the first human sitting can run
it without improvising. This task does **not** claim real-hardware evidence; it
produces the checklist, the serial-capture path, and the host proof for the code
paths that the sitting will exercise. The physical run is executed at **T37**.

## Context (read first)
- [10 §10.3 B1](../design/10-test-and-release.md) — the radio and storage bench matrix.
- [02 §2.7](../design/02-smoke-x-protocol.md) — pairing rules, including that the stock receiver is independent.
- [04 §4.3](../design/04-data-and-storage.md) — power-loss recovery guarantees.
- [04 §4.4](../design/04-data-and-storage.md) — canonical time/temperature rules.
- `docs/hardware-verified.md` — where the T37 result rows live.
- `firmware/bench/t10_probe/tools/capture.py` — the existing serial capture helper.
- **Verification:** H (host/CI). **Board:** no. Physical proof is **T37**.
- Depends on T16, T19, and T21.

## Scope
- [ ] Write a short bench checklist for T37 covering: real X4 pair, stock
      receiver still updating, USB power cut mid-recording, detach/reattach, and
      °F/°C flip.
- [ ] Make each step produce a serial log or a committed evidence artifact; no
      verbal-only results.
- [ ] Reuse `firmware/bench/t10_probe/tools/capture.py` (or a product-serial
      equivalent) so T37 can capture the run without writing new tooling.
- [ ] Add or confirm host tests for torn-tail recovery, detached sentinel, and
      canonical °F conversion.
- [ ] Add the T37 evidence rows to `docs/hardware-verified.md` as ⏳ with T37 as
      owner; do not mark them passed.
- [ ] Commit the checklist and supporting changes.

## Out of scope
- Actually pairing the X4, pulling USB power, detaching a probe, or flipping
  units — all physical and all executed at **T37**.
- App-driven unpair/re-pair: **T55**.
- Host FSM testing of the T16 pairing states → T16.
- Full ring rotation or `min_seq`/`max_seq`/`generation` over BLE → T39/T46.
- A 30-minute cadence run and page walk → T37 (physical), prepared by T26.
- 24 h soak and field cooks → T61/T63.
- Billows observation → T56–T60.
- Any Wi-Fi/HTTP/OTA test: outside MVP; no task owns it.

## Design notes
- This task is deliberately **not** a bench sitting. The unattended run cannot
  press the X4's SYNC control, unplug power, or detach a probe.
- The checklist is the deliverable: every T37 step names the command, the
  artifact, and the pass/fail rule.
- Do not pre-fill `docs/hardware-verified.md` with PASS. The rows stay ⏳ until
  T37 records real evidence.
- The stock receiver is independent of the bridge. A T37 failure there is a real
  failure, not a side effect to waive.

## Done when
- [ ] The T37 bench checklist is committed and covers pair, stock receiver,
      power cut, detach/reattach, and °F/°C.
- [ ] Every checklist step names its evidence artifact.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] `docs/hardware-verified.md` has ⏳ rows owned by T37 and no false PASS.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
