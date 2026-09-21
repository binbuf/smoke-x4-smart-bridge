# N7 — Graph

**Goal:** the multi-series chart with range chips, zoom/pan, fullscreen,
tap-to-isolate legend, labelled targets, pit-band shading, marks, and window stats.

**Design:** [`newui/app.js`](../app.js) §3 `buildChart`, §6 `viewGraph`,
`renderFullGraph`, `legendSwatch`, `graphDomain` · `newui/styles.css` `.chart`,
`.legend`, `.zoom-bar`, `.gantt`-adjacent · NOTES §6, §7.

---

## Invariants this epic must encode

| Rule | Where |
|---|---|
| Runs split at gaps **before** per-run LTTB decimation | chart series builder |
| Area fill ≤16% | chart styling |
| Target lines are labelled **on** the line | target overlay |
| Crosshair returns the nearest **real** sample | crosshair |
| Hue is never the only identity channel: P1 solid / P2 dashed / P3 dotted / P4 dash-dot | `legendSwatch`, series style |
| Green is transport health only | chart palette |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N7.1 | `CookChart` on `fl_chart`: y-gauge in display units, 4 gridlines, time x-axis labels | N4.3, N0.2 | W | `app.js` buildChart |
| N7.2 | Series builder: split at gaps → LTTB → min/max envelope for wide ranges | N1.14 | H | research notes §6.2 |
| N7.3 | Series identity: per-jack colour **and** stroke pattern; pit line thicker | N7.1 | W | `app.js` graphSeries, `legendSwatch` |
| N7.4 | `<16%` area fill under each visible series | N7.1 | W | `app.js` buildChart |
| N7.5 | Target lines, labelled on the line, per food probe | N7.1 | W | `app.js` viewGraph targets |
| N7.6 | Pit-band shaded band from `cook.pitBand` | N7.5 | W | `app.js` buildChart bands |
| N7.7 | Mark verticals (wrap/spritz/turn/etc.) | N7.1 | W | `app.js` buildChart marks |
| N7.8 | "Now" cursor line | N7.7 | W | `app.js` buildChart now |
| N7.9 | Range chips 15m / 1h / 6h / all | N7.1 | W | `app.js` graphDomain |
| N7.10 | Zoom in/out + pinch/scroll + drag-to-pan + Reset view; zoom indicator text | N7.9 | W | `app.js` graph zoom/pan |
| N7.11 | Fullscreen graph host: pan back/forward, zoom, reset, exit | N4.8, N7.10 | W | `app.js` renderFullGraph |
| N7.12 | Crosshair + tooltip returning the nearest real sample | N7.1 | W | research notes §6.2 |
| N7.13 | Legend: swatch + name + current value; tap-to-isolate; tap again to clear | N3.28, N7.3 | W | `app.js` isolate |
| N7.14 | Window statistics table (High/Avg/Low per attached probe) | N1.13 | W | `app.js` viewGraph |
| N7.15 | Actions: Add mark, Share graph (share sheet; CSV byte-compatible in N15) | N7.14 | W | `app.js` viewGraph export |
| N7.16 | Live and history charts are the **same widget** with different inputs | N7.1 | W | NOTES §6 (converge) |

## Exit gate

Scrolling a 15-hour cook stays smooth (decimation active); isolating one probe
dims the others without losing their stroke identity; the fullscreen chart
matches the inline chart for the same window.

## Must-not-regress

Run-splitting before decimation, ≤16% fill, on-line target labels, gap honesty.

---

## Hand-off

Status: **done** — all 16 sub-tasks landed; `make app.test` green (**339** tests; T07 recorded 302,
and N7 adds 36: 10 widget + 19 projection + 7 chart-data). `flutter analyze` and the format check
clean. `dart test test/domain test/data` still green (136).

### What landed (real paths)

- `app/lib/features/graph/graph_format.dart` — pure projections: `GraphRange`,
  `GraphViewState`, `GraphDomain` + the prototype's exact `graphDomain()`, stroke identity
  (`seriesDashArray`/`seriesDash`/`seriesWidth`), `buildGraphSamples`/`buildGraphSeries`,
  `graphYBounds`, `graphTargets`/`graphPitBand`/`graphMarks`/`graphWindowStats`, `graphZoomHint`.
- `app/lib/features/graph/graph_model.dart` — `graphNowProvider`, `graphViewProvider`
  (`NotifierProvider<GraphViewNotifier, GraphViewState>`), `graphSamplesProvider`,
  `graphModelProvider` + `GraphModel`. View state is **shared**, which is what makes the
  fullscreen chart identical to the inline chart.
