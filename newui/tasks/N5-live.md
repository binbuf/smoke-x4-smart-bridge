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

---

## Hand-off

**Status: done.** All of N5.1–N5.14 landed. `cd app && flutter test` green (**256** tests, was 229); `flutter analyze` clean; `dart format --set-exit-if-changed` clean; `cd app && dart test test/domain test/data` green (**134**, was 131).

**What landed**
- `app/lib/features/live/` — `LivePage` and the pieces: alarm strips (N5.1), notice banner (N5.2), adopt banner (N5.3), cook header (N5.4), stopwatch (N5.5), instrument card (N5.6), summary strip (N5.7), compact probe rail (N5.8), mini graph (N5.9), quick actions (N5.10), probe-tile → probe sheet (N5.11), real `mark`/`editStart`/`adopt` overlay bodies (N5.12/N5.13), cook-settings → setup edit context (N5.14).
- `LiveDestination` now returns `LivePage` instead of the placeholder.
- Tests: `app/test/features/live_test.dart` (24 incl. format) and `app/test/features/live_format_test.dart`; `app/test/data/mock_repository_test.dart` gained the three new-method cases. Shell golden regenerated.

**Exit gate evidence (real commands)**
- `cd app && flutter test test/features/live_test.dart test/features/live_format_test.dart` → `All tests passed!` (24).
- `cd app && flutter test` → `All tests passed!` (256).
- `cd app && dart test test/domain test/data` → `All tests passed!` (134).
- The gate asserts: `running`/`idle`/`existing`/`offline` render; detached tiles show `—`/`Unplugged` and no tile shows `0`; offline removes every "to pull" (I4); pause sets `cook.paused` and leaves `startedAtMs` untouched; `existing` has exactly one `PrimaryAction`.

**Deviations from the plan (and why)**
- **`MarkKind` gained `spritz` and `turn`.** The task's 8 mark kinds include them but the wire `mark_rec.kind` does not. They are app-originated user kinds; N15 must map or extend the wire. (`alarm`/`autoDetected` remain firmware-originated kinds the sheet does not offer.)
- **`BridgeRepository` gained `setCookPaused` / `setCookStart` / `discardSession`.** N5.5/N5.12/N5.3 need to mutate the snapshot; there was no seam. N15 must implement them.
- **I14 beats the prototype's literal layout.** In `existing`, the prototype renders two ember primaries (adopt + start a cook); Flutter demotes the instrument card's "Start a cook" to a normal button while the adopt banner is shown, so exactly one primary is on screen.
- **No stopwatch ticker.** Following N4's static status-bar clock, the stopwatch reads `liveNowProvider` once per build. Pause freezes by capturing the elapsed at the tap. A ticking clock would make `pumpAndSettle` unusable.
- **Shell fix (N4 code).** `ShellScrollHost` moved from wrapping `AppShell`'s route child (the go_router nested Navigator) into each destination (`LivePage`, `DestinationPlaceholder`). A Navigator inside a vertical `SingleChildScrollView` shrink-wraps during route transitions and transiently overflows a tall destination. `AppShell` now gives the Navigator a bounded height. N4.11's reset still holds (a destination change recreates the host).
- **Overlay framework extension.** `SheetOverlay`/`ModalOverlay` gained `bodyBuilder`/`actionsBuilder`; `ShellModalCard` gained `actions`. This lets the real `mark`/`editStart`/`adopt` bodies apply an action and close without importing the shell.
- **`ShellScope.openScreen`** added so destinations can navigate (Live → Graph/Temps); N4 had no destination-to-destination nav seam.
- The `adopt` modal is now real (summary + `live-adopt-confirm`), reached from the banner; the banner's "Start fresh" calls `discardSession()` directly.

**What the next task must know**
- N6: `DevOverlay.probe` is still a placeholder; Live opens it with `props['jack']`.
- N9: the setup sheet must honour `props['context'] == 'edit'` (Live's cook-settings button).
- N7: the mini graph is a `spark`-based preview; the fullscreen host body is still a placeholder.
- N11: `DevOverlay.alarmDetail` body is still a placeholder; Live opens it with `id`/`tier`, and ack/ack-all already mutate the repo.
- N15: the three new repo methods + `MarkKind.spritz`/`turn` on the wire.
- Any golden that renders Live must override the repository and `liveNowProvider` to a fixed instant (see `app_shell_golden_test.dart`).
