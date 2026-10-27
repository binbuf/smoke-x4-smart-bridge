# 0013 — Generated protocol codecs from YAML

## Status

Accepted

## Context

The 18-byte sample record and the BLE GATT payloads are consumed by firmware
(C), the Flutter app (Dart), and host tests. Hand-writing the same offsets,
CRC parameters, sentinels, and flag bits in each place is how firmware and app
drift apart. The legacy tree used a code generator, but its record semantics
(cook sessions, 16-byte records, a different BLE service) do not apply here.

## Decision

Make `protocol/records.yaml` and `protocol/ble.yaml` the single machine-readable
contract. `tools/protogen/protogen.py` deterministically generates
`protocol/gen/records.h`, `records.c`, and `records.dart` from both files. The
generated files are committed. The generator emits the constants, flags, enums,
payload structs, encode/decode helpers, CRC-16/CCITT-FALSE, the 24-bit sequence
codec, and the BLE UUID/slot table.

`make protocol` regenerates in place. `make protocol-check` regenerates in
memory and exits non-zero on any byte difference. `make protocol-test` compiles
and runs the C codec test and runs the Dart codec test against the shared `live`
example vector in 05 §5.4.

## Consequences

- A contract change is one YAML edit plus `make protocol`; every consumer sees
  the same bytes.
- Formatting and ordering are fixed by the generator, so `--check` is a real
  drift test rather than a whitespace lottery.
- Generated output must not be hand-edited or ignored by git.
- Changing a wire field requires regenerating and checking in the output, so a
  review sees the compatibility impact.
