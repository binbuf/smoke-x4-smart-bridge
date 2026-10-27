# T02 — Protocol contract and codegen

## Goal
Make the record and BLE protocol a single machine-readable contract with
generated C and Dart codecs, so firmware, app, and tests cannot drift from the
design. The generated output is checked in and its freshness is verifiable.

## Context (read first)
- Design: [04 §4.2](../design/04-data-and-storage.md),
  [05](../design/05-ble-contract.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T01.

## Scope
- [ ] Write `protocol/records.yaml`: sample record, sentinels, flags, constants.
- [ ] Write `protocol/ble.yaml`: service UUID, characteristic slots, payload
      layouts, control ops, result statuses.
- [ ] Generate `protocol/gen/records.h` and `protocol/gen/records.c` (C).
- [ ] Generate `protocol/gen/records.dart` (Dart).
- [ ] Add a `--check` mode that fails if committed output drifts.
- [ ] Include CRC16/CCITT-FALSE and the 24-bit sequence codec.
- [ ] Wire `make protocol` to regenerate and `make protocol-check` to run the
      drift check.
- [ ] Add a host test that encodes/decodes the `live` example vector from
      [05 §5.4](../design/05-ble-contract.md).

## Out of scope
- The BLE fake and app test seam — owned by T07.
- Firmware BLE service implementation and radio behaviour — M1/M2.
- App screens and state wiring — owned by T05/T06, then M2.
- Inventing or extending protocol layouts: the new layouts are defined in the
  design docs; legacy `records.yaml` is a shape reference only.

## Design notes
- The legacy `records.yaml` is a **shape reference only**. New layouts come
  from the design docs ([04 §4.2](../design/04-data-and-storage.md),
  [05](../design/05-ble-contract.md)); do not copy legacy semantics.
- Generated artifacts are committed and must be reproducible byte-for-byte;
  `--check` fails on any drift between YAML and committed output.
- Both C and Dart codecs must be generated from the same YAML sources so the
  host tests, firmware, and app share one contract.
- CRC16/CCITT-FALSE and the 24-bit sequence codec are part of the generated
  contract, not hand-written per consumer.
- Keep generation deterministic (stable ordering and formatting) so the drift
  check is meaningful.

## Done when
- [ ] `make protocol` regenerates the output successfully.
- [ ] `make protocol-check` is clean.
- [ ] A host test encodes/decodes the `live` example vector in
      [05 §5.4](../design/05-ble-contract.md).
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
