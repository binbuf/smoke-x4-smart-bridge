---
verify: powershell -NoProfile -ExecutionPolicy Bypass -File tools/ci/verify_host.ps1
---
# T47 — ble_service: config read/write and stats read

## Goal
Implement the 80-byte `config` characteristic end to end, so a phone can read and replace the Bridge's units, screen timeout and name, with validation, NVS persistence and immediate runtime/OLED effect. Also implement the 60-byte read-only `stats` characteristic so the app's History & storage view reports the real Bridge copy instead of `0 of 0`. This is the firmware half of every Settings field in M4.

## Context (read first)
- [05 §5.9](../design/05-ble-contract.md) — `0007 config`, fixed 80 B, Read/Write, encrypted + authenticated; the authoritative field layout and validation rules.
- [05 §5.10](../design/05-ble-contract.md) — `0008 stats`, fixed 60 B, Read, encrypted; the authoritative stats layout and flag bits.
- [05 §5.2.1](../design/05-ble-contract.md) — `config` and `stats` use Read Blob (`MTU−1` per response); config writes use queued writes.
- [05 §5.11](../design/05-ble-contract.md) — security: `config` is encrypted + authenticated, `stats` encrypted; up to 4 bonds.
- [05 §5.13](../design/05-ble-contract.md) — writes larger than the characteristic maximum are `invalid`, not truncated.
- [05 §5.14](../design/05-ble-contract.md) — required `config` and `stats` host vectors, including stats at empty log and full ring.
- [03 §3.7](../design/03-firmware-architecture.md) — configuration ownership and NVS.
- [03 §3.13](../design/03-firmware-architecture.md) — host and firmware build commands.
- T15 `bridge_config` stats keys (`boot_count`, `last_reset_reason`, `packets_ok`, `packets_bad`), T19/T20/T24 and T31 for the log extent, clock, battery and sync snapshots.
- **Verify:** H/B · **Board:** no / B
- Depends on T27, T15, T19, T20, T24 and T31.

## Scope

### `config` (0007)
- [ ] Implement characteristic `7f9b0007-4c5b-4b0f-9a3d-1c2e3f405162` (`config`) as Read/Write, encrypted + authenticated, fixed 80 B, little-endian.
- [ ] Read returns the current values as one 80-byte struct; support Read Blob at the default MTU 23 (`MTU−1` bytes per response).
- [ ] Implement the exact payload layout:

  | Offset | Size | Field |
  |---:|---:|---|
  | 0 | 1 | `ver = 1` |
  | 1 | 1 | `units`: 0 °C, 1 °F (OLED display; stored samples are always °F) |
  | 2 | 2 | `display_timeout_s` u16; 0 = never |
  | 4 | 16 | `device_name` UTF-8, NUL-padded (≤15 chars) |
  | 20 | 2 | `billows_target_f10` i16 — reserved, ignored/unwritten in the MVP |
  | 22 | 1 | `billows_mode` — reserved, must be 0 in the MVP; 1 control is refused |
  | 23 | 57 | reserved (probe names/roles were removed from the MVP) |

- [ ] Support full-struct writes only; no partial write. Accept queued writes that assemble the whole 80 B.
- [ ] Validate before applying: `device_name` is valid UTF-8 and NUL-terminated within its 16-byte field; `display_timeout_s` is one of 30/60/120/0; `units` is 0 or 1; `billows_mode` is 0.
- [ ] Reject any nonzero `billows_mode` with `unsupported`; `caps.billows_control` is always 0.
- [ ] Ignore the reserved probe name/role bytes and the reserved `billows_target_f10` field; never expose a target editor or write a target.
- [ ] A malformed body changes nothing. Return `invalid` for bad UTF-8, bad units, bad timeout or wrong length.
- [ ] Persist accepted values to NVS.
- [ ] Apply runtime changes immediately: OLED units and display timeout take effect without a reboot.
- [ ] Add host tests for the round trip and every invalid case, including the `config` vectors in 05 §5.14: minimum and maximum device name, timeout, units, and reserved control-mode refusal.

