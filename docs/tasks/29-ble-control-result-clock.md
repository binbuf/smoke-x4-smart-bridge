# T29 — ble_service: control, result, and the clock

## Goal
The bridge accepts authenticated control writes, executes `set_time`, and answers every op with an `op_id`-matched `result` using the defined status codes. This gives the app a reliable request/response path and a correct clock for stored samples.

## Context (read first)
- [05 §5.5, §5.6](../design/05-ble-contract.md) — `control` body, op table, result frame, status mapping, and destructive-op ordering.
- [05 §5.13](../design/05-ble-contract.md) — versioning and error rules.
- [04 §4.4](../design/04-data-and-storage.md) — clock handling: no RTC, estimated time before the app sets it.
- Design: [05](../design/05-ble-contract.md).
- Verify tier: **H/B**. Board: **no / B**.
- Depends on T27 and T20.

## Scope
- [ ] Implement the `control` write dispatcher: parse `ver u8, op u8, op_id u8, body…`, validate the entire body before acting, and echo the same `op_id`.
- [ ] Implement `set_time` (`op = 1`) with `unix_ms u64, tz_offset_min i16`; update the bridge clock through `bridge_state` and mark it valid.
- [ ] Implement the `result` notification encoder: `ver, op, op_id, status, len, detail[len]`, maximum 64 B, `detail` UTF-8 up to 59 B.
- [ ] Map every status code: `0 ok`, `1 invalid`, `2 unsupported`, `3 busy`, `4 unauthorized`, `5 failed`, `6 not_found`, `7 storage`. `detail` is human text, not the branch.
- [ ] Reject unknown ops as `unsupported` and malformed bodies/wrong lengths as `invalid`; a wrong length changes nothing.
- [ ] Answer before acting for later destructive ops on a short timer (≈250 ms) so the result can leave before the link drops or the device reboots. Destructive handlers themselves are T48.
- [ ] Enforce the write security level: encrypted + authenticated; an unencrypted write gets `ATT 0x0F Insufficient Encryption`, an encrypted-but-unauthenticated write gets `ATT 0x05 Insufficient Authentication`.
- [ ] Add host tests for `set_time`, every status value, unknown op, malformed body, wrong length, and `result` detail truncation.

## Out of scope
- `forget_phone`, `factory_reset`, `power_off`, `clear_history`, and `unpair_smoke_x` actions → T48 (M4).
- `set_billows_target` — reserved and always `unsupported`; Billows control is outside MVP and no task owns a control path (observation is T56, T57, T59).
- `config`/`stats` writes and reads → T47/T51 (M4).
- The app-side op queue, `op_id` matching, and 3 s timeout → T35.
- `info` encoding and service registration → T27; link security → T30.
- Wi-Fi/HTTP/OTA or any network command path — outside MVP; no task owns it.

## Design notes
- The app chooses `op_id` (0–255, wrapping) and must not reuse an outstanding one; the bridge echoes it unchanged and never invents one.
- `result` is `ver` @0, `op` @1, `op_id` @2, `status` @3, `len` @4, then `detail[len]`; the total is at most 64 B. Notifications may split at `MTU−3`; the first 5 bytes carry `len` so the client knows the total.
- Destructive ops answer first, then act. `factory_reset` must wipe before scheduling the reboot so a lost timer cannot leave a half-wiped device.
- `set_time` must not adjust earlier records; a clock correction changes future records only. `seq` keeps ordering unambiguous.
- No raw implementation detail belongs in `detail` strings — they are human hints such as "clock out of range" or "bond store full".
- 05 §5.5 op table (the V0 dispatcher must at least understand the shape; only `set_time` is live in this task):

| `op` | Name | Body | V0 |
|---:|---|---|---|
| 1 | `set_time` | `unix_ms u64, tz_offset_min i16` | implemented here |
| 2 | `forget_phone` | — | T48 |
| 3 | `factory_reset` | — | T48 |
| 4 | `power_off` | — | T48 |
| 5 | `clear_history` | — | T48 |
| 6 | `set_billows_target` | `target_f10 i16` | always `unsupported` in MVP |
| 7 | `unpair_smoke_x` | — | T48 |

## Done when
- [ ] `set_time` round-trips: a valid write produces a `result` with the same `op_id`, `op = 1`, `status = ok`, and the bridge clock/`clock_valid` updates.
- [ ] A wrong-length or malformed `set_time` returns `invalid` and changes nothing.
- [ ] A host test covers every status 0–7 and `result` truncation.
- [ ] An unknown op returns `unsupported`; a write on an insufficiently secured link returns the named ATT error.
- [ ] Hand-off below filled in

## Hand-off

Implemented in this session (T29 done).

**Changes**
- `firmware/components/ble_service/include/ble_control.h` + `ble_control.c`:
  pure-C `control` dispatcher (envelope parse, exact body validation, `set_time`
  through `bridge_state_set_time()`, op_id echo, status/detail mapping) and the
  `result` encoder (5..64 B, 59 B UTF-8-safe detail cap), plus the named ATT
  security helper and the reply-first action seam.
- `firmware/components/ble_service/ble_service.c`: wired the `control` write
  path to the dispatcher, sends `result` split at `MTU−3`, tracks the result
  CCCD subscription, uses `ble_control_write_security()` for authenticated
  slots, and arms a 250 ms one-shot timer only after the reply (unused until
  T48).
- `firmware/components/ble_service/CMakeLists.txt` adds `ble_control.c`.
- `firmware/test/test_ble_control.c` + `firmware/test/CMakeLists.txt` add the
  `ble-control` host suite.
- Docs: `docs/design/05-ble-contract.md` §5.6 implementation rules,
  `docs/design/adr/0036-control-dispatch-pure-core-reply-first.md`,
  `docs/progress/T29.md`.

**Deviations**
- Ops 2/3/4/5/7 validate their empty-body shape but return `unsupported` until
  T48 installs the handlers; returning `ok` with no effect would be wrong.
- V0 `set_time` requires the exact 13-byte frame (trailing bytes invalid),
  stricter than the forward-compatible trailing-byte rule in §5.13.
- Backward `set_time` is `invalid` ("clock out of range"), per the T20 note.

**Check results**
- Host: `ctest --test-dir firmware/test/build --output-on-failure` →
  100% passed, 19/19; new `ble-control` suite covers set_time, wrong length,
  malformed body, every status 0–7, truncation, unknown op and ATT errors.
- Firmware: ESP-IDF 6.0.2 Heltec build complete; image guard ok; `sx4_bridge.bin`
  0x8edb0 bytes, 0x171250 (72%) free.
- No board/phone run in this session (T29 verify tier H/B, board: no).

**Remaining work / blockers**
- None for T29. T48 must register `ble_control_set_action_handler()` and set
  `result.action`; T30 keeps `WRITE_AUTHEN` and the encrypted result CCCD; T37
  repeats the phone round trip and the 0x0F/0x05 rejection.

