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
- [ ] Implement `BleClient` as an interface.
- [ ] Implement `FakeBleClient` with scripted advertisements.
- [ ] Support connect/bond states, MTU, reads/writes, and notifications in the
      fake.
- [ ] Add a `FakeBridge` that serves `info`, `live`, `config`, `stats`, and a
      small sync stream.
- [ ] Use the generated codecs in `FakeBridge` for all payloads.

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
- [ ] A widget test can drive scan → connect → bond → subscribe → one live
      sample with no radio.
- [ ] A disconnect moves the UI to the right state.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
