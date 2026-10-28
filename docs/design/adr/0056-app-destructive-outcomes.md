# 0056 — Destructive results are device outcomes, never write returns

**Status:** Accepted (T52, 2026-10-27)

## Context

T48/T49 made every destructive `control` op reply first and then own the link
state. The app still cleared local state as soon as the confirmation sheet was
accepted, so a refused or undelivered op looked successful. Forget also had to
stay usable offline, while factory reset and power off must not wait for a
result that a reboot or deep sleep can never deliver.

## Decision

- `BridgeLink.attemptControl()` returns a `BridgeControlAttempt` with `written`,
  the `result`, or the error. `sendControl()` is the thin compatibility wrapper.
  `written` is true only after the GATT write returned, which is what makes a
  following disconnect meaningful.
- `BridgeController` maps outcomes to `DestructiveOutcome`:
  - any non-`ok` result is `failed`;
  - forget, factory reset and power off treat the disconnect after a written
    request as `disconnected` (success);
  - a control timeout is `disconnected` only when the link is already gone;
    a timeout with the link still up is `timedOut`;
  - `clear_history` accepts only `ok`.
- Forget is local-first: the saved connection is cleared before the best-effort
  send, phone history is kept, and the OS bond is removed on `ok` or the
  disconnect, whichever arrives first. When neither is confirmed, Setup renders
  `Pairing not confirmed` and says the Bridge may still hold the pairing.
- Factory reset clears the saved connection and bond only after `ok` or the
  expected disconnect, keeps phone history, and returns to Setup with the
  orphaned-history entry. Power off marks `bridgeOff`, moves the link to offline
  and never presents the Bridge as reachable until a healthy phase clears it.
- The confirmation sheet closes before a non-dismissible `destructive.sending`
  dialog runs the action. No success copy exists until the future resolves.
  Failures stay on the current screen with one named line.

## Consequences

- A GATT write response can never produce success UI. The only success signals
  are a matching `result ok` or the contract's expected disconnect.
- Forget remains useful offline; every other op requires a live link through
  the existing disabled-row reasons.
- Widget tests use a scripted controller for the sending/success/failure and
  Setup branches; the real op bytes and disconnect mapping are covered against
  the scripted GATT bridge.
- The real-phone destructive walk (forget re-advertise, factory reboot, power
  off sleep, clear generation) stays with T55.
