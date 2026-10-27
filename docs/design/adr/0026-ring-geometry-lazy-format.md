# ADR 0026 — Ring geometry is lazy-format, header-first, and generation-gated

- **Status:** accepted
- **Date:** 2026-10-26
- **Task:** T18

## Context

Design 04 §4.3 defines a raw 6,160,384-byte partition of 1,504 × 4,096-byte
sectors, two 16-byte headers per sector, 225 records per sector, and a random
32-bit generation written before a clear. The ring must recover torn tails and
torn headers on boot without touching flash in host tests.

Two implementation choices are not forced by the layout: how a format/clear
interacts with 1,504 sector erases, and what may be adopted when a sector header
is unreadable.

## Decision

`log_core.c` implements the ring over `log_io` with these rules:

- **Lazy format.** `log_ring_format(generation)` resets bookkeeping only. Old
  sectors keep a different generation, are ignored by mount, and are erased one
  at a time as rotation reaches them. A deliberate clear therefore does not
  stall boot for a whole-partition erase.
- **Header first, verified.** Before the first record of a sector, the core
  erases the sector, writes header copies A and B, and reads both back. A failed
  verify or write fails the append; the ring refuses further writes until a
  remount.
- **Generation gate.** A supplied (NVS) generation wins. A sector with a valid
  header of another generation is ignored. Headerless sectors are adopted only
  when the caller supplied the generation; without it, the newest valid header
  restores the generation and headerless sectors are left reclaimable.
- **Torn tail.** The scan stops at the first bad CRC/layout or sequence gap.
  Recovery never rewrites committed records; `next_seq = max_seq + 1`.
- **Header repair.** With a known generation, a header that is missing or does
  not match the first valid record is rewritten from that record and verified.
- **Physical rotation with holes.** The writer normally takes the next physical
  sector. If a wholly broken sector leaves a hole, it skips live sectors so
  committed records are not overwritten.

## Consequences

- T19 only has to supply the `log_io` adapter, the NVS generation and a random
  generation when mount reports `needs_format`. It must not re-implement
  geometry.
- Clear/erase is deferred and spread over later rotations; T19's `clear_pending`
  path may still walk and erase old-generation sectors in the background.
- On real NOR, rewriting a torn header in place is not guaranteed to work
  because erased bits cannot be set. The core verifies the read-back and fails
  the mount if repair does not take; T19 decides whether to reclaim that sector.
- Unknown-generation recovery prefers the valid header with the greatest
  `first_seq`. If NVS is lost while unreclaimed old-generation sectors remain,
  that heuristic can pick stale data. NVS is the normal path; T19 should treat
  an unknown generation as a repair case, not the common boot path.
