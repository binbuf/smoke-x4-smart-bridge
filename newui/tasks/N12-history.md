# N12 — History

**Goal:** past cooks as annotations over the continuous recording. A grouped list
and a cook detail with a planned-vs-actual recap, plus repeat, favourite, export
and delete.

**Design:** [`newui/app.js`](../app.js) §6 `viewHistory`, `viewCookDetail`,
`histPoints`, `recapRow` · `newui/NOTES.md` §2, §6 · `mock-data.js` HISTORY ·
`components_research_notes.md` §11.2.

---

## Invariants this epic must encode

I10 — a cook is a time-window annotation; **deleting or editing a cook never
rewrites a sample row** — and the "Every cook is an annotation over one
continuous recording" notice stays on screen.

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N12.1 | Entry point from Settings → History; app-bar variant (back + Start a cook + bell) | N4.4 | W | `app.js` viewHistory |
| N12.2 | Educational notice: annotation-over-recording, "you never lose the gap" | N12.1 | W | `app.js` viewHistory |
| N12.3 | Grouped list (This week / Earlier), count per group | N12.1 | W | `app.js` viewHistory |
| N12.4 | Cook card: avatar, name + favourite star, date/duration/marks/photos, peak temp, chevron | N12.3 | W | `app.js` viewHistory |
| N12.5 | Cook detail header: avatar, name, date/time/duration/style, star rating, favourite toggle | N12.4 | W | `app.js` viewCookDetail |
| N12.6 | Recap card: cook time vs plan, peak vs target, longest stall, wrapped-at | N12.5 | W | `app.js` viewCookDetail |
| N12.7 | Result stat grid (Peak/Target/Marks) | N12.6 | W | `app.js` viewCookDetail |
| N12.8 | Chart (reuse `CookChart` from N7.16) with target line + time axis | N7.16, N12.5 | W | `app.js` viewCookDetail |
| N12.9 | Notes card | N12.8 | W | `app.js` viewCookDetail |
| N12.10 | Marks rail (actual events with times) | N12.9 | W | `app.js` viewCookDetail |
| N12.11 | Cook again: replays preset + style into a new cook (N9) | N12.4 | S | NOTES §2, `app.js` repeat-cook |
| N12.12 | Share/export (CSV byte-compatible with the device; generated from the cache so it works offline) | N12.8 | S | research notes §5.5 |
| N12.13 | Delete cook behind a cost sheet that states recording does not stop | N12.5 | W | research notes I8 |
| N12.14 | Cook detail supports marks/notes edit + pull/end/reopen metadata verbs | N12.10 | H | research notes §11.2 |
| N12.15 | Gaps card (connectivity vs buffer rollover) when a cook contains gaps | N1.18, N12.8 | W | research notes §6.2 |

## Exit gate

The 7 mock cooks list and group correctly; a cook detail renders chart, recap,
marks and notes; "Cook again" opens setup pre-filled with the same preset+style;
export works from cache with the app "offline".

## Must-not-regress

I10 and I8. Deleting a cook must not delete a sample.

## Hand-off

**Status: done.** All 15 sub-tasks landed; `make app.test` is green (analyze +
format + **541** flutter tests), and `dart test test/domain test/data` is green
(**182**). No golden changed.

### What landed
- **N12.1** Settings → History entry point (`destination-open-history` →
  `openScreen(ShellScreen.history)`); the History app-bar variant
  (back + Start a cook + bell) was already in `ShellAppBar` and is now asserted
  through the real router.
- **N12.2** the annotation-over-recording notice (`history-notice`).
- **N12.3** This week / Earlier grouping with per-group counts
  (`history-group-thisWeek` 4, `history-group-earlier` 3 over the 7 fixtures).
- **N12.4** the cook card (avatar, name + favourite star, date/duration/marks/
  photos, peak, chevron).
- **N12.5–N12.10** the cook detail: header (avatar, name, date/time/duration/
  style, star rating, favourite toggle), recap card, result stat grid, the N7
  `CookChart` reused with a target line and time axis, notes card and the marks
  rail.
- **N12.11** Cook again opens `DevOverlay.setup` with `food`, `style`, `jack`;
  `SetupSheetBody.initialStyleId` preselects the style and the cut's category.
- **N12.12** cache-side CSV export (`buildCookCsv`) byte-compatible with the
  device's `format=csv`; works with the link down.
- **N12.13** delete behind the design-system `CostSheet` that states the
  recording does not stop; deleting removes only the annotation (I10).
- **N12.14** notes edit, add/delete marks, Pull, End/Reopen.
- **N12.15** the gaps card (connectivity vs buffer rollover) with each reason's
  explanation.

### Deviations (and why)
- **Share is a toast, not a share sheet.** `share_plus` is N15.21's; the CSV is
  real and generated from the cache, and the toast reports its name/rows/bytes.
- **The marks rail is derived when the fixture has no explicit marks.** The
  generated `HistorySeed` carries only a mark count, so `historyRail` shows the
  prototype's milestones (Wrapped only when the cook was wrapped — a small
  honesty fix over `app.js`'s unconditional row). Editing seeds `markEvents`
  from that rail. N15 feeds the real `Marks` rows.
- **"Pull" is a mark** (`note`/`Pulled`); End/Reopen is the annotation status.
- **`historyGaps` uses the sample grid's own cadence**, not the device's 30 s,
  so the 60-point fixture curve is not read as 60 dropouts.
- Stars use `tokens.warning` (the prototype's gold `.fav`/`.stars`); a
  deliberate accent exception to the status-hue rule.

### What the next task must know
- **N15**: implement the six new `BridgeRepository` methods on the real
  transport/drift (`deleteCook`, `setCookNotes`, `setCookEnded`, `addCookMark`,
  `deleteCookMark`, `exportCookCsv`), stream the CSV (N15.14), wire the share
  sheet (N15.21), and replace the derived marks rail + `historySamples` with the
  cache's real rows.
- **N13**: the Settings tree replaces the placeholder around the History row
  (`destination-open-history` already navigates).
- **N16**: no History golden exists; consider list + detail goldens.

### Commands
- `make app.test` — analyze + format + full `flutter test` (541 pass).
- `cd app && flutter test test/features/history_test.dart test/features/history_format_test.dart` — 24 N12 tests.
- `cd app && dart test test/data/cook_export_test.dart` — 9 export tests.
- `cd app && dart test test/domain test/data` — 182 pass.
