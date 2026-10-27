# 13 — UI/UX Implementation Contract

**Status:** Approved UI baseline, production implementation not started · **Date:**
2026-10-26 · **Baseline:** the `app/` prototype in this tree (working tree after
`e6aa7b5`)

This document is the bridge between the clickable prototype and the production
app. The prototype is no longer a proposal or a mood board: its screens,
hierarchy, states, copy and interactions are the contract. Production work
replaces the prototype's in-memory fixtures with real business logic **behind the
same widgets** and maps every visible value to a named state.

If a production edge case is not covered here, [06 — Flutter App](06-app.md) and
[12 — Copy & Label Review](12-copy-and-label-review.md) decide the copy and
behaviour. If a screen needs a new control, destination, or state, update this
document first; do not invent UI while wiring data.

The prototype is a review artifact, not a product build. It contains no BLE,
database, permission, network, or firmware code.

---

## 13.1 What is fixed and what is variable

| Fixed (do not redesign while wiring) | Variable (business logic supplies it) |
|---|---|
| Three destinations: Live, History, Settings | Connection phase, freshness, signal, battery, counts |
| Setup flow and its named failure states | Which permission/scan/pairing state is active |
| Screen composition, visual hierarchy and card structure | Values, timestamps, units, dates, progress |
| Copy in [12](12-copy-and-label-review.md) and the state vocabulary | Whether an action is enabled, disabled or pending |
| Per-probe identity `P1`–`P4` plus colour | Probe presence, readings, sparkline history |
| History filters, chart, Summary and Cooks | Series, gaps, statistics, detected cooks |
| Settings object model and immediate-save rules | Persisted config, storage statistics, offline reasons |
| Dark/light themes, type scale, spacing, motion | Platform state, locale, text direction |
| Confirmation sheets that name exact loss | Exact counts, date ranges and live object names |
| Lab is debug-only and never in release | Which scenarios are available in a review build |

Production must not show fixture values, “simulated” labels, fake success, or a
generic spinner in place of a named state.

---

## 13.2 Screen and navigation map

```
App
├── Setup (first run, or after Forget / Factory reset)
│   ├── Connect your Bridge
│   ├── Permission primer / Bluetooth off / denied / blocked / unsupported
│   ├── Scanning / No Bridge found / Nearby bridges / protocol mismatch
│   ├── Pair with the Bridge → Pairing… → first sync → Live
│   ├── Pairing failures (wrong code, timeout, stale bond, phone list full)
│   └── History on this phone (orphaned archive; review/delete only)
├── Shell
│   ├── Live
│   │   ├── Connection card → Bridge details
│   │   ├── Probe tile → History (P#, 1 hour)
│   │   ├── Inline notices → troubleshooting / Bridge details
│   │   └── Billows card (only when detected) → Billows status
│   ├── History
│   │   ├── Filters (range + probe + reset)
│   │   ├── Chart → full-screen chart
│   │   ├── Chart help sheet
│   │   ├── Summary (Latest / Min / Max, sort)
│   │   ├── Cooks → all-cooks sheet → Cook view
│   │   └── Empty / offline / overwritten / estimated states
│   └── Settings
│       ├── Bridge status → Bridge details
│       │   ├── Smoke X4 pairing → Re-pair Smoke X4
│       │   ├── Bridge name / Bridge screen timeout / Billows
│       │   ├── Technical details / Connection log
│       │   └── Bridge actions → confirmations → power-off screen
│       ├── History & storage → delete phone history / clear Bridge history
│       ├── Preferences → units / Appearance
│       └── About this app → About (debug: Experimental lab)
└── Debug-only Experimental lab (never release)
```

Rules:

- Root screens use a plain centred app-bar title. Pushed detail screens use the
  compact title treatment already in the prototype; do not add a second title
  inside the content.
- The app bar has no connection chip. Live owns the connection status; History
  shows one banner only when degraded; Settings uses its Bridge header.
- Detail screens are pushed on top of the shell. Selecting Live/History/Settings
  in the bottom bar preserves each tab's scroll, filter and chart state.
- The full-screen chart and Cook view are separate routes, not replacements for
  the History tab state.
- Bottom sheets are used for filters, help, confirmations and short editors.
  They keep the underlying context visible and are dismissible without side
  effects unless a destructive action was confirmed.

---

## 13.3 Production ownership

Retain the prototype's visual layer and move all state ownership behind it.

