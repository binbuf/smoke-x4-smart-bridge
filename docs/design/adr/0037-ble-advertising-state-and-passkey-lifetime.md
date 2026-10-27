# 0037 — Advertising state machine and passkey lifetime are pure C

## Status

Accepted

## Context

T30 has to prove the advertising wire format, the 250 ms → 1,000 ms interval
change and the passkey/bond-slot rules on the host, but NimBLE's GAP layer is
only linkable on the ESP32-S3. Putting those rules inside the GAP callback would
also make them race with the controller: `ble_gap_adv_start()` must not run
inside the callback, and restarting advertising after a disconnect has to be
deferred.

## Decision

Keep the policy in two plain-C11 modules under `firmware/components/ble_service`:

- `ble_adv.[ch]` owns the flags+UUID PDU, the name+manufacturer scan response,
  the 9-byte status blob, the 250/1,000 ms states and every start/stop/timeout
  transition. Its state machine returns an action (`advertise`, `interval_ms`)
  that the firmware applies.
- `ble_security.[ch]` owns the four-bond limit (no eviction) and the six-digit
  passkey lifetime (60 s, fresh code per attempt, cancel on bond end).

`ble_service.c` is the only NimBLE glue. It builds the AD bytes, arms esp_timer
one-shots for the fast-window and deferred restarts, and injects the generated
passkey with `ble_sm_inject_io()`. The OLED overlay is reached through a
`ble_service_set_passkey_callback()` seam so `ble_service` does not depend on
the `ui` component.

## Consequences

The host `ble-adv` suite pins the PDU, scan response and blob byte-for-byte and
walks every state transition without ESP-IDF. The board/phone behaviour still
has to be observed at T37, but a format or policy regression fails CI first.
The deferred start means advertising appears a few milliseconds after a
disconnect rather than in the same GAP callback; that is invisible to a scanner.
