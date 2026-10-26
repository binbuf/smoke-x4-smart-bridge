# 06 — Flutter App

## 6.1 Product shape

The app has three destinations and one setup flow:

```
┌─────────────────────────────────────────┐
│  Live        History        Settings     │  NavigationBar
├─────────────────────────────────────────┤
│  Live: connection-chain card, 2×2 probe  │
│        tiles + sparklines, Billows       │
│  History: range/probe filters, chart,    │
│           summary, past cooks            │
│  Settings: one Bridge section,           │
│            preferences, storage, about   │
└─────────────────────────────────────────┘

Setup (pushed above the shell when no bridge is remembered):
  connect → scan → select → passkey → sync recent → live
```

There is **no** separate Graph tab, session list, cook clock, alarm tab,
onboarding wizard, multi-bridge picker, or notification service. **History** is
the archive and the only multi-probe chart.

Probe identity in the MVP is probe order and colour: `P1`, `P2`, `P3`, `P4`.
There are no probe names, roles or tags in the app, the OLED or the config.

## 6.2 Stack and structure

| Concern | Choice |
|---|---|
| UI | Flutter stable, Material 3, Android first (iOS out) |
| Min/target SDK | 24 / 35 (or the current stable target) |
| State | One `BridgeController extends ChangeNotifier`; no Riverpod/Bloc |
| BLE | `flutter_blue_plus`, behind a narrow `BleClient` seam |
| Local DB | SQLite via `sqflite`; in-memory/FFI for tests |
| Chart | Custom-painted `HistoryChart` and `ProbeSparkline`; pure-Dart data model |
| Prefs | `shared_preferences` for small settings only |
| Permissions | `permission_handler` or platform channels; Android 12+ BLE permissions |
| Navigation | `NavigationBar` + `IndexedStack`; `Navigator.push` for setup/settings detail |
| Tests | `flutter_test`, fake BLE peripheral, in-memory SQLite |

No HTTP client, WebSocket, mDNS, notifications, foreground service, OTA, or
cloud package is included.

### Directory shape

```
app/lib/
├── main.dart
├── app/
│   ├── bootstrap.dart          DI, DB open, controller creation
│   ├── smoke_bridge_app.dart   MaterialApp, theme
│   ├── shell.dart              NavigationBar + IndexedStack
│   └── bridge_controller.dart  connection + sync + settings orchestration
├── domain/
│   ├── models/                 BridgeInfo, LiveState, Probe, Config, Sample
│   ├── freshness.dart          live / stale / offline calculation
│   ├── gaps.dart               split series at >90 s
│   └── decimate.dart           LTTB / min-max envelope
├── data/
│   ├── ble/
│   │   ├── ble_client.dart     scan/connect/bond/MTU/read/write/subscribe
│   │   ├── codecs.dart         generated/checked payload codecs
│   │   └── bridge_link.dart    GATT procedure layer
│   ├── db/
│   │   ├── database.dart       schema + migrations
│   │   └── sample_dao.dart     range queries, bulk insert, deletion
│   ├── repository.dart         cache-first reads/writes
│   └── sync.dart               cursor sync + gap detection
├── features/
│   ├── setup/                  connect, scan, pairing, progress
│   ├── live/                   probe tiles, sparklines, Billows, banners
│   ├── history/                chart, filters, summary, past cooks, empty states
│   ├── settings/               preferences, bridge, history/storage, about
│   └── common/                 banners, sheets, empty states, error views
└── platform/
    └── permissions.dart        Android permission/Bluetooth state
```

`domain/` imports no Flutter. `data/ble` knows GATT slots and payload bytes, not
widgets. `features/` composes the controller and repository.

## 6.3 Connection lifecycle

### State machine

