# T18 — sample_log: ring geometry

## Goal
A pure ring core over a `log_io` seam implements sector headers, append, wrap, oldest-sector erase, sequence/generation tracking, capacity arithmetic, and boot recovery. A RAM fake can simulate torn tails, dual-header recovery, empty/full, and full-wrap without touching flash.

## Context (read first)
- [04 §4.3](../design/04-data-and-storage.md) — raw sector layout, dual headers, write path, recovery, generation, and capacity arithmetic.
- [03 §3.14](../design/03-firmware-architecture.md) — the `log_io` test seam: `read`, `write`, `erase`.
- `firmware/components/sample_log/` — `log_core.c` (this task) and `log_flash.c` (T19).
- **Verification:** H (host/CI). **Board:** no.
- Depends on T17.

## Scope
- [ ] Define the `log_io` seam (`read`, `write`, `erase`) so the core is independent of ESP-IDF.
- [ ] Implement sector headers with two 16-byte copies, A and B:

  | Offset | Size | Field |
  |---|---:|---|
  | 0 | 4 | magic `SX4L` |
  | 4 | 1 | version = 1 |
  | 5 | 1 | flags (reserved) |
  | 6 | 3 | `first_seq` u24 |
  | 9 | 4 | `generation` u32 |
  | 13 | 2 | CRC-16/CCITT-FALSE over bytes 0..12 |
  | 15 | 1 | reserved |

- [ ] Implement append, sector transitions, wrap, and oldest-sector erase (rotation).
- [ ] Write header copies A and B before the first record of a sector, then verify by read-back.
- [ ] Implement `min_seq`, `max_seq`, and `generation` tracking.
- [ ] Implement the capacity arithmetic and assert it matches **338,400 records**:

  ```
  6,160,384 bytes / 4,096 = 1,504 sectors
  (4,096 - 32 header) / 18 = 225 records/sector (14 bytes spare)
  1,504 × 225 = 338,400 records
  ```

- [ ] Implement the recovery scan: accept any valid header copy; scan records until the first bad CRC or impossible sentinel combination; reconstruct a missing header from valid records when the generation still matches; set `next_seq = max_seq + 1` (or 0 when empty).
- [ ] Simulate with the RAM fake: torn tails, dual-header recovery, empty log, full log, and full wrap.
- [ ] Add a test for generation mismatch: sectors from an old generation are ignored and reclaimed.

## Out of scope
- Binding the core to the `samples` partition and mapping `esp_partition` errors → T19.
- Record byte layout/CRC definition → T17 (this task consumes it).
- App `clear_history` / factory-reset command path and UI → M4 settings (T47–T55); the boot-side pending-clear behavior is T19.
- BLE sync reads (`sync_ctrl` / `sync_data`) → Phase 3 BLE tasks (T27–T38).
- LittleFS or any filesystem: outside MVP; the partition is raw.
- OTA slots or a second application partition: outside MVP; no task owns it.
- Wear-levelling beyond the natural sector rotation: not needed; see [04 §4.3](../design/04-data-and-storage.md).

## Design notes
- The `samples` partition is raw flash, not a filesystem. Rotation is a sector erase, not a file rewrite.
- Sector geometry: 4 KB sectors, 32 bytes of header (A + B), 225 × 18-byte records, 14 bytes spare.
- The header is written **before** the first record of the sector; records are appended after it.
- A sector is usable if either header copy has a valid CRC and agrees with the records found in it.
- A torn tail is ignored; earlier committed records are never rewritten.
- `generation` is a random 32-bit value, not a counter. It is set on first format, clear, or a wholly unusable log; a single bad sector must not change it.
- Recovery determines `min_seq`/`max_seq` across valid sectors. A sector with no valid records is empty/reclaimable.
- Every record is CRC-checked on read and on write (the latter in host tests).
- There is no per-sample `fsync`; NOR writes commit as they complete. The per-record CRC catches a torn tail.

## Done when
- [ ] The RAM fake passes all scenarios: fill, wrap, oldest-sector erase, torn tail, dual-header recovery, empty, full, full-wrap, and generation change.
- [ ] The capacity assert matches **338,400 records**.
- [ ] A torn tail leaves earlier records readable and resumes at the next valid sequence.
- [ ] A valid record set with one damaged header copy is still usable; a wholly bad header can be reconstructed when the generation matches.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
