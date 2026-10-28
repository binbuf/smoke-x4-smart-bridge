---
verify: make app-check
---
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

### What landed

All eight app-side findings have a regression test and a fix; details in
`docs/progress/T46a.md`.

- **A — offline semantics.** `BridgeController._probeSemantics` says
  `last reading … ago, showing saved readings` whenever the link is offline and
  never `updated live`. Test: `live_screen_test` (probe semantics).
- **B — Live sparklines.** `prepareLaunch` seeds `RecentHistoryStore` from
  `SampleDao` after the newest-reading read. The seeded window ends at the
  newest saved reading when the archive is older than an hour, so a 6 h-old
  archive still shows the last recorded hour instead of `No history yet`. No
  new timer or sync path. Tests: `live_backfill_and_identity_test`.
- **C — saved-Bridge identity.** Offline launch sets `deviceName`/`deviceId`
  from the saved `bridge` row (`savedBridgeShortId`; MAC `…:82:76` → `8276`,
  unknown → `—`). The fixture `A4F2` is unreachable from that path. Test:
  `live_backfill_and_identity_test`.
- **D — blocked adapter.** `ConnectionPhase.blocked` clears `syncState` and
  progress in all three blocked entry points, and Live refuses to render the
  sync card while blocked. Tests: `live_screen_test`, `launch_connect_test`.
- **F — gap bands.** Stored gaps are mapped by `from_seq`/`to_seq` onto the
  readings that flank them (`SampleDao.samplesAroundSeq`), never by
  `detected_ms`. `Not synced` bands are labelled even when narrow; inferred
  holes stay `No signal`. Tests: `history_archive_test`,
  `history_gap_chart_test`.
- **G — Cooks / Since cook start.** Cook detection and cook-gap spans use the
  visible `[startMs, endMs)` window. A 3-day ring produces a ≤24 h cook in the
  24 h view and the sort is disabled when the range has no cook. Tests:
  `history_archive_test`.
- **H — Bridge reboot.** `BridgeLink.healthCheck` re-arms the `live`
  notification after reading `live`, recovering the paired X4 state and values
  when Android keeps the GATT link marked connected through a peripheral
  reboot. Test: `bridge_link_test` (simulated peripheral restart).
- **J — permanent-loss banner.** `missingFromBridge` comes from the same
  visible-range bands, so an old loss does not raise the banner in a loss-free
  range. Test: `history_archive_test`.

### Checks

```powershell
cd app
flutter analyze                  # No issues found
flutter test --timeout 180s      # 289 tests, all passed
# from the repository root
make app-check                   # analyze + 289 tests pass
```

The full suite grew from 223 to 289 tests; no existing test was deleted. The
two-cook archive test was widened to `twoDays` because cooks are now
range-scoped by design.

### Real-phone re-check — blocked

The new debug APK was built (`app/build/app/outputs/flutter-apk/app-debug.apk`)
and installed on the Pixel 11 Pro Fold. The device was on its lock screen when
the after-run started; `adb` could not dismiss the keyguard and no app screen
could be brought forward. No after screenshots were captured, and the bogus
lock-screen capture was removed. T55 must re-check A–D, F–H and J on the
unlocked phone against the T46 states (seeded debug DB for full-ring/`Not
synced`, real X4/Bridge for the reboot).

### Docs

- `docs/design/adr/0058-history-gap-placement-and-reboot-recovery.md` (new)
- `docs/design/06-app.md` (T46a implementation note)
- `docs/progress/T46a.md` (facts, commands, follow-ups)

### Next task must know

- History reads `gaps()` + `samplesAroundSeq`; `gapsInRange` stays the
  detection-time helper for sync/deletion. Do not mix them.
- A gap with no surviving neighbour row is skipped rather than guessed.
- `RecentHistoryStore.sparkline` now follows the newest sample; the 15-minute
  fixture window is unchanged.
- T55 owns the real-phone evidence and the 320 dp/TalkBack pass for these
  states; T54 owns the layout/truncation gate.
