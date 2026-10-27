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
- [x] Define the `log_io` seam (`read`, `write`, `erase`) so the core is independent of ESP-IDF.
- [x] Implement sector headers with two 16-byte copies, A and B:

  | Offset | Size | Field |
  |---|---:|---|
  | 0 | 4 | magic `SX4L` |
  | 4 | 1 | version = 1 |
  | 5 | 1 | flags (reserved) |
  | 6 | 3 | `first_seq` u24 |
  | 9 | 4 | `generation` u32 |
  | 13 | 2 | CRC-16/CCITT-FALSE over bytes 0..12 |
  | 15 | 1 | reserved |

- [x] Implement append, sector transitions, wrap, and oldest-sector erase (rotation).
- [x] Write header copies A and B before the first record of a sector, then verify by read-back.
- [x] Implement `min_seq`, `max_seq`, and `generation` tracking.
- [x] Implement the capacity arithmetic and assert it matches **338,400 records**:

  ```
  6,160,384 bytes / 4,096 = 1,504 sectors
  (4,096 - 32 header) / 18 = 225 records/sector (14 bytes spare)
  1,504 × 225 = 338,400 records
  ```

- [x] Implement the recovery scan: accept any valid header copy; scan records until the first bad CRC or impossible sentinel combination; reconstruct a missing header from valid records when the generation still matches; set `next_seq = max_seq + 1` (or 0 when empty).
- [x] Simulate with the RAM fake: torn tails, dual-header recovery, empty log, full log, and full wrap.
- [x] Add a test for generation mismatch: sectors from an old generation are ignored and reclaimed.

## Out of scope
- Binding the core to the `samples` partition and mapping `esp_partition` errors → T19.
- Record byte layout/CRC definition → T17 (this task consumes it).
- App `clear_history` / factory-reset command path and UI → M4 settings (T47–T55); the boot-side pending-clear behavior is T19.
- BLE sync reads (`sync_ctrl` / `sync_data`) → Phase 3 BLE tasks (T27–T37).
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
- [x] The RAM fake passes all scenarios: fill, wrap, oldest-sector erase, torn tail, dual-header recovery, empty, full, full-wrap, and generation change.
- [x] The capacity assert matches **338,400 records**.
- [x] A torn tail leaves earlier records readable and resumes at the next valid sequence.
- [x] A valid record set with one damaged header copy is still usable; a wholly bad header can be reconstructed when the generation matches.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off
Landed:
- `firmware/components/sample_log/include/log_core.h` — ring geometry and API.
  Constants pin 4,096-byte sectors, 32 header bytes (two 16-byte copies), 225
  records/sector, 1,504 sectors and **338,400 records** with `_Static_assert`s
  (including the 14 spare bytes). `log_ring_t`, `log_ring_info_t`,
  `log_ring_mount`, `log_ring_format`, `log_ring_append`, `log_ring_read_seq`
  and `log_ring_info`.
- `firmware/components/sample_log/log_core.c` — pure ring over the existing
  `log_io.h` seam (no ESP-IDF, no heap):
  - dual header copies, magic/version/CRC checks, write A+B then read-back
    verify before the first record;
  - recovery scans each usable sector to the first bad CRC/layout or sequence
    gap, accepts either header copy, repairs a missing/torn header from the
    first valid record when the generation is known, and sets
    `next_seq = max_seq + 1` (0 when empty);
  - generation tracking: supplied NVS generation wins; other-generation
    sectors are ignored and reclaimed later; unknown mode restores the newest
    valid header; `format` is lazy and does not stall boot on an erase of all
    1,504 sectors;
  - append assigns `seq`, rotates at 225 records, erases the oldest sector,
    handles a single-sector wrap and skips holes left by a wholly bad sector;
  - `min_seq`/`max_seq`/`next_seq`/live-count bookkeeping and CRC-checked reads.
- `firmware/test/test_sample_log_ring.c` + `sample-log-ring` CTest: capacity
  arithmetic, empty/format, fill, wrap, oldest-sector erase, torn tail,
  dual-header recovery, wholly bad header reconstruction, generation mismatch
  and reclamation, unknown-generation restore, full 338,400-record default
  partition and one full wrap.
- Design 04 §4.3 "Ring core and the `log_io` seam"; design 03 §3.14; ADR 0026;
  `docs/progress/T18.md` with API/commands/gotchas for T19.

Deviations:
- The ring lives in `log_core.c` (design 03 already assigns it there) rather
  than a new file; the IDF component and host library already build it.
- `log_ring_format` is lazy: it selects the generation but leaves old sectors
  for rotation to erase. This avoids a whole-partition erase at boot; T19's
  `clear_pending` path may still erase them explicitly.
- The recovery scan also stops on a sequence gap, not only bad CRC/sentinel, so
  a valid-looking stale record past a torn write is never adopted.
- Unknown-generation restore uses the greatest `first_seq` header. If NVS is
  lost while unreclaimed old-generation sectors remain, it can pick stale data;
  the normal path supplies the NVS generation (ADR 0026).

Checks:
- Host: `cmake -S firmware/test -B firmware/test/build -G Ninja`,
  `cmake --build firmware/test/build`,
  `ctest --test-dir firmware/test/build --output-on-failure` -> 10/10 passed
  (new `sample-log-ring` runs the full 338,400-record fill in 0.40 s).
- Firmware: `idf.py -B build
  "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`
  -> complete; `sx4_bridge.bin` 0x3aa70 bytes.
- Capacity assert matches **338,400** records in `log_core.h` and the test.

Remaining work:
- T19: implement the `esp_partition` `log_io` adapter, pass the NVS generation
  to `log_ring_mount`, generate and persist a fresh generation when
  `info.needs_format`, and measure real-flash recovery. The core scans
  record-by-record, so a buffered adapter may be needed for the ~2 s budget.
- T19: finish `clear_pending` by erasing old-generation sectors; decide what to
  do if in-place header reconstruction fails read-back on NOR.
- T21/T27: consume `log_ring_append`/`log_ring_read_seq`; T27 may add a backward
  scan helper reusing the header walk.
- No blockers.
