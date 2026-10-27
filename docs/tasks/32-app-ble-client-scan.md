# T32 — app: BLE client and scan

## Goal
The app has a real `BleClient` on `flutter_blue_plus` that handles permissions, scanning by service UUID, connect/disconnect, bonding, MTU, read/write/subscribe, and maps every platform failure to a named app state. It replaces the fake's transport while keeping the same seam, so the rest of the app never touches a plugin exception.

## Context (read first)
- [06 §6.3, §6.9](../design/06-app.md) — connection lifecycle, Android permissions, bonding, MTU, and manufacturer quirks.
- [05 §5.1, §5.2.1](../design/05-ble-contract.md) — service UUID and MTU/reassembly constraints the client must honour.
- [13 §13.3](../design/13-ui-implementation-contract.md#133-production-ownership) — production ownership of the BLE/data layer.
- Design: [06](../design/06-app.md).
- Verify tier: **H**. Board: **no**.
- Depends on T07 (BLE fake and app test seam) and T30.

## Scope
- [ ] Define the `BleClient` interface used by the app: permission/Bluetooth-state query, scan start/stop, connect/disconnect, bond/removeBond, MTU request, read, write, subscribe/unsubscribe.
- [ ] Implement the real client on `flutter_blue_plus`.
- [ ] Keep `FakeBleClient` implementing the same interface; no screen or controller imports the plugin directly.
- [ ] Map permission states: not determined, granted, denied, permanently denied/blocked; surface Android 12+ `BLUETOOTH_SCAN` (with `neverForLocation`) and `BLUETOOTH_CONNECT`, and location on Android 11 and below.
- [ ] Detect Bluetooth off and unsupported phones, returning a named state rather than a raw plugin error.
- [ ] Scan by the service UUID `7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162`; stop after 10 s; prefer the remembered bridge by device ID, then by name; do not auto-connect to an arbitrary first result.
- [ ] Connect/disconnect GATT, call `bond()`/`removeBond()`, and request MTU **247** while recording the negotiated value.
- [ ] Implement read (including Read Blob for `info`), write, and subscribe/unsubscribe, including CCCD writes at the characteristic's security level.
- [ ] Define typed exceptions for every platform failure and map each to the named app states in 06 §6.8; no raw exception, stack trace, or platform error string reaches the UI.
- [ ] Keep a debug log of scan/connect/bond failures plus phone model, Android version, and negotiated MTU.
- [ ] Add unit tests for every exception mapping using the fake/plugin fault injection.

## Out of scope
- Setup screens, copy, and passkey flow → T33.
- Link procedure order (info → MTU → bond → subscribe → live → set_time → sync) and the control/result queue → T35.
- Live screen rendering → T34.
- History/sync engine and local database → T36/T40/T41.
- The firmware GATT server, security, and advertising → T27–T31.
- iOS, web, or desktop support — outside MVP; no task owns it.
- Wi-Fi/HTTP/OTA or a cloud transport — outside MVP; no task owns it.

## Design notes
- BLE stack: `flutter_blue_plus`, behind a narrow seam (06 §6.2). `data/ble/ble_client.dart` owns scan/connect/bond/MTU/read/write/subscribe; `codecs.dart` owns payload bytes; `bridge_link.dart` owns GATT procedures.
- Service UUID is the new `7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162` — not the legacy `7f9a…` contract. A legacy device must not be treated as compatible.
- Requested MTU is 247, but every fixed payload works at MTU 23. Record the negotiated value for diagnostics; if it is below 64, sync still works but is slow and the UI later shows the slow-link note.
- Android: do not request location on 12+; explain location for 11 and below. Bonding is owned by the OS dialog; the app may call `bond()` but cannot type the code.
- Named states to map to (from 06 §6.8 / 13 §13.4): Bluetooth off, permission needed, permission blocked, unsupported phone, no results, pairing failed/wrong code, prompt timeout, stale bond, phone list full, connection failed, GATT error, timeout. Use the approved copy; the client returns state/enum values, not user strings.
- A remembered bridge is preferred by device ID, then by name. Do not auto-connect to an arbitrary first scan result.
- The fake remains the test seam: `FakeBleClient` drives the whole connect → pair → subscribe → sync → live path with no radio.
- Scanning is foreground-only. Do not add a foreground service, background scan, or battery-optimization exemption.

## Done when
- [ ] Unit tests cover every platform exception mapping to a named state, run with `flutter test`.
- [ ] A manual scan on a real phone sees the bridge advertising the service UUID.
- [ ] A denied permission produces the named state and the approved recovery action; a permanently denied permission produces the blocked state.
- [ ] The negotiated MTU is recorded and visible in diagnostics.
- [ ] `FakeBleClient` still satisfies the same interface and the existing fake-driven tests pass.
- [ ] Hand-off below filled in

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