### `stats` (0008)
- [ ] Implement characteristic `7f9b0008-4c5b-4b0f-9a3d-1c2e3f405162` (`stats`) as Read, encrypted, fixed 60 B, little-endian. There is no write path.
- [ ] Support Read Blob at the default MTU 23 (`MTU−1` bytes per response).
- [ ] Implement the exact 05 §5.10 layout:

  | Offset | Size | Field |
  |---:|---:|---|
  | 0 | 1 | `ver = 1` |
  | 1 | 1 | `flags` |
  | 2 | 4 | `uptime_s` |
  | 6 | 4 | `records_stored` |
  | 10 | 4 | `records_capacity` (338,400) |
  | 14 | 4 | `min_seq` (`0xFFFFFFFF` if empty) |
  | 18 | 4 | `max_seq` (`0xFFFFFFFF` if empty) |
  | 22 | 4 | `generation` |
  | 26 | 4 | `packets_ok` |
  | 30 | 4 | `packets_bad` |
  | 34 | 2 | `battery_mv` |
  | 36 | 1 | `battery_pct` (255 unknown) |
  | 37 | 1 | `lora_rssi` i8 |
  | 38 | 1 | `lora_snr` i8 |
  | 39 | 1 | reserved (0) |
  | 40 | 4 | `heap_free` |
  | 44 | 4 | `heap_min` |
  | 48 | 2 | `dropped_samples` u16 |
  | 50 | 2 | reserved (0) |
  | 52 | 4 | `oldest_unix_s` (0 if unknown) |
  | 56 | 4 | `newest_unix_s` (0 if unknown) |

- [ ] Fill `flags` from the live snapshot: bit 0 `smoke_paired`, bit 1 `smoke_live`, bit 2 `advertising`, bit 3 `connected`, bit 4 `clock_valid`, bit 5 `storage_ok`, bit 6 `billows_attached`; bit 7 `billows_control` is always 0.
- [ ] Fill `records_stored`, `min_seq`, `max_seq`, `generation`, `oldest_unix_s` and `newest_unix_s` from one sample-log extent snapshot; an empty log uses `0xFFFFFFFF` for min/max and 0 for the timestamps.
- [ ] Fill `packets_ok`/`packets_bad` from the protocol counters, battery from `board_battery_stats_get()`, LoRa RSSI/SNR from the last valid X4 packet, `heap_free`/`heap_min` from the ESP heap, and `dropped_samples` from the sample-pipe counter.
- [ ] A read returns a fresh snapshot; no caching across reads, no writes, reserved bytes zero.
- [ ] Add host tests for `stats` at empty log and full ring (05 §5.14): exact 60 B, flags bits, min/max sentinels, capacity, signed RSSI/SNR, unknown battery 255, 0 oldest/newest, and Read Blob at MTU 23.

### Bench
- [ ] Bench-verify with a real phone: change units and display timeout, then observe both on the OLED.
- [ ] Bench-verify `stats`: records/capacity/min/max/generation are non-zero and the app's History & storage Bridge copy stops showing `0 of 0` (T44 read is already wired).

## Out of scope
- `control` characteristic and device actions (forget/factory reset/power off/clear history/unpair) → T48.
- Link teardown, re-advertising and destructive-action state handling → T49.
- App Settings editors, read-modify-write UI and per-field save states → T51.
- `set_time` and the clock path → T29.
- Probe names and roles — removed from the MVP; outside MVP, no task owns it.
- Billows control or a target editor — M5 Billows (T56–T60); `caps.billows_control` is always 0.
- Wi-Fi/HTTP/OTA and a local web UI — outside MVP; no task owns it.

