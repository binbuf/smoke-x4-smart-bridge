# 0039 - One platform BLE client behind named states

**Status:** Accepted (T32, 2026-10-27)

## Context

T07 defined the `BleClient` seam and a scripted fake. T32 must put a real
`flutter_blue_plus` transport behind that seam, map Android permissions,
adapter and GATT failures to the named states in 06 §6.8, and keep every plugin
type and exception out of screens and controllers. The plugin's 2.x line adds a
commercial licence gate; the MVP is a for-profit product, so the dependency must
stay on the last BSD-3 release. Android 12+ also forbids using location for BLE
scanning, while Android 11 and below require it.

## Decision

- Pin `flutter_blue_plus: 1.35.12` (BSD-3) and `permission_handler: 11.4.0`.
  Upgrading to 2.x is a licensing decision, not a code change; it requires an
  explicit ADR.
- `data/ble/flutter_blue_plus_ble_client.dart` is the only file that imports
  `flutter_blue_plus` or `permission_handler`. `ble_error_mapper.dart` turns
  plugin, `TimeoutException` and `PlatformException` failures into
  `BleException(BleFailure)`, which exposes `appState` and `recoveryAction`.
  Screens render the named `BleAppState` and approved copy, never the message.
- `BleClient` adds `platformStatus()`, `requestPermissions()`, `removeBond()`
  and `diagnostics`. `FakeBleClient` implements the same interface and accepts
  scripted permission, adapter, support and per-operation faults.
- `BlePlatformStatus` selects unsupported phone, Bluetooth off, permission
  needed or permission blocked before any scan or connect. Android 12+ requests
  `BLUETOOTH_SCAN` (`neverForLocation` in the manifest) and `BLUETOOTH_CONNECT`;
  Android 11 and below requests location. Permanently denied is only knowable
  after a request on Android, so status reports denied and the request result
  reports blocked.
- Scan filters on the contract service UUID
  `7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162` and stops after 10 s.
  `selectPreferredBridge` matches the remembered device ID first, then name,
  and returns `null` rather than an arbitrary first result. A legacy `7f9a…`
  service is never compatible.
- Connect leaves MTU negotiation to `requestMtu(247)` so T35 owns the procedure
  order, but `read` detects an MTU-boundary value, negotiates 247 and re-reads
  once. The plugin exposes no Read Blob offset, so this is the long-read
  fallback for the 32-byte `info` characteristic at MTU 23.
- `BleDiagnostics` keeps a bounded log of scan/connect/bond failures plus phone
  model, Android version and the negotiated MTU. The phone model comes from a
  small `smoke_bridge/device_info` method channel in `MainActivity`; a missing
  channel falls back to the Dart platform version.
- Scanning is foreground-only. There is no background scan, foreground service
  or battery exemption.

## Consequences

- Unit tests inject `FlutterBluePlusException` / `PlatformException` objects and
  fake faults to prove every `BleFailure`, `BleAppState` and recovery action.
- No controller or screen imports a plugin; a release import check can enforce
  this later.
- The MTU 23 `info` read depends on renegotiating 247. If the controller caps
  below 247, the read falls back to whatever the platform returns and the
  protocol decoder reports a short payload; the link is then treated as a slow
  or failed link, not a parse gamble.
- T33 owns the primer/copy/buttons for `BleAppState`; T35 owns the fixed
  procedure order and reconnect loop.
