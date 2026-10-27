# 0046 - Durable two-phase sync over one transport and one transaction per batch

- **Status:** accepted
- **Date:** 2026-10-27
- **Task:** T41

## Context

T36 kept recent History in an in-memory `RecentHistoryStore` and T35 ran a
15-minute backward pass plus a 30 s forward pass inside `BridgeLink`. The
archive now has durable cursors (T40) and the device has exact backward/gap
semantics (T39, ADR 0044). Re-syncing a 30-day or full 338,400-record ring cannot
block Live, cannot duplicate rows, and must resume after a disconnect or app
relaunch. The UI already owns a single 30 s timer and a single live-notification
path; adding another cadence would race the same `sync_ctrl` characteristic.

## Decision

- `ArchiveSyncCoordinator` (`app/lib/data/sync/archive_sync.dart`) owns the
  sync algorithm over a `SyncTransport`; `BridgeLink` implements that interface
  over its existing framed `sync_ctrl`/`sync_data` procedure. The coordinator
  has no timer and no BLE dependency.
- `connectSync` reads the extent with `sync_ctrl cmd = 0`, then:
  - empty log -> `complete` with `deviceEmpty`, no gap;
  - no local rows for the generation -> backward from `max_seq + 1`, 32-record
    pages, until 2,880 records (24 h) are stored; return `partial` and continue
    older records in a background future;
  - local rows but `cursor_before > device_min_seq` -> `partial` and resume the
    background backfill from `cursor_before`;
  - otherwise forward catch-up from the local maximum `seq`.
- `catchUp` is the existing 30 s pass. It re-reads status (generation/extent),
  finishes an interrupted backfill if needed, then catches forward. Transport
  calls are serialised, so the background backfill and the timer never
  interleave requests.
- A request/batch and its cursor advance are one SQLite transaction
  (`SampleDao.storeSyncBatch`). The primary key `(bridge_id, generation, seq)`
  makes a re-request idempotent; a crash resumes at the last committed cursor.
- Backward stops only on `count = 0`; `next_seq = 0` is a valid exclusive
  cursor. Forward `status = gap` stores `[cursor + 1, start_seq - 1]` with
  reason `Not synced` and continues from the device extent.
- A generation change is an epoch boundary: old rows remain, the new segment
  starts with null cursors. A live notification is stored by `seq`; the
  contiguous `cursor_after` advances only for `seq = cursor_after + 1`.
- `BridgeLink` still owns the one 30 s timer. In archive mode it delegates to
  `connectSync`/`catchUp` instead of its legacy 15-minute window. The accepted
  batch is forwarded to the in-session History store, so the UI seam and
  `BridgeSyncSink` hand-off are unchanged.

## Consequences

- First sync is useful after the 24 h recent pass; the 30-day/338k backfill is
  background work that resumes across disconnects and relaunches.
- The status model is `idle`, `syncing`, `partial`, `complete`, `error` with an
  internal `recent`/`backfill`/`forward` phase. Product copy stays
  `Syncing saved readings` / `Loading saved readings`.
- Host tests cover recent-first order, zero-record termination, record 0,
  mid-batch disconnect resume, the 338,400-record ring, generations, gaps,
  live append, frame-sequence holes and every status branch.
- T42 reads the archive through the DAO; it must not add another sync path.
  T43 uses `connectSync` on reconnect; T44's deletion must also reset the
  cursors it invalidates.