```
UNINITIALIZED
  ├─ no saved bridge ──► SETUP
  └─ saved bridge ─────► SCANNING
SCANNING ── found remembered bridge ──► CONNECTING
SCANNING ── no results after 10 s ──► NO_RESULTS (retry / settings)
SETUP ── scan/select ──► CONNECTING ──► PAIRING ──► SECURING
SECURING ── read info + live; subscribe ──► SYNCING ──► LIVE
LIVE ── link lost ──► RECONNECTING (backoff 1,2,4,8,15,30 s)
RECONNECTING ── all six attempts fail ──► FAILED (tap to retry / forget)
LIVE ── no notification > 110 s ──► STALE
STALE ── read succeeds with fresh age ──► LIVE
STALE ── read succeeds but Smoke X4 quiet ──► STALE
STALE ── new live notification ──► LIVE
STALE ── read fails ──► RECONNECTING
Any ── Bluetooth off/permission denied ──► BLOCKED (named reason)
```

Config/stats are read once the firmware serves them (M4); V0 needs only
`info`, `live`, and `sync`.

- **Scanning**: scan for the service UUID, stop after 10 s, show results. A
  remembered bridge is preferred by device ID, then by name. Do not auto-connect
  to an arbitrary first result if a remembered bridge is present.
- **Connecting**: connect GATT; read `info` (open); request MTU 247.
- **Pairing**: if the link is not encrypted, show the passkey instruction, then
  call the platform bond API. The OS owns the passkey dialog.
- **Securing**: subscribe to `live`, `result`, `sync_data`; read `info` and
  `live`. Read `config`/`stats` when the firmware serves them.
- **Syncing**: first sync after pairing sets the clock and pulls the recent
  24 h, then backfills. A reconnect with existing data sets the clock and pulls
  **forward from the local max** immediately; it does not re-read 24 h.
- **Live**: append notifications; periodic forward sync every 60 s; health
  watchdog.
- **Reconnecting**: exponential backoff 1, 2, 4, 8, 15, 30 s. A user
  pull-to-refresh or app resume cuts the wait short.
- **Failed**: after all six attempts show "Can’t reach the bridge" with a Retry
  button and a "Forget this phone" escape. Never spin forever silently.
- **No results**: after the 10 s scan, show "No bridge found" with Retry,
  "Open Bluetooth settings", and a hint to hold PRG if the bridge is asleep.
- **Blocked**: Bluetooth off, permission denied, or unsupported phone. Each has
  a specific message and a button that opens the relevant system surface.

### Health checks

- Notifications arrive on each sample (~30 s). If none for 110 s, read `live`.
- If the read succeeds, update the age: fresh (`age_s` within 90 s) → `LIVE`;
  quiet Smoke X4 → stay `STALE`. A bridge that answers but has no new readings
  is not offline.
- If the read fails, mark `RECONNECTING`.
- A GATT disconnect always moves to `RECONNECTING`, even if the last sample was
  recent.
- `live.age_s` is displayed as "last reading Xs ago"; the app also uses its own
  receipt time so a bad bridge clock cannot fake freshness.
- The UI uses time, not a health taxonomy: `Updated 62s ago`,
  `No new reading for 4m`, `Showing last saved readings`. `Aging`, `Stale` and
  `Frozen` remain internal.

### App lifecycle

- No foreground service. If Android kills the app, recording continues on the
  bridge.
- On pause, keep the BLE link if the OS allows; on resume, run a health check and
  sync forward.
- Do not scan in the background. Auto-connect happens when the app is in the
  foreground.

## 6.4 Setup and pairing

### First run

1. **Connect your bridge** — a short screen: “Power it on. If the screen is off,
   hold PRG for 1.5 seconds.” Primary action `Find bridge`. If a saved device
   log exists, a secondary `View device log` entry.
2. **Permission** — ask in context when the user taps `Find bridge`, with one
   sentence of rationale. Android 12+ requests `BLUETOOTH_SCAN`
   (`neverForLocation`) and `BLUETOOTH_CONNECT`; Android 11 and below use the
   location permission required by the platform, explained as such.
3. **Bluetooth off** — a named state with an "Open Bluetooth settings" button.
4. **Scan** — live list of nearby bridges, remembered bridge first. Show signal
   as `Strong / Good / Weak`; keep dBm in a detail line. A scan-response preview
   may show `P4 225 °F · 87%` when present.
5. **Select** — connect and read `info`. If the bridge is not the expected
   protocol major, show "This bridge needs a newer app" and stop.
