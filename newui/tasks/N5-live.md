# N5 — Live

**Goal:** the "now" glance — the most-used screen. Sticky alerts, cook identity,
stopwatch, at-a-glance summary, compact probe rail, mini graph, quick actions.

**Design:** [`newui/app.js`](../app.js) §6 `viewLive`, `alarmStrips`, `compactProbe`,
`miniChart` · `newui/NOTES.md` §3, §7.1, §7.3 · `mock-data.js` scenarios.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| I2 | Device is authoritative; recording continues even if the phone drops | cook header line |
| I3 | Detached probe renders `—` + "Unplugged", never `0°` | `compactProbe` |
| I4 | Derived values (ETA, trend) are removed when not live, not greyed | compact probe + mini graph |
| I14 | At most one ember primary action on screen | quick actions |
| §7.3 | Pausing the stopwatch freezes the **display only**; it never stops device recording | stopwatch |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N5.1 | Alarm strip(s): highest-severity first, up to 3, tier tag (Device/Insight), inline acknowledge, "Acknowledge all" when >1 | N4.3, N3.23 | W | `app.js` alarmStrips |
| N5.2 | Scenario `notice` banner (post-restart / rollback / resync copy) | N5.1 | W | `app.js` viewLive |
| N5.3 | **Adopt banner** when a bridge session exists and no cook is adopted: elapsed, probes, sample count, Adopt + Start fresh | N4.6, N2.18 | W | `app.js` viewLive pendingSession, NOTES §5.2 |
| N5.4 | Cook header: food avatar, name, "Recording on the bridge — safe even if this phone drops", cook-settings button | N5.1 | W | `app.js` viewLive, I2 |
| N5.5 | Stopwatch: `HH:MM:SS`, "Started <clock>", pause/resume (display-only), edit-start | N5.4 | W | NOTES §7.3, `app.js` fmtStopwatch |
| N5.6 | Instrument-mode card when no cook: copy + Start a cook (primary) + View graph | N5.4 | W | `app.js` viewLive else-branch |
| N5.7 | Summary strip: Grate (or "No pit probe"), Hottest food, To target (+ ready count) | N5.4 | W | `app.js` viewLive |
| N5.8 | Compact probe rail: 4 tiles, jack badge, name (catalog name when assigned), temp parts, sub line, DONE/STALL flags, progress rule; grate tile tagged | N5.7 | W | `app.js` compactProbe |
| N5.9 | Mini graph card → tap to Graph; label "°F · last Nm" | N5.8 | W | `app.js` miniChart |
| N5.10 | Quick actions: Mark (opens mark sheet) + Add food (opens setup) | N5.8 | W | `app.js` viewLive |
| N5.11 | Tap a probe tile → probe sheet (N6) | N5.8 | W | `app.js` open-probe |
| N5.12 | `editStart` modal: quick offsets (now/30m/1h/2h/4h) + current start; **moving the window never rewrites samples** | N5.5 | W | `app.js` overlayEditStart, I10 |
| N5.13 | `mark` sheet: 8 kinds (note/wrapped/spritz/turn/lid_open/fuel/probe_moved/phase_change) + optional note | N5.10 | W | `app.js` overlayMark |
| N5.14 | Cook-settings button opens setup in edit context (N9) | N5.4 | W | `app.js` open-setup |

## Exit gate

The `running`, `idle`, `existing`, and `offline` scenarios each render correctly;
detached/stale probes visibly remove derived values; a widget test asserts no
tile shows `0` for an absent probe; stopwatch pause does not stop recording.

## Must-not-regress

I2, I3, I4, I14 and the display-only pause semantics.