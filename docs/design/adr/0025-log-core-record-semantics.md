# ADR 0025 — Sample-record semantics live in `log_core`, bytes stay generated

- **Status:** accepted
- **Date:** 2026-10-26
- **Task:** T17

## Context

Design 04 §4.2 makes `protocol/records.yaml` the single definition of the
18-byte record, with `protocol/gen/records.c` owning the byte layout,
CRC-16/CCITT-FALSE and the 24-bit sequence codec. T17 also names
`firmware/components/sample_log/log_core.c` as the codec's home and adds rules
the generated codec does not know: exact sentinels, attach-bit agreement, and an
explicit `record_size`.

Writing a second encoder in `log_core.c` would duplicate offsets and CRC logic
and let firmware drift from the committed contract. Calling the generated
codec directly from every consumer would scatter validation and invite
`sizeof(sx4_sample_rec_t)` as a wire size.

## Decision

`log_core.h/.c` is the firmware-facing record codec and the only record API
ring, flash and pipeline code should use.

- The generated `sx4_sample_rec_encode` / `_decode`, CRC and u24 codec remain
  the sole byte-level implementation. `log_core` wraps them; it does not
  re-implement offsets.
- `sample_log_record_encode` / `_decode` add the semantic checks: for each
  probe, attached bit 0 requires `TEMP_DETACHED` and attached bit 1 requires
  any other value (`TEMP_INVALID` included). A disagreement is corrupt.
- Decode verifies length and CRC first, validates into a local, and copies to
  the caller only on success, so a rejected record is never partially exposed.
- The wire size is exposed as `SAMPLE_LOG_RECORD_SIZE` / `sample_log_record_size()`;
  callers never use `sizeof(sx4_sample_rec_t)` as the record size.
- `firmware/components/protocol_gen/` is a thin ESP-IDF component that compiles
  the committed `protocol/gen/records.c` once for firmware, without generating
  at build time.

## Consequences

- T18/T19/T21 must use `sample_log_record_*`; sector headers may use the
  generated sector-header codec directly because `log_core` does not wrap it.
- Any layout or CRC change still happens in `protocol/records.yaml` and
  `make protocol`. `log_core.h` compile-time asserts keep the generated size and
  sentinels aligned with the firmware boundary.
- The validation rule is symmetric: both "flag 0, numeric temperature" and
  "flag 1, detached" are rejected on write and read.
- Readers may pass a buffer longer than one record; decode consumes exactly
  `sample_log_record_size()` bytes, leaving future versioning to the sector
  header.
