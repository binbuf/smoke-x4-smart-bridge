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
- [x] Register the new base UUID `7f9bXXXX-4c5b-4b0f-9a3d-1c2e3f405162` and service `7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162`.
- [x] Register all eight characteristic slots `0001`–`0008` with the properties and security levels in 05 §5.1, even where the V0 payload is empty/busy and a later task fills it in.
- [x] Add a standard CCCD (`0x2902`) to every Notify characteristic and require the characteristic's security level for CCCD writes.
- [x] Implement the pure `info` encoder: fixed 32 bytes, little-endian, `ver = 1`, with `device_id`, `fw`, `model`, `probes`, `caps`, and `bonds_free` from `bridge_config`.
- [x] Serve `info` as an open Read (Read Blob at `MTU−1` per response), readable before any bond.
- [x] Implement the NimBLE init and disconnect callbacks. Do not start advertising from this task; T30 owns the advertising policy and restart-on-disconnect wiring.
- [x] Add host encoder tests for `info` with all caps and with `billows_control = 0`, matching the byte vector.
- [x] Do not register Wi-Fi or OTA characteristics.

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
- [x] `cmake -S firmware/test -B firmware/test/build -G Ninja`, `cmake --build firmware/test/build`, and `ctest --test-dir firmware/test/build` pass, including the `info` byte-vector tests for all-caps and `billows_control = 0`.
- [x] A phone/bench scanner sees the service and its characteristic slots, and reads a correct 32-byte `info` with `ver = 1`, the expected protocol major/minor, `caps`, `probes`, `device_id`, firmware, model, and `bonds_free`. **Deferred to T37** (real phone/scanner); host byte-vector tests are the gate now.
- [x] `info` is readable without a bond. Host-tested; real central at T37.
- [x] No Wi-Fi or OTA characteristic is present in the service.
- [x] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_

### What landed
- `ble_info.c/.h` — pure 32-byte `info` encoder. `BLE_INFO_CAPS_ALL` (0xFF) is
  masked so `billows_control` is always 0 (wire `caps = 0xFD`). Field sources:
  MAC suffix for `device_id`, persisted pairing probes (4 when unknown),
  `4 − NimBLE peer-security count` for `bonds_free`, `fw = 0.1.0`,
  `model = heltec3`, protocol major/minor from generated `records.h`.
- `ble_gatt_spec.c/.h` — eight-slot table from the generated
  `SX4_BLE_CHAR_*` macros; no Wi-Fi/OTA/DFU slot. Host test pins all slots,
  properties, security, and CCCD-on-Notify.
- `ble_service.c` — NimBLE init, custom 128-bit service and all eight
  characteristics, open Read-Blob `info` at `MTU−1` per response, encrypted /
  authenticated value flags, auto CCCDs with `NOTIFY_INDICATE_ENC`, and a GAP
  listener that tracks connect/disconnect. Advertising is deliberately not
  started.
- V0 placeholders: `live`/`config`/`stats` return a ver=1 zero buffer; writes to
  `control`/`sync_ctrl`/`config` are drained no-ops. T28/T29/T31/T47 replace
  them.
- Build boundary: local `firmware/components/esp_wifi` override (headers only,
  no Wi-Fi code), empty `lwip/ip_addr.h` compatibility shim, `bt` in
  `COMPONENTS`, NimBLE settings in `sdkconfig.defaults`, and a linked-object
  network check in `check_image.py` (ADR 0034).
- Tests: `firmware/test/test_ble_info.c`, `ble-info` CTest.
- Docs: design 03 §3.9/§3.13, design 05 §5.3, ADR 0034, `docs/progress/T27.md`.

### Deviations
- `device_id`/`bonds_free` cannot come from `bridge_config` alone: the bridge
  identity is the BLE MAC and the bond count is NimBLE's store. The encoder is
  pure and firmware glue supplies those values (ADR 0034).
- `probes` reports 4 until a valid pairing says 2/4; the contract only allows
  2 or 4 and the bridge UI supports four channels.
- IDF 6's `bt` hard-requires `esp_wifi` and its hidden `ESP_WIFI_ENABLED`
  cannot be disabled from sdkconfig. A project override plus the linker-map
  guard keeps the image free of Wi-Fi/lwIP/netif objects.

### Checks
- Host: `cmake -S firmware/test -B firmware/test/build -G Ninja`,
  `cmake --build firmware/test/build`,
  `ctest --test-dir firmware/test/build --output-on-failure` → 17/17 pass,
  including `ble-info`.
- Firmware: `idf.py -B build fullclean` then
  `idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`
  → complete; image guard ok (84 components, no linked Wi-Fi/lwIP/netif, no
  HTTP/OTA); `sx4_bridge.bin` 0x8dc40 bytes, 72% free.
- `python -m py_compile firmware/tools/check_image.py` → ok.

### Remaining
- T37: real phone/scanner sees all slots + CCCDs and reads the 32-byte `info`
  before bonding.
- T30: advertising, passkey/bonding, restart on disconnect. Use the existing
  `ble_service_gap_event()` and `ble_service_is_connected()`.
- T28/T29/T31/T47/T51: fill the payload handlers; preserve the slot table and
  security levels.
