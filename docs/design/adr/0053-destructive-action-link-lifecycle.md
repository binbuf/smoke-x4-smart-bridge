# 0053 — Destructive actions answer first, then own the link state

**Status:** Accepted (T49, 2026-10-27)

## Context

T48 wired the five destructive `control` ops to reply-first backends: the result
is notified, then a ≈250 ms timer runs the effect. Three gaps remained. The app
can drop the link between the result and the timer (out of range, OS closes the
socket, user backgrounds the app), and the deferred action must still run.
Forget looked up the current connection when it ran, so a dropped link made it a
no-op and left the bond behind. Power off went straight to deep sleep without
stopping the advertising policy, and the boot outcome after a power cut during a
wipe was implicit.

## Decision

- Add the pure `ble_destructive.c` state machine. It tracks idle / answered /
  running / complete / reboot / sleep, the pending action, the link and the
  advertising flag. `ble_service.c` drives it from the result path, GAP
  connect/disconnect and the action timer; the host test drives the same code.
- Invariant: advertising is never true while the link is up, and a pending
  factory reset or power off never re-advertises. Forget, clear and unpair do
  re-advertise on a link drop because their effect needs no link.
- Forget captures `peer_id_addr` at write time. The deferred action removes that
  captured peer when the link is already gone; other bonds are untouched. The
  link is terminated only when it is still the same peer.
- `ble_service_prepare_sleep()` stops advertising, cancels the advertising
  timers and clears the passkey before deep sleep, without deinitialising
  NimBLE (it is called from the BLE action timer and must not delete itself).
- Boot recovery uses `clear_pending` as the durable marker. The factory-reset
  step table writes the new generation and `clear_pending` before erasing any
  config key or bond; `log_flash_open()` finishes the erase before the first
  append, and only then does `on_sync` start advertising. A power cut resolves
  to a fully cleared log on boot, never a half-wiped log that advertises.

## Consequences

- Every destructive path (result-then-disconnect, forget re-advertise, factory
  wipe-and-reboot, power-off sleep, normal disconnect, app drop mid-op and a
  power cut with `clear_pending`) is host-provable without a board.
- A late backend failure returns to discovery so the app can reconnect and
  retry; the already-sent `result ok` is not rewritten.
- The real destructive board walk stays deferred to T55 (bench-safety note):
  the T49 image is built and hashed only.
- Adding an action means extending the switch in `ble_destructive.c` so its
  radio outcome stays explicit.