- `app/lib/features/graph/chart_data.dart` — `buildCookChartData` → `LineChartData`; the unit-test
  surface for every chart invariant. `chartAreaFillAlpha = 0.10`.
- `app/lib/features/graph/cook_chart.dart` — `CookChart` (fl_chart `LineChart`, `Duration.zero`).
  Built-in touch is off; a custom `graph-crosshair` tip shows each bar's nearest **real** sample.
  Gestures: chart `touchCallback` pan + outer scale (pinch) + `PointerScrollEvent` wheel.
- `app/lib/features/graph/graph_page.dart` — `GraphPage` (destination).
- `app/lib/features/graph/graph_fullscreen.dart` — `GraphFullscreenBody`.
- `app/lib/features/graph/graph.dart` — barrel.
- Wired: `destinations.dart` `GraphDestination` → `GraphPage`; `shell.dart` fullscreen child →
  `GraphFullscreenBody`. Deleted `ShellFullscreenGraphPlaceholder` (N7 replaces it); `shell_test`
  now passes a plain child.

### Tests / commands

- `make app.test` — analyze + format check + `flutter test` (**338 pass**).
- `cd app && flutter test test/features/graph_test.dart test/features/graph_format_test.dart test/features/graph_chart_data_test.dart`
  — the N7 gate (10 + 19 + 7 = 36).
- `cd app && dart test test/domain test/data` — unchanged (136).
- `make app.golden` regenerates `app/test/golden/goldens/graph.golden.txt`; pin
  `shellClockProvider` **and** `graphNowProvider` plus a fixed `MockBridgeRepository`.

### Deviations / decisions

- **The mock has no sample stream.** `buildGraphSamples` resamples each `ProbeState.spark` onto one
  aligned session-seconds grid (30 s cadence, widened so the grid never exceeds 1200 points) and
  feeds it to N1.14's `buildChartSeries`; run-splitting and decimation therefore stay real and the
  exit gate is exercised. N15's real transport should call `buildGraphSeries` with actual `Sample`s
  and the same `CookChart` (N7.16).
- **Fullscreen is still local shell state.** The N4 follow-up's URL-driven `?fullscreen=1` was not
  done (out of the N7 task file). The view window itself is a provider, so making fullscreen
  URL-driven later changes only the mount condition.
- **Pinch is best-effort.** Wheel zoom, the zoom in/out buttons and drag-to-pan are fully wired and
  tested; two-finger pinch is handled in `onScaleUpdate` when `pointerCount >= 2` (untested — the
  prototype's `app.js` only had wheel + drag + buttons).
- **Share is a toast** (`Opening share sheet — graph`); the CSV export and share sheet are N15's.
- **The Live mini-graph preview is unchanged** (`LiveMiniGraphCard` still draws a spark). It is a
  Glance card, not the chart destination; swapping it to `CookChart` is a follow-up for whoever
  revisits Live, and would move the `app_shell` golden.
- The y-axis draws 4 interval gridlines (min/max forced labels off) rather than exactly the
  prototype's 5 (its endpoints); the values are still display-unit and the extent is the same.
- fl_chart's `LineChart` gets `duration: Duration.zero`; no `Duration(` literal is introduced
  (`design_layering_test` stays green).

### What the next task must know

- Reuse `CookChart(model:, domain:, unit:, series:, targets:, band:, marks:, isolatedJack:)` for the
  history/detail chart (N12). Build a `ChartSeriesModel` from the stored samples; `CookChart` and
  `buildCookChartData` do not read any provider.
- Keys: `graph-page`, `graph-range`, `graph-zoom-out`/`graph-zoom-in`/`graph-fullscreen`,
  `graph-chart`, `graph-legend`, `graph-zoom-hint`, `graph-reset`, `graph-stats`,
  `graph-stat-<jack>`, `graph-add-mark`, `graph-share`, `graph-empty`; fullscreen:
  `shell-graph-title`, `graph-fullscreen-zoom`, `graph-pan-back`/`graph-pan-fwd`,
  `graph-fullscreen-zoom-out`/`graph-fullscreen-zoom-in`/`graph-fullscreen-reset`,
  `shell-graph-exit`, `graph-fullscreen-chart`, `graph-fullscreen-legend`; crosshair
  `graph-crosshair`.
- N15: implement graph share/CSV; feed real `Sample`s into `buildGraphSeries`; keep `Sparkline`
  out of the chart.