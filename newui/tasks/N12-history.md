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