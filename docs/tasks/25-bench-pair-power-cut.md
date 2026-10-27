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

**Status:** done (host/CI). No board run was performed; physical evidence is
T37.

### What landed

- `artifacts/bench/T37/CHECKLIST.md` — step-by-step T37 procedure for real X4
  pairing, stock receiver, USB power cut, detach/reattach and °F/°C. Each step
  names its capture command, artifact filenames and pass/fail rule.
- `artifacts/bench/T37/README.md` — evidence manifest (settings, time, what
  changed, artifacts, result). All result cells are `⏳`.
- `docs/hardware-verified.md` — radio/storage rows now name T37 as owner and
  link the checklist; the combined four-probe/detached/units row was split into
  separate rows. No PASS was added.
- `docs/design/10-test-and-release.md` §10.3 B1 — links the checklist.
- `docs/design/03-firmware-architecture.md` §3.6 — documents the new stored
  sample log.
- `firmware/components/sample_pipe/sample_pipe_esp.c` — after a successful
  append, logs `sx4.sample: stored seq=<n> t=<f10>,... flags=0x<hex>`; on
  failure logs `sx4.sample: not stored: <err>`. This gives T37 serial evidence
  for canonical °F, the detached sentinel and Celsius provenance instead of
  adding new bench tooling.
- `firmware/bench/t10_probe/tools/capture.py` — creates the `--out` parent
  directory and turns a USB power-cut `SerialException` into a
  `# serial error: ...` line with a clean close.
- `docs/progress/T25.md` — facts and follow-ups.

### Deviations

- No new ADR: the task adds no architectural decision, only a bench procedure
  and a one-line observability log.
- No new host suites: torn-tail, detached-sentinel and canonical-°F coverage
  already existed and was confirmed (test names and assertions are listed in
  `docs/progress/T25.md`).
- The checklist's power-cut step requires the pack to be disconnected (or both
  rails switched); pulling USB while the pack is connected is not a power cut.

### Check results

```text
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# 100% tests passed, 16/16 (includes sample-log-flash, sample-pipe, ui-render,
# sx-protocol, sample-log-rec)
```

`python -m py_compile firmware/bench/t10_probe/tools/capture.py` — ok.

Firmware build (no flash, board gate is T37) — see `docs/progress/T25.md`.

### Remaining work

- **T37:** execute `artifacts/bench/T37/CHECKLIST.md`, fill
  `artifacts/bench/T37/README.md`, commit the logs/photos, then replace the
  T37 `⏳` rows in `docs/hardware-verified.md` with dated results and links.
- **T26:** add the cadence/page-walk captures to the same sitting.
- Out of scope and still open: app-driven unpair/re-pair (T55), ring rotation
  and BLE `min_seq`/`max_seq`/`generation` (T39/T46).