6. **Passkey** — before triggering the OS bond, show:

   > **Pair with the bridge**
   > The bridge’s screen shows a 6-digit code. Enter it in the phone’s prompt.
   > [ Pair ]

   Trigger the OS bond. The bridge displays the code at bonding start. Do not
   show a code in the app; the app cannot know it. The simulated Android prompt
   belongs in the scenario lab, not the product flow.
7. **Pairing outcomes**:
   - success → set time, sync recent, go Live;
   - wrong code → "The code didn’t match." with Retry; after two failures,
     explain how to remove the pairing in Android settings;
   - prompt timeout → "No prompt appeared. Check the notification shade." with
     Retry and "Open Bluetooth settings";
   - pairing out of date (bridge was factory-reset) → remove the OS pairing and
     re-pair, with copy explaining why;
   - phone list full (`info.bonds_free == 0`) → "This bridge already has 4
     phones paired. Forget one from a paired phone, then try again." Do not
     start the OS bond just to discover this.
8. **Success** — land on Live, not a dead summary screen.

If the phone has saved history but no current bridge (first run after a forget
or factory reset), the setup screen shows a small **Device log** entry:
reading count, date range, and a delete action. This is the only way to reach
that data after the bridge identity is removed; it is never deleted
automatically.

### Later launches

- Load the remembered bridge and scan.
- Connect automatically when found; no passkey prompt.
- If the bridge is not found for 10 s, show the last-known Live data with
  "Looking for the bridge…" and a manual Connect button.
- "Forget this phone" clears the saved bridge and the OS pairing only after
  confirmation. It does not factory-reset the bridge and does **not** delete the
  local history; the setup screen offers a **Device log** entry so the user can
  review or delete it explicitly.

## 6.5 Live screen

```
┌────────────────────────────────────────────┐
│ Live                                       │
├────────────────────────────────────────────┤
│   [phone]      →      [bt]      →    [x4]  │
│     App               Bridge         Smoke X4 │
│  This phone          Connected      Receiving │
│                                            │
│ Connected for 2h 14m · last contact 4s ago > │
├────────────────────────────────────────────┤
│ ┌──────────────────┐ ┌──────────────────┐  │
│ │ ● P1             │ │ ● P2             │  │
│ │ 165.2 °F         │ │ 164.0 °F         │  │
│ │ ╭──────╮   +0.8° │ │ ╭──────╮   -0.3° │  │
│ │ ╰──────╯    1h   │ │ ╰──────╯    1h   │  │
│ └──────────────────┘ └──────────────────┘  │
│ ┌──────────────────┐ ┌──────────────────┐  │
│ │ ● P3             │ │ ● P4             │  │
│ │ —                │ │ 225.0 °F         │  │
│ │ Not connected    │ │ ╭──────╮   +2.1° │  │
│ │                  │ │ ╰──────╯    1h   │  │
│ └──────────────────┘ └──────────────────┘  │
├────────────────────────────────────────────┤
│ Billows                   Detected          │
│ CH 4 set temp 225 °F · Read-only           │
└────────────────────────────────────────────┘
```

Rules:

- The **Connection** card is the single status surface on Live. It shows the
  whole chain as simple icons with labels underneath: **App → Bridge → Smoke
  X4**. Tapping anywhere on the card opens Bridge details, where the manual
  `Sync now` action lives.
- The Bridge detail line states when the phone last connected and the current
  session length, for example `Connected for 2h 14m · last contact 4s ago`.
  Offline it becomes `Last connected 2h ago`. The Smoke X4 node keeps its
  `Receiving` / `No recent data` state without repeating a last-data age.
- There is no `Sync now` action on the Live card. The product is designed so
  manual sync is rarely needed; pull-to-refresh remains the recovery gesture.
- There is no small connection chip in the app bar. Healthy status lives in the
  card; a problem state changes the relevant LED and adds one inline notice.
- Four tiles in probe order, always four. A detached probe is **"—" + "Not
  connected"**, never 0 °F and never omitted.
- Probe identity is `P1`–`P4` plus colour. No names, roles or tags.
- Each tile shows a **relative last-hour sparkline** when that probe has history.
  The sparkline is scaled to its own min/max; it communicates shape, not a
  cross-probe comparison.
