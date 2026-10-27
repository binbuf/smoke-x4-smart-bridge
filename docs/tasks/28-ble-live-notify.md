# T28 — ble_service: live notify

## Goal
A subscribed phone receives the 20-byte live snapshot on every stored sample and on every flag change, with a read fallback, so Live can show four probes and link health without polling. The fixed 20-byte size is what keeps live telemetry working at the default MTU of 23.

## Context (read first)
- [05 §5.4](../design/05-ble-contract.md) — `live` layout, `flags`, notification policy, and the example vector.
- [05 §5.2.1](../design/05-ble-contract.md) — MTU 23 / 247 behaviour and notification reassembly.
- [03 §3.3, §3.14](../design/03-firmware-architecture.md) — `ble_tx` is the single notification writer; `ble_service` encoders are pure.
- Design: [05](../design/05-ble-contract.md).
- Verify tier: **H/B**. Board: **no / B**.
- Depends on T27 and T21.

## Scope
- [x] Implement the pure encoder for the fixed **20-byte** `live` payload from the `bridge_state` snapshot.
- [x] Add the standard CCCD (`0x2902`) for `live` and require the encrypted security level (set by T30) for subscribing and reading.
- [x] Send a notification on every stored sample.
- [x] Send a notification whenever a `live.flags` bit changes: connection, pairing, Billows, clock, display, and sync start/end.
- [x] Implement the read fallback: a plain read returns the latest snapshot, not a queued value.
- [x] Feed notifications from a bounded queue/hand-off owned by `ble_tx`, not from the radio task; no dynamic allocation on the sample path.
- [x] Keep the payload at ≤20 B so it always fits an MTU 23 notification.
- [x] Add host tests for the 05 §5.4 byte vector and the required states: four attached, one detached, all detached, clock invalid, Billows attached.

## Out of scope
- `info` and service registration → T27.
- `control`/`result` and `set_time` → T29.
- The encrypted link, bonding, and CCCD security enforcement mechanics → T30.
- `sync_ctrl`/`sync_data` and the catch-up path for a missed notification → T31; the app-side periodic forward sync → T35/T41.
- Billows target validation and the Billows UI → T56–T60 (M5). The target field is carried here but not validated by this task.
- Wi-Fi/HTTP/OTA or any network telemetry path — outside MVP; no task owns it.

## Design notes
- `live` offsets (05 §5.4): `ver` @0, `flags` @1, `temp[4]` i16 tenths °F @2 (8 B, sentinels allowed), `seq` u32 last stored sample @10 (`0xFFFFFFFF` if none), `billows_target_f10` i16 @14 (0 = unknown), `battery_pct` @16 (255 = unknown), `rssi_lora` i8 @17, `age_s` u16 seconds since the last valid Smoke X4 state packet @18.
- `flags`: 0 `smoke_paired`, 1 `smoke_live` (valid state packet within the last 90 s), 2 `billows_attached`, 3 `billows_output` (**reserved; always 0 in the MVP**), 4 `clock_valid`, 5 `storage_ok`, 6 `display_on`, 7 `sync_active`.
- Temperature sentinels: `INT16_MIN` = probe detached (surface as null; never plot as a temperature); `INT16_MIN + 1` = present but invalid/unmapped. Otherwise the value is temperature × 10 in canonical °F.
- Reference vector from 05 §5.4 — P1 225.0 °F, P2 165.2 °F, P3 detached, P4 80.0 °F, `seq = 1234`, Billows target 225.0 °F, battery 87%, RSSI −71, age 12 s, flags `paired|live|billows|clock`:

```
01 17 CA 08 74 06 00 80 20 03 D2 04 00 00 CA 08 57 B9 0C 00
```

- A missed notification is normal and must be recoverable by sync; live is a freshness/notification path, not the record archive.
- Detached must be encoded as the sentinel, never as 0 °F.

