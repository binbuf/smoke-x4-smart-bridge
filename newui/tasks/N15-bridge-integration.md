# N15 — Bridge integration

**Goal:** swap `MockBridgeRepository` for real transports, persistence and platform
services — **without touching a single screen**. The repository seam from N2 is the
contract that makes this a drop-in.

**Design:** `newui/NOTES.md` §3, §6 · `components_research_notes.md` §4, §5, §7,
§8 · `docs/design/05`–`09`, `protocol/` · `app.old/lib/data` (behavioural
reference only) · `tools/sim` for S-verification.

---

## Invariants this epic must encode

I7 (verify by behaviour) · I9 (one transport active) · I10 (samples key on
`(bridgeId, sessionId, t)`, idempotent, never rewritten) · I11 (no fabricated
timestamps) · I15 (no raw exception reaches the user).

## 15.1 Transport

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N15.1 | `BridgeTransport` contract: status, live, sessions, samples, marks, config, applyNetwork, verbs — with capability flags | N2.27 | H | research notes §4 |
| N15.2 | `HttpTransport` (Dio): `/api/v1` endpoints, Bearer, streamed sample parsing, WebSocket `/api/v1/stream` | N15.1 | S | research notes §3.3–§3.4 |
| N15.3 | `BleTransport` (flutter_blue_plus): GATT service, 11 characteristics, chunked notify history stream, LE Secure passkey entry | N15.1 | B | research notes §3.5 |
| N15.4 | `MockTransport` retained for tests and the UX lab | N15.1 | H | `app.js` |
| N15.5 | `ConnectionManager`: six-lane race (manual → cachedIp → mdns → mdnsName → apDefault → ble); a lane wins only on a real `GET /status` 200; backoff | N15.2 | S | research notes §7 |
| N15.6 | `ConnectionSupervisor`: BLE leads → Wi-Fi upgrades → BLE held warm → silent failover → climb back; exactly one active | N15.5 | S | I9 |
| N15.7 | `BridgeSession`: status → sync → live → cache → subscribe; 10 s backstop poll; link loss verified by a `status()` read | N15.6 | S | research notes §7 |
| N15.8 | Real `BridgeRepository` impl over the supervisor, feeding the same `snapshotProvider` from N2 | N15.7 | S | N2.27 |

## 15.2 Persistence & sync

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N15.9 | Drift schema: `Bridges`, `Sessions`, `Samples` (nullable `unixMs`), `Marks`, `Cooks`, `CookProbeRoles`, `AlarmRules`, `Gaps`, `SyncStates` — fresh schema, not legacy v2 | N15.1 | H | research notes §5.1 |
| N15.10 | Idempotent sample upsert keyed `(bridgeId, sessionId, t)`; no row is ever rewritten | N15.9 | H | I10 |
| N15.11 | Sync engine high-water-mark: detect rollover → record permanent gap **before** fetch; skip closed+cached; choose `fromT`; stream, upsert, advance | N15.9 | S | research notes §5.3 |
| N15.12 | Cook annotation membership by time range; backdate/split/merge touch no sample | N15.9 | H | I10, NOTES §5.2 |
| N15.13 | Real `PrefsRepository` via `shared_preferences`, loaded once at boot for synchronous reads | N15.9 | H | research notes §5.2 |
| N15.14 | CSV export byte-compatible with the device (same header/order/ISO-8601; detached = empty field), streamed from cache | N15.13, N12.12 | H | research notes §5.5 |

## 15.3 Platform services

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N15.15 | Notification channels (critical/warning/info/ongoing) + permission + full-screen intent capability | N11.12 | B | research notes §8 |
| N15.16 | `ForegroundServiceHost` (`connectedDevice`) + battery-exemption opt-in | N15.15 | B | research notes §8 |
| N15.17 | `CookMonitor`: background loop persists samples, mirrors alarms, posts notifications; start on cook, stop after idle | N15.16, N11.14 | B | research notes §8 |
| N15.18 | Permission + system-settings seams (BLE scan/connect, location, notification; deep links) | N14.3 | B | research notes §8 |
| N15.19 | `network_binder` for hosted-AP join (`bindProcessToNetwork`); onBound/onLost | N10.8 | B | research notes §8 |
| N15.20 | `firmware_picker` (file_selector) + OTA upload streamed over HTTP only | N13.13 | B | research notes §8, NOTES §3.8 |
| N15.21 | `share_plus` wiring for CSV/field-report/graph share | N15.14 | B | research notes §8 |
| N15.22 | Diagnostics read-back (`device_facts` + device read-back over HTTP; BLE limitations surfaced as copy) | N13.15 | B | research notes §4, I13 |