- Tapping a tile opens **History** with that probe selected and the 1 h range.
- Healthy tiles are quiet: no repeated “Live · updated 4s ago”. A delayed probe
  shows `62s ago`; a stale probe shows `No new 4m`; a detached probe shows
  `Not connected`.
- Offline with cache: dim values and keep one Bridge status surface. Do not
  repeat a no-reading line four times.
- No aggregate preview graph and no footer instruction text on Live.
- Pull-to-refresh reads `live`, runs a forward sync, and reports failure with a
  named error. It is the one action allowed to throw visibly.
- Billows appears **automatically when detected**. There is no off switch, no
  mode switch, no target setter, and no second “Connected” pill. The target is
  simply the Smoke X4 channel 4 set temp; when it has not been validated it
  shows `—`. The Live card shows only the fan name and its two metrics, with no
  explanatory read-only copy. If Billows was detected earlier in the session and
  is now missing, Live shows one `Billows disconnected` notice. Detection and
  loss events join the regular Bridge / Smoke X4 connection log in Settings >
  Bridge; the Billows details screen is read-only and has a focused log.
- The Bridge/health banner appears only on History for degraded states. Live owns
  its own status card.

## 6.6 History screen

### Purpose

History is the archive: chart + per-probe summary + past cooks + data-quality
states. It is not a demo chart and it is not a second dashboard.

### Layout

```
┌────────────────────────────────────────────┐
│ History                                    │
├────────────────────────────────────────────┤
│ [ 24H ▾ ]  [ All probes ▾ ]          ↺     │
├────────────────────────────────────────────┤
│ Oct 24 6:30 PM – Oct 25 6:30 PM            │
│ Saved 2m ago · 4 probes                    │
│                                            │
│ 275 ┤          ╭─╮                         │
│ 225 ┤──╮   ╭───╯ ╰──╮      P4              │
│ 175 ┤  ╰───╯        ╰──╮   P1/P2           │
│ 125 ┤                   ╰──                │
│     └──────────────────────────────        │
│      6:30 PM   2:30 AM   10:30 AM   Now    │
│  ● P1 166.0° ● P2 171.9° ● P4 215.8°       │
│  Pan · pinch or scroll to zoom   − + ⛶ Now │
├────────────────────────────────────────────┤
│ Summary                         °F  Probe ▾│
│ PROBE   CURRENT        MIN       MAX       │
│ ● P1    166.0°         149.9°    181.5°  > │
│ ● P2    171.9°         148.4°    175.9°  > │
│ ● P3    159.6°         132.6°    168.2°  > │
│ ● P4    215.8°         202.7°    247.0°  > │
├────────────────────────────────────────────┤
│ Past cooks                     View all    │
│ Detected from recorded readings            │
│ [OCT 25] Today                             │
│          9:10 AM – 6:30 PM · 9h 20m · 4    │
│ [OCT 24] Yesterday                         │
│          10:05 AM – 7:20 PM · 9h 15m · 4   │
└────────────────────────────────────────────┘
```

### Features

- Range menu: `1H`, `6H`, `24H`, `2D`, `Custom`. `Custom` starts with the entire
  archive in memory and opens a date-and-time sheet for exact start/end minutes.
- Probe menu: `All probes`, `P1`–`P4`. A probe with no data in the range is
  disabled and labelled `No data`.
- The two compact dropdown buttons sit in one card; the reset control appears as
  an icon only when a filter is active.
- Past cooks are reached from the dedicated card below Summary; the filter header
  does not duplicate that entry point.
- Full-screen chart: a dedicated view, not a restyled History page. It never
  forces an orientation; portrait and landscape are both allowed. The graph
  fills the screen either way, with only a compact window label, legend and
  zoom controls around it.
- Shared y-axis when all probes are visible; auto-scale to the selected probe
  when one is selected.
- Nice y-axis ticks (1/2/2.5/5 × 10ⁿ) and one unit label (`°F` / `°C`).
- Locale-aware time labels; date labels at midnight for multi-day ranges.
- Crosshair + tooltip with the timestamp and every visible probe value. The
  tooltip is pinned until the user taps elsewhere.
