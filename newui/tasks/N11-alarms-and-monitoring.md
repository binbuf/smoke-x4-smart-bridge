# N11 — Alarms & monitoring

**Goal:** the two-tier alarm system — device rules (authoritative) and app
insights (advisory), kept visibly separate — plus notification delivery, quiet
hours and background monitoring.

**Design:** [`newui/app.js`](../app.js) §6 `alarmStrips`, §7 `overlayAlarms`,
`overlayAlarmDetail` · `newui/NOTES.md` §3.1, §6 · `mock-data.js` ALARM_RULES,
alarm scenarios · `docs/design/09`.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| I2 | The device is authoritative; the app mirrors device alarms and never re-decides them | tier tags, no merge without tag |
| — | App alarms are labelled **Insight**; device alarms **Device**; the two are never merged untagged | list rows |
| — | Quiet hours 22:00–06:00 silence warning/info, **never critical**, in phone local time | preferences |
| — | Critical escalation: repeat 5 min, full-screen 10 min (critical only) | delivery |
| I15 | No raw exception reaches the user; failures are named states with copy | `BridgeRefusal` |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N11.1 | Alarm strip on Live (already in N5.1) completed with tier tags + ack | N5.1 | W | `app.js` alarmStrips |
| N11.2 | Alerts sheet: "Active now" list (severity icon, rule, tier, detail, ack) or the all-clear notice | N5.1 | W | `app.js` overlayAlarms |
| N11.3 | Delivery card: "This phone will wake you" verdict + Send a test alarm | N11.2 | W | `app.js` overlayAlarms |
| N11.4 | "From the bridge — authoritative" group: the 9 device rules with enable toggles | N2.23 | W | `mock-data.js` ALARM_RULES |
| N11.5 | "Insights from the app — never overrides the bridge" group: the 3 app rules | N11.4 | W | `app.js` overlayAlarms |
| N11.6 | Preferences: prefer my own alarms, quiet hours, background monitoring | N2.25 | W | `app.js` overlayAlarms |
| N11.7 | Alarm detail: severity card, fired time/ago, tier tag, "why this fired" (rule, trigger, reading, suggestion) | N11.2 | W | `app.js` overlayAlarmDetail |
| N11.8 | Detail actions: Acknowledge, Snooze 10m, View on graph | N11.7 | W | `app.js` overlayAlarmDetail |
| N11.9 | Acknowledge silences, does not resolve (device semantics) | N11.8 | H | `components_research_notes.md` §2.2 |
| N11.10 | "Prefer my own alarms" changes which notification wins; device alarms remain authoritative in the list | N11.6 | H | Start.md, NOTES §3.1 |
| N11.11 | Pure `planNotifications()` over device alarms, on-screen keys, wall clock, app findings, quiet hours, monitoring flag → post/withdraw | N1.19 | H | research notes §6.4 |
| N11.12 | Four channels (critical/warning/info/ongoing); critical bypasses quiet hours | N11.11 | H | research notes §6.4 |
| N11.13 | Escalation ladder (repeat 5 min, full-screen 10 min, critical only) | N11.12 | H | research notes §6.4 |
| N11.14 | Background monitoring surface: service checks the bridge and bubbles alarms when the app is backgrounded | N11.11, N15 (real) | S | `Start.md`, research notes §8 |
| N11.15 | Bridge-unreachable insight when the link drops mid-cook | N11.11 | W | `mock-data.js` offline scenario |
| N11.16 | Alarm rule editor for **app** tier only (device rules are toggled, not invented) | N11.4 | W | `components_research_notes.md` §11.3, I5 |

## Exit gate

The `running` and `offline` scenarios raise and acknowledge alarms correctly; a
test alarm proves delivery; quiet hours silence a warning but not a critical; the
list never shows a device rule without its Device tag.

## Must-not-regress

I2, I15 and the two-tier separation. **Do not merge the tiers.**

## Open question

Q4 — does stopwatch pause suppress alarms/notifications, or only the displayed
clock? The prototype assumes the latter (device is authoritative). Resolve with
N5.5.

---

## Hand-off

