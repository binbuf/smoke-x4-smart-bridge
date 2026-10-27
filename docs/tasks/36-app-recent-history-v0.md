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
- [ ] Mount the approved History UI from the prototype (`features/history/`, `widgets/`, `theme/`) instead of creating a new screen.
- [ ] Render the filter card: range trigger and probe trigger in one card, with the reset icon only when a filter is active.
- [ ] Render the chart shell with the four probe series, legend, axes, and gap handling.
- [ ] Render the Summary with `Latest`, `Min`, and `Max` per probe and no temperature deltas.
- [ ] Render the Cooks card with the label `Cooks` and the subtitle “Grouped automatically from your readings”.
- [ ] Render the empty and offline states: `No readings yet`, offline with cache, and the saved-readings label.
- [ ] V0 has only the last 15 minutes of data: selections beyond that legitimately show the same recent data or an honest no-data state, never invented data.
- [ ] Break the series at any adjacent-sample delta greater than **90 s**; never connect across a gap.
- [ ] Keep probe identity `P1`–`P4` and colour, consistent with Live and the OLED.
- [ ] Preserve range/probe state across tab switches and app resume.
- [ ] Drive the screen from the fake sync of 30 records, including a gap and a detached probe.
- [ ] No placeholder chart, fixture series, or second simplified History implementation.

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
- [ ] A fake sync of 30 records draws four series with a gap and does not connect across it.
- [x] A real phone shows the last 15 minutes after pairing. **Deferred to T37**; the fake-sync widget test is the gate now.
- [ ] The full History shell is present: filter card, chart shell, Summary, and Cooks card.
- [ ] The empty and offline states are present, with no placeholder chart and no fixture data presented as current.
- [ ] `flutter test` passes, including the History widget test for the 30-record fixture.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