- Drag to pan; pinch or mouse-wheel/scroll to zoom; double-tap to fit. A visible
  `Now` action appears when the view is not at the latest data.
- A compact legend under the chart shows the visible probes and their latest
  values; single-probe views add a soft area fill.
- Latest-point dots at the end of each visible series.
- Gap bands with a reason (`No data`, `Overwritten`) and a tap explanation.
  Never connect across a gap.
- Estimated-time badge when any visible sample is estimated.
- Offline cache banner on History; the chart still renders.
- `Expand` for a full-screen chart for precise scrubbing.
- Empty states: no readings at all, no readings in the selected range, offline
  with no cache.
- Accessibility: a chart summary for screen readers and a Summary table that
  does not depend on colour.

### Summary and sorting

The summary is where sorting belongs. A time series is chronological.

| Field | Meaning |
|---|---|
| `Current` | Newest valid reading in range |
| `Min` | Lowest valid reading in range |
| `Max` | Highest valid reading in range |
| `No data` | No valid reading for that probe in range |

There are **no temperature deltas** in the summary. Show current, min and max
only, in aligned columns. Default order is probe order. Sort options: hottest
now, highest peak, most recent and **since cook started**. The last option uses
the recorded sample timestamps to find the current cook (or the most recent past
cook when none is in progress) and orders probes that have reported since that
start with the most recent first. It shows the cook start age above the rows so
the detected reference is explicit. Tapping a row focuses that probe.

### Past cooks

For every archive range, show detected cooks derived from recorded readings and
gaps. A cook row carries its date, exact start/end time, duration, probe count and
whether it contains a gap. `View all` in the Past cooks card opens the full list;
the card under the summary shows the most recent three. The cook still receiving
new readings is marked **In progress**, so it is not confused with a closed past
cook. Cooks are archive navigation, not named or user-created sessions.

Selecting a cook opens a **new Past cook view** with its historical graph,
summary and probe filter. It never replaces the current History tab state, so
History keeps showing the current cook (or its own range when there is no current
cook). The past cook view uses `Recorded` instead of a live sync age, labels the
right edge with the cook end time instead of `Now`, and can be closed with Back.

### Data rules

- Four series, one colour per probe, consistent with the tiles and OLED order.
- Gaps: if the time delta between adjacent points is > 90 s, break the line.
  Never connect across a gap.
- No data for a probe in a range: no line and no zero.
- Decimation: LTTB to ~2 points per horizontal pixel per series, plus a min/max
  envelope for wide ranges.
- SQL-bucket long ranges; keep the chart under a few thousand points.
- `sample` already has `p1..p4`; per-probe sparklines and filters require no
  schema change.
- `gap` already has `reason`; render the reason, not a hard-coded marker.
- Estimated time is shown next to the chart when `time_estimated` is set.

## 6.7 Settings

### Root

```
Settings

BRIDGE
┌────────────────────────────────────────────┐
│ Backyard Bridge                          > │
│ Bridge A4F2 · Bluetooth                     │
│ ● Connected                    Battery 87%  │
│ Signal ▂▄▆▁ Fair                            │
│ Last contact 4s ago                         │
└────────────────────────────────────────────┘

HISTORY & STORAGE
  Device & Bridge logs  128,430 device · 24,810 Bridge >

PREFERENCES
  Temperature units                    [°F][°C]
  Appearance                           System >

ABOUT
  About                                App 0.1.0 >
```

- There is **one** Bridge section on the Settings root. Its status header is also
  the entry point to Bridge details; the Smoke X4 pairing, Billows, Bridge name
  and Bridge screen timeout rows live inside that sub-view instead of competing
  with the status header.
- The Bridge status header is status only. It shows the LED and `Connected`,
  battery, a cell-style signal meter with an `Excellent / Good / Fair / Weak`
  label, and `Last contact`. It does not repeat `Connected for 2h 14m`; the LED
  and label already carry that meaning. Tapping the header opens Bridge details,
  where `Sync now` / `Reconnect` and `Disconnect` live once. There are no
  duplicate sync or repair actions on the Settings root.
