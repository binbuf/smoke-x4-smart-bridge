# 06 — Flutter App

> **Copy/state note (2026-10-26):** [12 — Copy & Label Review](12-copy-and-label-review.md)
> is the copy baseline; [13 — UI/UX Implementation Contract](13-ui-implementation-contract.md)
> is the production UI contract. The prototype in `app/` implements the approved
> visuals. Where prose in this document conflicts with 12 or 13, those
> documents win.
>
> Production keeps the prototype's `features/`, `widgets/` and `theme/` layers
> and replaces `prototype/` with a real controller plus immutable view models.
> See [13 §13.3](13-ui-implementation-contract.md#133-production-ownership).

## 6.1 Product shape

The app has three destinations and one setup flow:

```
┌─────────────────────────────────────────┐
│  Live        History        Settings     │  NavigationBar
├─────────────────────────────────────────┤
│  Live: connection-chain card, 2×2 probe  │
│        tiles + sparklines, Billows       │
│  History: range/probe filters, chart,    │
│           summary, Cooks                 │
│  Settings: one Bridge section,           │
│            preferences, storage, about   │
└─────────────────────────────────────────┘

Setup (pushed above the shell when no bridge is remembered):
  connect → permission → scan → select → passkey → sync recent → live
```

The full route map, modal stack and every reachable state are in
[13 §13.2–13.4](13-ui-implementation-contract.md#132-screen-and-navigation-map).

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
│   ├── history/                chart, filters, summary, Cooks, empty states
│   ├── settings/               preferences, bridge, history/storage, about
│   └── common/                 banners, sheets, empty states, error views
└── platform/
    └── permissions.dart        Android permission/Bluetooth state
```

`domain/` imports no Flutter. `data/ble` knows GATT slots and payload bytes, not
widgets. `features/` composes the controller and repository.

The prototype already contains the approved UI layer. In production:

- keep `app/lib/features/`, `app/lib/widgets/` and `app/lib/theme/` as the visual
  contract;
- T05 moved the controller to `app/lib/app/bridge_controller.dart`, added
  `app/lib/app/bootstrap.dart`, `data/repository.dart` and the `AppDatabase`
  open path, and removed the Windows/web targets;
- T06 moved formatters to `app/lib/app/formatters.dart` and introduced immutable
  `LiveViewState`, `HistoryViewState`, `SetupViewState`, `SettingsViewState` and
  `BridgeDetailsViewState` objects in `app/lib/app/view_state.dart`. Widgets
  render those objects; they never read the controller's mutable fields;
- fixture generators and the scenario lab live under `app/lib/debug/`
  (`fixtures.dart`, `demo_content.dart`, `scenario_lab.dart`). Production screens
  do not import them. `domain/content.dart` is the data seam; production uses
  `EmptyBridgeContent` until M2/M3, while tests and the screenshot tool inject
  `DemoBridgeContent`;
- T07 added the BLE seam in `app/lib/data/ble/ble_client.dart`: scan, connect,
  bond, MTU, read, write and notification methods over raw payloads with named
  security failures. `BridgeController` and `createBridgeController` accept an
  optional `BleClient`; production still passes none until M2. The scripted
  fake and fake GATT bridge live under `app/test/support/`, never in `lib/`;
- T40 added schema version 2 and the archive DAO in
  `app/lib/data/db/sample_dao.dart`: bulk insert, range/count/extent reads, gap
  storage, date deletion and the saved-`bridge` identity queries. The in-memory
  test database is `AppDatabase.openInMemory` with the same DAO contract;
- keep simulation timers and fake OS prompts under debug/test only. They must not
  be reachable from a release build.

Do not rebuild the screens “properly later”. Wire the approved widgets to real
state and let the tests prove every state in
[13 §13.4](13-ui-implementation-contract.md#134-complete-state-inventory).

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
  window — **15 minutes in V0**, not the full 24 h. A reconnect with existing
  data sets the clock when needed and pulls **forward from the local max**
  immediately; it does not re-read 24 h. The UI says `Syncing saved readings`
  for the recent pass and `Loading saved readings` for background backfill;
  `Syncing` or `backfill` alone never reaches a product screen. The procedure
  and its local-max seam live in `data/ble/bridge_link.dart`; T39–T41 replace
  the no-op sync sink with the durable archive and background loading.
- **Live**: append notifications; quiet periodic forward sync every 30 s; health
  watchdog. A pull-to-refresh reads `live` and runs a forward sync.
- **Reconnecting**: exponential backoff 1, 2, 4, 8, 15, 30 s. A user
  pull-to-refresh or app resume cuts the wait short.
- **Failed**: after all six attempts show `Can’t reach the Bridge` with a Retry
  button and a `Forget this phone` escape. Never spin forever silently.

### Link procedures (T35)

- `app/lib/data/ble/bridge_link.dart` runs the fixed order: connect → read
  `info` → request MTU 247 → bond when not secured → subscribe `live`, `result`,
  `sync_data` → read `live` → `control(set_time)` → sync. It never imports a
  plugin or a widget.
- `BridgeController.ensureLink()` wires the procedure to the approved phase,
  live, info, sync and reconnect copy. Setup calls
  `completeFirstConnect(device)` after the OS bond; Live pull-to-refresh and
  app resume reuse the same instance.
- The control queue allocates a non-reused 0–255 `op_id`, matches the `result`
  by op + op_id, and times out after 3 s. ATT `0x0F`/`0x05` (mapped to
  `notBonded`) takes the bond path once; it is never retried in a loop. The
  production controller never starts an OS bond here: only `SetupFlow.pair()`
  does, after the approved passkey instruction. A reconnect that needs a bond
  lands in the named unreachable/Forget state.
- `set_time` sends the phone's UTC milliseconds and `tz_offset_min`. It always
  runs on first connect. A reconnect re-sends when `live.clock_valid` is false
  or the phone wall clock moved more than 2 s from the monotonic elapsed time
  since the last successful set (see ADR 0042).
- The health watchdog reads `live` after 110 s without a notification.
  Fresh `age_s` → `LIVE`; quiet X4 → `STALE`; read failure → `RECONNECTING`.
  Any GATT disconnect → `RECONNECTING` regardless of sample age.
- Pull-to-refresh and app resume complete a backoff wait immediately. After the
  six attempts the Live card shows the named unreachable state with `Retry` and
  `Forget this phone`.
- **No results**: after the 10 s scan, show `No Bridge found` with `Try again`,
  `Open Bluetooth settings`, and a hint to press PRG to wake the screen, or hold
  PRG if the Bridge is off.
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
  `No readings for 4 min`, `Showing saved readings`. `Aging`, `Stale` and
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

The approved prototype flow and copy are the baseline. Every state is listed in
[13 §13.4](13-ui-implementation-contract.md#setup), and every label is in
[12](12-copy-and-label-review.md).

1. **Set up / Connect your Bridge** — app-bar title `Set up`; headline
   `Connect your Bridge`; body “Power it on. Press PRG to wake the screen. If the
   Bridge is off, hold PRG for 1.5 seconds to turn it on.” Primary `Find bridge`.
   If saved history exists, show a `History on this phone` notice with the
   reading count and date range, plus `View history on this phone`.
2. **Permission primer** — shown only when the platform permission is not
   already granted, after the user taps `Find bridge`. Title `Allow Bluetooth to
   find your Bridge`; explain Android 12+ Nearby devices versus Android 7–11
   location; state that permission is only needed to find the Bridge. Primary
   `Continue`; secondary `Not now`. Do not show an Android-version table on the
   first screen.
3. **Bluetooth off** — `Bluetooth is off`; “Turn Bluetooth on so the app can find
   your Bridge. The Bridge keeps recording while you do.” Primary `Open
   Bluetooth settings`; secondary `Check again`.
4. **Scanning** — `Looking for your Bridge…`; “Scanning stops after 10 seconds.
   We’ll check your last Bridge first.” Primary `Cancel`. A remembered Bridge is
   preferred by device ID, then by name; do not auto-connect to an arbitrary
   first result.
5. **No results** — `No Bridge found`; “Make sure it’s on and within about 10
   meters (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.”
   Primary `Try again`; secondary `Open Bluetooth settings`; footer `View history
   on this phone` when saved history exists.
6. **Nearby bridges** — live list, remembered first. Show signal as `Strong /
   Good / Weak`; keep dBm in the detail line. A scan-response preview may show
   `P4 225°F · 87%`. Mark the remembered row `Last used`. A protocol-mismatch row
   says `Requires a newer app`; selecting it opens `Update the app to use this
   Bridge`.
7. **Select** — connect and read `info`. If the protocol major is not expected,
   show `Update the app to use this Bridge` and stop. Production also offers
   `View history on this phone` and `Learn more`; the prototype only has
   `Close` in the lab.
8. **Passkey** — before triggering the OS bond, show:

   > **Pair with the Bridge**
   > Enter the 6-digit code shown on the Bridge screen in the Android prompt.
   > `Look at the Bridge screen`
   > Example code block: `418 302`
   > “Example: the code appears on the Bridge screen. Only the Bridge screen
   > shows the real code.”
   > [ Pair ] [ Cancel ]

   Trigger the OS bond. Do not show a real code in the app; the app cannot know
   it. The simulated Android prompt belongs in the scenario lab, not the product
   flow.
9. **Pairing** — `Pairing…`; steps `Connecting to the Bridge`, `Checking the
   code`, `Syncing recent history`. No GATT or “secure characteristics” language.
10. **Pairing outcomes**:
    - success → set time, sync recent, first-sync screen, then Live;
    - wrong code → `The code didn’t match`; after two failures explain how to
      remove the pairing in Android settings;
    - prompt timeout → `No prompt appeared`; “Open your notifications and look
      for the Android pairing request, then try again.”;
    - pairing out of date → `This phone’s pairing is out of date`; explain the
      Bridge was reset and offer `Forget and re-pair`;
    - phone list full (`info.bonds_free == 0`) → `This Bridge already has 4
      phones paired`; “Open the app on a phone that’s already paired and choose
      Forget this phone. If none is available, the Bridge needs a USB reset.”
      Do not start the OS bond just to discover this.
11. **First sync** — `Loading history`; “Your latest readings are ready. Older
    readings will load in the background.” Progress for `last 24 hours`; steps
    `Time set`, `Loading the last 24 hours`, `Loading older readings`, `Live view
    ready`. Primary `View live readings`. The V0 build only reads the last
    15 minutes, so it says `Loading recent readings` / `last 15 minutes` until
    the M3 sync engine lands; never claim 24 hours before it can deliver them.
12. **Success** — land on Live, not a dead summary screen.

If the phone has saved history but no current bridge (first run after a forget
or factory reset), Setup shows a **History on this phone** entry: reading count,
date range, storage used, and a delete action. This is the only way to reach that
data after the bridge identity is removed; it is never deleted automatically.
The screen is also reachable from `Setup → View history on this phone` and from
`Settings → History & storage` while a Bridge is still saved.

### Later launches

- Load the remembered bridge and scan.
- Connect automatically when found; no passkey prompt.
- If the bridge is not found for 10 s, show the last-known Live data with
  "Looking for the bridge…" and a manual Connect button.
- "Forget this phone" clears the saved bridge and the OS pairing only after
  confirmation. It does not factory-reset the bridge and does **not** delete the
  local history; the setup screen offers a **History on this phone** entry so the
  user can review or delete it explicitly.

## 6.5 Live screen

```
┌────────────────────────────────────────────┐
│ Live                                       │
├────────────────────────────────────────────┤
│   [phone]  ▂▄▆▁  →  [bt]  ▂▄▆▁  →   [x4]  │
│     App    2h 14m   Bridge   12s    Smoke X4│
│                                            │
│ ⌁ Receiving readings · updated 12s ago      │
├────────────────────────────────────────────┤
│ Probes                                     │
│ ┌──────────────────┐ ┌──────────────────┐  │
│ │ ● P1           > │ │ ● P2           > │  │
│ │ 165.2°F          │ │ 164.0°F          │  │
│ │ Min 164.8 Max 166.1│ │ Min 162.9 Max 165.4│ │
│ │ ╭──────╮         │ │ ╭──────╮         │  │
│ │ ╰──────╯         │ │ ╰──────╯         │  │
│ │ 5m · +0.4°F      │ │ 5m · -1.4°F      │  │
│ └──────────────────┘ └──────────────────┘  │
│ ┌──────────────────┐ ┌──────────────────┐  │
│ │ ● P3           > │ │ ● P4           > │  │
│ │ —                │ │ 225.0°F          │  │
│ │ No history yet   │ │ Min 223.1 Max 227.4│ │
│ │ Not connected    │ │ ╭──────╮         │  │
│ │                  │ │ ╰──────╯         │  │
│ │                  │ │ 5m · +7.3°F      │  │
│ └──────────────────┘ └──────────────────┘  │
├────────────────────────────────────────────┤
│ Billows                                    │
│ Set temp 225.0°F      Last detected        │
│                       12s ago              │
│ Set on the Smoke X4.                       │
└────────────────────────────────────────────┘
```

Rules:

- The **Connection** card is the single status surface on Live. It shows the
  whole chain as simple icons with labels underneath: **App → Bridge → Smoke
  X4**. Tapping anywhere on the card opens Bridge details, where the manual
  `Sync now` action lives.
- Each radio link carries its own signal meter and connected duration:
  **phone→Bridge** uses the BLE RSSI and **Bridge→Smoke X4** uses the LoRa RSSI.
  Put the bars between the nodes and the duration on the node label baseline
  (`2h 14m`, `12s`, `Reconnecting`, `Offline`). Do not show one shared signal
  meter for two different radios. The phone→Bridge meter comes from the live
  connection read, not from the X4 packet.
- The chain uses colour as a secondary cue, not the only state. Do not rely on
  grey/green/amber/red alone. The X4 node carries one amber warning icon when
  the Bridge is connected but the X4 is quiet; tapping it opens the SYNC-mode
  dialog. Do not add a second inline `No data from Smoke X4` notice. When the X4
  is healthy, `Receiving readings · updated 12s ago` is the only telemetry line.
  For 90 s–10 min use `No readings for 4 min`; after 10 min use `Smoke X4 signal
  lost · 10 min ago`. Offline the card is `Bridge disconnected · last connected
  2h ago`, both signal meters are hidden and the chain is dimmed. When showing
  cache, add `Showing saved readings · last reading 20 min ago`.
- On the Bridge, recording is independent of the phone. The app may say
  `Recording` only when connected and `storage_ok`; when disconnected it says
  “The Bridge keeps recording while it’s on” as reassurance, not as a live
  status. A storage failure shows the `Not recording` notice: “Live readings are
  available, but the Bridge can’t save them. Check the Bridge’s storage.”
- Sync is its own card: `Syncing saved readings` with `Newest readings load
  first.`, or `Loading saved readings` with “Your latest readings are ready.
  Older readings continue in the background.” Add `Slow connection` when the
  negotiated MTU is low. A sync failure says `History sync failed` and offers
  `Retry sync`; live readings keep updating.
- There is no `Sync now` action on the Live card. The product is designed so
  manual sync is rarely needed; pull-to-refresh remains the recovery gesture.
- There is no small connection chip in the app bar. Healthy status lives in the
  card; a problem state changes the relevant LED and adds one notice. The X4
  warning is the one exception: it lives on the X4 node as an amber icon and
  opens a dialog, so the healthy card stays compact.
- Four tiles in probe order, always four. A detached probe is **“—” + “Not
  connected”**, never 0 °F and never omitted. A tile with no sparkline history
  says `No history yet`; the tile height does not change.
- Probe identity is `P1`–`P4` plus colour. No names, roles or tags. The whole
  tile is the tap target and carries a chevron.
- If all four probes are absent, show one `No probes connected` notice: “Plug a
  probe into the Smoke X4 to see a reading.” Keep the four tiles.
- Each tile shows a **relative last-hour sparkline** when that probe has history.
  The sparkline is scaled to its own min/max; it communicates shape, not a
  cross-probe comparison.
- Above the sparkline show the current range as `Min 225.0°F · Max 231.2°F`
  when the probe has values. The footer reads `<window> · +0.4°F`, where the
  window is the **Live change window** preference (`1`, `5`, `10`, `15`, `30` or
  `60 min`; default `5 min`). The change is signed and computed from the newest
  and oldest stored readings inside that window. Do not put an unrelated window
  and delta at opposite edges, and do not show `0°F` for a detached probe.
- Tapping a tile opens **History** with that probe selected and the 1 h range.
- Healthy tiles are quiet: no repeated “Live · updated 4s ago”. A delayed probe
  shows `Updated 62s ago`; a stale probe shows `No readings for 4 min`; a frozen
  probe shows `No readings for 12 min`; a detached probe shows `Not connected`.
- When the Bridge is connected but the Smoke X4 is quiet, show one amber warning
  icon on the X4 node. Tapping it opens a dialog with `No data from Smoke X4` (or
  `Smoke X4 signal lost`), the SYNC-mode steps and `Pairing steps`. Do not add a
  second inline notice and do not repeat the warning on every tile.
- Offline with cache: dim values and keep one Bridge status surface. Do not
  repeat a no-reading line four times.
- Offline without cache: show `Bridge disconnected · nothing saved yet` and do
  not render fixture or last-session probe values as if they were current. One
  next action (`Retry`) is enough. The view state carries this explicitly as
  `showSavedReadings = false`; probe values and sparklines become empty rather
  than falling back to the last known content. See ADR 0041.
- No aggregate preview graph and no footer instruction text on Live.
- Pull-to-refresh reads `live`, runs a forward sync, and reports failure with a
  named error. It is the one action allowed to throw visibly.
- Billows appears **automatically when detected**. There is no off switch, no
  mode switch, no target setter, and no second “Connected” pill. `Detected` comes
  only from the `billows_attached` field in a recent valid X4 packet; never claim
  the fan is running. The target is the Smoke X4 channel 4 set temp; when it has
  not been validated it shows `-`. The Live card shows `Billows`, `Set temp`,
  `Last detected`, and the caption `Set on the Smoke X4.` When
  `caps.billows_observe = 0` the card and every Billows notice are absent; Live
  models that as a null `billows` view state (ADR 0041). The `Last detected`
  value is an age (`12s ago`), not a bare `Detected`. When offline, use
  `Set temp (last known)` and a last-detected age. If Billows was detected
  earlier in the session and is now missing, Live shows one `Billows not
  detected` notice with `View connection log`. Detection and loss events join
  the regular Bridge / Smoke X4 connection log in Settings → Bridge; the Billows
  details screen is status-only and has a focused log.
- The Bridge/health banner appears only on History for degraded states. Live owns
  its own status card.

## 6.6 History screen

### Purpose

History is the archive: chart + per-probe summary + detected Cooks + data-quality
states. It is not a demo chart and it is not a second dashboard.

### Layout

```
┌────────────────────────────────────────────┐
│ History                                    │
├────────────────────────────────────────────┤
│ [ 24 hours ▾ ]  [ All probes ▾ ]      ↺    │
├────────────────────────────────────────────┤
│ Oct 24, 6:30 PM – Oct 25, 6:30 PM          │
│ Synced 2 min ago · 4 probes                │
│                                            │
│ °F 275 ┤          ╭─╮                      │
│    225 ┤──╮   ╭───╯ ╰──╮      P4           │
│    175 ┤  ╰───╯        ╰──╮   P1/P2        │
│    125 ┤                   ╰──             │
│        └──────────────────────────────     │
│         6:30 PM  2:30 AM  10:30 AM   Now   │
│  ● P1 165.0° ● P2 171.9° ● P4 215.8°       │
│  Drag to pan · pinch to zoom   − + ⛶ Now   │
├────────────────────────────────────────────┤
│ Summary                         °F  Probe ▾│
│ Probe   Latest         Min       Max       │
│ ● P1    165.0°         149.9°    181.5°  > │
│ ● P2    171.9°         148.4°    175.9°  > │
│ ● P3    159.6°         132.6°    168.2°  > │
│ ● P4    215.8°         202.7°    247.0°  > │
├────────────────────────────────────────────┤
│ Cooks                          View all    │
│ Grouped automatically from your readings   │
│ [OCT 25] Today  In progress                │
│          9:10 AM – 6:30 PM · 9h 20m · 4    │
│ [OCT 24] Yesterday                         │
│          10:05 AM – 7:20 PM · 9h 15m · 4   │
└────────────────────────────────────────────┘
```

### Features

- Range trigger values are `1 hour`, `6 hours`, `24 hours`, `2 days`, `Custom`.
  The menu entries are `Last hour`, `Last 6 hours`, `Last 24 hours`, `Last 2
  days`, `Custom range…` (“Any date and time”).
- `Custom range…` starts with all saved history and opens a date-and-time sheet
  for exact start/end minutes. Quick picks are `All saved history`, `Today`,
  `Yesterday`, `Last 6 hours`; the primary action is `Apply`. Only `Apply`
  changes the History range; `Cancel` restores the previous range and viewport.
- Probe menu: `All probes`, `P1`–`P4`. A probe with no data in the range is
  disabled and labelled `No data`.
- The two compact dropdown buttons sit in one card; the reset icon appears only
  when a filter is active. Range, probe and sort persist across tab switches and
  app resume.
- Cooks are reached from the dedicated card below Summary; the filter header does
  not duplicate that entry point.
- The chart header has a `?` help action (“Reading the chart”) and an expand
  action for the full-screen chart.
- Full-screen chart: a dedicated view, not a restyled History page. It never
  forces an orientation; portrait and landscape are both allowed. The graph
  fills the screen either way, with only a compact window label, legend and
  zoom controls around it. Close returns to the exact History state.
- Shared y-axis when all probes are visible; auto-scale to the selected probe
  when one is selected.
- Nice y-axis ticks (1/2/2.5/5 × 10ⁿ) and one unit label (`°F` / `°C`); no
  degree sign on every tick.
- Locale-aware time labels; date labels at midnight for multi-day ranges.
- Crosshair + tooltip with the timestamp and every visible probe value. The
  tooltip is pinned until the user taps elsewhere or closes it.
- Drag to pan; pinch or mouse-wheel/scroll to zoom; double-tap to fit. A visible
  `Now` action appears when the view is not at the latest data.
- A compact legend under the chart shows the visible probes and their latest
  values; single-probe views add a soft area fill.
- Latest-point dots at the end of each visible series.
- Gap bands with a reason (`No signal`, `Bridge off`, `Not synced`) and a tap
  explanation. Never connect across a gap.
- Estimated-time badge (`times estimated`) when any visible sample is estimated.
- Offline cache banner on History; the chart still renders.
- The chart help sheet explains tap, pan/zoom, Cooks, gaps, shared scale and
  estimated times. It is not a developer diagnostics panel.
- Empty states: no readings at all, no readings in the selected range, offline
  with no cache. Metadata must not claim four probes when none have data.
- Accessibility: a chart summary for screen readers and a Summary table that
  does not depend on colour.

### Summary and sorting

The summary is where sorting belongs. A time series is chronological.

| Field | Meaning |
|---|---|
| `Latest` | Newest valid reading in range |
| `Min` | Lowest valid reading in range |
| `Max` | Highest valid reading in range |
| `No data` | No valid reading for that probe in range |

There are **no temperature deltas** in the summary. Show latest, min and max
only, in aligned columns. Default order is probe order. Sort options are
`Probe order`, `Hottest`, `Highest`, `Latest reading` and `Since cook start`.
The last option uses the recorded sample timestamps to find the current cook (or
the most recent detected cook when none is in progress) and orders probes that
have reported since that start with the most recent first. It shows the cook start
age above the rows so the detected reference is explicit. When no cook exists the
option is disabled with `No cook detected yet`. Tapping a row focuses that probe.

### Cooks

For every archive range, show detected cooks derived from recorded readings and
gaps. The product label is **Cooks** (not “Past cooks”). A cook row carries its
date, exact start/end time, duration, probe count and whether it contains a gap.
`View all` opens the full list; the card under the summary shows the most recent
three. The cook still receiving new readings is marked **In progress**, so it is
not confused with a closed cook. Cooks are archive navigation, not named or
user-created sessions.

Selecting a cook opens a **Cook view** with its historical graph, summary and
probe filter. It never replaces the current History tab state, so History keeps
showing the current cook (or its own range when there is no current cook). The
Cook view uses `Recorded history` instead of a live sync age, labels the right
edge with the cook end time instead of `Now`, and can be closed with Back. Its
app-bar title is `Cook`.

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

Implementation note (T42): the shell now reads the durable archive through
`HistoryArchive` (ADR 0048). Ranges up to 4,000 rows are read raw; longer
windows are SQL-bucketed to about 1,200 rows and LTTB-decimated to 800 points
per series with a min/max envelope. Summary is computed by SQL over raw rows, so
it is exact even when the chart is decimated. Gap bands come from the `gap`
table and from real holes; a decimated series is drawn with its explicit break
points instead of the raw 90 s rule, which would otherwise split every bucket.
Cooks are detected from recorded timestamps by `CookDetection`; the card and the
Cook view never use fixture cooks in production. `HistoryViewLoader` owns the
async read, so the same approved widgets render with or without a database.

Implementation note (T36): V0 mounted the same shell against
`RecentHistoryStore`, which held only the current session's recent readings in
memory. The T42 read model replaced that source without changing the screen
(ADR 0043 → ADR 0048).

## 6.7 Settings

### Root

```
Settings

BRIDGE
┌────────────────────────────────────────────┐
│ Backyard Bridge                          > │
│ Bridge A4F2                                 │
│ ● Connected                    Battery 87%  │
│ Signal ▂▄▆▁ Fair                            │
│ Updated 4s ago                              │
└────────────────────────────────────────────┘

HISTORY & STORAGE
  Storage  128,430 on this phone · 24,810 on the Bridge >

PREFERENCES
  Temperature units                    [°F][°C]
  Live change window                   5 min >
  Appearance                           System >

ABOUT
  About this app         App 0.1.0 · Firmware 0.1.0 >
```

- There is **one** Bridge section on the Settings root. Its status header is also
  the entry point to Bridge details; the Smoke X4 pairing, Billows, Bridge name
  and Bridge screen timeout rows live inside that sub-view instead of competing
  with the status header.
- The Bridge status header is status only. It shows the LED and `Connected`,
  battery, a cell-style signal meter with an `Excellent / Good / Fair / Weak`
  label, and `Updated`. It does not repeat `Connected for 2h 14m`; the LED
  and label already carry that meaning. Tapping the header opens Bridge details,
  where `Sync now` / `Reconnect` and `Disconnect` live once. There are no
  duplicate sync or repair actions on the Settings root.
- Bridge details includes the same signal meter, the Smoke X4 pairing card and
  `Re-pair Smoke X4`, the editable Bridge name and screen timeout rows, Billows
  status, one `Connection log`, and the destructive actions. Re-pairing is not a
  separate Settings row or a second Smoke X4 screen.
- `History & storage` is one destination row. Its sub-view shows History on this
  phone and History on the Bridge side by side with separate deletion rules. The
  Settings root does not duplicate those two rows.
- Preferences follow History & storage. Units apply immediately; no save-all bar.
  `Live change window` is a local display preference (`1 / 5 / 10 / 15 / 30 /
  60 min`, default 5) that sets the signed change period on the Live probe
  tiles. It does not affect stored samples, the History chart or the OLED.
- `History on this phone` is the local copy on this phone. `History on the Bridge`
  is the copy on the Bridge. The two copies are never merged even though they
  share one screen.
- Destructive actions live in Bridge details, not a top-level `Actions` screen.
- There is no `Device settings`, `Probe names & roles`, or `Actions` screen.

### Save model

| Control | Behaviour |
|---|---|
| Temperature units | Immediate; local change + queued bridge write if offline |
| Live change window | Immediate; local only; persisted across relaunch |
| Appearance | Immediate; local only |
| Bridge screen timeout | Immediate; requires connection, disabled with reason offline |
| Bridge name | Edit dialog; apply on Done; inline `Saving…` / `Saved` / `Couldn’t save` |
| Billows | Status only; detection/last-seen only. No mode or target write. |
| Destructive actions | Confirmation sheet with exact loss, count and range |

Remove bottom `Save changes` bars. A preference should not need a second tap.
Do not show a global success banner for a successful write; a small inline state
is enough.

### Bridge details

- Status card: name, `Bridge A4F2`, `Connected`, `Battery 87%`, `Signal` +
  bars + `Fair`, `Updated 4s ago`, `Sync now`, `Disconnect`. No second
  connected/pairing pill. Offline the buttons become `Reconnect` / `Connect`,
  and the card notes “Recording continues on the Bridge.”
- Smoke X4 pairing card: `Smoke X4 pairing`, state pill (`Receiving`,
  `No readings`, `Signal lost`, `Not paired`, `Last known`), `Updated 12s ago`,
  and `Re-pair Smoke X4`. When fresh, the state is `Receiving readings`; only
  use `Receiving` as a compact pill if the surrounding text carries the full
  state. This is the only re-pairing entry point in the app.
- Bridge settings: Bridge name, Bridge screen timeout and Billows rows.
  Timeout values are 30 sec / 1 min / 2 min / Never with subtitles such as
  `1 min · screen turns off` or `Screen stays on`.
- `Technical details` collapsed: `Bridge ID`, `Firmware`, `Protocol`, `Signal`
  (dBm), `MTU`, `Connected for`, `Last synced`. No MTU/RSSI/GATT language on the
  main status card.
- `Connection log`: Bridge connection, Smoke X4 pairing, Billows
  detection/loss and sync events in one timeline, newest first. The subtitle is
  “Bridge, Smoke X4, and Billows events”.
- `Bridge actions`: `Power off the Bridge`, `Factory reset Bridge`,
  `Forget this phone`. These are action rows, not navigation rows; no chevrons.
  Factory reset uses the error colour; forget is available offline.
- Power-off copy must not mention a “current cook”; there are no user-created
  cook sessions. The confirmation says recording stops while the Bridge is off,
  phone history is kept, and PRG must be held for 1.5 seconds to turn it back on.
- Factory reset confirmation lists all paired phones, Bridge settings/screen
  preferences, saved readings and the clock; it says the Bridge becomes
  available to pair as a new device. Disconnect is success. Phone history is
  kept.

### History & storage

Two clearly labelled copies:

- **History on this phone** — readings, date range, storage used, delete action.
  It stays when the bridge is reset.
- **History on the Bridge** — readings/capacity, used percentage, oldest/newest,
  automatic overwrite note, clear action. Clear requires a connection.

`Delete history from this phone…` opens one sheet with `Older than 30 days`,
`Older than 90 days`, `All history on this phone`, each showing the exact count
and date range before the final confirmation. `Clear history on the Bridge…` is
separate and says history on this phone is kept. Use **readings**, not
**records**, in user copy.

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
| Live change window | Available (local only) |
| Appearance | Available |
| Bridge screen timeout | Disabled with `Connect to change this` |
| Smoke X4 pairing | Disabled with reason |
| Billows status | Last observed attached/target visible; no action |
| Bridge name | Disabled with reason |
| Sync now | Becomes `Reconnect` |
| Delete history from this phone | Available |
| Clear history on the Bridge | Disabled with `Connect to the Bridge to clear it.` |
| Power off / factory reset | Disabled with `Connect to the Bridge first` |
| Forget this phone | Available (local clear) |

Show one global offline banner, not a `Connect to edit` notice on every
subscreen. Each disabled control gets a short inline reason.

## 6.8 Error and empty states

Every failure names its cause and offers one next action.

| State | Copy | Action |
|---|---|---|
| No Bridge configured | `Connect your Bridge` / “Power it on. Press PRG to wake the screen. If the Bridge is off, hold PRG for 1.5 seconds to turn it on.” | `Find bridge` |
| Permission primer | “Allow Bluetooth to find your Bridge.” Android 12+ Nearby devices; Android 7–11 location; only needed to find the Bridge. | `Continue` / `Not now` |
| Scanning | `Looking for your Bridge…` | `Cancel` |
| No results | `No Bridge found` / “Make sure it’s on and within about 10 meters (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.” | `Try again` / `Open Bluetooth settings` |
| Connect failed | `Couldn’t connect to the Bridge` / “The Bridge was found but the Bluetooth connection didn’t finish. Keep it nearby and try again. It keeps recording while you do.” | `Try again` (no rescan) / `Find another Bridge` |
| Bluetooth off | `Bluetooth is off` / “Turn Bluetooth on so the app can find your Bridge. The Bridge keeps recording while you do.” | `Open Bluetooth settings` / `Check again` |
| Permission denied | `Bluetooth permission needed` / “The app needs Nearby devices permission to scan for the Bridge.” | `Grant permission` / `Open app settings` |
| Permission permanently denied | `Bluetooth permission is blocked` / “Enable Nearby devices permission in Android settings, then come back.” | `Open app settings` |
| Pairing failed | `The code didn’t match` | `Try again` / `Open Android settings` |
| Prompt timeout | `No prompt appeared` / “Open your notifications and look for the Android pairing request, then try again.” | `Try again` / `Open Bluetooth settings` |
| Pairing out of date | `This phone’s pairing is out of date` | `Forget and re-pair` |
| Phone list full | `This Bridge already has 4 phones paired` / USB reset if no paired phone is available | `Try again` |
| Connected, no Smoke X4 | `No data from Smoke X4` / “The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.” | `Pairing steps` (X4 warning dialog) |
| No probe data | `No probes connected` / “Plug a probe into the Smoke X4 to see a reading.” | Bridge details |
| No history | `No readings yet` / “The Bridge records whenever it’s on and paired with the Smoke X4.” | `View Live` |
| No history in range | `No readings in this range` / “Probe 3 has no readings in this range. Try another range or show all probes.” | `Show all probes` |
| Offline with cache | `Showing saved readings · last reading 20 min ago` | `Retry` |
| Offline, no cache | `Bridge disconnected · nothing saved yet` | `Retry` |
| Sync failed | `History sync failed` / "Live readings are still updating. Retry when the Bluetooth connection is stable." | `Retry sync` |
| Cannot reach the Bridge | `Can’t reach the Bridge` / "The app tried six times. Recording continues on the Bridge. Move closer and try again, or forget this phone and set it up again." | `Retry` / `Forget this phone` |
| Storage unavailable | `Not recording` / “Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.” | Bridge details |
| Protocol major mismatch | `Update the app to use this Bridge` / “The Bridge hasn’t been changed.” | `Update app` (+ saved history / learn more) |

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
- **Implementation (T32)**: `data/ble/flutter_blue_plus_ble_client.dart` is the
  only plugin import. `flutter_blue_plus` is pinned to 1.35.12 (BSD-3); 2.x adds
  a commercial licence gate. `BlePlatformStatus` resolves unsupported phone,
  Bluetooth off, permission needed and permission blocked before scanning.
  Scan runs unfiltered, filters the new service UUID in Dart, merges split
  advertisement/scan-response reports, and stops after 10 s; the remembered
  bridge is matched by device ID then name and never replaced by the first
  result. A first connect after scan is retried once because Android commonly
  reports GATT status 133.
  `BleDiagnostics` records phone model, Android version, negotiated MTU and
  scan/connect/bond failures. See ADR 0039.
- **Setup (T33)**: `features/setup/setup_flow.dart` is the setup state machine
  over the BLE seam; `SetupScreen` owns only approved copy. `Find bridge` checks
  the platform, the primer's `Continue` requests permission, and the passkey
  block always precedes `bond()`. `info` is read before bonding so
  `proto_major` and `bonds_free == 0` are handled without an OS prompt. The app
  mounts setup while the controller has no saved Bridge and lands on Live after
  first sync. See ADR 0040.
- **Launch and connection health (T43)**: `bootstrap` calls
  `BridgeController.prepareLaunch()` before the first frame and then
  `connectSavedBridge()` without blocking the UI. A saved `bridge` row keeps the
  shell on Live: the controller loads the newest archived sample for last-known
  values, scans the foreground for 10 s by BLE identity then advertised name,
  and connects with the stored bond (no passkey prompt). A missing Bridge stays
  on Live with `Looking for the Bridge…`, the archive and a manual `Connect`.
  The saved row is the only identity store: `bridge.id` is the BLE address,
  `bridge.name` the advertised name and `last_seen_ms` is touched on every
  healthy transition. Forget/factory reset delete that row and leave
  `sample`/`gap` orphaned. `BleClient.platformStates` feeds both the launch and
  the live link, so turning phone Bluetooth off leaves `Connected`, enters the
  named BLOCKED state and clears the live receipt values; turning it on resumes
  the bounded reconnect budget. See ADR 0047.

## 6.10 Testing

- **Domain**: freshness, gap splitting, decimation, time estimation, unit
  conversion, nice ticks.
- **Codecs**: golden byte vectors shared with firmware.
- **Sync**: fake device cursor scenarios — recent-first, backward backfill,
  forward catch-up, generation change, gap, rollover, disconnect mid-batch.
- **Database**: in-memory SQLite; bulk insert idempotency; deletion ranges.
- **BLE**: `app/lib/data/ble/ble_client.dart` is the only radio seam (scan,
  connect, bond, MTU, read, write, notify). `app/test/support/fake_ble_client.dart`
  scripts advertisements, link/bond transitions and security failures, while
  `fake_bridge.dart` implements the GATT server with the generated codecs. A
  widget test drives scan → connect → bond → subscribe → live → disconnect with
  no radio; `flutter test` runs it. The fake stays in test support, never in the
  release import graph. T32 adds `ble_client_mapping_test.dart`, which injects
  `FlutterBluePlusException`/`PlatformException` objects and fake faults to
  prove every plugin failure maps to a named state, and pins the production
  service UUID/local-name constants to the generated contract.
- **Setup (T33)**: `test/setup_flow_test.dart` drives the real screen with
  `FakeBleClient` through primer, denied/blocked, Bluetooth off, unsupported,
  scanning, no results, results ordering, protocol mismatch, passkey, pairing,
  wrong code, prompt timeout, stale bond, full bond store, first sync and
  orphaned history. `test/setup_codec_test.dart` pins the `info`/advertisement
  decoder to the generated contract.
- **Widget**: the full state inventory in
  [13 §13.4](13-ui-implementation-contract.md#134-complete-state-inventory) —
  Live healthy/aging/stale/frozen/detached/no-probes/offline-cache/no-cache,
  sparkline present/no history, every inline notice; History
  default/ranges/filters/gap/no-data/offline/estimated/overwritten/Cooks/Cook
  view/full-screen; Settings connected/offline/units/appearance/storage/Bridge
  details/confirmations; all setup and pairing states.
- **Layout**: 320 dp and 390 dp, dark and light, no overflow; screen-reader
  semantics for connection, probes, chart summary, filters and summary rows.
- **Visual**: the screenshot/golden set in `app/screenshots/` is reviewed
  intentionally; a UI change updates it in the same change.
- **Manual**: real phone + real bridge; record model, Android version, MTU,
  timings.

## 6.11 What the app deliberately does not do

- It does not start/stop recording. The bridge always records.
- It does not delete app data automatically.
- It does not compute alarms, ETA, stall, or lid-open.
- It does not create, name, split or edit cook sessions. Detected Cooks are
  read-only archive navigation derived from recorded readings.
- It does not show a zero for a missing probe.
- It does not display “live” from the cache.
- It does not update firmware.
- It does not work on iOS in this MVP.
- It does not name or tag probes; identity is `P1`–`P4` and colour.

## 6.12 UI implementation contract

The production UI is the approved prototype, not a rebuild. The detailed
contract is in [13](13-ui-implementation-contract.md):

- [§13.2](13-ui-implementation-contract.md#132-screen-and-navigation-map) —
  route and modal map.
- [§13.3](13-ui-implementation-contract.md#133-production-ownership) —
  prototype-to-production ownership and view models.
- [§13.4](13-ui-implementation-contract.md#134-complete-state-inventory) —
  every screen state, including empty, offline, error and destructive states.
- [§13.5](13-ui-implementation-contract.md#135-ui-lifecycle-flows) — first-run,
  returning, reconnect, history, settings and power flows.
- [§13.7](13-ui-implementation-contract.md#137-prototype-only-pieces-and-known-gaps)
  — the prototype gaps production must close.
- [§13.8](13-ui-implementation-contract.md#138-evidence-and-test-keys) — test
  keys and evidence.

A production task is not done when the screen “looks close”. It is done when the
real state produces the same UI, the disabled/empty/error variants are reachable,
and the widget/golden evidence is committed.
