# ADR 0022 — Parser validates, filters and canonicalises before output

- **Status:** Accepted
- **Date:** 2026-10-26
- **Task:** T14 (sx_protocol)

## Context

The legacy `smoke_x_parser.c` proved the Smoke X wire shapes but returned
temperatures in the packet's active unit, trusted the frozen value on a
detached probe, had no paired-ID filter, and could leave a caller's struct
partly written when a later field failed. The sample record needs canonical
°F tenths, `TEMP_DETACHED`, a foreign-ID counter, and an atomic reject.

## Decision

`sx_protocol_parse_state()` is a pure-C parser that:

1. Rejects the whole payload before touching `*out` unless it has exactly 16
   (X2 defensive) or 26 (X4) commas, one trailing comma, no empty fields and
   only strictly numeric values. Output is built in a local struct and copied
   only on success.
2. Compares the device ID against the paired ID before parsing the remaining
   fields. A mismatch returns `SX_PROTOCOL_ERR_FOREIGN_DEVICE`, increments the
   foreign counter, and leaves `*out` untouched.
3. Emits every attached probe as canonical °F tenths
   (`F10 = (C10 × 9) / 5 + 320`) and every detached probe (`state == 3`) as
   `SX_PROTOCOL_TEMP_DETACHED` (`INT16_MIN`), discarding the X4's frozen
   number. `source_celsius` records the wire unit only.
4. Preserves `new_alarm` and `billows_attached`. Probe 4 `max` is exposed as a
   **candidate** target (`billows_target_valid == false`) until M5 validates
   the max↔target relation.
5. Keeps `strtok_r`, a fixed 128-byte stack buffer and no heap. Counters cover
   valid states, parse failures, CRC failures (radio hook), foreign IDs, sync
   beacons and ACK attempts.

Sync beacons are parsed without a paired-ID filter because sync is the
discovery path; the pairing FSM (T16) owns the frequency and ID policy.

## Consequences

- Callers must check `billows_target_valid`; the MVP UI shows only "Billows
  detected".
- `alarm_high_deg` / `alarm_low_deg` stay in the packet's active unit; they
  are not canonical storage and no record field carries them.
- The parser is single-writer for counters. Housekeeping reads a snapshot.
- T21 must use this API rather than re-parse payloads, and T16 must apply the
  902–928 MHz check separately after `sx_protocol_parse_sync()`.
- X2 parsing remains defensive only; no X2 product behaviour is implied.