- Bridge details includes the same signal meter, the Smoke X4 pairing card and
  `Re-pair Smoke X4`, the editable Bridge name and screen timeout rows, Billows
  status, one `Connection & pairing log`, and the destructive actions. Re-pairing
  is not a separate Settings row or a second Smoke X4 screen.
- `History & storage` is one destination row. Its sub-view shows the `Device log`
  and `Bridge log` side by side with separate deletion rules. The Settings root
  does not duplicate those two rows.
- Preferences follow History & storage. Units apply immediately; no save-all bar.
- `Device log` is the local copy on this phone. `Bridge log` is the copy on the
  Bridge. The two copies are never merged even though they share one screen.
- Destructive actions live in Bridge details, not a top-level `Actions` screen.
- There is no `Device settings`, `Probe names & roles`, or `Actions` screen.

### Save model

| Control | Behaviour |
|---|---|
| Temperature units | Immediate; local change + queued bridge write if offline |
| Appearance | Immediate; local only |
| Bridge screen timeout | Immediate; requires connection, disabled with reason offline |
| Bridge name | Edit dialog; apply on Done; inline `Saving…` / `Saved` / `Couldn’t save` |
| Billows | Read-only; detection/last-seen only. No mode or target write. |
| Destructive actions | Confirmation sheet with exact loss, count and range |

Remove bottom `Save changes` bars. A preference should not need a second tap.
Do not show a global success banner for a successful write; a small inline state
is enough.

### Bridge details

- Status card: name, Bluetooth name, connected/offline, last update, battery,
  signal, `Sync now`, `Disconnect`. No second connected/pairing pill.
- Smoke X4 pairing card: current pairing state and `Re-pair Smoke X4`. This is
  the only re-pairing entry point in the app.
- Bridge settings: Bridge name, Bridge screen timeout and Billows rows.
- `Technical details` collapsed: device ID, firmware, protocol, RSSI, MTU,
  last sync.
- `Connection & pairing log`: Bridge connection, Smoke X4 pairing, Billows
  detection/loss and sync events in one timeline.
- `Bridge actions`: Power off bridge, Factory reset bridge, Forget this phone.
  These are action rows, not navigation rows; no chevrons.
- Power-off copy must not mention a “current cook”; there are no user-created
  cook sessions.

### History & storage

Two clearly labelled copies:

- **Device log** — readings, date range, database size, delete action. It stays
  when the bridge is reset.
- **Bridge log** — readings/capacity, used percentage, oldest/newest, automatic
  overwrite note, clear action. Clear requires a connection.

`Delete device log…` opens one sheet with `Older than 30 days`, `Older than
90 days`, `Everything`, each showing the exact count and date range before the
final confirmation. `Clear bridge log…` is separate and says the device log is
kept. Use **readings**, not **records**, in user copy.

### About

- App version/build, bridge firmware, protocol, bridge ID.
- USB-only firmware update note.
- Privacy: no cloud, no account, data stays on the phone and bridge.
- Attribution: Smoke X protocol decoding derives from G-Two/smoke-x-receiver
  (MIT © 2022 G-Two). Not affiliated with or endorsed by ThermoWorks. Smoke X is
  a trademark of its owner.
- No visible prototype mode in release builds. Debug builds show an
  `Experimental lab` item in the app-bar menu so every UI/UX state can be
  reviewed without real hardware. The entry point is also available from a
  long-press on the app title in About. Release builds can opt in with
  `--dart-define=ENABLE_EXPERIMENTAL_LAB=true`.

### Offline behaviour

| Control | Offline |
|---|---|
| Temperature units | Local change; bridge write queued |
| Appearance | Available |
| Bridge screen timeout | Disabled with `Connect to change this` |
| Smoke X4 pairing | Disabled with reason |
| Billows status | Last observed attached/target visible; no action |
| Bridge name | Disabled with reason |
| Sync now | Becomes `Reconnect` |
| Delete device log | Available |
| Clear bridge log | Disabled |
| Power off / factory reset | Disabled |
| Forget this phone | Available (local clear) |

