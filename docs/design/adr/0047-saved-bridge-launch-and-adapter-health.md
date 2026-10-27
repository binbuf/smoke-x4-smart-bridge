# 0047 — Saved Bridge launch, persistent last-known values and adapter health

- **Status:** accepted
- **Date:** 2026-10-27
- **Task:** T43

## Context

T35/T36 made the live link honest after a connection exists, but every launch
still started in Setup because the identity lived only in controller memory. The
archive (T40/T41) now stores samples and durable cursors, and the approved Live
state is gated by `LiveViewState.showSavedReadings` (ADR 0041). Three gaps
remained:

- a returning user was asked to set up the same Bridge again;
- an offline state kept only the current process's `live` values, so a kill lost
  the last-known readings;
- turning phone Bluetooth off could leave the UI on `Bridge Connected` because a
  GATT disconnect is not guaranteed, and the launch path had no runtime adapter
  signal.

## Decision

- The `bridge` row is the single saved-identity store. `bridge.id` is the BLE
  address used for scan matching, `bridge.name` the last advertised name and
  `last_seen_ms` the ordering key. `BridgeLink` now keys the archive by the BLE
  address (`_device.id`), not `info.device_id`; the advertised name is the scan
  fallback. `Android` MAC addresses are stable enough for one saved Bridge.
- `BridgeController.prepareLaunch()` runs before the first frame. It loads
  `SampleDao.savedBridge()` and the newest archived sample. With a row, the
  controller enters Live (`offline`, `lookingForBridge = true`), sets the
  last-known probe values and ages them from `recorded_ms`; without a row it
  calls `beginSetup()`. The last-known values are never promoted to live: the
  phase stays offline, the probe health is frozen and the surface stays dimmed.
- `connectSavedBridge()` runs a bounded, foreground-only scan (10 s in
  production) and matches by BLE identity then name through
  `selectPreferredBridge`. It never connects to an unrelated first result. On a
  match it reuses the existing `BridgeLink.connectAndSecure` procedure, so a
  valid stored bond produces no passkey prompt. A missing Bridge leaves the
  shell on Live with `Looking for the Bridge…` and a manual `Connect`.
- A stale bond on launch uses the existing one-shot bond failure, which maps to
  the named `Can’t reach the Bridge` surface with Retry/Forget (the setup flow
  remains the owner of `Forget and re-pair`); launch never raises a silent OS
  prompt.
- `BleClient.platformStates` is a new named-event stream (`ready`,
  `bluetoothOff`, `permissionBlocked`, …). The production client maps
  `FlutterBluePlus.adapterState`; the fake can toggle the adapter. `BridgeLink`
  and the controller both observe it: a blocked adapter clears `_secure`, the
  watchdog/periodic sync and the subscriptions, enters `ConnectionPhase.blocked`
  and reports the named `BlockReason`; `ready` resumes the bounded reconnect
  budget. This is the runtime fix for the T37 stale `Bridge Connected` case.
- `forgetPhone()` and `factoryReset()` delete the saved `bridge` row (by saved
  and remembered ids) and keep `sample`/`gap` as orphaned `History on this
  phone`.

## Consequences

- A cold launch with a saved Bridge reaches Live without Setup and without a
  passkey prompt; an absent Bridge stays on Live with the archive and Connect.
- Offline values survive a process kill because they come from SQLite, and the
  no-cache state still renders no probe values.
- The archive identity changes from `info.device_id` to the BLE address; this is
  a pre-release migration only. Existing rows keyed by the protocol id remain
  readable but are not the saved identity.
- Tests are in `app/test/launch_connect_test.dart` (first install, saved present,
  unrelated result, absent, blocked at launch, kill/relaunch from a file,
  forget/reset, runtime adapter off/on); `flutter test` and `flutter analyze`
  are the acceptance gate.
- T46 proves the same path on a real phone. T50/T51 own the final placement of
  Connect/Forget and the system-settings action.
