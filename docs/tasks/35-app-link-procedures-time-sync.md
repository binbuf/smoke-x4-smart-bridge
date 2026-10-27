# T35 — app: link procedures and time sync

## Goal
The app performs the real GATT procedure sequence from connect to live data: read `info`, negotiate MTU, bond, subscribe, read `live`, set the clock, and sync recent records, with an `op_id`-matched control queue and a bounded reconnect state machine. This makes the fake-driven app work against the real bridge and recover from a dropped link.

## Context (read first)
- [06 §6.3](../design/06-app.md) — connection state machine, health checks, lifecycle, and backoff.
- [05 §5.12](../design/05-ble-contract.md) — first-connect, reconnect, control-op, and sync procedures.
- [13 §13.5](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows) — first launch, returning launch, and connection health.
- [05 §5.5, §5.6](../design/05-ble-contract.md) — control/result and `op_id` echo.
- Design: [06](../design/06-app.md), [05](../design/05-ble-contract.md).
- Verify tier: **H/P**. Board: **no / phone**.
- Depends on T32, T06, T29, and T30.

## Scope
- [x] Implement the first-connect sequence: scan/connect → read `info` → request MTU 247 → pair when the link is not encrypted → subscribe to `live`, `result`, `sync_data` → read `live` → `control(set_time)` → sync recent.
- [x] Show the "look at the Bridge screen" passkey instruction before triggering the OS bond; a valid stored bond produces no passkey prompt on reconnect.
- [x] Never write `control` or `config` before the link is `SECURED`; treat ATT `0x0F` / `0x05` as "bond/authenticate first", not retry-forever.
- [x] Implement the control/result queue: choose a non-reused `op_id`, write `control`, wait for the matching `result`, and time out after **3 s**.
- [x] Never assume `ok` because the GATT write returned; branch on the result status.
- [x] Implement `set_time` with the phone's UTC milliseconds and timezone offset; set it on first connect and on reconnect when the clock differs by more than 2 s.
- [x] Implement the reconnect state machine: `LIVE` → `RECONNECTING` on link loss with backoff **1, 2, 4, 8, 15, 30 s**; after all six attempts show `Can’t reach the Bridge` with Retry and a `Forget this phone` escape.
- [x] A user pull-to-refresh or app resume cuts the reconnect wait short.
- [x] Health watchdog: no notification for **110 s** → read `live`; success with fresh age → `LIVE`; success with a quiet X4 → stay `STALE`; read failure → `RECONNECTING`. Any GATT disconnect → `RECONNECTING` even if the last sample was recent.
- [x] On reconnect with existing data, set the clock when needed and sync **forward from the local max seq** immediately; do not re-read the last 24 h.
- [x] On first sync, pull recent records after pairing; V0 reads the last 15 minutes, not the full 24 h.
- [x] Keep the background skip/backfill vocabulary out of product copy: `Syncing saved readings` for the recent pass, `Loading saved readings` for background loading; never show `Syncing` or `backfill` alone.
- [x] Drive the whole sequence from the fake in tests, including a link drop and recovery.

## Out of scope
- `config`/`stats` reads and writes → T47/T51 (M4); V0 needs only `info`, `live`, and sync.
- Full sync cursor, gap/generation handling, local DB, and two-phase repository sync → T39–T41 (M3).
- History UI → T36 and T42.
- Setup/passkey screen copy and states → T33.
- `BleClient` platform exception mapping and plugin internals → T32.
- Destructive control actions (`forget_phone`, factory reset, power off, clear history) → T48.
- Billows observation/UI → T56–T60 (M5); no Billows control path exists.
- Background scanning, a foreground service, or a battery-optimization exemption — outside MVP; no task owns them.
- Wi-Fi/HTTP/OTA or a cloud sync path — outside MVP; no task owns it.

## Design notes
- State names (06 §6.3): `UNINITIALIZED`, `SETUP`, `SCANNING`, `NO_RESULTS`, `CONNECTING`, `PAIRING`, `SECURING`, `SYNCING`, `LIVE`, `RECONNECTING`, `FAILED`, `STALE`, `BLOCKED`. `Aging`, `Stale`, and `Frozen` are internal; the UI uses time language.
- Procedure order is fixed: connect → read info → MTU → pair → subscribe → read live → set_time → sync. Reading `live` before the bond is expected to fail with an encryption/authentication ATT error and is the trigger to pair.
- `op_id` is 0–255 and wraps; the app must not reuse an outstanding value. The 3 s timeout is the contract, not an implementation detail.
- Time handling: no RTC on the bridge. `unix_s = 0` means the clock was unknown. Never adjust earlier records; a correction changes future records only. The app labels estimated time where the bridge clock was unset.
- The state machine's backoff is bounded and visible. Do not spin forever silently, and do not auto-connect to an arbitrary scan result when a remembered bridge exists.
- `info.proto_major` must be `1`; another major shows `Update the app to use this Bridge` and does not write.
- Scanning is foreground-only; on resume, run a health check and forward sync.

## Done when
- [x] The fake drives connect → info → MTU → pair → subscribe → live → set_time → sync end to end in `flutter test`.
- [x] A real phone sets the bridge time and a `result` with the matching `op_id` is received within 3 s. **Deferred to T37**; the fake-driven test is the gate now.
- [x] A forced link drop recovers through the backoff sequence and resumes forward sync from the local max without a 24 h re-read.
- [x] An unsecured `live` read triggers the bond path rather than a retry loop.
- [x] The all-attempts-fail state shows the named `Can’t reach the Bridge` state with Retry/Forget.
- [x] Hand-off below filled in

## Hand-off

**Landed.** `data/ble/bridge_link.dart` runs the fixed GATT procedure (connect →
info → MTU 247 → bond → subscribe live/result/sync_data → read live →
`control(set_time)` → sync), with a non-reused `op_id` queue, an exact 3 s
result timeout, `result.status` branching, a bounded 1/2/4/8/15/30 s reconnect
loop, a 110 s health watchdog, pull/resume wait cancellation, forward sync from
`localMaxSeq`, and a V0 15-minute backward first sync. `BridgeController`
wires it through `ensureLink()`, publishes real attempts in the approved copy,
and Live/Setup/app-resume call the same instance. `data/ble/bridge_protocol.dart`
holds the V0 codec slice, pinned to `protocol/gen` by `test/link_codec_test.dart`.
The failed state renders `Can’t reach the Bridge` with `Retry` and
`Forget this phone`. Tests: `test/bridge_link_test.dart` (16) and
`test/link_codec_test.dart` (6).

**Deviations.** The bridge clock is not readable in V0 (stats is out of scope),
so reconnect compares the phone wall clock against monotonic elapsed time since
the last successful set (`clock_valid` forces a reset after power loss); see ADR
0042. The procedure bonds proactively when not bonded rather than provoking ATT
`0x0F` with a doomed read; security failures still take the same one-shot bond
path. A reconnect-time stale bond has no approved passkey surface yet (setup
owns that copy). Recent sync skips records older than 15 minutes by advancing
the cursor to the bridge max, matching V0 semantics.

**Checks.** `flutter analyze` clean; `flutter test` 132 pass;
`flutter build apk --debug` succeeds; `make app-check` passes.

**Remaining.** Real-phone verification is T37 (time set + matching result
within 3 s, forced drop/backoff, no passkey prompt with a stored bond). Durable
sync sink/cursor and background loading are T39–T41; the packaged codecs are
T40/T47; destructive controls and reconnect-time re-pair UI are T48; remembered
bridge persistence/auto-connect is T50.
