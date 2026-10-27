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
- [ ] Implement the pure encoder for the fixed **20-byte** `live` payload from the `bridge_state` snapshot.
- [ ] Add the standard CCCD (`0x2902`) for `live` and require the encrypted security level (set by T30) for subscribing and reading.
- [ ] Send a notification on every stored sample.
- [ ] Send a notification whenever a `live.flags` bit changes: connection, pairing, Billows, clock, display, and sync start/end.
- [ ] Implement the read fallback: a plain read returns the latest snapshot, not a queued value.
- [ ] Feed notifications from a bounded queue/hand-off owned by `ble_tx`, not from the radio task; no dynamic allocation on the sample path.
- [ ] Keep the payload at ≤20 B so it always fits an MTU 23 notification.
- [ ] Add host tests for the 05 §5.4 byte vector and the required states: four attached, one detached, all detached, clock invalid, Billows attached.

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
- [ ] The read fallback returns the same latest snapshot as the last notification.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
