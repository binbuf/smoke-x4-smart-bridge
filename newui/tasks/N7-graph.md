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