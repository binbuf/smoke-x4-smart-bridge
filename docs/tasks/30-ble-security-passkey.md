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
- [ ] Configure LE Secure Connections with Passkey Entry, using `DisplayOnly` IO capability; generate a fresh six-digit code when bonding starts.
- [ ] Persist bonds in NimBLE's NVS store; cap at **4** phones, allow **one active connection**, and do not evict. Report remaining slots as `info.bonds_free`.
- [ ] Enforce the characteristic security levels: `info` open; `live`, `stats`, `sync_ctrl`, `sync_data` encrypted; `control`, `config` encrypted + authenticated. CCCD writes require the same level as their characteristic.
- [ ] Implement the scan-response status blob: 9 B after the 2-byte company ID, with `ver`, `flags`, `pit_temp_f10`, `battery_pct`, `billows_target_f10`, `age_s`, reserved.
- [ ] Set the advertising PDU to Flags + 128-bit service UUID (21 of 31 bytes), and the scan response to the complete local name + manufacturer-specific status blob.
- [ ] Use local name `SmokeX4-XXXX`, where `XXXX` is the last two bytes of the BLE MAC in uppercase hex.
- [ ] Advertise at **250 ms for 60 s** after boot/button/disconnect, then at **1,000 ms**.
- [ ] Start advertising at boot when not connected, on disconnect, after a failed connect, and on advertising timeout; stop on connection.
- [ ] Restart advertising after disconnect.
- [ ] Display the six-digit passkey on the OLED overlay: `PAIR WITH PHONE`, the code, `enter this code on your phone`; the code expires when bonding ends or after 60 s, and a tap cancels the attempt.
- [ ] Keep the `live` flag `sync_active`/connection-related flags coherent with the advertising/connected state where they overlap.
- [ ] Add host tests for the scan-response blob and the advertising/security state transitions.
- [ ] No Just Works fallback: if the phone cannot do passkey entry, the app says so rather than silently downgrading.

## Out of scope
- The app's setup/passkey screens and OS-dialog handoff → T33.
- Scanning and the app BLE client → T32.
- Device-name and display-timeout configuration → T51 (M4).
- `forget_phone` / `factory_reset` bond removal → T48; lost-phone USB recovery is outside MVP and no task owns it.
- Billows observation and target validation → T56–T60 (M5). The blob carries the observed target; it does not enable control.
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
- [ ] A real phone bonds using the six-digit code shown on the OLED.
- [ ] A wrong code fails and does not create a usable bond.
- [ ] A bond survives a bridge reboot; reconnecting does not show a passkey prompt.
- [ ] `info` is readable without a bond; `live` is not readable or subscribable without encryption.
- [ ] Advertising is visible at boot, stops on connection, and restarts after disconnect; the 250 ms → 1,000 ms change is observed.
- [ ] A fifth phone is refused at the bond limit rather than evicting an existing bond.
- [ ] Host tests cover the scan-response blob and the advertising/security state transitions.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
