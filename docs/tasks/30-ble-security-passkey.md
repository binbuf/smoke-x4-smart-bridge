# T30 — ble_service: security, passkey, and advertising

## Goal
A phone bonds with the bridge using LE Secure Connections and the six-digit code shown on the OLED, and the bridge advertises so it can be found whenever it is on and idle. This is the security boundary that keeps `live` and history private while leaving `info` open for discovery.

## Context (read first)
- [05 §5.2, §5.11](../design/05-ble-contract.md) — advertising, scan-response status blob, security model, bond limit.
- [07 §7.3](../design/07-display-and-controls.md) — the passkey overlay and its expiry/cancel behaviour.
- [05 §5.1](../design/05-ble-contract.md) — characteristic security levels.
- Design: [05](../design/05-ble-contract.md), [07](../design/07-display-and-controls.md).
- Verify tier: **H/B**. Board: **no / B**.
- Depends on T27 and T22.

## Scope
- [x] Configure LE Secure Connections with Passkey Entry, using `DisplayOnly` IO capability; generate a fresh six-digit code when bonding starts.
- [x] Persist bonds in NimBLE's NVS store; cap at **4** phones, allow **one active connection**, and do not evict. Report remaining slots as `info.bonds_free`.
- [x] Enforce the characteristic security levels: `info` open; `live`, `stats`, `sync_ctrl`, `sync_data` encrypted; `control`, `config` encrypted + authenticated. CCCD writes require the same level as their characteristic.
- [x] Implement the scan-response status blob: 9 B after the 2-byte company ID, with `ver`, `flags`, `pit_temp_f10`, `battery_pct`, `billows_target_f10`, `age_s`, reserved.
- [x] Set the advertising PDU to Flags + 128-bit service UUID (21 of 31 bytes), and the scan response to the complete local name + manufacturer-specific status blob.
- [x] Use local name `SmokeX4-XXXX`, where `XXXX` is the last two bytes of the BLE MAC in uppercase hex.
- [x] Advertise at **250 ms for 60 s** after boot/button/disconnect, then at **1,000 ms**.
- [x] Start advertising at boot when not connected, on disconnect, after a failed connect, and on advertising timeout; stop on connection.
- [x] Restart advertising after disconnect.
- [x] Display the six-digit passkey on the OLED overlay: `PAIR WITH PHONE`, the code, `enter this code on your phone`; the code expires when bonding ends or after 60 s, and a tap cancels the attempt.
- [x] Keep the `live` flag `sync_active`/connection-related flags coherent with the advertising/connected state where they overlap.
- [x] Add host tests for the scan-response blob and the advertising/security state transitions.
- [x] No Just Works fallback: if the phone cannot do passkey entry, the app says so rather than silently downgrading.

## Out of scope
- The app's setup/passkey screens and OS-dialog handoff → T33.
- Scanning and the app BLE client → T32.
- Device-name and display-timeout configuration → T51 (M4).
- `forget_phone` / `factory_reset` bond removal → T48; lost-phone USB recovery is outside MVP and no task owns it.
- Billows observation and target validation → T56, T57, T59 (M5). The blob carries the observed target; it does not enable control.
- Wi-Fi/HTTP/OTA and any provisioning service — outside MVP; no task owns it.

## Design notes
- Advertising table (05 §5.2):

| | |
|---|---|
| Local name | `SmokeX4-XXXX` (last two MAC bytes, uppercase hex) |
| Advertising PDU | Flags + 128-bit service UUID (21 of 31 bytes) |
| Scan response | Complete local name + manufacturer-specific status blob |
| Interval | 250 ms for 60 s after boot/button/disconnect, then 1,000 ms |
| Starts | At boot when not connected; on disconnect; after a failed connect; on advertising timeout |
| Stops | On connection |

- Company ID is `0xFFFF` (Bluetooth SIG reserved test ID) for the bench build. Do not ship a production advertisement with a test company ID; assign one before public release. The app must not require manufacturer data.
- Scan-response blob offsets: `ver` @0, `flags` @1 (same bits as `live.flags`), `pit_temp_f10` i16 @2 (P4), `battery_pct` @4 (255 unknown), `billows_target_f10` i16 @5 (0 unknown), `age_s` @7 (clamped 0–255), reserved @8.
- Bonding is not multi-user support; the four slots are for phone replacement/handoff. `info.bonds_free == 0` must be visible to the app before it starts a bond.
- The bridge displays the code when bonding starts, not while merely advertising. The app must show the "look at the Bridge screen" instruction before triggering the OS prompt.
- Lost-phone recovery is a USB erase/reflash (`idf.py erase-flash`); there is no on-device factory reset gesture in the MVP.
- BLE is peripheral-only: the bridge advertises; the app initiates the connection.

## Done when
- [x] A real phone bonds using the six-digit code shown on the OLED. **Deferred to T37**; host security-state tests are the gate now.
- [x] A wrong code fails and does not create a usable bond. Host-tested; real phone at T37.
- [x] A bond survives a bridge reboot; reconnecting does not show a passkey prompt. Host-tested; real phone at T37.
- [x] `info` is readable without a bond; `live` is not readable or subscribable without encryption. Host-tested; real central at T37.
- [x] Advertising is visible at boot, stops on connection, and restarts after disconnect; the 250 ms → 1,000 ms change is observed. Host/host-timer tested; real scanner at T37.
- [x] A fifth phone is refused at the bond limit rather than evicting an existing bond. Host-tested; real phones at T37.
- [x] Host tests cover the scan-response blob and the advertising/security state transitions.
- [x] Hand-off below filled in

## Hand-off
**Status: done.** Advertising, passkey/bonding policy and the T30 host gate
landed. Real-phone checks remain deferred to T37 by the task's Done-when.

### Changes

- New pure-C cores: `ble_adv.[ch]` (PDU, scan response/status blob, name,
  250→1,000 ms state machine) and `ble_security.[ch]` (4-bond cap, six-digit
  passkey lifetime). Host suite `ble-adv` pins the bytes and transitions.
- `ble_service.c`: DisplayOnly/SC-only/MITM bonding, `esp_random()` passkey
  injected with `ble_sm_inject_io()`, 60 s expiry, tap cancel, no store
  eviction (`store_status_cb = NULL`), deferred advertising start/restart on
  boot/disconnect/failed connect/timeout, stop on connect, bond-count cache.
- `boot.c` wires the passkey display callback to `ui_set_passkey()`; `ui.c`
  shows the real connection/bond state and cancels pairing on a passkey tap.
- Docs: design 05 §5.2 implementation rules; ADR 0037; progress T30.

### Verification

- `ctest --test-dir firmware/test/build --output-on-failure` → 20/20 pass
  (new `ble-adv`).
- `idf.py -B build ... build` → complete; image guard ok; `sx4_bridge.bin`
  `0x903d0`, 72% free.

### Deviations

- The overlay is reached through a callback seam to avoid a `ble_service` ↔
  `ui` component cycle.
- Passkey expiry and a tap terminate the link so the phone sees a failed bond.
- `sm_sc_only` is set in addition to `sm_sc`/`sm_mitm` to refuse legacy
  downgrades.
- The status blob refreshes at each advertising start, not per sample.

### Remaining work (T37, board/phone)

Bond with the OLED code; wrong code fails; reboot keeps the bond with no
prompt; `info` open and `live` encrypted; advertising visible at boot, gone on
connect, back on disconnect; observe 250→1,000 ms; fifth phone refused. Also T33
must show the "look at the Bridge screen" instruction before the OS prompt.
