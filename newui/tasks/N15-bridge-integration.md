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