| Prototype path | Production treatment |
|---|---|
| `app/lib/theme/` | Keep. It is the design-token source. |
| `app/lib/widgets/` | Keep the shared cards, banners, status LED, signal meter, tiles, chart, sparkline, pills and loss sheet. Remove lab-only helpers from release. |
| `app/lib/features/` | Keep the screens and composition. Rename imports from `prototype/` to view models/controller. |
| `app/lib/prototype/prototype_controller.dart` → `app/lib/app/bridge_controller.dart` | T05 moved the controller to the production seam. T06 replaces its screen-facing fields with view states. The scenario switchboard and fixture getters must not ship. |
| `app/lib/prototype/fixtures.dart` | Test-only fixtures. Production data comes from SQLite/sync. |
| `app/lib/prototype/scenario_lab.dart` | Debug/review only. Never reachable in a release build unless explicitly enabled. |
| `app/lib/prototype/formatters.dart` | Move reusable formatting into a locale-aware production formatter; keep pure functions testable. |
| `app/test/widget_test.dart` | Reuse the state cases; retarget to production controllers and add golden coverage. |
| `app/tool/ui_screenshots_test.dart` | Keep as the review/golden generator; update names only when the UI intentionally changes. |

### View models

The widget layer consumes immutable view state. It must not call BLE, SQLite or
`shared_preferences` directly.

```dart
class LiveViewState {
  final LinkState link;
  final Duration? connectedFor;
  final DateTime? lastContactAt;
  final int signalBars;
  final String signalLabel;
  final TelemetryState telemetry; // fresh, delayed, stale, lost, unpaired
  final Duration? telemetryAge;
  final List<ProbeView> probes; // always four, in order
  final SyncViewState sync;
  final bool storageOk;
  final BillowsView? billows; // null = never detected / no card
  final bool billowsLostThisSession;
  final bool showSavedReadings;
  final String? syncError;
}

class ProbeView {
  final int number;          // 1..4
  final double? tempF;       // null = detached / unavailable
  final ProbeFreshness freshness;
  final List<ChartPoint> lastHour;
  final double? deltaLastHourF;
}

class HistoryViewState {
  final HistoryRange range;  // oneHour, sixHours, twentyFourHours, twoDays, custom
  final DateTimeRange? customRange;
  final int? probe;          // null = all
  final HistorySeries series;
  final List<ProbeStats> stats;
  final List<GapView> gaps;
  final List<CookView> cooks;
  final HistorySort sort;
  final bool estimated;
  final bool missingFromBridge;
  final bool offline;
  final bool hasAnyHistory;
  final SyncViewState sync;
}
```

The same pattern applies to `SetupViewState`, `BridgeDetailsViewState` and
`SettingsViewState`. Per-field save state is `idle / saving / saved / error`, not
one global flag.

### State-source mapping

| Prototype field | Production source |
|---|---|
| `phase` | Connection state machine (scan/connect/bond/secure/sync/live/reconnect/fail/blocked) |
| `bridgeLastContactAge`, `bridgeConnectedFor` | Monotonic receipt time and session start, not the Bridge clock |
| `probes`, `probeHealth` | Latest `live` notification plus freshness calculation |
| `smokeXStatus`, `smokeXLastPacketAge` | Last valid X4 packet and the 90 s / 10 min boundaries |
| `storageOk` | `live.flags.storage_ok` / `stats.flags.storage_ok` |
| `syncState`, `syncProgressPercent` | Sync engine status and completed/total records |
| `billowsAttachment`, `smokeXChannel4SetF` | `billows_attached` and the validated target field; target unknown → `—` |
| `historyRange`, `historyProbe`, `historyCustomRange`, `historySort` | View-model state persisted across tab switches; not recalculated from widgets |
| `history series` / `ProbeRangeStats` | SQLite queries + decimation + summary computation |
| `cooks` | Pure cook detection over recorded sample timestamps and gaps |
| `connectionLog` | Persisted app-side event log, newest first |
| `bridgeRecords`, `phoneRecords`, `bridgeCapacity` | `stats` characteristic and local DB counts |
| `units`, `displayTimeoutSeconds`, `deviceName`, `themeMode` | Preferences plus `config` read-modify-write with queued writes |
| `savedDataSize`, `savedDataRange` | Local DB metadata, never a fixture string |
| `simulateSync`, `simulateSave`, `retryConnection`, setup timers | Real controller operations and bounded async state |
| `ScenarioLabScreen` | Debug-only route, gated by `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB` |