Show one global offline banner, not a `Connect to edit` notice on every
subscreen. Each disabled control gets a short inline reason.

## 6.8 Error and empty states

Every failure names its cause and offers one next action.

| State | Copy | Action |
|---|---|---|
| No bridge configured | "Connect your bridge." / "Power it on. If the screen is off, hold PRG for 1.5 seconds." | Find bridge |
| Scanning | "Looking for your bridge…" | Cancel |
| No results | "No bridge found. Make sure it is on, then hold PRG for 1.5 s if it is asleep." | Retry / Open Bluetooth settings |
| Bluetooth off | "Bluetooth is off." | Open settings |
| Permission denied | "This app needs Bluetooth permission to find the bridge." | Grant / Open settings |
| Permission permanently denied | "Bluetooth permission is blocked. Enable it in Android settings." | Open app settings |
| Pairing failed | "The code didn’t match." | Try again / Android settings |
| Pairing out of date | "This phone’s pairing is out of date." | Forget pairing and re-pair |
| Phone list full | "This bridge already has 4 phones paired." | Forget one from a paired phone |
| Connected, no Smoke X4 | "The bridge is connected but hasn't heard your Smoke X4. Put the Smoke X4 in SYNC." | Pairing instructions |
| No probe data | "No probes connected." | Show bridge status |
| No history | "No readings yet. The bridge records whenever it is on and synced." | — |
| No history in range | "No data in this range." | Show all probes / another range |
| Offline with cache | "Showing last saved readings. Last sync 2h ago." | Retry |
| Offline, no cache | "Can’t reach the bridge, and there is nothing saved yet." | Retry |
| Sync failed | "Couldn’t catch up: <reason>." | Retry |
| Storage unavailable | "The bridge can’t write its log. Live readings only." | Contact/support (bench) |
| Protocol major mismatch | "This bridge needs a newer app." | Stop |

No raw exception, stack trace, or platform error string reaches the UI. Map
platform exceptions to these named states.

## 6.9 Android specifics

- **Permissions**: Android 12+ `BLUETOOTH_SCAN` with `neverForLocation` and
  `BLUETOOTH_CONNECT`; do not request location on 12+. Android 11 and below
  require location for scanning; explain it.
- **Bonding**: the OS owns the passkey dialog. The app may call `bond()` but
  cannot type the code for the user.
- **MTU**: request 247; record the negotiated value in diagnostics. If < 64,
  sync still works but is slow; show the slow-link note and keep full-ring
  backfill in the background. At MTU 23, use 32-record batches and expect roughly
  a minute for 24 h.
- **Doze/background**: no foreground service. When the app is backgrounded, the
  BLE link may drop; that is acceptable. On resume, reconnect and sync.
- **Battery optimization**: do not ask for an exemption. The app does not need
  background execution.
- **Manufacturer quirks**: keep a debug log of scan/connect/bond failures and the
  phone model/Android version. The test phone must be recorded in release notes.

## 6.10 Testing

- **Domain**: freshness, gap splitting, decimation, time estimation, unit
  conversion, nice ticks.
- **Codecs**: golden byte vectors shared with firmware.
- **Sync**: fake device cursor scenarios — recent-first, backward backfill,
  forward catch-up, generation change, gap, rollover, disconnect mid-batch.
- **Database**: in-memory SQLite; bulk insert idempotency; deletion ranges.
- **BLE**: `FakeBleClient` drives the whole connect → pair → subscribe → sync →
  live path with no radio. `flutter test` runs it.
- **Widget**: Live detached/live/stale, sparkline present/no history, History
  empty/one probe/gap/filter/units, Settings connected/offline/units, and all
  error states.
- **Manual**: real phone + real bridge; record model, Android version, MTU,
  timings.

## 6.11 What the app deliberately does not do

- It does not start/stop recording. The bridge always records.
- It does not delete app data automatically.
- It does not compute alarms, ETA, stall, or lid-open.
- It does not rename or split cooks; there are no cooks.
- It does not show a zero for a missing probe.
- It does not display “live” from the cache.
- It does not update firmware.
- It does not work on iOS in this MVP.
- It does not name or tag probes; identity is `P1`–`P4` and colour.
