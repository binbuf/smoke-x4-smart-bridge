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

**Resolved (T09): shipped read-only, overrides only in setup.** The timeline
table (`kTimelines`/`kCatalogTable.timelines`) stays reviewer-owned and
immutable; the only per-cook edit is the wrap/spritz reminder toggle. It is
stored on `CookItem.wrapEnabled` / `CookItem.spritzEnabled` (`bool?`, null =
seed from the cut's timeline) and written through the repository's
`setItemInterventions`. N9.11 seeds the same fields at item creation.

## Hand-off

**Status: done.** All N8.1–N8.12 landed; the Timeline destination is real.
`make app.test` green (**370** tests; N8 adds 18 pure + 11 widget + 1 golden +
1 repo = 31); `flutter analyze` and `dart format` clean; `dart test test/domain
test/data` green (**137**, was 136).

**Real paths**
- `app/lib/features/timeline/` — `timeline_format.dart` (pure projections),
  `timeline_model.dart` (`timelineNowProvider`, `timelineModelProvider`),
  `timeline_page.dart` (`TimelinePage` + the Gantt/upcoming/reminders/rail
  widgets), barrel `timeline.dart`.
- `app/lib/features/shell/destinations.dart` — `TimelineDestination` →
  `const TimelinePage()`.
- Tests `app/test/features/timeline_format_test.dart` (17),
  `app/test/features/timeline_test.dart` (11), `app/test/golden/
  timeline_golden_test.dart` + `goldens/timeline.golden.txt`, and one new
  `setItemInterventions` test in `app/test/data/mock_repository_test.dart`.

**Commands that work**
- `make app.test` — the N8 gate (370 pass).
- `cd app && flutter test test/features/timeline_test.dart test/features/timeline_format_test.dart` — 28 fast tests.
- `cd app && dart test test/domain test/data` — data/domain gate (137).
- `make app.golden` regenerates `timeline.golden.txt` too.

**Contract facts later tasks need**
- `buildTimelineModel({cook, pendingSession, catalog, marks, nowMs,
  autoWrapReminder}) → TimelineModel`. Pure, no Flutter; the unit-test surface
  for the projection invariants. Projection rules are prototype-exact: bar =
  `totalMin.mid`, stall = 38–72 %, wrap tick = 55 %, domain tail = 45 min,
  served-by = +30 min, upcoming cap 4.
- `TimelineRow` exposes `endMs`, `wrapAtMs`, `stallStartMs`/`stallEndMs`,
  `progressAt(nowMs)`, `hasWrapMilestone`/`hasStall`/`hasSpritz`. The **wrap
  milestone is a fact of the cut** (draws whenever `timeline.wrap != null`);
  the per-cook toggle only gates the *nudge*.
- **`CookItem` gained `timeline` (per-item `CookTimeline?`, the N9.18 custom-
  food seam), `wrapEnabled` and `spritzEnabled` (`bool?`, null = seed from the
  cut's timeline).** `MockBridgeRepository._addItem` does **not** yet carry
  `timeline` across a re-add — N9 must set it.
- **`BridgeRepository` gained `setItemInterventions(jack, {wrap, spritz})`**
  (null = leave unchanged). Mock implemented; **N15 must implement it on the
  real transport.**
- Keys: `timeline-page`, `timeline-empty`, `timeline-header`/`-off-by`/
  `-served-by`/`-item-count`/`-estimate-note`, `timeline-gantt`/`-axis`/
  `-gantt-empty`, `timeline-row-<jack>`/`-row-name-<jack>`/`-bar-<jack>`/
  `-row-end-<jack>`/`-stall-<jack>`/`-wrap-<jack>`/`-now-<jack>`/`-now-label`,
  `timeline-upcoming`/`-note`/`-empty`/`-<i>`/`-time-<i>`,
  `timeline-reminders`/`-off`/`-empty`/`-<jack>`/`-wrap-toggle-<jack>`/
  `-spritz-toggle-<jack>`, `timeline-rail`/`-empty`/`-<i>`/`-dot-<i>`/
  `-time-<i>`/`-now`, `timeline-add`, `timeline-log-event`.

**Deviations from the plan (deliberate)**
- **Upcoming is future-only.** `app.js` adds every turn regardless of time, so
  the `running` scenario would list the sausage's turn ~35 min in the past
  under "Upcoming". `buildUpcoming` drops `atMs < nowMs`; the section's name
  and the honesty rule win. Recorded here, not in the prototype.
- **The now line is on every track** (task N8.5) even though `app.js` draws it
  only on jack 1; the "NOW" label is on the first track only.
- **Per-cook reminders are a new UI surface.** The prototype has no toggles on
  the Timeline view (the seed lives in setup); N8.10's verify is W, so the
  toggles are rendered here and write the same fields N9.11 will seed.
- `railTimeLabel` says `· expected` on predictions (prototype); the header
  caption, the upcoming caption and the section label carry the estimate
  wording for N8.8.

**Follow-ups for later tasks**
- N9.11: seed `wrapEnabled`/`spritzEnabled` from the setup toggle and thread
  custom-food `CookItem.timeline` through `addItem`/`startCook`.
- N9.14: the long-item guard is N9's; the Timeline view already re-renders on
  any snapshot change (verified by the add-item widget test).
- N15: implement `setItemInterventions` on the real transport; `CookItem`
  serialisation must include the three new fields.
- N16: consider Timeline goldens for `idle`/`existing`/`offline` (only
  `running` is pinned).
