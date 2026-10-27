# T47 — ble_service: config read/write

## Goal
Implement the 80-byte `config` characteristic end to end, so a phone can read and replace the Bridge's units, screen timeout and name, with validation, NVS persistence and immediate runtime/OLED effect. This is the firmware half of every Settings field in M4.

## Context (read first)
- [05 §5.9](../design/05-ble-contract.md) — `0007 config`, fixed 80 B, Read/Write, encrypted + authenticated; the authoritative field layout and validation rules.
- [05 §5.2.1](../design/05-ble-contract.md) — `config` uses Read Blob (`MTU−1` per response); writes use queued writes.
- [05 §5.11](../design/05-ble-contract.md) — security: `config` is encrypted + authenticated; up to 4 bonds.
- [05 §5.13](../design/05-ble-contract.md) — writes larger than the characteristic maximum are `invalid`, not truncated.
- [05 §5.14](../design/05-ble-contract.md) — required `config` host vectors.
- [03 §3.7](../design/03-firmware-architecture.md) — configuration ownership and NVS.
- [03 §3.13](../design/03-firmware-architecture.md) — host and firmware build commands.
- **Verify:** H/B · **Board:** no / B
- Depends on T27 and T15.

## Scope
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
- [ ] Bench-verify with a real phone: change units and display timeout, then observe both on the OLED.

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
- Status codes follow 05 §5.6: the status byte is the branch; `detail` is human-readable, ≤59 bytes, and not for machine branching.
- Never expose or accept a Billows target write path. There is no fan output and no Billows TX path in the MVP.
- Keep payload encoders pure functions; NimBLE callbacks stay thin (03 §3.14).
- Design: [05 §5.9](../design/05-ble-contract.md), [05 §5.2.1](../design/05-ble-contract.md), [03 §3.7](../design/03-firmware-architecture.md).

## Done when
- [ ] Config round-trip and every invalid case are host-tested, including min/max device name, all four timeout values, both units, bad UTF-8 and reserved control-mode refusal.
- [ ] `ctest --test-dir firmware/test/build` passes.
- [ ] A real phone changes units and display timeout and sees both on the OLED.
- [ ] `caps.billows_control` reads 0 and a nonzero `billows_mode` write returns `unsupported`.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
