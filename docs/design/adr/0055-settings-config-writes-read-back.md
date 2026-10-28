# 0055 — Settings config writes are whole-struct, read-back confirmed

**Status:** accepted
**Date:** 2026-10-27
**Task:** T51

## Context

The Bridge's `config` characteristic is a fixed 80-byte struct with no `result`
notification (05 §5.9). A write either completes at the ATT layer or is refused
with an application error (`0x81` invalid, `0x82` unsupported, `0x87` storage,
and the same `0x80 | status` shape for the other result statuses). Settings must
show honest per-field state: a successful GATT write alone is not proof that the
Bridge persisted the value, and a refusal must name why. Units also have a local
meaning ("all temperatures in the app") and must keep working offline, while the
Bridge screen updates only after a write.

## Decision

- The app has one `BridgeConfig` codec for the whole 80-byte struct. Every edit
  reads the current struct, changes exactly one field, and writes the whole
  struct back. A partial struct is never sent.
- After the write, the editor reads `config` back. Only a read-back that matches
  the intended field updates the display and marks the field `Saved`.
- Per-field state (`units`, `name`, `timeout`) is independent:
  `idle / saving / saved / error` with an error string derived from the refusal
  status. Writes are serialised so two quick taps cannot interleave
  read-modify-write.
- `BleException` keeps the raw ATT application code in `attCode`. The config
  controller maps it to `BridgeConfigStatus` (`invalid`, `unsupported`, `busy`,
  `unauthorized`, `failed`, `not_found`, `storage`) and branches only on that.
  The generic mapper recognises `0x81`, `0x82` and `0x87`; 133 stays the common
  Android GATT error because the firmware does not use `failed` on the wire.
- Units apply on the phone immediately. Offline the change is queued and written
  on the next healthy connect; the row says the Bridge screen updates on
  reconnect. A refusal keeps the local units but shows the named error, never
  `Saved`.
- Bridge name and timeout are not applied optimistically: the name changes in
  the row only after the read-back; the timeout option is selected only after the
  read-back. The name is an app-facing label; the Bluetooth name is unchanged.
- Appearance is the first persisted local preference. It lives in the archive
  database's `preference` table (schema v3) behind `AppPreferences`, so tests use
  an in-memory implementation and later local preferences can reuse the seam.
- There is one connection log. The former Billows-only filtered copy is removed;
  Billows events stay in the shared Bridge details timeline.

## Consequences

- A config edit costs one read, one write and one confirming read. That is small
  (80 bytes) and makes `Saved` truthful.
- A Bridge that accepts the write but returns a different value (for example a
  canonicalised name) shows the read-back value, not the draft.
- The review/demo path with no BLE client applies the field locally and marks it
  saved; production always has the BLE seam, so it cannot take that path.
- T53's units, change-window and theme persistence can build on
  `AppPreferences`; it must not add a second preference store.
