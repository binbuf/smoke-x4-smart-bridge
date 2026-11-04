# 0061 — Forward sync resumes from the contiguous cursor, never the archive maximum

**Status:** accepted (post-T55 field fix)

## Context

A long cook showed many `No signal` bands in History even though the Bridge
stayed in range of the Smoke X4. The phone database proved the Bridge still held
the records: the current generation had a `0..4063` extent but only 3,539 rows,
and the `gap` table was empty. The missing ranges matched periods when Android
had frozen the app, including a 202-record hole from `04:24` to `06:07`.

The failure was in the app's forward cursor. `recordLive` correctly refuses to
advance `cursor_after` across a missed sequence, but both `connectSync` and the
30 s `catchUp` then replaced that cursor with `extent.maxSeq` — the absolute
maximum stored row. The first live notification after a freeze sat above the
hole, so forward sync resumed above it and never re-read the missing records.
The next launch persisted the same too-high cursor, making the loss permanent
from the app's point of view. History could only paint those holes as
`No signal`.

`cursor_after` is already defined as the highest **contiguous** sequence. It is
the only safe forward cursor.

## Decision

1. `SampleDao.contiguousMaxSeq(bridgeId, generation, fromSeq)` returns the
   highest sequence such that every sequence from `fromSeq` to it is stored, or
   null when the anchor row is absent.
2. On connect and on every catch-up, the coordinator recomputes the contiguous
   end from the lowest stored sequence in the current generation. If it is below
   the saved `cursor_after`, the cursor is lowered and persisted before the
   forward pass; the pass then re-reads the missing range. If it is above the
   saved cursor, the contiguous rows are trusted and the cursor is raised.
3. The absolute `extent.maxSeq` is never used as a forward cursor. It is still
   the correct source for the device extent and for the recent-first/backfill
   decision.
4. `HistoryDeletionService` uses the same contiguous end when reconciling
   cursors after a deletion, so a deletion cannot leave a cursor above a hole.
5. A relaunch repairs an archive that was already damaged by the old behaviour;
   no migration or manual reset is required.

## Consequences

- Existing phone archives self-heal on the next connect or app resume. The
  repair is bounded by the normal forward page budget (`maxForwardPages` ×
  `forwardPageSize`) and resumes on the next 30 s pass if a large hole remains.
- A hole is re-read, not converted to a permanent `Not synced` gap, whenever the
  Bridge still holds the records.
- Remaining `No signal` bands now mean the Bridge itself has no record (time
  delta with contiguous `seq`), exactly as the History contract says.
- `archive_sync_test.dart` covers both the same-session catch-up and a relaunch
  with a cursor already stored above a hole; `local_database_test.dart` covers
  the contiguous-bound query.
