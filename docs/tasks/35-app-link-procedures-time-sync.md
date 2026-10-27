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
- [ ] Implement the first-connect sequence: scan/connect → read `info` → request MTU 247 → pair when the link is not encrypted → subscribe to `live`, `result`, `sync_data` → read `live` → `control(set_time)` → sync recent.
- [ ] Show the "look at the Bridge screen" passkey instruction before triggering the OS bond; a valid stored bond produces no passkey prompt on reconnect.
- [ ] Never write `control` or `config` before the link is `SECURED`; treat ATT `0x0F` / `0x05` as "bond/authenticate first", not retry-forever.
- [ ] Implement the control/result queue: choose a non-reused `op_id`, write `control`, wait for the matching `result`, and time out after **3 s**.
- [ ] Never assume `ok` because the GATT write returned; branch on the result status.
- [ ] Implement `set_time` with the phone's UTC milliseconds and timezone offset; set it on first connect and on reconnect when the clock differs by more than 2 s.
- [ ] Implement the reconnect state machine: `LIVE` → `RECONNECTING` on link loss with backoff **1, 2, 4, 8, 15, 30 s**; after all six attempts show `Can’t reach the Bridge` with Retry and a `Forget this phone` escape.
- [ ] A user pull-to-refresh or app resume cuts the reconnect wait short.
- [ ] Health watchdog: no notification for **110 s** → read `live`; success with fresh age → `LIVE`; success with a quiet X4 → stay `STALE`; read failure → `RECONNECTING`. Any GATT disconnect → `RECONNECTING` even if the last sample was recent.
- [ ] On reconnect with existing data, set the clock when needed and sync **forward from the local max seq** immediately; do not re-read the last 24 h.
- [ ] On first sync, pull recent records after pairing; V0 reads the last 15 minutes, not the full 24 h.
- [ ] Keep the background skip/backfill vocabulary out of product copy: `Syncing saved readings` for the recent pass, `Loading saved readings` for background loading; never show `Syncing` or `backfill` alone.
- [ ] Drive the whole sequence from the fake in tests, including a link drop and recovery.

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
- [ ] The fake drives connect → info → MTU → pair → subscribe → live → set_time → sync end to end in `flutter test`.
- [x] A real phone sets the bridge time and a `result` with the matching `op_id` is received within 3 s. **Deferred to T37**; the fake-driven test is the gate now.
- [ ] A forced link drop recovers through the backoff sequence and resumes forward sync from the local max without a 24 h re-read.
- [ ] An unsecured `live` read triggers the bond path rather than a retry loop.
- [ ] The all-attempts-fail state shows the named `Can’t reach the Bridge` state with Retry/Forget.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
