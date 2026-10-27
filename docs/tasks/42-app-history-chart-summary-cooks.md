# T42 — app: full History chart, Summary and Cooks

## Goal
Turn the History shell into the approved full archive: every range and custom range, probe filtering, a decimated multi-series chart that draws gaps honestly, Summary sorting, and read-only detected Cooks with a dedicated Cook view. This is the product surface for everything synced in T41.

## Context (read first)
- Design: [06 §6.6](../design/06-app.md), [13 §13.4 — History](../design/13-ui-implementation-contract.md#history)
- Verification: **H/P** (host/CI plus phone) · Board required: **no / phone**
- Depends on T41.
- Copy is fixed by [12 §12.2 — History](../design/12-copy-and-label-review.md#history); read the UI contract before changing any approved screen.
- **Post-T36 status:** the approved History shell is already mounted on
  `RecentHistoryStore` for the current session's recent window; T42 swaps the
  data source to the durable DAO/repository and fills the full chart,
  Summary and Cooks. Do not rebuild the shell or reintroduce fixture series.

## Scope
- [ ] Complete the default History screen: `24 hours`, `All probes`, four series, Summary, and Cooks.
- [ ] Implement the range trigger values `1 hour`, `6 hours`, `24 hours`, `2 days`, `Custom`.
- [ ] Implement the range menu entries `Last hour`, `Last 6 hours`, `Last 24 hours`, `Last 2 days`, `Custom range…` with `Any date and time`.
- [ ] Implement the custom range sheet starting with all saved history, exact start/end date and time, validation, and the quick picks `All saved history`, `Today`, `Yesterday`, `Last 6 hours`.
- [ ] Apply a custom range only on `Apply`; `Cancel` restores the previous range and viewport.
- [ ] Implement the probe filter `All probes` and `P1`–`P4`, disabling options with no data and labelling them `No data`.
- [ ] Show the reset icon only when a filter is active.
- [ ] Persist range, probe, and sort across tab switches and app resume.
- [ ] Implement the chart crosshair with a pinned tooltip, pinch/scroll zoom, drag/pan, double-tap fit, zoom controls, `Now`, latest-point dots, and single-probe area fill.
- [ ] Implement shared y-axis when all probes are visible, auto-scale to the selected probe, nice ticks (1/2/2.5/5 × 10ⁿ), and one unit label.
- [ ] Implement LTTB decimation plus a min/max envelope, SQL bucketing for long ranges, and gap splitting with reasons `No signal`, `Bridge off`, `Not synced`.
- [ ] Show the estimated-time label when any visible sample is estimated.
- [ ] Implement `Summary` with `Latest`, `Min`, and `Max` and no deltas.
- [ ] Implement sort options `Probe order`, `Hottest`, `Highest`, `Latest reading`, `Since cook start`; disable the cook sort with `No cook detected yet` when no cook exists.
- [ ] Implement the `Cooks` card with the latest three detected cooks, `In progress` on the live cook, and `View all`.
- [ ] Implement the dedicated `Cook` view with `Recorded history`, the cook end time instead of `Now`, and a close/back action that leaves History unchanged.
- [ ] Implement the chart help sheet `Reading the chart` and the dedicated full-screen chart in portrait or landscape with a close action.
- [ ] Implement empty states for no readings at all, no readings in range, no probe data, and offline with no cache.
- [ ] Add a chart summary for screen readers and a Summary table that does not depend on colour.

## Out of scope
- Connection health, stale/offline transitions, and reconnect behavior — owned by T43.
- Exhaustive empty/error-state matrix and copy verification — owned by T45.
- History deletion and storage screen — owned by T44.
- Settings shell, Bridge details, units, and appearance — M4 (T47–T55).
- Full UI state/accessibility/copy gate at 320 dp — owned by T54.
- Live screen implementation — owned by T34.
- Billows surfaces — M5 (T56–T60).
- User-created cook sessions, names, marks, phases, or cook clock — outside MVP; no task owns them. Detected Cooks are read-only archive navigation.
- Alarms, phone notifications, export/share, and cloud sync — outside MVP; no task owns them.
- A second chart or a UI redesign — outside MVP; the contract is [13](../design/13-ui-implementation-contract.md).

## Design notes
- Decimation: LTTB to about 2 points per horizontal pixel per series, plus a min/max envelope for wide ranges. SQL-bucket long ranges; keep the chart under a few thousand points. Never load all 338,400 × 4 values into a widget.
- A time delta of more than 90 s between adjacent records breaks the line; never connect across a gap. The `gap` table's `reason` is rendered as-is, with the approved explanation for `Not synced`: “The Bridge overwrote this part of its history before it reached your phone. The readings can’t be recovered, so the chart leaves this period blank.”
- A probe with no readings in range renders no line and no zero; Summary shows `—` / `No data`.
- Summary default order is probe order; tapping a row focuses that probe. `Latest` is the newest valid reading in range; `Min`/`Max` are the lowest/highest valid reading. There are no temperature deltas.
- `Since cook start` uses recorded sample timestamps to find the current cook, or the most recent detected cook when none is in progress, and orders probes that reported since that start with the most recent first. Show the cook start age above the rows. With no cook, disable the option with `No cook detected yet`.
- Cooks are detected automatically from recorded readings and gaps. A row shows its date, exact start/end time, duration, probe count, and whether it contains a gap (e.g. `9h 20m · 4 probes · missing readings`). The live cook is marked `In progress`. The card shows the most recent three; `View all` opens the full list.
- The Cook view is a pushed route with app-bar title `Cook`, its own probe filter, `Recorded history` metadata, and the cook end at the right edge. Closing it returns to the exact prior History state, including range and viewport.
- Custom range starts with all saved history and never extends beyond it. Validation copy: `Choose a range within your saved history.` and `End time must be after start time.`
- Exact chart copy: `Drag to pan · pinch to zoom`, `Now`, `Fit range`, `Full-screen chart`, `Close full-screen chart`, `Reading the chart`, `times estimated`, and metadata like `Synced 2 min ago · 4 probes` or `· 3 of 4 probes`.
- Offline with cache keeps the chart usable under the `Showing saved readings` banner; it must not present cached values as live.
- Arriving from a probe tile opens History at `1 hour` with that probe selected.
- The approved UI must remain intact at 320 dp. Do not add prototype chrome, fixture values, or a second chart.

## Done when
- [ ] A 30-day, four-series fake DB renders within one frame budget on the target phone.
- [ ] Filters, custom range, gaps, estimated times, and detached probes are correct.
- [ ] Summary sorting and Cooks work from recorded timestamps.
- [ ] Tapping a Cook opens the historical view without changing the current History range.
- [ ] No fake zeros are rendered.
- [ ] A range with no data says so and offers one next action.
- [ ] The approved UI is intact at 320 dp.
- [ ] Widget/golden tests and `flutter test` pass; `flutter analyze` is clean.
- [ ] Hand-off below filled in.

## Hand-off

**Result:** done (host/CI). **Commands:** `flutter analyze` → No issues found;
`flutter test --timeout 120s` → 194/194 passed.

### Landed
- History now reads the durable DAO through `HistoryArchive`
  (`app/lib/data/history/history_archive.dart`): raw rows up to 4,000,
  SQL bucketing to ~1,200 rows for long ranges, LTTB to 800 points per series
  with a min/max envelope (`app/lib/domain/history_decimate.dart`), exact
  Summary from `SampleDao.probeStatsInRange`, gap bands from `gap` rows plus
  real holes, and Cooks from recorded timestamps
  (`app/lib/domain/cook_detection.dart`).
- `HistoryViewLoader` feeds History, the full-screen chart and the Cook view
  from the archive; a controller without a DAO keeps the synchronous fixture
  path.
- Custom range applies only on `Apply`; `Cancel` leaves range and viewport
  untouched. Quick picks clamp to saved history.
- `Since cook start` is disabled with `No cook detected yet`; the Cook view
  receives the archive DAO and keeps History unchanged on back.
- Every gap band renders its own reason; decimated series use explicit break
  points instead of the raw 90 s rule.
- Tests: `history_archive_test.dart` (10, includes 30-day bounded chart,
  gaps/estimated/detached probes, cook detection/sorting, offline no-cache);
  `history_archive_widget_test.dart` (3, archive-backed screen at 320 dp, Cook
  navigation preserving range, disabled no-data probe, 30-day decimation frame
  budget); updated widget tests for custom range and the disabled cook sort.
- Docs: ADR 0048 and a T42 note in `docs/design/06-app.md` §6.6.

### Deviations
- "Persist across app resume" is satisfied for tab switches and lifecycle
  resume because filters live on the controller; no preference store exists yet,
  so a process kill does not retain them. Noted for T53/T54.
- Gap bands are labelled and explained by copy, but tapping a band does not yet
  open a dedicated explanation sheet (T45 owns the full error/gap matrix).
- A very long range cannot recover detail below its SQL bucket width on zoom;
  the chart stays bounded rather than re-querying per viewport.

### Next task must know
- Call `controller.loadHistoryView()` when `sampleDao != null`; `historyViewFor`
  is fixture-only.
- T44 must bump `historyRevision` after deletion.
- T46 should benchmark the 30-day first paint on the phone and check the Cook
  back path and viewport preservation.