---

## 13.4 Complete state inventory

Every row below must exist in production and have a widget test or a documented
manual check. The wording comes from [12](12-copy-and-label-review.md).

### Setup

| State | Required UI | Primary / secondary action |
|---|---|---|
| No saved Bridge | “Connect your Bridge”; PRG instruction; saved-history notice if present | `Find bridge` / `View history on this phone` |
| Permission primer | “Allow Bluetooth to find your Bridge”; Android 12+ vs 7–11 explanation; “only needed to find your Bridge” | `Continue` / `Not now` |
| Bluetooth off | Named cause; Bridge keeps recording | `Open Bluetooth settings` / `Check again` |
| Permission denied | Named cause; can grant again | `Grant permission` / `Open app settings` |
| Permission blocked | Android settings explanation | `Open app settings` / `Back` |
| Unsupported phone | No BLE scanning; saved history remains reachable | `Close` / `View history on this phone` |
| Scanning | “Looking for your Bridge…”; stops after 10 s; checks remembered Bridge first | `Cancel` |
| No results | “No Bridge found”; distance and PRG hint; saved history footer | `Try again` / `Open Bluetooth settings` |
| Results | “Nearby bridges”; remembered first; `P4 225°F · 87%`; signal words; legacy row | row tap / `Rescan` |
| Protocol mismatch | “Update the app to use this Bridge”; Bridge unchanged | `Update app` (+ saved history / learn more in production) |
| Passkey | “Pair with the Bridge”; example code only; “Only the Bridge screen shows the real code.” | `Pair` / `Cancel` |
| Pairing | “Pairing…”; Connecting → Checking the code → Syncing recent history | — |
| Wrong code | “The code didn’t match”; retry; Android settings after repeat failure | `Try again` / `Open Android settings` |
| Prompt timeout | “No prompt appeared”; notification-shade hint | `Try again` / `Open Bluetooth settings` |
| Stale bond | “This phone’s pairing is out of date”; explains Bridge reset | `Forget and re-pair` / `Cancel` |
| Phone list full | “This Bridge already has 4 phones paired”; USB recovery if no paired phone | `Try again` / `Cancel` |
| First sync | “Loading history”; progress; Time set → last 24 hours → older readings → Live ready | `View live readings` |
| Orphaned history | “History on this phone”; readings, range, storage, delete; never auto-deleted | `Delete history from this phone…` / `Back` |

### Live

| State | Required UI |
|---|---|
| Healthy | Chain + `Bridge connected · 2h 14m` + `Receiving readings · updated 12s ago`; four quiet tiles; sparklines |
| Aging | Bridge row stays healthy; tile says `Updated 62s ago`; amber cue plus text |
| Stale | Bridge stays connected; `No readings for 4 min`; values remain |
| Frozen / lost X4 | `Smoke X4 signal lost · 10 min ago`; values dim; one inline notice with `Troubleshoot` |
| Syncing recent | `Syncing saved readings`; progress; “Newest readings load first.” |
| Backfill | `Loading saved readings`; “Your latest readings are ready. Older readings continue in the background.”; `Slow connection` when MTU is low |
| Sync failed | `History sync failed`; live readings still update; `Retry sync` |
| Reconnecting | `Reconnecting… attempt 2 of 6`; bounded retry |
| Failed | `Can’t reach the Bridge`; retry/forget escape; “Recording continues on the Bridge.” |
| Blocked | Named reason and the system settings action |
| Offline with cache | `Bridge disconnected · last connected 2h ago`; `Showing saved readings · last reading 20 min ago`; signal hidden; values dim |
| Offline without cache | `Bridge disconnected · nothing saved yet`; no fake probe values; one next action |
| No X4 data | `No data from Smoke X4` notice; SYNC-mode help |
| Detached probe | `—` and `Not connected`; never `0 °F` |
| No probes | `No probes connected`; “Plug a probe into the Smoke X4 to see a reading.” |
| No sparkline history | `No history yet`; tile height unchanged |
| Storage failure | `Not recording`; “Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.” |
| Billows detected | `Billows`; `Set temp`; `Last detected`; `Set on the Smoke X4.`; no Connected pill |
| Billows lost | One `Billows not detected` notice; `View connection log` |
| Billows never detected | No card and no notice |

### History

