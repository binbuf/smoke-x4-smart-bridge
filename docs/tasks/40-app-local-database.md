# T40 — app: local database and DAO

## Goal
Create the on-phone SQLite archive with the `bridge`, `sample`, and `gap` tables, its migrations, and the DAO operations the History and sync tasks need. This is the durable local copy that must survive relaunches and never be deleted implicitly.

## Context (read first)
- Design: [04 §4.7](../design/04-data-and-storage.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T05.
- The schema is fixed by [04 §4.7](../design/04-data-and-storage.md); storage-volume expectations are in [04 §4.9](../design/04-data-and-storage.md).

## Scope
- [ ] Implement the SQLite schema with the `bridge`, `sample`, and `gap` tables.
- [ ] Add schema migrations with a versioned database open path.
- [ ] Implement bulk insert in one transaction per batch, idempotent by `(bridge_id, generation, seq)`.
- [ ] Implement range queries over `recorded_ms` for the History chart and Summary.
- [ ] Implement min/max queries for the local sequence extent and time extent.
- [ ] Implement count queries for readings and date range reporting.
- [ ] Implement deletion by date, returning the number of readings and gaps affected.
- [ ] Add an in-memory database for tests.
- [ ] Keep `unix_s` nullable and map an unknown device clock to `NULL` with `time_estimated = 1`.
- [ ] Add the bridge-identity queries T43 needs: upsert/last-used by
      `last_seen_ms`, read the saved bridge on launch, and clear it on forget or
      factory reset. The `bridge` row is the saved connection; do not add a
      second preferences store for the same identity.

## Out of scope
- Repository, sync orchestration, and cursor management — owned by T41.
- History chart, Summary, and Cooks rendering — owned by T42.
- Retention copy, deletion UI, and confirmation flow — owned by T44.
- Bridge firmware storage, ring geometry, and boot recovery — owned by T18/T19; sync exposure is T39.
- Server/cloud sync and export/share — outside MVP; no task owns them.
- Automatic deletion — outside MVP; no task owns it.

## Design notes
- Use the exact schema from [04 §4.7](../design/04-data-and-storage.md):

```sql
CREATE TABLE bridge (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  last_seen_ms INTEGER NOT NULL,
  generation INTEGER NOT NULL,
  cursor_after INTEGER,            -- highest contiguous seq; NULL until data
  cursor_before INTEGER,           -- lowest contiguous seq; NULL until data
  device_min_seq INTEGER,          -- NULL when the bridge log is empty
  device_max_seq INTEGER
);

CREATE TABLE sample (
  bridge_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  unix_s INTEGER,                  -- NULL when the device clock was unknown
  recorded_ms INTEGER NOT NULL,    -- wall time or estimated wall time
  time_estimated INTEGER NOT NULL,
  p1 INTEGER, p2 INTEGER, p3 INTEGER, p4 INTEGER,  -- tenths °F; NULL = absent
  flags INTEGER NOT NULL,
  PRIMARY KEY (bridge_id, generation, seq)
);
CREATE INDEX sample_time ON sample(bridge_id, recorded_ms);

CREATE TABLE gap (
  bridge_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  from_seq INTEGER NOT NULL,
  to_seq INTEGER NOT NULL,
  reason TEXT NOT NULL,
  detected_ms INTEGER NOT NULL,
  PRIMARY KEY (bridge_id, generation, from_seq)
);
```

- Temperatures are stored in tenths °F, never converted at rest. `NULL` means the probe was absent; never substitute `0`.
- `recorded_ms` is the query axis. A real device timestamp keeps `time_estimated = 0`; a missing device clock uses the estimate `recorded_ms = sync_wall_ms - (device_max_seq - seq) * 30000` with `time_estimated = 1`.
- Inserts are idempotent by primary key. Re-syncing the same `(bridge_id, generation, seq)` must not duplicate or overwrite with a worse record.
- Bulk insert one batch per transaction. Do not issue one transaction per record.
- Deletion by date must also delete or trim `gap` rows that fall inside the deleted range, so a stale gap cannot outlive the samples it described.
- Use the app's chosen `sqflite`/`sqlite3` package from [06 §6.2](../design/06-app.md); keep the DAO behind an interface so the in-memory test database implements the same contract.
- A 20–30 MB database for a full 338,400-record ring is acceptable; do not load full tables into memory.
- `bridge.id` is the BLE address/identity used by the saved connection;
  `bridge.name` is the last observed `SmokeX4-XXXX`/user-facing name and
  `last_seen_ms` orders the saved-bridge lookup. T43 loads this row on launch and
  starts the preferred scan; forgetting the phone or a factory reset deletes it
  only after the UI confirms, while `sample`/`gap` rows stay readable as the
  orphaned `History on this phone`.

## Done when
- [ ] 10,000 records insert/query/delete in tests.
- [ ] Duplicate `seq` insertion is idempotent.
- [ ] A relaunch reads the same data from the same database file and returns the
      saved Bridge identity for T43.
- [ ] Forgetting the Bridge removes the `bridge` row but leaves `sample`/`gap`
      rows readable as orphaned history.
- [ ] `flutter test` passes for the DAO suite.
- [ ] `flutter analyze` passes.
- [ ] Hand-off below filled in.

## Hand-off

**Landed.** The durable on-phone archive and its DAO:

- `app/lib/data/db/app_database.dart` is schema version 2 with forward-only
  migrations. A fresh file and an existing empty version-1 T05 file both create
  the exact `bridge`, `sample` (+ `sample_time`) and `gap` schema from 04 §4.7.
  `openInMemory(factory: databaseFactoryFfi)` is the host-test database.
- `app/lib/data/db/sample_dao.dart` defines the `SampleDao` interface and the
  single `SqfliteSampleDao` implementation:
  - `insertBatch`/`insertSamples` in one transaction per batch, idempotent by
    `(bridge_id, generation, seq)`; a re-sync never duplicates a row and never
    replaces a better record with a worse one. An estimated row is upgraded when
    a later batch has the real device clock.
  - unknown clock → `unix_s = NULL`, `time_estimated = 1`, and the estimate
    `syncWallMs - (deviceMaxSeq - seq) * 30000`; probe sentinels/absent probes
    become `NULL`, never 0 °F.
  - `samplesInRange` over `recorded_ms` (half-open `[from, to)`),
    `newestSamples`, `countSamples`, `extent` (min/max seq and time + count),
    `gaps`/`insertGaps`.
  - `deleteRange` returns `samplesDeleted`, `gapsDeleted`, `gapsTrimmed` and
    `gapsAffected`; it removes gaps detected inside the window and trims or
    removes gaps overlapping the deleted sequence extent.
  - saved-Bridge identity: `savedBridge()` (ordered by `last_seen_ms`),
    `bridgeById`, `saveBridge`, `touchBridge`, `removeBridge`,
    `removeAllBridges`. The `bridge` row is the only saved-connection store;
    forgetting removes only that row and leaves `sample`/`gap` orphaned and
    readable.
- `app/test/local_database_test.dart` adds 11 tests: schema/index, 10,000-row
  insert/range/count/extent/delete, duplicate idempotency, estimated→exact
  upgrade, unknown-clock mapping, Bridge ordering/touch, forget keeps history,
  gap trim then removal, same-file relaunch with saved identity, and v1→v2
  migration. `app/test/app_skeleton_test.dart` now seeds the real `sample`
  table instead of creating a temporary one.
- Docs: implementation notes in 04 §4.7 and 06 §6.2; ADR 0045; reusable facts
  and follow-ups in `docs/progress/T40.md`.

**Decisions / deviations.** The deletion window is half-open `[from, to)` so
“older than N days” and “all” compose without double-counting the boundary.
`gap` has no time column, so date deletion uses `detected_ms` for gaps detected
inside the window and also trims by the deleted sequence extent; this keeps a
stale gap from outliving the samples it described. Upserts use portable
`INSERT OR IGNORE` + conditional `UPDATE` rather than `ON CONFLICT DO UPDATE`
for older Android system SQLite. There is no schema FK from `sample`/`gap` to
`bridge`, deliberately, so orphaned history survives a forget.

**Checks run (all foreground, in `app/`).**

```powershell
flutter analyze
# No issues found! (ran in 1.4s)

flutter test test\local_database_test.dart
# 11/11 passed

flutter test
# 157/157 passed
```

**Next task must know.** T41 should call `insertBatch` with the phone receive
time and the device extent, then advance the `bridge` cursor fields; a batch is
durable before the cursor moves, but cursor advancement is not yet in the same
DAO transaction (add one DAO method if that atomicity is required). Record keys
include `generation`, so a generation change is a new segment, not a delete.
Deletion is `recorded_ms >= fromMs AND recorded_ms < toMs`; use
`0 .. 0x7FFFFFFFFFFFFFFF` for “all”. `SavedBridge.copyWith` cannot clear a
nullable field, so construct a new row when cursors must become `NULL`. T43
loads `savedBridge()` on launch and calls `touchBridge()` on every successful
connect.

