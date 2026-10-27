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

**Landed**

- `protocol/records.yaml` — sample_rec, sector_header, temperature sentinels,
  record flags, ring/log constants, CRC-16/CCITT-FALSE parameters.
- `protocol/ble.yaml` — service UUID, all eight characteristic slots with
  properties/security/payload, payload layouts, seven control ops, eight result
  statuses, flags and enums.
- `tools/protogen/protogen.py` — deterministic YAML-to-C/Dart generator with
  layout/CRC validation and a `--check` drift mode.
- `protocol/gen/records.h`, `records.c`, `records.dart` — committed output with
  payload structs, constants, flag masks, enums, encode/decode helpers,
  CRC-16/CCITT-FALSE, and the u24 sequence codec.
- `Makefile` — `make protocol`, `make protocol-check`, `make protocol-test`.
- `protocol/test/test_records.c` and `protocol/test/records_test.dart` — C and
  Dart tests that decode and re-encode the design 05 §5.4 `live` vector, plus
  record CRC rejection, u24, CRC check vector, result and sync payloads.
- `docs/design/adr/0013-generated-protocol-codecs.md`; codegen notes in design
  04 §4.2 and 05 §5.1; reusable notes in `docs/progress/T02.md`.

**Deviations**

- The task named `records.h/.c/.dart` only, so BLE payloads and constants are
  emitted into those same files rather than extra `ble.*` files. The YAML
  sources remain split as required.
- The task 05 §5.4 vector is used as the normative `live` test. Additional
  vectors cover the record codec and framing but are not an exhaustive 05 §5.14
  suite; T03 extends the fixture-driven coverage.
- The generator is Python rather than reusing the legacy Dart protogen; the
  legacy YAML is a shape reference only, as the task required.

**Check results**

```text
make protocol                 # wrote protocol/gen/records.{h,c,dart}
make protocol-check           # protocol/gen is current
make protocol-test CC=gcc DART=<dart>   # C asserts pass; Dart tests pass
dart analyze protocol/gen/records.dart protocol/test/records_test.dart
                              # No issues found
# drift probe: appended a comment to records.h
make protocol-check           # stale: protocol/gen/records.h (non-zero)
make protocol && make protocol-check     # current again
```

On this bench the working compiler is `C:\msys64\ucrt64\bin\gcc.exe` (add it to
PATH for `make`), and `make`'s shell needs
`DART=D:/flutter/bin/cache/dart-sdk/bin/dart.exe`.

**Remaining work / next task must know**

- No blockers. `protocol/gen/` is committed; do not ignore or hand-edit it.
- T03 should compile `protocol/gen/records.c` into the CMake host suite and fold
  `protocol/test/test_records.c` into `ctest`; T08 should wire
  `protocol-check`/`protocol-test` into CI.
- Firmware/app tasks must consume the generated symbols (`sx4_*` in C,
  `SampleRec`/`Live`/`SyncCtrl`/`Result` in Dart) instead of restating offsets,
  UUIDs, flags, or CRC parameters. `docs/progress/T02.md` lists the naming
  and u24/result gotchas.