| State | Required UI |
|---|---|
| Default | `24 hours`, `All probes`, four series, Summary, Cooks |
| Ranges | `Last hour`, `Last 6 hours`, `Last 24 hours`, `Last 2 days`, `Custom range…`; trigger `1 hour`, `6 hours`, `24 hours`, `2 days`, `Custom` |
| Custom range | Sheet starts with all saved history; start/end date and time; `All saved history`, `Today`, `Yesterday`, `Last 6 hours`; `Apply` / `Cancel`; validates range |
| Probe filter | `All probes`, `P1`–`P4`; no-data options disabled with `No data`; reset icon appears only with an active filter |
| Chart | Shared/auto y-axis, one unit, nice ticks, crosshair + pinned tooltip, pan/zoom/fit, `Now` when panned, latest dots, gap bands, area fill for one probe |
| Chart help | “Reading the chart” sheet; tap, pan/zoom, Cooks, gaps, shared scale, estimated times |
| Summary | `Latest`, `Min`, `Max`; no deltas; unit once; `Probe order`, `Hottest`, `Highest`, `Latest reading`, `Since cook start` |
| No cook detected | `Since cook start` disabled with `No cook detected yet` |
| Cooks | Card label `Cooks`; “Grouped automatically from your readings”; latest three; `In progress` on the live cook; `View all` |
| Cook view | App bar `Cook`; probe filter; `Recorded history`; end label is the cook end, not `Now`; back returns to unchanged History state |
| Full-screen chart | Dedicated route; portrait or landscape; window label, legend, zoom, close; no orientation lock |
| No readings at all | `No readings yet`; “The Bridge records whenever it’s on and paired with the Smoke X4.”; `View Live` |
| No data in range | `No readings in this range`; `Probe 3 has no readings in this range`; `Show all probes` |
| Offline with cache | Banner `Showing saved readings` + last reading; chart and Summary still render |
| Estimated time | `times estimated` beside metadata; chart help explains it |
| Overwritten before sync | Gap label `Not synced`; permanent-loss explanation; never a straight line |
| Empty filtered probe | No line, no zero; `—` values in Summary |

### Settings, Bridge details and confirmations

| State | Required UI |
|---|---|
| Settings connected | Bridge status, `History & storage`, units, Appearance, About |
| Settings offline | `Bridge disconnected` + last connected; controls disabled with reasons; local delete/forget still available |
| Units | Segmented `°F` / `°C`; applies immediately; offline copy says the Bridge screen updates on reconnect |
| Appearance | `System / Light / Dark`; immediate; local only |
| History & storage | `History on this phone` and `History on the Bridge`; separate counts/ranges/rules; delete and clear actions |
| Bridge details | Status, sync/reconnect, disconnect, Smoke X4 pairing, re-pair, name, timeout, Billows, technical details, connection log, actions |
| Name edit | Dialog; `Saving…` / `Saved` / `Couldn’t save`; no save-all bar |
| Timeout | 30 sec / 1 min / 2 min / Never; immediate; offline disabled |
| Billows | Status only; `Last observed state` when offline; `Set temp`; no mode/target editor |
| Connection log | Bridge, Smoke X4, Billows and sync events in one timeline; newest first |
| Destructive actions | Exact loss, count, date range, kept-copy note; confirm before sending; disconnect can mean success |
| Power off | Confirm; then “Bridge is off”; hold PRG 1.5 s to turn it on |
| Factory reset | Confirm; explain all phones, settings, readings and clock; return to setup; phone history kept |
| Forget this phone | Confirm; clear local saved Bridge; keep phone history; setup shows orphaned history |
| About | App/firmware/protocol/Bridge ID, USB-only update, privacy, attribution; no prototype card |

### Bridge screen (OLED)

The OLED is monochrome and has no app chrome. The app preview in
`features/device/device_preview_screen.dart` is the visual reference for the
labels in [07](07-display-and-controls.md): `Probes`, `Connection`, `Billows`,
`Bridge`; overlays `Pairing code`, `Power off`, `Storage failure`, `Resetting`,
`Clearing log`, `Off`, `Boot`.

### Experimental lab

Debug/review only. It must cover every state in this document, preserve search /
reset / first-run flow, and never be reachable in a release build unless
`ENABLE_EXPERIMENTAL_LAB=true` is explicitly set.

---

## 13.5 UI lifecycle flows

### First launch

