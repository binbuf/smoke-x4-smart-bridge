# ADR 0035 — Live notifications: pure encoder and a ble_tx-owned bounded hand-off

**Status:** accepted (T28, 2026-10-27)

## Context

`live` is the app's freshness path: a 20-byte snapshot on every stored sample
and on every `flags` change, with a read fallback for a missed notification.
The fixed 20 bytes must fit an MTU 23 notification. The sample pipeline runs on
`sample_pipe`/`log_writer`, the flags are changed from several other tasks, and
design 03 makes `ble_tx` the single notification writer. The radio task must
never call NimBLE, and the sample path must not allocate.

`bridge_state_live_t.seq` was not enough to tell "no stored sample yet" from a
real first record (`seq = 0`), so the wire sentinel `0xFFFFFFFF` needed an
explicit validity bit. Flag transitions also had no single observation point.

## Decision

1. **`ble_live_encode()` is the only `live` encoder.** It is plain C11, maps a
   `bridge_state_live_t` to the generated `sx4_live_t` and delegates the offsets
   and little-endian layout to `protocol/gen/records.c`. It forces
   `SX4_TEMP_DETACHED` for every probe whose `attached_mask` bit is clear, emits
   `SX4_SEQ_NONE` until a sample has a stored sequence, writes 0 for an invalid
   Billows target and always clears the reserved `billows_output` bit.
2. **`bridge_state_live_t`/`bridge_state_sample_t` carry `have_seq`.** The
   sample pipeline sets it only when the log assigned the sequence. This is an
   additive field, not a second snapshot source.
3. **`ble_tx` owns a fixed 8-frame ring of encoded payloads.** The pure core
   (`ble_tx_core.c`) dedupes on the wire `seq` and `flags`, so an unchanged
   snapshot is a no-op while a new stored sequence or a flag transition queues
   exactly one frame. A full ring drops the newest frame and increments
   `dropped`; every consumer recovers it with a log sync.
4. **`bridge_state` exposes an optional change hook.** It runs after sample
   publication, an actual flag transition and a successful `set_time`, outside
   the seqlock. The firmware installs `ble_tx_live_changed()`, which only reads
   the snapshot and appends to the ring under a short critical section; the
   `ble_tx` task performs the NimBLE send. The 1 s task timeout catches
   time-driven transitions such as `smoke_live` expiry.
5. **The read fallback and a new subscription both use the latest snapshot.**
   A GATT read encodes the current `bridge_state_snapshot()` (never a queued
   frame), and a successful CCCD subscription clears stale frames and primes the
   queue with the same current snapshot. The CCCD and read remain encrypted via
   the existing `BLE_GATT_CHR_F_READ_ENC` /
   `BLE_GATT_CHR_F_NOTIFY_INDICATE_ENC` flags.

## Consequences

- The sample path cost is one 20-byte encode and one ring append; no NimBLE
  call and no allocation ever runs on `radio_rx`/`sample_pipe`/`log_writer`.
- A dropped live notification is normal; T31/T37 verify that a sequence-cursor
  sync recovers the record. Live is not an archive.
- Later tasks that change a `live.flags` bit or call `bridge_state_update()`
  are notified automatically. New snapshot fields that do not change `seq` or
  `flags` (battery, for example) do not generate a notification; read/sync
  carries them.
- T30 still owns advertising, bonding and the actual security enforcement.
