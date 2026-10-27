# 0036 — Control dispatch is a pure core with a reply-first action seam

**Status:** Accepted (T29, 2026-10-27)

## Context

`control` is the only authenticated write path in the MVP. It must validate a
whole op body before touching state, echo the app's `op_id` on every answer, map
failures to the fixed status set, and for future destructive ops send the
`result` notification before the link drops or the device reboots. T29 only owns
`set_time`; T48 adds forget/factory-reset/power-off/clear-history/unpair.

NimBLE callbacks cannot be host-tested, and a destructive handler needs a delay
between the reply and the effect.

## Decision

- `ble_control.c` is a plain C11, allocation-free dispatcher. It parses
  `ver, op, op_id, body…`, validates the exact body size for every known op
  (`set_time` 10 B, `set_billows_target` 2 B, the rest 0 B), executes only
  `set_time`, and always fills a `ble_control_result_t`.
- `set_time` converts `unix_ms / 1000` and calls `bridge_state_set_time()`. The
  bridge keeps UTC; `tz_offset_min` is advisory. `ERR_TIME` / zero time map to
  `invalid` with "clock out of range" and change nothing.
- Unknown ops are `unsupported`; known destructive ops answer `unsupported`
  until T48, but their empty-body shape is already validated.
- `result` is encoded by `ble_control_encode_result()`: 5-byte header plus a
  detail truncated to 59 B (and never inside a UTF-8 sequence), 64 B maximum.
- The NimBLE write callback notifies the full result, split at `MTU-3`. The
  `result` slot tracks its own CCCD subscription.
- Destructive ops get `result.action` + `action_delay_ms`; the adapter arms a
  one-shot `esp_timer` **after** sending the result and then calls the handler
  registered with `ble_control_set_action_handler()`. T48 fills that seam.
- Write security is a pure function returning the contract's ATT values
  (`0x0F` unencrypted, `0x05` encrypted-but-unauthenticated); `ble_service.c`
  static-asserts they equal NimBLE's constants.

## Consequences

- The dispatcher, every status code, body-length rules and truncation are
  host-tested without NimBLE or a board.
- T48 must set `action`/`action_delay_ms` and register a handler; it must not
  send a second result or act inside the write callback.
- Adding an op means adding its exact body length here; trailing bytes stay
  invalid for the V0 ops.
- The app must subscribe to `result` before writing `control`; an unsubscribed
  result is dropped, matching the 3 s app timeout.