## Design notes
- The characteristic is 80 B so the packet size does not churn before M0. The former probe name/role bytes are reserved, not repurposed.
- Stored samples are always °F. `config.units` and `display_timeout_s` affect the OLED only.
- `billows_mode` is a reserved byte that must be 0. A control value is a named refusal (`unsupported`), not a silent clamp.
- The app owns read-modify-write; the device never merges a partial struct.
- `stats` is a read-only snapshot, encrypted but not authenticated. The app reads it after secure connect and before the quiet sync; a later re-read is how the app refreshes.
- Use one extent snapshot for `records_stored`/`min_seq`/`max_seq`/`generation`/oldest/newest; do not mix two reads.
- Status codes follow 05 §5.6: the status byte is the branch; `detail` is human-readable, ≤59 bytes, and not for machine branching.
- Never expose or accept a Billows target write path. There is no fan output and no Billows TX path in the MVP.
- Keep payload encoders pure functions; NimBLE callbacks stay thin (03 §3.14).
- The app's config editor lands in T51. Use a generic BLE client for the T47 phone/OLED check, or defer that check to T51/T55 and record the deferral; do not block the firmware/host landing.
- Design: [05 §5.9](../design/05-ble-contract.md), [05 §5.10](../design/05-ble-contract.md), [05 §5.2.1](../design/05-ble-contract.md), [03 §3.7](../design/03-firmware-architecture.md).

## Done when
- [ ] Config round-trip and every invalid case are host-tested, including min/max device name, all four timeout values, both units, bad UTF-8 and reserved control-mode refusal.
- [ ] `stats` is host-tested at empty log and full ring, including flags, min/max sentinels, capacity, signed RSSI/SNR, unknown battery and exact 60-byte length.
- [ ] `ctest --test-dir firmware/test/build` passes.
- [ ] A real phone changes units and display timeout and sees both on the OLED.
- [ ] A real phone reads non-zero `stats` records/capacity/min/max/generation; the app's Bridge storage copy is no longer `0 of 0`.
- [ ] `caps.billows_control` reads 0 and a nonzero `billows_mode` write returns `unsupported`.
- [ ] Hand-off below filled in.

## Hand-off

**Landed.** `config` (0007) is a full 80-byte Read/Write handled by pure
`ble_config.c`: exact-length parse, `ver = 1`, units 0/1, timeout 0/30/60/120,
1–15-byte UTF-8 NUL-terminated name, reserved target/bytes ignored, nonzero
`billows_mode` refused as `unsupported`. A write is validated before anything
changes, persisted in one `bridge_config_set_device()`, then applied at runtime:
the UI snapshot reads units from NVS and boot.c's config-applied handler calls
`ui_set_display_timeout()` + `ui_mark_dirty()`. `stats` (0008) is a fresh
60-byte read-only snapshot from one sample-log extent plus live bridge_state,
battery, heap and sample-pipe drop values; empty log uses `0xFFFFFFFF` min/max
and 0 times. Both reads return the whole payload and rely on NimBLE's
`MTU−1` Read Blob slicing.

**Deviation.** A GATT write has no result notification, so config refusals are
ATT application errors `0x80 | status`: `0x81` invalid, `0x82` unsupported,
`0x87` storage (recorded in ADR 0051 and 05 §5.9). The real-phone/OLED bench
checks are deferred to T51/T55, as this task's design note explicitly allows
once the firmware/host half is green.

**Checks.** `make host-test` → 23/23 CTest passed, including new `ble-config`,
`ble-stats` and the °C render assertion. (Add `C:\msys64\ucrt64\bin` to PATH on
this machine or cc1.exe fails to start.) No ESP-IDF build was run in this
session; the host gate is the task's objective trigger.

**Attempt 2.** No code changes were needed: the attempt-1 failure was only the
missing UCRT DLL path, not the implementation. The harness verify now runs
`tools/ci/verify_host.ps1`, which prepends `C:\msys64\ucrt64\bin` and
`C:\msys64\usr\bin`. Deleted `firmware/test/build`, ran the script from clean,
and `ctest` reported `100% tests passed out of 23` (exit 0), including
`ble-config` and `ble-stats`. Bench deferral to T51/T55 stands.

**Attempt 3.** Re-ran the objective trigger
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/ci/verify_host.ps1`
against the existing implementation: CTest reported `100% tests passed out of
23`, including `ble-config` and `ble-stats`, exit 0. No code or test changes
were needed; the only working-tree change is the harness's `docs/ROADMAP.md`
status line. Bench deferral to T51/T55 stands.

**Next.** T51 maps 0x81/0x82/0x87 to the Settings copy and adds the app editor;
T55 does the real-phone config/stats bench checks. T48/T49 still own the
destructive control actions and the clear-generation boundary.

