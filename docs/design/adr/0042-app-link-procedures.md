# ADR 0042 — App link procedures own the GATT sequence, clock and backoff

**Status:** accepted (T35)

## Context

The setup flow (T33) only proved the bond and left a shim that requested MTU and
jumped to the first-sync screen. V0 needs the full procedure order from
[05 §5.12](../../05-ble-contract.md#512-procedures): connect, read `info`, MTU
247, bond, subscribe, read `live`, `control(set_time)`, recent sync; plus the
reconnect/health machine in [06 §6.3](../../06-app.md#63-connection-lifecycle).
The app cannot import `protocol/gen`, and the archive/cursor and full codecs are
later tasks (T39–T41, T47).

## Decision

1. `data/ble/bridge_link.dart` owns the whole procedure as a Flutter-free
   service over `BleClient`. It reports through a `BridgeLinkHost` callback
   bundle; `BridgeController.ensureLink()` wires those callbacks to the
   controller's phase, live, info, sync and reconnect state. Later tasks reuse
   the same instance instead of re-implementing the order.
2. `data/ble/bridge_protocol.dart` carries the V0 codec slice (`live`,
   `control`/`set_time`, `result`, `sync_ctrl`, sync framing and records).
   `test/link_codec_test.dart` decodes and re-encodes the same bytes with
   `protocol/gen`, so the duplicate offsets cannot drift. T40/T47 replace the
   slice with the packaged codec.
3. The control queue allocates a non-reused 0–255 `op_id`, subscribes to
   `result` before writing, matches op + op_id, and times out after exactly 3 s.
   The write return value is never success; only `result.status` branches.
4. Time sync sends the phone's UTC milliseconds and local `tz_offset_min`. The
   first connect always sets the clock. A reconnect re-sends only when
   `live.clock_valid` is false or the phone wall clock has moved more than 2 s
   against the monotonic elapsed time since the last successful set. V0 cannot
   read the bridge clock (stats is out of scope), so this is the strongest
   comparison available; a bridge power loss reports `clock_valid = 0`.
5. Reconnect is bounded: `LIVE → RECONNECTING` on any GATT disconnect, attempts
   after 1, 2, 4, 8, 15, 30 s, then `FAILED` with the named
   `Can’t reach the Bridge` banner and Retry/Forget. Pull-to-refresh and app
   resume complete the wait immediately. The watchdog reads `live` after 110 s
   without a notification and maps fresh/quiet/failure to LIVE/STALE/RECONNECT.
6. First sync is a backward read of the last **15 minutes** (V0), not 24 h, and
   moves the local cursor to the bridge max. A reconnect with a cursor syncs
   forward from the local max immediately. Records are handed to a
   `BridgeSyncSink`; V0 uses a no-op sink and T39–T41 implement the store.

## Consequences

- The procedure is testable end to end against the scripted fake, including a
  forced link drop and the six-attempt failure, with an injected clock/timer so
  the suite does not wait 60 s.
- The 110 s watchdog is a real `Timer`. Widget tests that complete a first
  connect must end the link (`link.dispose()`) inside the test body before the
  pending-timer invariant runs.
- A reconnect that finds a stale bond does not call `bond()`; it falls through
  to the named failed state with `Forget this phone`, which returns to setup.
  The "look at the Bridge screen" instruction stays owned by setup (T33), and a
  dedicated reconnect-time re-pair surface can reuse the same host callback
  later (T37/T48).
- Background APK sync, gap/generation handling and the durable cursor remain
  T39–T41; the link's `BridgeSyncSink` and `localMaxSeq` are the seams.