## Done when
- [x] A subscribed client receives one notification per stored sample and on every flag change. **Deferred to T37** for a real phone; the host notification vector is the gate now.
- [x] The host test reproduces the 05 §5.4 vector byte for byte, plus the four-attached, one-detached, all-detached, clock-invalid, and Billows-attached cases.
- [ ] A missed notification is recoverable by a sync from the log (verified in the bench pass with T31/T37).
- [x] The read fallback returns the same latest snapshot as the last notification.
- [x] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_

### What landed
- `ble_live.c/.h` — pure 20-byte `live` encoder over the generated `sx4_live_t`.
  Detached probes are forced to `SX4_TEMP_DETACHED`; `seq = 0xFFFFFFFF` until a
  stored sample; invalid Billows target → 0; reserved `billows_output` cleared.
- `ble_tx_core.c/.h` — pure bounded 8-frame ring. It dedupes on the wire `seq`
  and `flags` (one frame per stored sample and per flag transition), drops the
  newest frame when full and exposes `queued`/`dropped`/`sent` counters.
- `ble_tx.c` — the single writer task. `ble_tx_start()` creates it and installs
  the `bridge_state` change hook; producers only encode + append under a short
  critical section; the task calls `ble_gatts_notify_custom()`. A 1 s timeout
  catches clock-driven `smoke_live` expiry. Subscribe clears stale frames and
  primes with the current snapshot; disconnect clears.
- `ble_service.c` — `live` read now returns the current `bridge_state_snapshot()`
  through the same encoder; GAP CONNECT/DISCONNECT/SUBSCRIBE drive `ble_tx`;
  CCCD/read encryption flags unchanged (NimBLE auto-CCCD).
- `bridge_state` — additive `have_seq` on the sample/live snapshot and an
  optional change hook that fires after sample publication, a real flag
  transition and a successful `set_time`.
- `boot.c` starts `ble_tx` before `ble_service`.
- Tests: `firmware/test/test_ble_live.c` (`ble-live` CTest) plus a change-hook
  case in `test_bridge_state.c`. Covers the 05 §5.4 vector byte-for-byte, the
  four-attached/one-detached/all-detached/clock-invalid/Billows-attached states,
  the no-sample sentinel, the reserved bit, one-frame-per-sample, every flag
  transition, unchanged-snapshot dedupe and queue overflow.
- Docs: design 05 §5.4 implementation rules, design 03 §3.14, ADR 0035,
  `docs/progress/T28.md`.

### Deviations
- Added `have_seq` because the log's first stored sequence is legitimately 0, so
  `seq == 0` cannot mean "none".
- Flag notifications use a `bridge_state` observer rather than wiring every
  caller; it covers current and future setters. The hook must stay non-blocking.
- `ble_tx` polls once per second in addition to queue wake-ups to catch
  time-driven `smoke_live` expiry.
- Battery-only changes do not notify (no `seq`/flag change); read and sync carry
  them, per the notification policy.

### Checks
- Host: `cmake -S firmware/test -B firmware/test/build -G Ninja`,
  `cmake --build firmware/test/build`,
  `ctest --test-dir firmware/test/build --output-on-failure` → 18/18 pass,
  including `ble-live` and the extended `bridge-state`.
- Firmware: `idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`
  → complete; image guard ok (84 components, no linked Wi-Fi/lwIP/netif,
  no HTTP/OTA); `sx4_bridge.bin` 0x8e330 bytes, 72% free.

### Remaining
- T37 (with T31): phone/bench notification count on stored samples and every
  flag transition, and a forced missed notification recovered by a
  sequence-cursor sync. This is the only unchecked Done-when item.
- T30: advertising/bonding/passkey; keep the live CCCD encryption requirement.
- T31: set `sync_active` around a transfer; the change hook emits start/end.
- T29/T47/T51: `control`/`result`/`set_time`, `config` and `stats` remain
  separate; `set_time` already triggers the live flag notification.
