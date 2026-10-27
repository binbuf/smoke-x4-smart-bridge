# T61 — 24-hour soak

## Goal
A 24-hour run on the release image produces a committed stats trace and report against criteria fixed before the run. It proves the bridge stays stable and within memory bounds through advertising, BLE, logging, and periodic sync.

## Context (read first)
- Design: [10 §10.4](../design/10-test-and-release.md); board bring-up and bench context in [10 §10.3 B0](../design/10-test-and-release.md).
- Original verification: **B** (bench) · **board:** yes.
- Depends on T37, T46, T55, T59.
- The software under test must already be the release candidate image; T64 and T65 own the app and firmware release artifacts.
- Run on USB power first, then on the pack.

## Scope
- [ ] Run the release image for 24 h with real samples (or a fixture transmitter), BLE advertising, a phone connected for part of it, OLED asleep, and periodic sync.
- [ ] Keep a phone connected for at least 4 h of the run.
- [ ] Capture `heap_free`, `heap_min`, stack margins, packet counters, storage, and reconnect counts.
- [ ] Apply the fixed criteria in [10 §10.4](../design/10-test-and-release.md).
- [ ] Absorb the T37 physical residuals that need a long run: a 30-minute
      cadence/RSSI/gap segment with the OLED awake then asleep, the stock
      receiver kept alongside, a probe detach/reattach, an X4 °F/°C flip, and
      a deliberate USB power cut with log recovery. Record each with a capture
      and a dated result.
- [ ] Commit the raw stats trace, the cadence segment and a short report.
- [ ] Turn each failure into a named follow-up task.

## Out of scope
- The field cook and overnight cook (→ T63).
- The dedicated power/current and 24 h pack-runtime measurements (→ T62); the soak's battery row references that evidence.
- The app release build (→ T64) and firmware release build (→ T65).
- Lowering a failed threshold after the run — outside this task; a failure is a finding and gets a named task.
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, multi-bridge, and Billows setpoint control — outside MVP; no task owns them.

## Design notes
- Conditions: real Smoke X4 sending (or a fixture transmitter), BLE advertising for most of the run, a phone connected for at least 4 h, OLED asleep, Billows observation if available, and the app syncing periodically.
- Criteria are fixed before the run:

  | Metric | Pass |
  |---|---|
  | Reboots/panics | 0 |
  | `heap_free` floor | ≥ 80 KB |
  | `heap_free` slope | ≥ −256 B/h |
  | `heap_min` | ≥ 64 KB |
  | Missed samples | 0 unexplained; any gap has a radio cause |
  | Log recovery | clean after the run |
  | BLE reconnects | bounded; no storm |
  | App sync | catches up without duplication |
  | Battery | ≥ 24 h on the pack with OLED sleep (separate run if needed) |

- If a criterion fails, that is a finding, not a reason to lower the bar after the fact.
- Capture raw counters rather than a hand-written summary so the trace can be re-checked.
- The T37 cadence residual is a **30-minute segment at the start of the run**,
  with the OLED awake for the first part and asleep for the rest. Generate
  `CADENCE-REPORT.md` with `tools/bench/cadence_report.py`; every >90 s gap needs
  a real cause. The full 24 h trace supplies the longer stability evidence.
- The T37 power-cut residual is a deliberate USB removal **after** the cadence
  segment, before the 24 h clock starts. It proves earlier records survive; the
  soak itself then starts from a clean boot.
- The probe detach/reattach and X4 °F/°C flip can be done during the cadence
  segment. Record the exact times and confirm the stored values stay canonical
  Fahrenheit with the detached sentinel, never zero.
- The stock receiver must stay powered and updating for the whole run; a freeze
  is a failure even if the bridge keeps recording.

## Done when
- [ ] The trace and report are committed.
- [ ] Every fixed criterion is marked pass or fail with evidence.
- [ ] Failures become named tasks, not silently lowered thresholds.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
