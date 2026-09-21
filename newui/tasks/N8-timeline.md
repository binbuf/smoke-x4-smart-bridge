# N8 — Timeline

**Goal:** the database-driven expectation. A Gantt of everything on the grill,
upcoming interventions (wrap/spritz/turn), and the cook's event rail — predicted
vs actual. This is the one genuinely new system in the prototype.

**Design:** [`newui/app.js`](../app.js) §6 `viewTimeline` · `newui/NOTES.md` §4 ·
`mock-data.js` `normalizeTimeline`, `buildPhases` · `docs/design/17-…` for tone.

---

## The timeline database (read NOTES §4 before starting)

`CookTimeline` (from N1.9 and N2.11) drives everything:
`totalMin` [lo,hi] · `stall {minF,maxF,durationMin}` · `wrap {tempF,label,note}` ·
`spritzEveryMin` · `turn {elapsedMin,note}` · `restMin` · `phases[]`.

Projection rules the prototype uses (replace placeholders once real crossing data
exists): Gantt bar length = `totalMin` midpoint; stall band = 38–72% of the bar;
wrap milestone = 55%; upcoming = `wrap` + `spritzEveryMin` + `turn`; event rail =
actual marks ∪ predicted `phases`. **Every intervention is optional and editable**
(`autoWrapReminder` gates the nudge; `wrap: null` means no reminder).

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N8.1 | Empty state when no cook/session: one action "Start a cook" | N4.3 | W | `app.js` viewTimeline, I6 |
| N8.2 | Expected-schedule header: "Everything off by", "Served by", item count | N8.1 | W | `app.js` viewTimeline |
| N8.3 | Gantt: axis (start/mid/end), per-item row (avatar, name), bar colored by jack with progress fill, end-time label | N8.2 | W | `app.js` `.gantt` |
| N8.4 | Milestones on the bar: stall band and wrap tick | N8.3 | W | `app.js` gantt-milestone |
| N8.5 | Now line on each track | N8.4 | W | `app.js` gantt-now |
| N8.6 | "Upcoming" cards (up to 4): wrap / spritz / turn with time + note | N8.3 | W | `app.js` viewTimeline upcoming |
| N8.7 | Event rail: actual marks (done) ∪ predicted phases (expected); "now" node | N8.6 | W | `app.js` viewTimeline rail |
| N8.8 | Derived values state the word **expected**; never imply certainty | N8.7 | W | NOTES §4 honesty rule |
| N8.9 | `autoWrapReminder` setting gates wrap/spritz nudges; a cut with no wrap shows none | N8.6, N2.25 | W | NOTES §4.4 |
| N8.10 | Per-cook wrap/spritz toggle seeded from setup (N9) | N8.9 | W | NOTES §7.7 |
| N8.11 | Actions: Add something (setup) + Log event (mark) | N8.6 | W | `app.js` viewTimeline |
| N8.12 | A cut with an empty timeline is tolerated (no crash, no phantom bar) | N2.11 | H | NOTES §4 |

## Exit gate

The `running` scenario renders the brisket/ribs/sausage schedule with stall and
wrap where the data has them; adding a long item (N9) is reflected immediately;
every derived time reads as an estimate.

## Must-not-regress

The timeline is data-driven, not hard-coded per screen; every intervention is
optional; estimates say they are estimates.

## Open question

Q2 — is the timeline DB user-tunable per cook (stall window, spritz cadence) or
shipped read-only with overrides only in setup? Resolve before N8.10.