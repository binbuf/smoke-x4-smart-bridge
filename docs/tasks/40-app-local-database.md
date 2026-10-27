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
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