1. Load saved Bridge and local DB.
2. No saved Bridge → Setup “Connect your Bridge”. If local history exists, show
   the counts and `View history on this phone`.
3. `Find bridge` → permission primer if the platform permission is not granted →
   OS prompt.
4. Scanning for 10 s; remembered Bridge first.
5. Select → read `info` → protocol check.
6. Passkey instruction → OS bond → pairing progress.
7. Set time + recent-first sync → `Loading history` → `View live readings`.
8. Land on Live. Never end on a summary/dead screen.

### Returning launch

1. Load saved Bridge and local history.
2. Scan for the remembered Bridge.
3. Found → connect → secure → read live → set time → forward catch-up from local
   max; no 24 h re-read.
4. Not found after 10 s → last-known Live with `Looking for the Bridge…` and a
   manual Connect action; History remains usable.
5. App resume → health check + forward sync. No background scanning or
   foreground service.

### Connection health

- A live notification is fresh for 90 s. 90 s–10 min is delayed/stale; after
  10 min the X4 link is lost. BLE link state and X4 telemetry are separate.
- No notification for 110 s → read `live`. Success with a fresh age returns to
  Live; success with a quiet X4 stays stale; failure → reconnect.
- Any GATT disconnect → reconnect with backoff 1, 2, 4, 8, 15, 30 s, then the
  named `Can’t reach the Bridge` state.
- Never present cached data as live. One status surface, not four repeated
  no-reading lines.

### History

- First open: `24 hours`, `All probes`.
- Arriving from a probe tile: `1 hour`, that probe.
- Range/probe/sort persist across tab switches and app resume; a deliberate
  reset is the only thing that clears them.
- Custom range opens with all saved history and never extends beyond it.
- Cook view is a pushed route; closing it returns to the exact History state.
- Offline with cache keeps the chart usable and labels it as saved.
- Deleting history is always explicit and confirmed with counts and dates.

### Settings and device actions

- Preferences apply immediately; no global save bar.
- Unit changes update Live, History, Billows, confirmations and the OLED (queued
  if offline).
- Bridge name/timeout require a connection; disabled controls explain why.
- `Sync now` and `Reconnect` live only in Bridge details.
- Forget/reset return to Setup and keep phone history until explicitly deleted.
- Power off shows the wake instruction; the app never pretends the Bridge is
  reachable while off.

### Units, theme and locale

- Units are one conversion path used everywhere; sample storage stays °F.
- Theme is `System / Light / Dark`, local only, applied immediately.
- Times and dates use the device locale and 12/24-hour setting. No hard-coded
  `PM`/`AM` strings in production widgets.

---

## 13.6 Visual, interaction and accessibility contract

- **Width:** the UI must work at 320 dp and scale up. Chart, Summary and Cooks
  are the stress points.
- **Themes:** dark and light are both first-class; no colour-only state.
- **Type:** tabular figures for every temperature/axis; Live value 40–46 px;
  chart labels ≥11 px; body 14–15; labels 11–12.
- **Touch:** every actionable target ≥48 dp, including chart controls, filter
  menus, rows and destructive actions.
- **Status:** use a label and an icon in addition to colour for healthy,
  delayed, lost, blocked, error and destructive states.
- **Motion:** 150–220 ms ease-out; range changes crossfade; reduced-motion is
  respected. No bouncy or decorative animation.
- **Haptics:** light impact on filter/range changes, selection tick on scrub,
  success only for a confirmed device action.
- **Charts:** never connect across a gap; no zero for missing data; Summary is
  the accessible table equivalent; chart has a screen-reader summary.
- **Copy:** sentence case for buttons/labels; product names keep their casing;
  no raw exceptions or platform error strings; no “simulated” text on product
  screens.
- **Formatting:** `165.2°F` (no space), `2h 14m`, `1 min`, `12s ago`, locale
  dates/times, `readings` not `records` in user copy.

---

## 13.7 Prototype-only pieces and known gaps

These are intentional prototype details or gaps that production must close. They
are tracked in the task plan, not silently copied.

