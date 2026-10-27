# ADR 0040 — Setup is a pure state machine over the BLE client seam

- **Status:** accepted
- **Date:** 2026-10-27

## Context

T32 landed the platform BLE client and named failures, but `SetupScreen` still
advanced through hard-coded states with a timer and a fixed device list. The
product setup route also was not mounted: the app always booted into Live with
prototype values. T33 must make every 13 §13.4 setup state real, testable without
a radio, and safe around the OS bond.

## Decision

1. `features/setup/setup_flow.dart` owns the setup state machine
   (`SetupStep`), scan results, `info` checks and bond outcomes. It talks only to
   `BridgeController.bleClient`; the screen renders approved copy and never
   imports a radio plugin.
2. `Find bridge` only checks `platformStatus()`. `requestPermissions()` is called
   after the primer's `Continue`/`Grant permission`, never from the first tap.
3. Scan rows decode the advertisement for the `P4 225°F · 87%` preview and use
   the scan-specific `Strong` / `Good` / `Weak` words. A `SmokeX4-` name without
   the current contract service is a protocol-mismatch row, not a selectable
   bridge.
4. Selecting a compatible row connects, reads open `info`, and stops before the
   OS bond when `proto_major` is unknown or `bonds_free == 0`. Only the passkey
   screen's `Pair` calls `bond()`; the app never supplies a real passkey.
5. `data/ble/bridge_codecs.dart` decodes only the `info` and `adv_status` fields
   setup needs. Its offsets are pinned to `protocol/gen/records.dart` by
   `test/setup_codec_test.dart`; the full packaged codec remains later work.
6. `SmokeBridgeApp` mounts `SetupScreen` while `phase == setup` (or no saved
   Bridge) and the approved Live shell afterwards. `bootstrap()` starts in setup
   until Bridge identity persistence lands, so a fresh install never shows
   simulated Live data.

## Consequences

- Every setup state is widget-testable with `FakeBleClient`; the lab keeps a
  frozen flow for review and screenshots.
- T35 can replace the short `_afterBond` progress shim with the real time/sync
  procedures without touching the copy or the state names.
- `open Bluetooth settings` / `open app settings` currently show a neutral
  Android-settings instruction because the seam has no intent call. A real
  intent belongs with the platform work; the button never claims the settings
  screen opened.
- Remembered bridge identity is held on the controller for the session; T35/T50
  still own durable persistence and automatic reconnect.
