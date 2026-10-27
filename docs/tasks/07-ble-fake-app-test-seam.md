# T07 — BLE fake and app test seam

## Goal
Introduce a `BleClient` interface and a scripted `FakeBleClient`/`FakeBridge`
so the app can be developed and widget-tested end to end with no radio and no
board. This is the decoupling point between the firmware and app lanes.

## Context (read first)
- Design: [06 §6.10](../design/06-app.md), [05](../design/05-ble-contract.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T02 and T05.
- The fake uses the generated codecs from T02, so protocol drift breaks the
  app tests too.

## Scope
- [x] Implement `BleClient` as an interface.
- [x] Implement `FakeBleClient` with scripted advertisements.
- [x] Support connect/bond states, MTU, reads/writes, and notifications in the
      fake.
- [x] Add a `FakeBridge` that serves `info`, `live`, `config`, `stats`, and a
      small sync stream.
- [x] Use the generated codecs in `FakeBridge` for all payloads.

## Out of scope
- Real BLE transport and platform permissions — M2.
- Firmware BLE service implementation — M1/M2.
- Full History sync, resume, and archive — M3.
- Config write handling and device actions in production — M4.
- Protocol YAML/codegen changes — owned by T02.
- A production UI redesign — outside MVP; screens are T05/T06.

## Design notes
- `BleClient` is the single app-side BLE seam; production and fake implement
  the same interface.
- `FakeBleClient` is scripted: advertisements, connect/bond state transitions,
  MTU negotiation, reads, writes, and notifications are all driven by test
  scripts, with no radio.
- `FakeBridge` serves `info`, `live`, `config`, `stats`, and a small sync
  stream, and must encode/decode with the generated codecs — do not hand-roll
  payload bytes in tests.
- The fake lives with test tooling (`tools/` / app test support), not in the
  release path.
- The fake must be able to model a disconnect so the UI's offline state is
  testable.

## Done when
- [x] A widget test can drive scan → connect → bond → subscribe → one live
      sample with no radio.
- [x] A disconnect moves the UI to the right state.
- [x] Hand-off below filled in.

## Hand-off

### What landed

- `app/lib/data/ble/ble_client.dart`: the single app-side BLE seam. It defines
  `BleClient`, `BleDevice`, `BleConnectionState`, `BleBondState`, `BleFailure`
  and `BleException`, with scan, stopScan, connect/disconnect, bonding, MTU
  request, complete characteristic read/write, notifications and setNotify.
- `BridgeController` and `createBridgeController` accept an optional
  `BleClient`; `main.dart` is untouched, and the controller disposes an injected
  client. `createBridgeController` can be used from tests directly.
- `app/test/support/fake_ble_client.dart`: scripted advertisements,
  connect/disconnect transitions, expected-passkey bonding (wrong-passkey
  supported), forced bond failures, MTU negotiation, encryption requirements
  from the generated characteristic metadata, and notification chunking at
  `MTU-3`.
- `app/test/support/fake_bridge.dart`: GATT server for `info`, `live`, `config`,
  `stats`, `control` results and a framed `sync_ctrl`/`sync_data` batch. Every
  payload is encoded/decoded with the T02 generated codecs; config writes are
  validated (units, display timeout, Billows mode 0).
- `app/test/support/fake_bridge_session.dart`: test-only link harness that
  decodes live notifications into a `BridgeContent` and maps fake disconnect to
  the controller's offline state. It lives in test support, not `lib/`.
- `app/test/ble_fake_test.dart`: 8 tests for advertisement decode, security,
  bond states, MTU, reads/writes, notifications, framed sync, disconnect,
  bootstrap injection and a release-import guard.
- `app/test/ble_widget_flow_test.dart`: one widget test drives scan → connect →
  bond → subscribe → one live sample and asserts the approved Live UI, then a
  fake disconnect asserts the offline UI.
- Docs: `docs/design/adr/0018-ble-client-seam-and-scripted-fake.md`,
  `docs/design/06-app.md` (§6.2 and §6.10), `docs/progress/T07.md`.

### Deviations and boundaries

- No production `flutter_blue_plus` adapter exists yet; that is T32. The
  `BleClient` interface is the full seam T32 implements.
- `SetupScreen` still uses its own review timers (T33 owns), so the widget test
  drives the BLE seam through `FakeBridgeSession` and then asserts the approved
  UI rather than tapping simulated setup buttons. The seam, bond states and
  disconnect path are exercised end to end.
- Dart package rules do not allow `app/lib/` to import `protocol/gen`. The fake
  and tests reach the generated codec through `app/test/support/codecs.dart`.
  T32 must package/relocate the generated Dart for production; this is recorded
  in ADR 0018 and the T07 progress notes.
- Fake config write validation is test-scoped; production read/write handling
  remains M4/T47.

### Checks run

```text
make app-check        -> analyze clean; 47 tests passed
make protocol-check   -> protocol/gen is current
cd app && flutter test test/ble_fake_test.dart test/ble_widget_flow_test.dart
                      -> 9 tests passed
```

### Next task must know

- T08 CI should run `make app-check`; it now includes the fake BLE suite.
- T32 implements `BleClient` over `flutter_blue_plus`, handles Read Blob and
  chunked notifications, and must package the generated codec for `app/lib/`.
- T33/T34 can reuse the flow encoded in `FakeBridgeSession` for setup and Live
  wiring; do not import `test/support/` from production.
- T64 must prove no `test/support/` import reaches the release graph.
