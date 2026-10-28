# 0052 — Control destructive actions: reply-first routing and a runtime clear

**Status:** Accepted (T48, 2026-10-27)

## Context

T29 built the `control` dispatcher and a reply-first seam: for ops 2/3/4/5/7 it
fills `result.action` + a ≈250 ms delay, and the NimBLE adapter arms a one-shot
timer after notifying `result`. T48 must actually run the five destructive
effects without letting NimBLE, NVS, flash or the board leak into the pure
dispatcher or its host tests.

Two effects need new seams. `clear_history` must physically erase the sample
ring at runtime (T19 only implemented the boot-time pending clear), and
`unpair_smoke_x` must call the pairing FSM from the BLE timer while the
`radio_rx` task can also be feeding it.

## Decision

- `ble_control_actions.{c,h}` is a pure router: one callback per action, each
  returning an `SX4_RESULT_STATUS_*` value (never a raw ESP-IDF/NimBLE error).
  A missing action/callback is `unsupported`. It is host-tested with fake
  backends; the dispatcher and router are linked together in that suite.
- `boot.c` owns the firmware backend because it already sees every component:
  - `forget_phone` → `ble_service_forget_current_peer()`: delete only the
    current connection's peer bond, then terminate the link. The existing
    disconnect path re-advertises; other bonds stay.
  - `factory_reset` → `bridge_config_factory_reset()` (config, generation,
    pending clear and all NimBLE bonds) **then** arm a 50 ms `esp_restart()`
    timer. A lost timer leaves a fully wiped, still-running device, never a
    half-wiped one.
  - `power_off` → Vext off, SX1262 sleep, `board_enter_deep_sleep()`.
  - `clear_history` → `sample_log_clear()`.
  - `unpair_smoke_x` → `sx_radio_unpair()`.
- `log_flash_clear()` is the runtime clear: `begin_clear` persists the new
  generation and `clear_pending`, every non-blank sector is erased,
  `finish_clear` drops the flag, and the ring restarts empty on the new
  generation. A failed begin leaves the old ring usable; a failed erase parks
  the log READ_ONLY and the next boot resumes the pending clear.
  `sample_log.c` serializes append/read/info/clear with one mutex.
- `sx_radio.c` serializes `radio_rx`'s FSM calls and `sx_radio_unpair()` with
  one mutex, so the BLE action cannot race the scan/state machine.
- Late backend failures are logged (`ble_control_run_action()` returns the
  status). They cannot rewrite the already-notified `result ok`; the app's
  disconnect/timeout path is the recovery.

## Consequences

- Ordering, `op_id` echo, idempotency, failure mapping and malformed bodies are
  host-proven per op without hardware.
- T49 owns the real link-state ordering (disconnect once, re-advertise,
  power-cut `clear_pending` outcomes), the BLE stop-before-sleep polish and the
  destructive board walk (deferred from T48 to T55).
- `clear_history` is synchronous and can take seconds on a full ring; it runs
  on the BLE action timer after the answer, so the app only sees the result.
- Adding another op means adding a router callback and a backend function; the
  wire envelope and status set do not change.
