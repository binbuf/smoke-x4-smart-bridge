"""Generate the T46 debug-app seeded archive used for the History state walk.

This is a bench fixture, not product data. It writes:

  artifacts/bench/T46/seeded-phone.db  full 117-day ring, gapped
  artifacts/bench/T46/empty-phone.db   same identity, zero readings

The seeded archive has:
  * a 1-day `Yesterday` hole (empty-range state);
  * a 14 h..6 h `Not synced` gap (overwritten-before-sync state);
  * a last hour containing only a 5-minute estimated block, with P3 NULL
    (estimated + no-cook + empty-filtered-probe states);
  * 251,999 readings older than 30 days for the deletion check.

Push it into the debug app with `adb push` + `run-as ... cp` while the app is
force-stopped; the T46 report records the exact procedure and results.
"""

import datetime as dt
import math
import os
import sqlite3
import time

OUT = os.path.join("artifacts", "bench", "T46", "seeded-phone.db")
EMPTY = os.path.join("artifacts", "bench", "T46", "empty-phone.db")
N = 338400
STEP = 30000
GEN = 42
BRIDGE_ID = "AC:A7:04:38:82:76"
BRIDGE_NAME = "SmokeX4-8276"

now_ms = int(time.time() * 1000)
start_ms = now_ms - (N - 1) * STEP

SCHEMA = [
    """CREATE TABLE IF NOT EXISTS bridge (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, last_seen_ms INTEGER NOT NULL,
      generation INTEGER NOT NULL, cursor_after INTEGER, cursor_before INTEGER,
      device_min_seq INTEGER, device_max_seq INTEGER)""",
    """CREATE TABLE IF NOT EXISTS sample (
      bridge_id TEXT NOT NULL, generation INTEGER NOT NULL, seq INTEGER NOT NULL,
      unix_s INTEGER, recorded_ms INTEGER NOT NULL, time_estimated INTEGER NOT NULL,
      p1 INTEGER, p2 INTEGER, p3 INTEGER, p4 INTEGER, flags INTEGER NOT NULL,
      PRIMARY KEY (bridge_id, generation, seq))""",
    "CREATE INDEX IF NOT EXISTS sample_time ON sample(bridge_id, recorded_ms)",
    """CREATE TABLE IF NOT EXISTS gap (
      bridge_id TEXT NOT NULL, generation INTEGER NOT NULL, from_seq INTEGER NOT NULL,
      to_seq INTEGER NOT NULL, reason TEXT NOT NULL, detected_ms INTEGER NOT NULL,
      PRIMARY KEY (bridge_id, generation, from_seq))""",
]


def make_db(path, with_rows=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=DELETE")
    for statement in SCHEMA:
        db.execute(statement)
    db.execute("PRAGMA user_version=2")
    db.execute(
        "insert into bridge values (?,?,?,?,?,?,?,?)",
        (BRIDGE_ID, BRIDGE_NAME, now_ms, GEN, N - 1 if with_rows else None,
         0 if with_rows else None, 0 if with_rows else None,
         N - 1 if with_rows else None),
    )
    if not with_rows:
        db.commit()
        db.close()
        return

    rows = []
    for seq in range(N):
        t = start_ms + seq * STEP
        base = 2250 + 35 * math.sin(seq / 900.0) + 8 * math.sin(seq / 37.0)
        p1 = int(base)
        p2 = int(base - 18 + 6 * math.sin(seq / 71.0))
        p3 = int(base + 12 + 5 * math.sin(seq / 53.0))
        p4 = int(base - 6 + 4 * math.sin(seq / 29.0))
        if t >= now_ms - 3600_000:
            p3 = None  # empty filtered probe in the last hour
        rows.append((BRIDGE_ID, GEN, seq, t // 1000, t, 0, p1, p2, p3, p4, 47))
        if len(rows) >= 20000:
            db.executemany("insert into sample values (?,?,?,?,?,?,?,?,?,?,?)", rows)
            rows.clear()
    if rows:
        db.executemany("insert into sample values (?,?,?,?,?,?,?,?,?,?,?)", rows)

    def seq_at(t):
        return max(0, min(N - 1, (t - start_ms) // STEP))

    def delete_range(t0, t1, reason):
        s0, s1 = seq_at(t0), seq_at(t1 - 1)
        db.execute(
            "delete from sample where generation=? and seq between ? and ?",
            (GEN, s0, s1),
        )
        # detected_ms is set to the gap end so the HistoryArchive band lands on
        # the missing period. The real sync path writes the detection time; the
        # placement difference is recorded as finding F in the T46 report.
        db.execute(
            "insert or replace into gap values (?,?,?,?,?,?)",
            (BRIDGE_ID, GEN, s0, s1, reason, t1),
        )

    today = dt.datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    y0 = int((today - dt.timedelta(days=1)).timestamp() * 1000)
    y1 = int(today.timestamp() * 1000)
    delete_range(y0, y1, "Bridge off")

    delete_range(now_ms - 14 * 3600_000, now_ms - 6 * 3600_000, "Not synced")

    b0 = now_ms - 55 * 60_000
    b1 = now_ms - 50 * 60_000
    db.execute(
        "update sample set time_estimated=1 where generation=? and recorded_ms>=? and recorded_ms<?",
        (GEN, b0, b1),
    )
    delete_range(now_ms - 60 * 60_000, b0, "Bridge off")
    delete_range(b1, now_ms, "Bridge off")

    db.commit()
    db.close()


if __name__ == "__main__":
    make_db(OUT, True)
    make_db(EMPTY, False)
    print("wrote", OUT, "and", EMPTY)
