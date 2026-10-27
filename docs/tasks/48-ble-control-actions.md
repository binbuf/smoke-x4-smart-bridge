# T48 — ble_service: control actions

## Goal
Implement the `control` characteristic actions so the phone can forget its bond, factory-reset the Bridge, power it off, clear the sample log, and re-pair the Smoke X4. Each action answers before it acts, so destructive outcomes are predictable on the real bridge.

## Context (read first)
- [05 §5.5](../design/05-ble-contract.md) — `0003 control`, ops, bodies, security, ordering and op rules.
- [05 §5.6](../design/05-ble-contract.md) — `result` payload and status mapping.
- [05 §5.11](../design/05-ble-contract.md) — `control` is encrypted + authenticated; bond ownership.
- [05 §5.12](../design/05-ble-contract.md) — re-pair the Smoke X4 and destructive-action consequences.
- [05 §5.14](../design/05-ble-contract.md) — required control vectors.
- [03 §3.9](../design/03-firmware-architecture.md) — BLE service responsibilities.
- [03 §3.13](../design/03-firmware-architecture.md) — host and firmware build commands.
- **Verify:** H/B · **Board:** no / B
- Depends on T29, T30 and T19.

## Scope
- [ ] Implement the `control` payload `ver u8, op u8, op_id u8, body…`, ≤16 B, on the encrypted + authenticated characteristic.
- [ ] Echo `op_id` in every `result`; the app must not reuse an outstanding `op_id` (05 §5.5).
- [ ] Implement `forget_phone` (op 2): remove only the current peer's bond, then disconnect and re-advertise; other bonds stay.
- [ ] Implement `factory_reset` (op 3): wipe config, the sample log and all bonds before rebooting.
- [ ] Implement `power_off` (op 4): enter deep sleep.
- [ ] Implement `clear_history` (op 5): erase the sample ring, write a new random generation, and keep pairing and config.
- [ ] Implement `unpair_smoke_x` (op 7): clear the stored Smoke X4 device ID/frequency, keep the log, config and phone bonds, and restart the 915/920 scan. The app then tells the user to put the Smoke X4 in SYNC.
- [ ] Keep `set_billows_target` (op 6) reserved and always return `unsupported`; there is no Billows control path in the MVP.
- [ ] Answer first, then act: send `result ok`, then perform the destructive action on a short timer (≈250 ms) so the notification can leave before the link drops or the device reboots.
- [ ] For `factory_reset`, wipe before scheduling the reboot so a lost timer cannot leave a half-wiped device.
- [ ] Validate the whole body before acting; a malformed body changes nothing and returns `invalid`.
- [ ] Return `unsupported` for an unknown op; return the status codes from 05 §5.6 (`invalid`, `unsupported`, `busy`, `unauthorized`, `failed`, `not_found`, `storage`) rather than raw errors.
- [ ] Add host tests for each op covering ordering, idempotency and failure, plus malformed bodies, wrong length, unknown op and `set_billows_target` always `unsupported`.
- [ ] Run the destructive paths on the board: forget, factory reset and power off.

## Out of scope
- Post-action link teardown, re-advertising state machine and power-cut recovery → T49.
- `config` read/write and validation → T47.
- `set_time` (op 1) and the clock path → T29.
- App confirmation sheets, destructive copy and Setup return → T52.
- Billows control, mode or target editing → M5 Billows (T56–T60); `caps.billows_control` is always 0.
- On-device factory reset gesture or boot-time button menu — outside MVP; no task owns it.
- Notifications — outside MVP; no task owns it.

## Design notes
- Op table and bodies (05 §5.5):

  | `op` | Name | Body | Meaning |
  |---:|---|---|---|
  | 1 | `set_time` | `unix_ms u64, tz_offset_min i16` | Owned by T29, not this task |
  | 2 | `forget_phone` | — | Remove the current phone's bond, disconnect, re-advertise; other bonds remain |
  | 3 | `factory_reset` | — | Wipe config, bonds, history; reboot |
  | 4 | `power_off` | — | Enter deep sleep |
  | 5 | `clear_history` | — | Erase the sample ring; keep config/pairing; new generation |
  | 6 | `set_billows_target` | `target_f10 i16` | **Reserved.** Always `unsupported` in the MVP; the app never sends it |
  | 7 | `unpair_smoke_x` | — | Forget the Smoke X4 pairing, keep log/config/bonds, restart the 915/920 scan |

- Security: a write on an unencrypted link gets `ATT 0x0F Insufficient Encryption`; an encrypted-but-unauthenticated write gets `ATT 0x05 Insufficient Authentication`. The app treats both as "bond/authenticate first", not "retry forever".
- Answer-first ordering is a contract requirement, not an optimisation. The ≈250 ms delay exists only so the `result` can leave.
- `factory_reset` ordering is wipe-then-schedule-reboot. It must not depend on the timer firing.
- `clear_history` changes the generation boundary; it does not clear pairing or config, and it does not touch phone history.
- `unpair_smoke_x` is the only path to follow a Smoke X4 re-synced to a new channel; a factory reset is not required and the log is preserved.
- `forget_phone` is current-peer only. Factory reset clears every bond. There is no eviction; up to 4 phones.
- `set_billows_target` stays on the wire so a future control build can add it without a wire break, but this build has no fan output and no Billows TX path.
- Design: [05 §5.5](../design/05-ble-contract.md), [05 §5.6](../design/05-ble-contract.md), [05 §5.12](../design/05-ble-contract.md), [03 §3.9](../design/03-firmware-architecture.md).

## Done when
- [ ] Each op is host-tested for ordering, idempotency and failure, including malformed bodies, wrong length, unknown op and op_id echo.
- [ ] `set_billows_target` is host-tested to always return `unsupported`.
- [ ] `ctest --test-dir firmware/test/build` passes.
- [ ] The destructive paths (forget, factory reset, power off) run on the board with `result ok` observed before the link drops or the device sleeps.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
