# T27 — ble_service: GATT server and `info`

## Goal
The bridge exposes the new custom GATT service with every characteristic slot registered and a correct 32-byte `info` readable before bonding, so a phone can discover the bridge and check compatibility. This is the base every other BLE payload and the app setup flow builds on.

## Context (read first)
- [05 §5.1, §5.3](../design/05-ble-contract.md) — service UUID, characteristic table, `info` layout and `caps` bits.
- [03 §3.2, §3.14](../design/03-firmware-architecture.md) — `ble_service` component; payload encoders are pure functions and the NimBLE callbacks stay thin.
- Design: [05](../design/05-ble-contract.md).
- Verify tier: **H/B**. Board: **no / B** — host test first, then a BLE scan on the board.
- Depends on T16.

## Scope
- [ ] Register the new base UUID `7f9bXXXX-4c5b-4b0f-9a3d-1c2e3f405162` and service `7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162`.
- [ ] Register all eight characteristic slots `0001`–`0008` with the properties and security levels in 05 §5.1, even where the V0 payload is empty/busy and a later task fills it in.
- [ ] Add a standard CCCD (`0x2902`) to every Notify characteristic and require the characteristic's security level for CCCD writes.
- [ ] Implement the pure `info` encoder: fixed 32 bytes, little-endian, `ver = 1`, with `device_id`, `fw`, `model`, `probes`, `caps`, and `bonds_free` from `bridge_config`.
- [ ] Serve `info` as an open Read (Read Blob at `MTU−1` per response), readable before any bond.
- [ ] Implement the NimBLE init and disconnect callbacks. Do not start advertising from this task; T30 owns the advertising policy and restart-on-disconnect wiring.
- [ ] Add host encoder tests for `info` with all caps and with `billows_control = 0`, matching the byte vector.
- [ ] Do not register Wi-Fi or OTA characteristics.

## Out of scope
- `live` payload, CCCD, and notifications → T28.
- `control`/`result` dispatch and `set_time` → T29.
- Bonding, passkey display, scan response, and advertising intervals → T30.
- `sync_ctrl`/`sync_data` streaming → T31.
- `config`/`stats` payloads and writes → T47/T51 (M4).
- Wi-Fi/HTTP/OTA or any network provisioning characteristic — outside MVP; no task owns it.

## Design notes
- All multi-byte fields are **little-endian**. Every payload begins with `ver = 1`; readers ignore unknown trailing bytes and never reject on `ver` alone. An unknown **major** protocol version is a named refusal, not a parse gamble.
- Characteristic slots and security (05 §5.1):

| Slot | Characteristic | Properties | Security | V0 payload |
|---|---|---|---|---|
| `0001` | `info` | Read | open | 32 B fixed (this task) |
| `0002` | `live` | Read, Notify | encrypted | 20 B fixed (T28) |
| `0003` | `control` | Write | encrypted + authenticated | ≤16 B (T29) |
| `0004` | `result` | Notify | encrypted | ≤64 B (T29) |
| `0005` | `sync_ctrl` | Write | encrypted | 10 B fixed (T31) |
| `0006` | `sync_data` | Notify | encrypted | framed, ≤ `MTU−3` (T31) |
| `0007` | `config` | Read, Write | encrypted + authenticated | 80 B fixed (T47) |
| `0008` | `stats` | Read | encrypted | 60 B fixed (T47) |

- `info` offsets (05 §5.3): `ver` @0, `proto_major` @1, `proto_minor` @2, `caps` @3, `probes` @4 (2 or 4), reserved @5, `device_id` ASCII hex @6 (4 B), `fw` UTF-8 NUL-padded @10 (12 B), `model` UTF-8 NUL-padded @22 (8 B, e.g. `heltec3`), `bonds_free` @30 (0–4), reserved @31.
- `caps` bits: 0 `billows_observe`, 1 `billows_control` (**always 0 in the MVP**), 2 `history`, 3 `battery`, 4 `display_config`, 5 `power_off`, 6 `factory_reset`, 7 `config`. A client must not invent a capability the bit does not set.
- The service UUID is a deliberate bump from the legacy `7f9a…` contract so a legacy app cannot connect and misread a payload.
- Component location is `firmware/components/ble_service/`; host tests live under `firmware/test/` and use the plain-CMake harness from 03 §3.13.

## Done when
- [ ] `cmake -S firmware/test -B firmware/test/build -G Ninja`, `cmake --build firmware/test/build`, and `ctest --test-dir firmware/test/build` pass, including the `info` byte-vector tests for all-caps and `billows_control = 0`.
- [x] A phone/bench scanner sees the service and its characteristic slots, and reads a correct 32-byte `info` with `ver = 1`, the expected protocol major/minor, `caps`, `probes`, `device_id`, firmware, model, and `bonds_free`. **Deferred to T37** (real phone/scanner); host byte-vector tests are the gate now.
- [x] `info` is readable without a bond. Host-tested; real central at T37.
- [ ] No Wi-Fi or OTA characteristic is present in the service.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
