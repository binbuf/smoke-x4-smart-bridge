# T46a — app: fix T46 History and connection findings

## Goal
Close the app-side defects found during the T46 full-history bench, so the M3 History and connection surfaces match the approved contract before the M4 UI gate. This task owns findings A, B, C, D, F, G, H and J from `docs/progress/T46.md`; it adds regression tests and re-checks the affected states on the real phone.

## Context (read first)
- [`docs/progress/T46.md`](../progress/T46.md) — findings A–L, evidence and the exact reproductions.
- [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) — Live, History, offline, empty and error rows this task must satisfy.
- [06 §6.6–§6.9](../design/06-app.md) — History read model, deletion, empty/error and launch/health behaviour.
- [04 §4.6–§4.7](../design/04-data-and-storage.md) — gaps, generations and the durable archive.
- `app/lib/data/history/history_archive.dart`, `app/lib/domain/cook_detection.dart`, `app/lib/features/history/history_screen.dart` — History gaps/Cooks/Summary.
- `app/lib/app/bridge_controller.dart`, `app/lib/data/ble/bridge_link.dart`, `app/lib/features/live/live_screen.dart` — launch, saved identity, blocked state and Live semantics.
- ADR [0048](design/adr/0048-history-archive-read-model.md), [0050](design/adr/0050-history-data-state-matrix.md), [0047](design/adr/0047-saved-bridge-launch-and-adapter-health.md).
- **Verify:** H · **Board:** no; T55 re-checks the bench states.
- Depends on T46; runs before T54.

## Scope

- [ ] **A — offline probe semantics.** While offline/stale, probe-tile semantics must never say `updated live`; use the last-known age and `Showing saved readings` vocabulary. Add a widget/semantics regression test.
- [ ] **B — Live sparklines.** After a cold launch with a durable archive, Live sparklines must backfill from `SampleDao` (or show the approved `No history yet` only when the archive has no rows for that probe). Do not add a second timer or sync path.
- [ ] **C — saved-Bridge identity.** The offline saved-Bridge header must not show the fixture default `A4F2`; show the saved short id, the saved name, or `—`. Add a regression test that fails if a fixture id is reachable.
- [ ] **D — blocked adapter.** Entering `ConnectionPhase.blocked` must clear the sync card and any pending sync/backfill UI; the blocked notice is the only sync surface. Add a widget test.
- [ ] **F — gap bands.** Stored gaps must be placed over the missing period, not at `detected_ms`; the `Not synced` label must render when the band is wide enough, with the permanent-loss explanation. Prefer a sequence→time mapping (from/to seq) over the detection timestamp. Add archive/chart tests for both `Not synced` and inferred holes.
- [ ] **G — Cooks and Summary sort.** Cooks and `Since cook start` must be scoped to the visible History range (or otherwise cannot show a 115-day full-ring cook or enable `Since cook start` when the range has no cook). Add full-ring and range-scoped tests.
- [ ] **H — Bridge reboot recovery.** If the Bridge reboots while the app is connected, recover live notifications and the paired X4 state without a process restart; a stale `Connected` + `Not paired` state is not acceptable. Add a link/controller test for the disconnect/reconnect path.
- [ ] **J — permanent-loss banner.** The `Some readings were lost…` banner must be scoped to the visible range, not the whole archive. Add a range test.
- [ ] Re-run `flutter analyze` and the full `flutter test` suite; keep the existing 223+ tests green.
- [ ] Re-check A–D, F–H and J on the real phone against the T46 evidence states and record before/after screenshots under `artifacts/bench/T46/fix-*` or the T55 evidence folder.

## Out of scope
- Finding E (Bridge `stats` `0 of 0`) → T47 (stats read).
- Finding I (320 dp truncations) → T54 layout/a11y gate.
- Finding K (`Live change window` not persisting across process death) → T53/T54.
- Finding L (NVS-owned generation; partition erase cannot start a new segment) → T48/T49/T52.
- `Readings`/storage counts, deletion ranges and destructive actions → T44/T52.
- New screens or design changes outside 13 §13.4.
- Firmware changes; the Bridge-side findings are T47/T48/T49/T52.

## Design notes
- Fix the data/state source, not the label: the same root cause should serve History, Live and semantics. Do not add a second archive/sync path or a new timer.
- Use `HistoryArchive`/`SampleDao` for range and gap data; `probeStatsInRange` remains the exact Summary source.
- Gap placement is a correctness issue: `gap.from_seq`/`to_seq` describe the missing period; `detected_ms` is when the app learned about it. Do not draw a loss at the detection time.
- Cooks and `Since cook start` use the visible range; an archive-wide cook list is not acceptable on a full ring.
- A blocked adapter is a named state, not a sync state: clear the sync card when the adapter blocks.
- Keep the T46 report as the reproduction record; add the before/after evidence to the Hand-off.
- Verify at 320 dp and with TalkBack once the fixes land; T54 still owns the full gate.

## Done when
- [ ] Findings A, B, C, D, F, G, H and J have regression tests that fail on the T46 builds and pass after the fix.
- [ ] `flutter analyze` is clean and the full `flutter test` suite passes.
- [ ] The affected states are re-checked on the real phone; before/after evidence is committed.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
