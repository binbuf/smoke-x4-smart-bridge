# 08 — Flutter App

Android first (Flutter target `android`, `minSdk 24`, `targetSdk 35`). iOS is not in v1 scope but
nothing here precludes it — all platform-specific code sits behind two narrow channels.

> **[13 — UX Architecture](13-ux-architecture.md) supersedes the screen inventory and navigation
> here**, and [14 — Design System](14-design-system.md) supersedes anything this document says about
> visual treatment. The transport abstraction, the sync engine, the local schema and the charting
> approach below stand. See [13 §13.9.1 U6](13-ux-architecture.md) for what an iOS port would have to
> redesign rather than port.

## 8.1 The one idea that shapes everything

**The UI never knows how it is talking to the bridge.**

```dart
abstract interface class BridgeTransport {
  BridgeCapabilities get capabilities;      // liveState, history, config, ota, …
  Stream<BridgeEvent> get events;           // sample · alarm · session · net · power
  Future<BridgeStatus> status();
  Future<LiveState> live({Duration window});
  Future<List<SessionSummary>> sessions();
  Stream<List<Sample>> samples(int sessionId, {int fromT, int? toT, int? bucketS});
  Future<void> control(ControlCommand cmd);
  Future<void> configure(BridgeConfig cfg);
}
```

Three implementations:

| Implementation  | Backed by                                                               | Capabilities                                                             |
| --------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `HttpTransport` | REST + WebSocket ([06](06-device-api.md))                               | everything                                                               |
| `BleTransport`  | Bridge Control Service ([05 §5.6](05-connectivity-and-provisioning.md)) | live state, 2 h pit preview, config, control, **and full history from v1.1** — no OTA |
| `MockTransport` | `tools/sim` or a recorded cook fixture                                  | everything, deterministic                                                |

The dashboard, the chart, the alarm engine, and the session list are written once. A capability flag
drives the places where the difference is visible to the user: the session list is read from the
local cache rather than the device, and the chart shows _"connected over Bluetooth — full history
needs Wi-Fi"_ instead of a stub.

**That notice is now conditional on the bridge, not on the transport.** v1.1 added
`history_ctrl`/`history_data` ([ble-gatt §5.10–§5.11](../../protocol/ble-gatt.md)), so
`BleTransport` reports `fullHistory` from `device_info.caps` b6 rather than declaring it false.
A bridge on older firmware still sets the flag clear and still gets the notice — the same app
build has to be right in front of both, and a v1.0 bridge does not refuse a history request, it
never answers one at all.

This is what makes decision D1 (custom GATT over `wifi_provisioning`) pay off in the app as well as
the firmware: **you can stand at the smoker with no Wi-Fi anywhere and still see your temperatures**,
using the same screen you use at home.

## 8.2 Packages

