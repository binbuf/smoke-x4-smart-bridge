---
hitl: true
---
# T36 — app: recent History (V0)

## Goal
The approved History UI is mounted in production and shows the last 15 minutes synced from the bridge: filter card, chart shell, Summary, Cooks card, and the empty/offline states. V0 uses the real History shell rather than a second simplified screen, so M3 can complete it instead of replacing it.

## Context (read first)
- **Human checkpoint.** This task carries `hitl: true`, so the harness pauses
  after T36 finishes and before T37 starts. T37 is the first V0 bench run and
  needs a factory-fresh phone install plus the real board; do not let it start
  unattended.
- [06 §6.6](../design/06-app.md) — History layout, filters, Summary, Cooks, and data rules.
- [13 §13.4 History](../design/13-ui-implementation-contract.md#history) — the state inventory.
- [13 §13.5 History](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows) — default range, probe-tile entry, and persistence.
- [04 §4.5, §4.6](../design/04-data-and-storage.md) — record stream, 18-byte records, and the >90 s gap rule.
- Design: [06](../design/06-app.md), [13](../design/13-ui-implementation-contract.md).
- Verify tier: **H/P**. Board: **no / phone**.
- Depends on T35 and T31.

## Scope
- [x] Mount the approved History UI from the prototype (`features/history/`, `widgets/`, `theme/`) instead of creating a new screen.
- [x] Render the filter card: range trigger and probe trigger in one card, with the reset icon only when a filter is active.
- [x] Render the chart shell with the four probe series, legend, axes, and gap handling.
- [x] Render the Summary with `Latest`, `Min`, and `Max` per probe and no temperature deltas.
- [x] Render the Cooks card with the label `Cooks` and the subtitle “Grouped automatically from your readings”.
- [x] Render the empty and offline states: `No readings yet`, offline with cache, and the saved-readings label.
- [x] V0 has only the last 15 minutes of data: selections beyond that legitimately show the same recent data or an honest no-data state, never invented data.
- [x] Break the series at any adjacent-sample delta greater than **90 s**; never connect across a gap.
- [x] Keep probe identity `P1`–`P4` and colour, consistent with Live and the OLED.
- [x] Preserve range/probe state across tab switches and app resume.
- [x] Drive the screen from the fake sync of 30 records, including a gap and a detached probe.
- [x] No placeholder chart, fixture series, or second simplified History implementation.

## Out of scope
- Full sync, resume, cursors, generation/gap handling, and local archive → T39–T41 (M3).
- Full chart interactions (pan/zoom/fit), decimation, Summary sorting, Cook detection, Cook view, full-screen chart, custom range, and estimated/overwritten states → T42 (M3).
- History deletion and retention → T44 (M3).
- Full History empty/error states → T45 (M3).
- Settings, units, and History & storage → T50–T53 (M4).
- Billows UI → T56–T60 (M5).
- A second dashboard, aggregate graph, or second simplified History screen — outside MVP; no task owns it.
- Wi-Fi/HTTP/OTA, cloud sync, or export — outside MVP; no task owns them.

## Design notes
- V0's History is the real shell, not a demo: M3 fills in the full archive and interactions, but the layout, labels, and state slots are the approved ones in [13 §13.4](../design/13-ui-implementation-contract.md#history).
- Data rules: four series, one colour per probe; gap if the time delta between adjacent points is >90 s; no line and no zero for a probe with no data; a detached probe is absent, not 0 °F.
- Range trigger values are `1 hour`, `6 hours`, `24 hours`, `2 days`, `Custom`; menu entries are `Last hour`, `Last 6 hours`, `Last 24 hours`, `Last 2 days`, `Custom range…`. V0 can only honestly fill the recent window.
- Summary fields: `Latest` (newest valid reading in range), `Min`, `Max`, `No data` where a probe has no valid reading. Default order is probe order; sorting belongs to M3/T42.
- Cooks are read-only archive navigation, never user-created sessions. V0 may show an empty or recent-only Cooks card; cook detection lands in M3.
- History is the only multi-probe chart; there is no Graph tab or separate session list.
- Offline with cache keeps the chart usable and labels it as saved; offline without cache must not render fixture values as current.
- `reading`/`readings` is the user word, not `records`, `points`, or `samples`.

## Done when
- [x] A fake sync of 30 records draws four series with a gap and does not connect across it.
- [x] A real phone shows the last 15 minutes after pairing. **Deferred to T37**; the fake-sync widget test is the gate now.
- [x] The full History shell is present: filter card, chart shell, Summary, and Cooks card.
- [x] The empty and offline states are present, with no placeholder chart and no fixture data presented as current.
- [x] `flutter test` passes, including the History widget test for the 30-record fixture.
- [x] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_

### What landed
- `app/lib/data/recent_history_store.dart` — `RecentHistoryStore implements
  BridgeSyncSink`; keeps this session's synced records, produces the
  `HistoryFixture` for the requested range, computes the largest >90 s hole and
  never turns a detached probe into 0 °F.
- `app/lib/app/bridge_controller.dart` — owns one store, feeds it from
  `BridgeLink` by default (`ensureLink(sink: ...)` still accepts a test sink),
  builds `historyViewFor` from it, and uses its range for Custom. Offline without
  cache yields empty series; offline with cache keeps the chart.
- `app/lib/domain/models.dart` — `historyGapThreshold` (90 s) and
  `historySeriesSegments`, the one break rule shared by the painter and tests.
- `app/lib/widgets/probe_chart.dart` — draws each segment separately; no line
  ever crosses a `null` value or a >90 s adjacent-sample delta.
- `app/lib/app/view_state.dart` / `features/history/history_screen.dart` —
  separate `No readings yet` from `No readings in this range`; the in-range empty
  state offers `Show recent readings` instead of showing another period.
- `app/lib/app/bootstrap.dart` — production starts with no History until a sync
  lands; `demoBridgeController` keeps the approved fixture for review builds.
- Tests: `test/recent_history_test.dart` (4) and `test/history_recent_test.dart`
  (5): the 30-record fake sync (P3 detached, 3 m 20 s hole) draws four series,
  two runs per attached probe, zero P3 runs; full shell keys; reset icon only
  with an active filter; range/probe survive tab switches; empty, offline cache
  and offline no-cache states. `test/support/recent_history.dart` is the shared
  30-record fixture.
- Docs: ADR 0043; 06 §6.6 implementation note.

### Verification
From `app/`:
```powershell
flutter analyze
# No issues found!
flutter test
# 141 tests pass
```

### Deviations / decisions
- V0's store is in-memory and session-scoped. Persistence across app restarts is
  deliberately left to the durable archive (T39–T41); the UI seam and sync sink
  do not change when it lands.
- Wider ranges are honest but do not stretch: the requested range is the chart
  window and only readings inside it are drawn. This matches "same recent data
  or an honest no-data state".
- Only the widest hole is labelled as a gap band in V0; every hole still breaks
  the line. Multiple bands belong to T42/T45.
- Cooks stay empty in the store path (cook detection is T42); the approved Cooks
  card label and subtitle are present.

### Next task must know
- T37: real phone + factory-fresh install; sync 30 records over the real link and
  confirm the chart gap/P3 absence. No placeholder chart remains.
- T39–T41: replace `RecentHistoryStore` content with the durable archive, keep
  `BridgeSyncSink`, and persist `localMaxSeq`.
- Widget tests that drive `BridgeLink` must run the async procedure inside
  `tester.runAsync(...)`; otherwise `Future.delayed` in the fake client hangs the
  fake-async zone. Dispose the link inside the test body to cancel the 110 s
  watchdog.
