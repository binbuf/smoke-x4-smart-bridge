---
verify: powershell -NoProfile -ExecutionPolicy Bypass -File tools/ci/verify_host.ps1
---
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
- [x] Implement the `control` payload `ver u8, op u8, op_id u8, body…`, ≤16 B, on the encrypted + authenticated characteristic.
- [x] Echo `op_id` in every `result`; the app must not reuse an outstanding `op_id` (05 §5.5).
- [x] Implement `forget_phone` (op 2): remove only the current peer's bond, then disconnect and re-advertise; other bonds stay.
- [x] Implement `factory_reset` (op 3): wipe config, the sample log and all bonds before rebooting.
- [x] Implement `power_off` (op 4): enter deep sleep.
- [x] Implement `clear_history` (op 5): erase the sample ring, write a new random generation, and keep pairing and config.
- [x] Implement `unpair_smoke_x` (op 7): clear the stored Smoke X4 device ID/frequency, keep the log, config and phone bonds, and restart the 915/920 scan. The app then tells the user to put the Smoke X4 in SYNC.
- [x] Keep `set_billows_target` (op 6) reserved and always return `unsupported`; there is no Billows control path in the MVP.
- [x] Answer first, then act: send `result ok`, then perform the destructive action on a short timer (≈250 ms) so the notification can leave before the link drops or the device reboots.
- [x] For `factory_reset`, wipe before scheduling the reboot so a lost timer cannot leave a half-wiped device.
- [x] Validate the whole body before acting; a malformed body changes nothing and returns `invalid`.
- [x] Return `unsupported` for an unknown op; return the status codes from 05 §5.6 (`invalid`, `unsupported`, `busy`, `unauthorized`, `failed`, `not_found`, `storage`) rather than raw errors.
- [x] Add host tests for each op covering ordering, idempotency and failure, plus malformed bodies, wrong length, unknown op and `set_billows_target` always `unsupported`.
- [x] Destructive board paths deferred to T55 per the bench-safety note (do not run forget/factory reset/power off on the shared bench board here).

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
- **Bench safety for this slice:** the app control client and destructive confirmations are T52. Do not run `factory_reset`, `forget_phone` or `power_off` against the shared bench board in this task; implement and host-test the handlers, run the firmware build, and defer the destructive board evidence to T55 with an NVS/samples backup and a re-pair plan. `clear_history` generation evidence is T49/T52/T55.
- The T47 config/stats image is not necessarily flashed on the bench board. Build the T48 image and record the hash; flashing and the destructive walk belong to T55.

## Done when
- [x] Each op is host-tested for ordering, idempotency and failure, including malformed bodies, wrong length, unknown op and op_id echo.
- [x] `set_billows_target` is host-tested to always return `unsupported`.
- [x] `ctest --test-dir firmware/test/build` passes.
- [x] Destructive board paths are **deferred to T55** per the bench-safety note; this task proves answer-first ordering, idempotency and failure in host tests and builds the T48 image with its hash recorded.
- [x] Hand-off below filled in.

## Hand-off

### What landed

- `ble_control.c/.h`: the dispatcher now rejects writes longer than 16 B with
  `invalid` ("control too long"), and the deferred action runner returns the
  backend status. Op parsing, body validation, `op_id` echo, unknown-op and
  `set_billows_target` behaviour are unchanged from T29.
- `ble_control_actions.c/.h`: pure routing from `result.action` to one backend
  callback per op. Missing backend/callback/action → `unsupported`. Backends
  return `SX4_RESULT_STATUS_*`, never raw errors.
- `boot.c`: registers the T48 backend before `ble_service_start()`:
  - forget → `ble_service_forget_current_peer()` (current peer bond only, then
    terminate; the existing disconnect path re-advertises);
  - factory reset → `bridge_config_factory_reset()` (config, generation +
    pending clear, all bonds) **then** a 50 ms `esp_restart()` timer; if the
    timer cannot be created it reboots immediately, still after the wipe;
  - power off → Vext off, SX1262 sleep, deep sleep;
  - clear history → `sample_log_clear()` then UI dirty;
  - unpair X4 → `sx_radio_unpair()` then UI dirty.
- `log_flash_clear()` / `sample_log_clear()`: runtime clear persists a new
  generation + `clear_pending`, erases non-blank sample sectors, clears the
  flag and restarts the ring empty. `sample_log.c` now serializes
  append/read/info/clear with one mutex.
- `sx_radio_unpair()` + a pairing mutex: the BLE action and `radio_rx` no longer
  race the FSM; unpair clears pairing, returns to UNPAIRED and restarts the
  915/920 scan.
- `ble_service.c` logs a late action failure (the result has already left).
- Tests: `firmware/test/test_ble_control_actions.c` (`ble-control-actions`) and
  new clear cases in `test_sample_log_flash.c`; `test_ble_control.c` updated for
  the status-returning seam.
- Docs: 05 §5.6 implementation rules, 03 §3.9, ADR 0052.

### Checks run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ci/verify_host.ps1
# 24/24 CTest passed, exit 0 (new: ble-control-actions; sample-log-flash grew
# runtime-clear success, begin-failure and erase-failure/resume cases)

. D:\esp\esp-idf\export.ps1
cd firmware
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete; image guard ok
# sx4_bridge.bin 0x93170 bytes (602,480 B)
# SHA-256 747349B08BAC5A3AAEC376FF26F5B9035AF07D3039F804A87B33EE25C08C2F1D
```

### Deviations / deferred work

- Destructive board paths were **not** run: the task's bench-safety note defers
  forget/factory-reset/power-off (and clear generation evidence) to T55. The
  T48 image above is built and hashed; it was not flashed here.
- T49 still owns the formal post-action link state machine: stop-before-sleep
  ordering, disconnect-once/re-advertise assertions, and the power-cut
  `clear_pending` state test. T48 leaves the existing disconnect handler to
  re-advertise after forget.
- `clear_history` runs synchronously on the action timer; a full ring can take
  seconds. The app only sees the earlier `ok`.

### Next task must know

- The registered handler covers ops 2/3/4/5/7. Do not act inside the GATT write
  callback; `result` must leave first.
- Factory reset is wipe-then-schedule; never move the wipe after the reboot
  timer.
- `log_flash_hooks_t` now requires `begin_clear`; any new hook table must fill
  it or `log_flash_open()` returns `LOG_FLASH_ERR_ARGUMENT`.
- `sample_log_get_info()` now takes the same mutex as append/read/clear; do not
  call it from inside a sample-log callback.