| Concern            | Package                                                   | Why this one                                                                                                                                               |
| ------------------ | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| State              | `riverpod` / `flutter_riverpod` + `riverpod_generator`    | Compile-time-safe providers, first-class async/stream primitives, testable with no widget tree                                                             |
| Models             | `freezed` + `json_serializable`                           | Immutable unions; exhaustive `switch` over `BridgeEvent` variants                                                                                          |
| BLE                | `flutter_blue_plus`                                       | Actively maintained, good Android 12+ permission handling, direct GATT control                                                                             |
| Discovery          | `nsd`                                                     | Wraps Android `NsdManager`. `multicast_dns` has a long-standing Android discovery bug ([flutter#155499](https://github.com/flutter/flutter/issues/155499)) |
| HTTP               | `dio`                                                     | Interceptors, cancel tokens, per-request timeouts, streamed responses for `format=bin`                                                                     |
| WebSocket          | `web_socket_channel`                                      |                                                                                                                                                            |
| Local DB           | `drift`                                                   | Typed queries, migrations, batch inserts, works on a background isolate                                                                                    |
| Charts             | `fl_chart`                                                | MIT, no licence cost, adequate at our data sizes after decimation. Syncfusion is faster at 10⁵ points but is commercial and we never exceed ~3×10³         |
| Notifications      | `flutter_local_notifications`                             | Channels, full-screen intent for critical alarms                                                                                                           |
| Foreground service | `flutter_foreground_task`                                 | Typed FGS for Android 14, isolate communication                                                                                                            |
| Prefs              | `shared_preferences`                                      |                                                                                                                                                            |
| Logging            | `logger` + a ring buffer exportable from the debug screen | Field diagnosis without a cable                                                                                                                            |

Deliberately **not** used: any ESP provisioning package. We speak our own GATT protocol, and those
packages assume Espressif's protobuf scheme.

## 8.3 Structure

```
app/lib/
├── main.dart
├── app/                 router (go_router), theme, bootstrap, error boundary
├── core/                Result/failure types, units, time, logging, extensions
├── domain/              ── pure Dart, zero Flutter imports, 100 % unit-tested
│   ├── entities/        Probe · Sample · CookSession · Mark · Alarm · BridgeStatus
│   └── analysis/        rateOfChange · eta · stallDetector · lidOpenDetector · lttb
├── data/
│   ├── transport/       BridgeTransport + Http/Ble/Mock implementations
│   ├── dto/             generated from protocol/ — wire types, never used in the UI
│   ├── local/           drift database, DAOs, migrations
│   └── repos/           BridgeRepository · SessionRepository (cache-first)
├── features/
│   ├── onboarding/      BLE scan → bond → passkey → mode choice → handoff
│   ├── dashboard/       live tiles + chart + session controls
│   ├── sessions/        history list, detail, compare, export
│   ├── alarms/          rules editor, alarm log
│   ├── settings/        probes, network, device, radio (advanced), OTA, about
│   └── debug/           raw packets, logs, transport inspector
└── platform/
    ├── network_binder/  MethodChannel → ConnectivityManager.bindProcessToNetwork
    └── cook_service/    foreground service host
```

`domain/` importing nothing from Flutter is a hard rule. It makes the interesting logic — ETA
projection, stall detection, LTTB decimation — testable in milliseconds and shareable with the
firmware's alarm rules as a reference implementation.

## 8.4 Connecting

The app never assumes one path works. On launch, and whenever the connection drops, the
`ConnectionManager` races every option and takes the first winner:

```
                    ┌──────────────────────────────────────┐
                    │  ConnectionManager.connect(bridgeId) │
                    └───────────────────┬──────────────────┘
        ┌───────────────┬───────────────┼───────────────┬──────────────┐
        ▼               ▼               ▼               ▼              ▼
  last known IP     mDNS scan      smokebridge     192.168.4.1     BLE scan
  (from cache)      (_smokebridge   .local          (AP default)   (by name +
   ~50 ms            ._tcp, 3 s)                                    service UUID)
        │               │               │               │              │
        └───────────────┴───────────────┴───────────────┘              │
                        first HTTP 200 wins ──────────► HttpTransport   │
                                                                        │
                        all HTTP paths fail ───────────────────────────►│
                                                              BleTransport (degraded)
                        everything fails ──────────► offline: read from drift cache
```

Manual IP entry is always available in settings and jumps the queue. Every successful connection
updates the cache, so the common case — same bridge, same network, second launch — is one 50 ms
request.

**v1 is single-bridge** ([D12](00-overview.md)). `connect(bridgeId)` takes an id and the `bridges`
table holds many rows, because the plumbing costs nothing to keep general — but there is no picker,
no switcher, and no aggregate view. Onboarding a second bridge replaces the first. Adding
multi-device support later is screens, not a migration.

Reconnect uses exponential backoff (1, 2, 4, 8, 15, 30 s, capped) and immediately retries on
`ConnectivityChanged`, so walking back into Wi-Fi range reconnects without user action.

> **Superseded for the shell (A16).** The race above still describes the HTTP lanes, but the
> production shell no longer *takes the first winner and stops*. `ConnectionSupervisor`
> (`lib/app/connection_supervisor.dart`) owns one BLE handle and the HTTP race together: it **leads
> with Bluetooth** so data shows the instant the app opens, **upgrades to Wi-Fi** in the background
> (`AppConnection.raceHttpUpgrade` over `ConnectionManager.raceHttpOnly` — the BLE-less race), **holds
> the BLE link as a warm standby**, and **fails over to it silently** when the active Wi-Fi link drops
> (`BridgeSession.onLinkLost` → `switchTransport`), then climbs back. `BridgeCapabilities.mqtt` joins
> the honesty record; a `preferredTransport` (auto/Wi-Fi/Bluetooth) and a "keep Bluetooth as backup"
> pref (`BridgePrefs`) steer it from the header-chip connection sheet. The single-transport
> `BridgeSession` invariant is unchanged — one *active* transport, honest capabilities — the supervisor
> just swaps which one it is.

## 8.5 Sync and the local cache

**The app owns a full copy of every cook it has seen.** Charts read from drift, never from the
network, so scrolling history works on the couch with the bridge unplugged.

```
on connect:
  GET /api/v1/status                     → firmware version gate, active session id
  GET /api/v1/sessions                   → reconcile: new · updated · deleted
  for each session with cachedMaxT < deviceMaxT:
      GET /sessions/{id}/samples?format=bin&from={cachedMaxT+1}
      → parse 16-byte records → drift batch insert in a transaction
  open WebSocket /api/v1/stream          → append live samples as they arrive
```

Delta sync means reconnecting mid-cook transfers only what was missed. A phone that was away for
three hours pulls 360 samples = 5.8 KB.

Drift schema — **v2** (newapp §D.2, §E.4, §E.5):

| Table              | Notes                                                                                            |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| `bridges`          | id, name, last seen                                                                              |
| `sessions`         | mirrors the on-device header                                                                     |
| `samples`          | `(bridgeId, sessionId, t)` PK; `p1..p4` nullable ints (tenths °F); `flags`, `rssi`; **`unixMs`** |
| `marks`            | including `autoAnchor`, for marks offerable as a cook start                                      |
| `alarmLog`         | local record of what fired and when it was seen                                                  |
| **`cooks`**        | the annotation: name, `startUnixMs`, nullable `endUnixMs`, notes, preset, hazard, safety mode, favourite, `pulledAtUnixMs`, `anchorSessionId` |
| **`cookProbeRoles`** | per-jack role, target, pull offset, doneness, hazard, `isIntact`                              |
| **`alarmRules`**   | both tiers: scope, jack, type, threshold, window, `pushedToDevice`, `lastConfirmedUnixMs`        |
| **`gaps`**         | `(bridge, session, fromT)` PK, with a **reason** — connectivity (recoverable) vs buffer rollover (permanent) |
| **`syncStates`**   | per-(bridge, session) high-water mark beside the **device's** reported buffer extent             |

### Why samples keep a session key

newapp §D.2 proposes making samples session-agnostic so cook edits are pure metadata. §E.7 requires
the opposite — *"key everything on device-authoritative IDs `(bridgeId, sessionId, t)`; never mint
phone-side session IDs"* — because that key is what makes the delta-sync upsert idempotent and a
mid-sync restart resumable.

Both are satisfied by taking the *property* §D.2 wanted rather than its mechanism: samples keep the
device's key and gain **`unixMs`**, a projection of it onto the wall clock. A cook resolves its
membership with an indexed range query instead of owning a foreign key on every sample, so
backdating, splitting and merging are metadata edits that touch no sample row — instant on an
eighteen-hour cook rather than a progress bar.

A bridge whose RTC was never set stores **NULL** there rather than a fabricated epoch time (§E.7),
and a cook over such a session pins itself with `cooks.anchorSessionId`. `SampleDao.projectWallClock`
backfills the column when a clock arrives mid-session, which is the ordinary case for a bridge that
syncs its time from the phone.

### The sync high-water protocol (§E.4, §E.5)

The cursor used to be recomputed as `MAX(t)` on every connect. That is a correct resume point and
says nothing about what the *device* still holds — so the app could not distinguish "I have
everything" from "the bridge overwrote the part I was missing while I was indoors". `syncStates`
stores our mark **beside the device's reported extent**, which is what makes a rollover detectable:
`deviceMinT > highWater + 1` means the span between them exists nowhere, and it is recorded as a
**permanent** gap that no later sync will clear. A connectivity gap is cleared the moment samples
fill it. Rendering both as one dashed line would tell a user to wait for something that is not coming.

One row per sample: a 24 h cook is 2,880 rows, 50 cached cooks is ~144 k rows — a size SQLite treats
as trivial, and it buys free range queries and aggregation. If profiling ever disagrees, the
fallback is storing the raw 16-byte records as per-session BLOB chunks, which is exactly the wire
format; the DAO interface is written so that swap doesn't reach the repository.

Inserts go through `batch()` inside one transaction on a background isolate — 2,880 rows lands in
tens of milliseconds and never touches the UI frame budget.

## 8.6 Screens

### Dashboard

```
┌────────────────────────────────────────┐
│  Brisket                    ⏱ 04:12:30 │
│  ● Wi-Fi · smokebridge.local · 🔋71%   │
├────────────────────────────────────────┤
│ ┌────────────────────┐ ┌─────────────┐ │
│ │ PIT                │ │ Brisket     │ │
│ │  243°F        ▼    │ │  163°F   ▲  │ │
│ │  target 250        │ │  → 203°F    │ │
│ │  ▁▂▃▅▆▅▄▃▂  −2°/hr │ │  ETA 6h20m  │ │
│ └────────────────────┘ │  ⚑ stalling │ │
│ ┌──────────┐┌────────┐ └─────────────┘ │
│ │ Point    ││ Flat   │                 │
│ │  159°F   ││   —    │                 │
│ │  +3.8/hr ││ unplug │                 │
│ └──────────┘└────────┘                 │
├────────────────────────────────────────┤
│  15m   1h   6h   [15h]   All      ⤢    │
│ 300┤                                   │
│    │      ╭──────────────╮             │
│ 200┤─────╯    · · · ·     ╰──────      │  ← dotted = gap (no packets)
│    │   ╭────────────────────────       │
│ 100┤──╯                                │
│    └───┬────┬────┬────┬────┬────┬──    │
│       12p   3p   6p   9p  12a   3a     │
│  ▲wrapped        ▲lid open             │  ← marks
├────────────────────────────────────────┤
│  ⏸ Stop cook    ⚑ Add mark    ⇪ Export │
└────────────────────────────────────────┘
```

Design intent: **the two numbers that matter are enormous.** You are reading this from four feet
away, in a dark yard, possibly through a screen door. Pit and the primary food probe get the space;
secondary probes collapse to compact tiles.

### Onboarding

A five-step wizard driven entirely by BLE, mirroring the handoff in
[05 §5.7](05-connectivity-and-provisioning.md):

1. **Find** — BLE scan; each result shows the scan-response blob (`Smoke Bridge A4F2 · pit 243°F`)
2. **Pair** — bond; a 6-digit passkey appears on the bridge's OLED, entered in the app
3. **Time** — silently sets the clock so the session is correctly dated from the first sample
4. **Network** — _"Host its own network"_ vs _"Join a Wi-Fi network"_, with honest copy about the
   battery cost of hosting and the range cost of joining. Wi-Fi list comes from the device's scan
5. **Handoff** — live progress, then verification, then _"Connected — you're all set"_. On failure,
   BLE is still up, so the recovery path (revert to hosting) is one button

### Sessions

List with a sparkline, duration, peak temp, and probe count per row. Detail view is the dashboard
chart without the live tiles, plus stats (time in band, pit σ, total cook time, stall duration),
the mark timeline, and export. Two sessions can be overlaid to compare cooks.

### Settings

Probes (name, role, target — roles drive which tile is large and which rules apply), Alarms
([09](09-alarms-and-insights.md)), Network (mode switch, credentials, current status), Device
(units, display timeout, LED, retention, battery calibration), Advanced (LoRa parameters, raw packet
view, logs), Firmware (current version, OTA upload), About.

## 8.7 Charting

`fl_chart` `LineChart`, with the work happening before it ever sees the data.

**Decimation.** A 24-hour cook at full resolution is 2,880 points per probe; a phone chart is
~400 logical pixels wide. Naive stride decimation can step straight over a lid-open spike.
`domain/analysis/lttb.dart` implements **Largest-Triangle-Three-Buckets**, which preserves the
visual envelope — peaks and troughs survive — at a target of ~2 points per pixel. For very wide
ranges the app instead asks the device for `bucket=90&agg=minmax` and renders mean as the line with
min/max as a faint band, so an excursion is visible as a widening even where the mean is smooth.

**Gaps are gaps.** Runs separated by a `t` delta > 45 s become separate `LineChartBarData`
segments with a dotted connector. A 30-minute dropout must look like a 30-minute dropout, not like a
straight line pretending everything was fine. This is only possible because samples carry time
([04 §4.2](04-storage-and-history.md)) — and it is the clearest single improvement over the
reference's untimestamped array.

**Detached probes** produce no points at all — never a zero.

**Overlays.** Horizontal dashed lines at each probe's target (`ExtraLinesData`); vertical lines at
marks; a shaded band for the pit's alarm min/max; a crosshair on drag that reads out every probe's
value at that instant.

**Interaction.** Window chips (15 m / 1 h / 6 h / 15 h / All) for the common cases; pinch and drag
adjust `minX`/`maxX` for free exploration; double-tap resets. Live mode auto-scrolls the window
unless the user has panned, in which case a _"jump to now"_ pill appears — the standard log-viewer
behaviour, and the one people expect.

**Colour.** Probe series need a categorical palette that is colourblind-safe, legible in direct
sunlight and in a dark theme, and consistent across the app, the exports, and the OLED's single bit
of ink. Roles carry semantic weight (pit is the reference series; food probes are the subjects).
Exact values are chosen at implementation time against the project's data-visualisation guidance
rather than fixed here — but the constraint set above is a requirement, not a preference.

**Theme.** Dark-first. This is an app used outdoors at 3 a.m. Large type, high contrast, generous
touch targets, and the ability to read the two headline numbers at arm's length.

## 8.8 Android platform work

Two platform channels, both small and both ours:

**`platform/network_binder`** — wraps `ConnectivityManager` for AP mode
([05 §5.8.1](05-connectivity-and-provisioning.md)): request a Wi-Fi network with
`NET_CAPABILITY_INTERNET` removed, `bindProcessToNetwork` on availability, unbind on teardown. Also
exposes `WifiNetworkSpecifier`-based joining so tapping _"Join SmokeBridge-A4F2"_ doesn't dump the
user into system settings. ~120 lines of Kotlin.

**`platform/cook_service`** — the foreground service host ([09](09-alarms-and-insights.md)).

Manifest work: the permission matrix in [05 §5.8.3](05-connectivity-and-provisioning.md), a scoped
`network_security_config.xml` for cleartext, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, and a
`POST_NOTIFICATIONS` request flow that explains itself before prompting.

**Battery optimisation.** Android will kill a long-running foreground service on some OEM builds
(the worst offenders are well documented). During onboarding, after the first cook starts, the app
offers a one-tap `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` with an honest explanation of why. It is
opt-in, and the app degrades to "reconnect when you open it" if declined.

## 8.9 Testing

| Layer        | Approach                                                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `domain/`    | Plain `flutter test`. ETA projection, stall detection, lid-open, LTTB, unit conversion, gap detection — all pure functions with table-driven cases           |
| Wire parsing | Golden tests against the fixtures in `protocol/fixtures/`, shared byte-for-byte with the firmware's host tests                                               |
| Repositories | `MockTransport` + an in-memory drift database                                                                                                                |
| Widgets      | `golden_toolkit` snapshots for the dashboard, tiles, and chart at several data shapes — including _no probes_, _all detached_, _mid-gap_, and _alarm active_ |
| Integration  | `integration_test` driving the app against `tools/sim` replaying a recorded 18-hour cook at 100× speed. Runs in CI with no hardware                          |

The simulator ([10 §10.3](10-repo-tooling-and-testing.md)) is what makes the app developable and
testable before the firmware exists, and what keeps CI honest afterwards.
</content>
