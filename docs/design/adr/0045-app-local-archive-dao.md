# 0045 — App local archive: versioned schema and a single DAO contract

- **Status:** accepted
- **Date:** 2026-10-27
- **Task:** T40

## Context

T05 opened an empty SQLite file at schema version 1. T40 adds the durable
`bridge`, `sample` and `gap` tables fixed by 04 §4.7. The database must survive
relaunches, accept re-synced batches without duplicates, support date-range
deletion without stale gaps, and expose the saved Bridge identity without a
second preferences store. Host tests need the same behaviour in memory, and the
Android system SQLite is older than the newest upsert syntax on some supported
devices.

## Decision

- `AppDatabase` owns schema version 2 and forward-only migrations. A fresh file
  and a version-1 development file both create the same tables; existing data is
  never dropped implicitly.
- `SampleDao` is the archive interface; `SqfliteSampleDao` is the only
  implementation. `AppDatabase.openInMemory` supplies the test database through
  the same contract, not a second fake.
- A batch is inserted in exactly one transaction with `INSERT OR IGNORE` per
  row. An existing `(bridge_id, generation, seq)` row is never replaced. A
  follow-up `UPDATE ... WHERE time_estimated = 1 AND ? = 0` upgrades an estimated
  row when the device clock becomes known. This is portable to older Android
  SQLite versions and means a worse duplicate cannot overwrite a better record.
- `unix_s` is nullable. An unknown device clock stores `NULL`, sets
  `time_estimated = 1`, and places the row with
  `sync_wall_ms - (device_max_seq - seq) * 30000`. Temperature sentinels and
  absent probes become `NULL`, never 0 °F.
- Range reads, counts and extents use `recorded_ms`, with the range half-open
  `[from, to)`. Extent queries return sequence and time minima/maxima plus the
  count, or null when no row matches.
- Date deletion removes samples in the window, removes gaps whose `detected_ms`
  falls inside it, and removes or trims gaps overlapping the deleted sequence
  extent. Other bridges and generations are untouched.
- The `bridge` row is the saved connection. Queries read the last-used row by
  `last_seen_ms`, upsert on save, update the observed name/last-seen in place,
  and delete only the row on forget or factory reset. `sample`/`gap` rows remain
  as orphaned history.

## Consequences

- T41 writes through `insertBatch`/`insertGaps` and updates cursors on the
  `bridge` row; it must not create another cache or preferences store.
- T42 queries `recorded_ms` windows and the DAO extent; T44 calls `deleteRange`
  and reports `samplesDeleted`/`gapsAffected` in its confirmation.
- T43 calls `savedBridge()` on launch, `touchBridge()` on every successful
  connect, and `removeBridge()`/`removeAllBridges()` only after user
  confirmation.
- Gap rows have no time column, so date deletion treats `detected_ms` as the
  detection time and additionally trims by the deleted sequence extent. A gap
  whose samples are gone cannot outlive them.