## Exit gate

Against `tools/sim`, the real repository drives Live/Temps/Graph/Timeline/History
identically to the mock; a 24-hour cook streams, persists and exports; killing
Wi-Fi mid-cook raises the unreachable insight and fills the gap on reconnect; OTA
refuses without Wi-Fi.

## Must-not-regress

I7, I9, I10, I11, I15. No screen may import a transport, drift or a platform
service — they read `BridgeRepository` only.

## Hand-off

**Status: continue.** Attempt 1 landed the **transport + connection + sync core**
(N15.1, 15.2, 15.4, 15.5, 15.6, 15.7, 15.10, 15.11, 15.12, 15.14). Attempt 2
landed the **exit-gate-critical drop-in** (N15.8) plus the persistence half of
N15.13. Attempt 3 landed the **real drift cache (N15.9), the persistent-prefs
plugin adapter (N15.13) and device alarms + the unreachable insight**. Attempt 4
landed **N15.3 `BleTransport`** and the **host-testable halves of N15.15–N15.22**.
The tree is green: `make app.test` is **715** (was 672; +43) and
`dart test test/domain test/data` is **295** (was 262; +33). No screen or
existing test was changed; the plugin set N15 needs is in `pubspec.yaml`
(pinned to `app.old`'s versions).

### What attempt 2 landed (pure Dart, `app/lib/data/repository/`)

- `real_bridge_repository.dart` — **N15.8**: `RealBridgeRepository implements
  BridgeRepository`. Composes the **unchanged** N2.27 seam over a
  `ConnectionSupervisor` + `BridgeSession` + `SampleCache`:
  - `connect()` starts the supervisor, attaches a `BridgeSession`, syncs, loads
    history, and listens to `updates`/`samples`/`linkLost`.
  - Transport DTOs map to the app model: `BridgeStatus`/`NetStatus`/`PowerStatus`
    → `ConnectionState` (+ `LinkState` bars from RSSI), `LiveStatus`/`LiveProbe`
    → `ProbeState` (4 jacks, absent-is-null I3), `SessionInfo` + cache → the
    `HistoryEntry` list (peak from cached samples, marks from `transport.marks`,
    gaps from the cache), `DeviceStatus`/`StorageStatus` → `DeviceInfo`.
  - An unadopted active session surfaces as `PendingSession`; adopt/discard/
    setCookStart/startCook/addItem/mark/markPulled map onto the cook clock and
    `postMark`. Every mutation swallows a wire error (I15) and re-emits the
    snapshot; a `linkLost` triggers `supervisor.failover()` then a re-attach.
  - `exportCookCsv` streams `exportCookCsvFromCache` (N15.14) so it works with
    the bridge away.
- `real_prefs_repository.dart` — **N15.13 (persistence half)**: `KeyValueStore`
  interface + `InMemoryKeyValueStore` + `JsonPrefsRepository` (`load()` once for
  synchronous `current`, persist on every `write`). Full `AppSettings`
  round-trip incl. all enum/bool fields, `bridgeName`/`onboardStatus`, and
  `CustomFood` with its `CookTimeline`. A corrupt blob falls back to defaults
  (I15); no Wi-Fi secret is ever stored. A `shared_preferences` adapter is now a
  three-method `KeyValueStore` implementation.
- `providers.dart` — the real repository is selectable at build time:
  `--dart-define=REAL_BRIDGE=true --dart-define=BRIDGE_HOST=…`. Default stays
  `MockBridgeRepository` so every existing widget test and the dev panel are
  untouched; `prefsProvider` still uses the mock until the platform adapter
  lands.

### Commands that work

- `make app.test` — full gate (analyze + format + `flutter test`, **657**).
- `cd app && flutter test test/data/real_bridge_repository_test.dart` — 10.
- `cd app && flutter test test/data/real_prefs_repository_test.dart` — 7.
- `cd app && dart test test/data/transport_test.dart` — the 31 transport tests.
- `cd app && dart test test/domain test/data` — data/domain gate (**250**).

Tests: `app/test/data/transport_test.dart` (loopback HTTP+WS via
`app/test/support/fake_bridge_server.dart`; connection half via `MockTransport`),
`real_bridge_repository_test.dart` (the drop-in over `MockTransport`),
`real_prefs_repository_test.dart`.

### Deviations / gotchas

- **HTTP is `dart:io`, not Dio.** Keeps the layer plugin-free; swap Dio in
  behind `HttpTransport` later.
- **Lanes are attempted in priority order, not concurrently** (same observable
  contract, deterministic).
- **Alarms and device read-back have no wire endpoint yet**: the real repo keeps
  alarms/alarm-rules app-side (test alarm, snooze, `bridge_unreachable` insight
  are not yet raised by the real repo) and `checkForUpdates` uses the firmware
  fixture. Real device alarms/alarm-config land with the platform work.
- **`_addItem` marks the jack attached app-side** (a started cook is a real
  request to monitor it); the live feed still owns the reading.
- App-only mark kinds (`spritz`, `turn`) are written to the wire as `note`.
- `InMemorySampleCache.clearConnectivityGapsBetween` clears connectivity gaps
  fully inside `[fromT,toT]`; the drift version must match.
- `RealBridgeRepository.dispose()` disposes the supervisor but not the
  `ConnectionManager` (no owner yet).

### What attempt 3 landed

- **N15.9 `app/lib/data/local/app_database.dart`** — a fresh drift schema
  (schemaVersion 1, **not** legacy v2): `Bridges`, `Sessions`, `Samples`
  (nullable `unixMs`), `Marks`, `Cooks`, `CookProbeRoles`, `AlarmRules`,
  `Gaps`, `SyncStates`. `Samples` is keyed `(bridgeId, sessionId, t)`;
  `Gaps` keys `(bridgeId, sessionId, fromT, toT, reason)`. Pure Dart, so it is
  in the `dart test test/data` gate.
- **`app/lib/data/local/drift_sample_cache.dart`** — `DriftSampleCache implements
  SampleCache`: `insertOrIgnore` on the sample key (I10, first value wins, never
  rewritten), null `unixMs` preserved (I11), range reads, gap record/read, and
  `clearConnectivityGapsBetween` clearing **only** connectivity holes fully
  inside the filled range (the permanent-rollover rule). Also upsert-only
  `upsertSessions` and `replaceMarks` for the cache's other half.
- **`app/lib/data/local/open_database.dart`** — the on-device file via
  `path_provider` + `NativeDatabase.createInBackground`; split out so the schema
  stays plugin-free for host tests.
- **`providers.dart`** — new `sampleCacheProvider` (in-memory by default);
  `bridgeRepositoryProvider` passes it to `RealBridgeRepository`.
  **`bootstrap.dart`** opens the real database and overrides the provider, and
  is now `Future<void>` (`main.dart` awaits it).
- **N15.13 `app/lib/data/repository/shared_prefs_store.dart`** —
  `SharedPrefsKeyValueStore implements KeyValueStore` over `shared_preferences`.
  `bootstrap.dart` loads `JsonPrefsRepository` once from it and overrides
  `prefsProvider`, seeding `OnboardStatus.fresh` only when nothing is stored.
  Settings now persist across launches.
- **Device alarms + insight (RealBridgeRepository)** — `BridgeStatus` gained an
  `ActiveAlarm` list parsed from `status.alarms` (OpenAPI `ActiveAlarm`); the
  real repo maps it to device-tier `Alarm`s, overlays the app's ack/snooze, and
  raises the `bridge_unreachable` insight once when a mid-cook link loss leaves
  no lane.
- **`pubspec.yaml`** — the N15 plugin set (flutter_blue_plus, drift,
  sqlite3_flutter_libs, path_provider, path, flutter_local_notifications,
  flutter_foreground_task, permission_handler, connectivity_plus, share_plus,
  file_selector; dev: drift_dev, sqlite3), pinned to `app.old`'s versions.

### What attempt 4 landed

- **N15.3 `BleTransport` (pure Dart, `app/lib/data/transport/ble_transport.dart`)**:
  the third `BridgeTransport` implementation, on the binary `protocol/records.yaml`
  contract. Decodes through the generated codec vendored as
  `app/lib/data/dto/records.g.dart` (+ `dto.dart` barrel). It implements the
  11-characteristic GATT hub via the unchanged `BleGattClient` seam
  (`ble_gatt.dart`): `device_info`/`live_state`/`net_status` reads, `result`
  correlation by `op_echo`, chunked `history_data` reassembly, and the full
  history stream (`sessions`/`samples`/`marks`) with `(seq, kind=end)` framing.
  Capabilities derive `fullHistory` from `device_info.caps` b6
  (`TransportCapabilities.withFullHistory`, added to `bridge_transport.dart`).
  Control ops cover marks, time, cook-clock, pairing, restart/factory/power,
  stop-session; Wi-Fi config goes through the `wifi_config` char and returns the
  AP PSK. Wi-Fi-only surfaces (OTA, delete, device/alarm config, commit) throw
  `TransportUnsupported`. App-only `spritz`/`turn` still write wire `note`.
- **`app/lib/platform/ble_gatt_fbp.dart`** — `FlutterBlueGattClient` over
  `flutter_blue_plus` (ported from `app.old`, plugin APIs identical at the
  pinned version) plus `openBleTransport()`: scan → connect → bond → MTU →
  started `BleTransport`, returning null on any miss.
- **Wiring** — `httpSupervisor` gained a `bleOpener`; `providers.dart` passes
  `openBleTransport` so `auto` can lead on BLE in a `REAL_BRIDGE=true` build.
  `transport.dart` re-exports `ble_gatt.dart` + `ble_transport.dart`.
- **N15.15/N15.16 `app/lib/platform/notifications.dart` + `notifications_plugin.dart`**:
  the four-channel table (importance can never change after creation), the
  `NotificationSink` seam + `RecordingNotificationSink`, `requestPermission` /
  `hasPermission` / full-screen-intent capability, the `PluginNotificationSink`
  (flutter_local_notifications 22), and the `ForegroundServiceHost` seam +
  `FakeForegroundServiceHost` + `PluginForegroundServiceHost`
  (`connectedDevice` type, battery-exemption opt-in).
- **N15.18 `permissions.dart` + `system_settings.dart`**: the runtime BLE/
  notification permission seam (version-gated scan+connect+optional location,
  granted/denied/permanentlyDenied reduction) over `permission_handler`, and the
  OS-settings deep-link MethodChannel (`smokebridge/system_settings`).
- **N15.19 `network_binder.dart`**: the `NetworkBinder` seam +
  `ChannelNetworkBinder` (`smokebridge/network_binder`, onBound/onLost) +
  `FakeNetworkBinder`, with the strict bind/unbind lifecycle.
- **N15.20 `firmware_picker.dart`**: `pickFirmwareImage()` over `file_selector`
  returning a streamed `PickedFirmware` (null on cancel).
- **N15.21 `share.dart` + `share_plugin.dart`**: the `ShareSheet` seam +
  `RecordingShareSheet` + `PluginShareSheet` (`share_plus`).
- **N15.22 `device_facts.dart`**: the field-report host facts map.
- `platform.dart` exports only the pure seams; the `*_plugin.dart` / `*_fbp.dart`
  files are imported directly by the composition root so `flutter test` never
  loads a platform channel it does not need.
- Tests: `test/data/ble_transport_test.dart` (26, against a ported
  `test/support/fake_peripheral.dart`), `test/data/platform_test.dart` (7, pure),
  `test/features/platform_permissions_test.dart` (10, fakes).

### What remains (next session)

1. **N15.17 `CookMonitor`** — the background reconciliation loop (persist
   samples, mirror device alarms, post notifications, start/stop the foreground
   service) adapted to the **new** model: watch `BridgeRepository.snapshot()`,
   feed `planNotifications()` (the escalation map is caller state), drive
   `NotificationSink` + `ForegroundServiceHost`. Persistence already happens in
   `BridgeSession`/`SampleCache`, so the loop's job is notifications + service
   lifecycle and the unreachable/stall/ETA findings.
2. **Composition-root wiring + Android manifest/Kotlin**: construct
   `PluginNotificationSink` / `PluginForegroundServiceHost` / `AppPermissions`
   / `SystemSettings` / `NetworkBinder` at `bootstrap.dart`; declare the
   foreground service (`connectedDevice`), notification permission, the
   `smokebridge/network_binder` and `smokebridge/system_settings` channels +
   their Kotlin handlers (`bindProcessToNetwork`, intents), and the full-screen
   intent / exact-alarm declarations.
3. **OTA upload plumbing**: `firmware_picker` exists; thread the picked stream
   to `BridgeTransport.uploadOta` (HTTP only) behind a repo-level seam, so
   `performVerb(DeviceVerb.ota)` can do more than set a notice. BLE already
   refuses with `TransportUnsupported`.
4. **Device alarm read-back**: map `alarmConfig()`'s `AlarmRule` array onto
   `_rules` and push rule edits back where the protocol allows, over HTTP.
5. Smoke the drop-in against `make sim` with
   `--dart-define=REAL_BRIDGE=true --dart-define=BRIDGE_HOST=127.0.0.1:8080`.
   Note `RealBridgeRepository.dispose()` still does not dispose the manager, and
   the `ConnectionManager` has no owner yet.