| Item | Production action | Task |
|---|---|---|
| Permission primer is a lab state; `Find bridge` goes straight to scanning | Request permission after tap and show the primer only when needed | T33 |
| Offline-without-cache still renders fixture probe values | Render no values and one offline/no-cache status; never show cached values as current | T34, T43 |
| Opening `Custom range…` changes the selected range before the sheet is applied | Apply only on `Apply`; `Cancel` restores the previous range and viewport | T42 |
| About long-press and app-bar lab entry share a gate, but no release-build test proves it | Keep the shared debug/`ENABLE_EXPERIMENTAL_LAB` gate and verify it in the release build | T64 |
| Setup protocol-mismatch/unsupported actions are only `Close` | Add `Update app`, `View history on this phone`, `Learn more` where applicable | T33 |
| Bridge details pill says `Receiving` | Use `Receiving readings` only when fresh; otherwise `No readings for 4 min` | T51 |
| Summary’s disabled sort reads `Since cook start (no cook detected)` | Keep `Since cook start` disabled and show `No cook detected yet` as supporting copy | T42 |
| Probe delta uses `+3.8°F` rather than an arrow | Keep the sign; it is clearer and accessible | Accepted |
| All strings are hard-coded | Centralize strings, use locale formatting, add a banned-term copy test | T54, T64 |
| Fixtures, simulation timers and fake OS prompts | Remove from release; keep under test/debug only | T06, T64 |
| Scenario lab uses the production `BridgeController` | Keep as a debug-only adapter; no release import | T06, T64 |
| Screenshot set is a review artifact | Regenerate intentionally and make the production set a release gate | T54, T64 |
| Appearance theme is a lab switch today | Persist it in Preferences and apply on launch | T51 |

---

## 13.8 Evidence and test keys

Stable keys from the prototype must be preserved or deliberately renamed with a
test update:

- Live: `status.connection`, `live.probe.1`–`4`, `live.sparkline.1`–`4`,
  `live.billows`
- History: `history.filters`, `history.range.menu`, `history.range.1h/.6h/.24h/.2d/.custom`,
  `history.filter.menu`, `history.filter.all/.p1`–`.p4`, `history.filters.reset`,
  `history.chart`, `history.summary`, `history.cooks`, `history.cooks.open`,
  `history.zoom.out/.in/.fit/.now`
- Cook view: `pastCook.history`
- Settings: `settings.bridge.status`, `settings.history.logs`,
  `settings.units`, `settings.appearance`
- Bridge: `bridge.name`, `bridge.timeout`, `bridge.billows`, `bridge.repair`,
  `bridge.connectionLog`
- Navigation/lab: `nav.experimental`

Required evidence before a UI task is done:

1. `flutter analyze` and `flutter test` clean.
2. Widget tests for every state in §13.4 that the task owns.
3. Dark and light screenshots at 390 × 844; a 320 dp layout test for Live,
   History and Settings.
4. No overflow, no raw exception, no fixture text in the production tree.
5. Screen-reader semantics for the connection card, probe tiles, chart summary,
   filters, Summary rows and destructive actions.
6. Screenshot/golden changes reviewed intentionally, not accepted blindly.

---

## 13.9 Task map

| UI surface / behaviour | Primary tasks |
|---|---|
| Production UI scaffold, view-model seam, screenshots | T05, **T06**, T07 |
| Setup, permission, scan, pairing, first sync, orphaned history | T33 |
| Live connection card, probes, sparklines, notices, Billows, refresh | T34 |
| Connect/secure/sync lifecycle, time sync, reconnect | T35 |
| History V0 shell with recent data | T36 |
| Full History: ranges, filters, chart, Summary, Cooks, full-screen, custom | T42 |
| Health/stale/offline/error states | T43, T45 |
| History & storage and explicit deletion | T44 |
| UI state matrix, accessibility, copy lint, golden suite | **T54** |
| Settings root, Bridge details, History & storage, About, Appearance | T50, T51 |
| Destructive actions, power-off screen, saved-history escape | T52 |
| Units, time, theme end-to-end | T53 |
| Billows status-only surfaces | T58 |
| OLED pages, overlays and labels | T22 |
| Release lab gate, parity walk, final UI acceptance | T64, T67 |

---

## 13.10 Definition of done

The UI/UX lifecycle is complete when:

- Every screen and state in §13.4 is reachable in production with real data or a
  named empty/error state.
- The prototype's visual layer is intact; only the state source changed.
- No fixture, simulation, lab-only control or fake success is reachable in a
  release build.
- Units, dates, times and counts are consistent across Live, History, Settings,
  confirmations and the OLED.
- The 320 dp, dark/light, offline, reconnect, no-data, detached-probe,
  destructive-action and accessibility checks pass.
- Screenshots and widget tests are updated in the same change as any intentional
  UI change.