Status: **done**. N11.1–N11.16 landed (N11.14 is the surface only; the real
Android foreground service is N15's).

**Verification**

- `cd app && flutter test` — **502 pass** (was 451; N11 adds 51).
- `cd app && flutter test test/features/alarms_test.dart` — 12 widget tests
  (alarms sheet + alarm detail).
- `cd app && dart test test/data/notification_policy_test.dart test/features/alarms_format_test.dart`
  — 35 pure host tests.
- `cd app && dart test test/domain test/data` — **169 pass** (was 143).
- `cd app && flutter analyze` clean; `dart format --set-exit-if-changed lib test`
  clean. No golden changed (no golden renders an overlay).

**What landed**

- `lib/data/alarms/notification_policy.dart` — pure `planNotifications()` over
  device alarms, on-screen keys, the wall clock, app findings, quiet hours, the
  monitoring flag and `preferManualAlarm`; four channels; critical bypasses
  quiet hours; the 5 min repeat / 10 min full-screen escalation ladder; snooze.
- `lib/features/alarms/` — `alarms_sheet.dart` (`?overlay=alarms`),
  `alarm_detail_sheet.dart` (`?overlay=alarmDetail`), `alarms_format.dart`
  (pure projections), barrel `alarms.dart`. Both overlays are wired in
  `shell/overlay.dart`; the placeholders are gone.
- `Alarm` gained `snoozedUntilMs` (+ `snoozedAt`, JSON key `snoozed_until_ms`).
- `BridgeRepository` gained `snoozeAlarm`, `sendTestAlarm`,
  `setAlarmRuleEnabled`, `saveAppAlarmRule`, `deleteAppAlarmRule` (mock
  implemented; **N15 must implement on the real transport / persist app rules**).
- `MockBridgeRepository.disconnect()` (and a `ble-dropped` that goes offline)
  raises a `bridge_unreachable` app insight once when a cook is active (N11.15).

**Contract deviations / decisions**

- The pure policy lives in `lib/data/alarms/` (not `lib/domain/`) because the
  alarm it reasons about is the data-layer `Alarm`; it imports no Flutter and
  runs under `dart test`.
- **N11.10 "prefer my own alarms"**: an active app insight (or app alarm)
  silences a **non-critical** device alarm's notification. A critical device
  alarm never defers and device alarms stay authoritative in the list (I2). This
  is the interpretation the tests pin.
- **N11.16** is add/edit/delete/toggle for the **app** tier only; device rules
  are toggle-only and `saveAppAlarmRule` refuses a non-app rule. App rules are
  held on the mock repository (not prefs); N15 decides persistence.
- N11.14 ships the preference, the monitoring card and the policy's
  `monitoringEnabled` (withdraw-all). No Android service is started here.
- Q4 resolved: pause is display-only; the policy reads only alarms + the wall
  clock (test "Q4 — pause never suppresses alarms").

**Keys** — sheet `alarms-sheet`; active `alarms-active`, `alarms-active-<id>`,
`alarms-ack-<id>`, `alarms-ack-all`, `alarms-active-count`,
`alarms-all-clear`, `alarms-finding-<name>`; delivery `alarms-delivery`,
`alarms-delivery-verdict`, `alarms-test`; rules `alarms-device-rules`,
`alarms-device-rule-<id>`, `alarms-device-toggle-<id>`,
`alarms-device-authoritative`, `alarms-app-rules`, `alarms-app-rule-<id>`,
`alarms-app-toggle-<id>`, `alarms-app-edit-<id>`, `alarms-app-delete-<id>`,
`alarms-app-add`, `alarms-app-never-overrides`, editor `alarms-app-editor`,
`alarms-app-name`, `alarms-app-severity-*` (the 3 `FilterChips` options),
`alarms-app-save`, `alarms-app-cancel`; preferences `alarms-preferences`,
`alarms-pref-prefer`, `alarms-pref-quiet`, `alarms-pref-monitoring`,
`alarms-monitoring`, `alarms-monitoring-copy`; detail `alarm-detail`,
`alarm-detail-severity`, `alarm-detail-rule`, `alarm-detail-fired`,
`alarm-detail-tier`, `alarm-detail-copy`, `alarm-detail-why`,
`alarm-detail-why-<label-slug>`, `alarm-detail-ack`, `alarm-detail-snooze`,
`alarm-detail-graph`, `alarm-detail-note`, `alarm-detail-missing`,
`alarm-detail-done`.

**Gotchas**

- `alarmsNowProvider` (in `alarms_sheet.dart`) pins the relative times; any test
  that settles the sheet must override it (or the times are non-deterministic).
- `AlarmTier` is defined twice (data `model/alarm.dart` and design `atoms.dart`);
  import one with `as`/`hide` in feature files, as `live/alarm_strips.dart` does.
- `AlarmDetailSheetBody` reads its id from `OverlayRequest.props['id']` captured
  in `resolveOverlay`; `?overlay=alarmDetail&id=…` works by deep link.
- The alarms sheet renders inside the shell's `ShellSheet` scroll view; in widget
  tests wrap it in a `SingleChildScrollView` and use `ensureVisible` for the
  lower toggles.