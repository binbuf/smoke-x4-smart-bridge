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
(N15.1, 15.2, 15.4, 15.5, 15.6, 15.7, 15.10, 15.11, 15.12, 15.14). The tree is
green: `make app.test` is **640** (was 609; +31) and `dart test test/domain
test/data` is **233** (was 202; +31). No screen, provider or existing file was
changed except adding the barrel export to `lib/data/data.dart`.

### What landed (real paths, all pure Dart under `app/lib/data/transport/`)

- `bridge_transport.dart` — N15.1: `BridgeTransport` contract (status, live,
  sessions, session, streamed samples, marks, config, network, time/cook-clock,
  pairing/verbs, OTA, `events()`), `TransportCapabilities` (http/ble/mock flags
  from research notes §4), `TransportException`/`TransportUnsupported`, and
  typed DTOs (`BridgeStatus`, `DeviceStatus`, `LiveStatus`, `SessionInfo`,
  `TransportEvent`, …) parsed from the `protocol/openapi.yaml` JSON.
- `http_transport.dart` — N15.2: real HTTP. **Uses `dart:io`, not Dio** (see
  deviation). Bearer auth, JSON + the `{error:{code,message,detail}}` envelope,
  streamed NDJSON samples (`format=ndjson`, batched), `/api/v1/stream`
  WebSocket, streamed `/ota` upload.
- `mock_transport.dart` — N15.4: programmable in-memory transport with
  `MockBridgeDevice`, failure injection (`failWith`), a `statusPlan` queue,
  `calls` log and `emitSample`. Used by the connection/session tests.
- `connection_manager.dart` — N15.5: six lanes in priority order (manual →
  cachedIp → mdns → mdnsName → apDefault → ble), a lane wins only on a real
  `status()` 200, losers are closed, documented backoff
  (`kConnectionBackoff`), `TransportFactory`/`HttpTransportFactory`.
- `connection_supervisor.dart` — N15.6: BLE leads → Wi-Fi upgrade → BLE held
  warm → failover; `TransportPreference { auto, wifi, ble }`, `verifyActive()`
  (a real status read), `failover()`, `disconnect()`.
- `bridge_session.dart` — N15.7: status → sync → live → cache → subscribe, a
  10 s backstop poll, `linkLost` on a failed status read, `resync()`.
- `sample_cache.dart` — N15.9/N15.10: the drift-shaped `SampleCache` interface +
  `SyncState` + `InMemorySampleCache`. `upsertSamples` is idempotent on
  `(bridgeId, sessionId, t)` and **never rewrites** a row (I10, pinned by test).
- `sync_engine.dart` — N15.11 high-water mark (skip closed+fully-cached,
  rollover detected before upsert and recorded as a permanent gap, streaming
  upsert, connectivity gaps recorded/cleared) + N15.12 `samplesInWindow` +
  N15.14 `exportCookCsvFromCache` (reuses `buildCookCsv`).
- `transport.dart` barrel is exported from `data.dart`; **screens must not
  import it** (they still read `BridgeRepository`).

### Commands that work

- `make app.test` — full gate (analyze + format + `flutter test`, **640**).
- `cd app && flutter test test/data/transport_test.dart` — the 31 new tests.
- `cd app && dart test test/data/transport_test.dart` — same 31, fast.
- `cd app && dart test test/domain test/data` — data/domain gate (**233**).

Tests live in `app/test/data/transport_test.dart` with a real loopback
HTTP+WS server in `app/test/support/fake_bridge_server.dart` (not the `tools/sim`
package — the app is standalone). The HTTP half is verified against that server;
the connection half against `MockTransport` with injected failures.

### Deviations from the plan

- **HTTP is `dart:io`, not Dio.** The task names Dio; `dart:io` keeps the whole
  layer pure Dart, in the `dart test test/data` gate, with no new dependency
  before a screen needs one. A later task may put Dio behind `HttpTransport`.
- **Lanes are attempted in priority order, not concurrently.** The observable
  contract ("a lane wins only on a real status 200") is identical and the result
  is deterministic; concurrent sockets to a dead address buy nothing.
- **`CustomFood`/`CookItem` serialisation and `AppSettings` persistence were not
  done** (N15.13) — this slice is transport/data-plane only.
- App-only mark kinds (`spritz`, `turn`) are written to the wire as `note`,
  matching the existing `mark.dart` library note; neither is carried natively.
- `mark_rec.kind` mapping lives in `http_transport.dart`
  (`_markKindToWire`/`_markKindFromWire`).

### What remains (next session)

1. **N15.8 — real `BridgeRepository` over the supervisor** (the drop-in the epic
   is about). Compose `ConnectionSupervisor` + `BridgeSession` + `SampleCache`
   and map transport DTOs to `BridgeSnapshot`, `HistoryEntry`, `DeviceInfo`,
   `ConnectionState`, alarms and every mutation method. Then wire
   `bridgeRepositoryProvider`/`prefsProvider` in `lib/data/providers.dart` and
   keep `MockBridgeRepository` for the dev panel. This is the largest remaining
   piece and the exit gate depends on it.
2. **N15.3 `BleTransport`** (flutter_blue_plus): 11 GATT characteristics,
   chunked history notify, LE Secure passkey. `TransportFactory.openBle()` is
   the seam; `HttpTransportFactory.bleOpener` is the hook.
3. **N15.9 real drift schema** implementing `SampleCache` (Bridges/Sessions/
   Samples/Marks/Cooks/CookProbeRoles/AlarmRules/Gaps/SyncStates) + codegen.
4. **N15.13 real `PrefsRepository`** over `shared_preferences`, loaded once at
   boot for synchronous reads; persist `AppSettings` (all fields incl.
   `CustomFood`/`CookTimeline`) and the prefs keys in research notes §5.2. No
   Wi-Fi password is ever persisted.
5. **N15.15–N15.22 platform services**: notification channels + foreground
   service + `CookMonitor`, permissions/system-settings, `network_binder`,
   `firmware_picker` (OTA) + `share_plus`, diagnostics read-back. These need
   plugins; do not add them before their code.
6. Check the `BridgeSnapshot` mapping against `tools/sim` with `make sim` and
   the `?scenario=`/dev-panel seams; `MockTransport` can be driven from the sim
   shapes if a live run is easier.
7. `InMemorySampleCache.clearConnectivityGapsBetween` clears connectivity gaps
   fully inside `[fromT,toT]`; the drift version should match.