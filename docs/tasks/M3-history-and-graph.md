# M3 — History

**Exit gate:** the app syncs the full ring, resumes after a disconnect, survives
an app relaunch, draws gaps honestly, and never deletes data without an explicit
user action. The bridge rotation and app archive are visibly separate.

**Design:** [04](../design/04-data-and-storage.md), [06 §6.6–§6.8](../design/06-app.md)

---

### F3.1 ble_service: full sync cursor, gap, and generation

- **blocked-by:** F2.5 · **verify:** H/B · **board:** no / B
- **design:** [04 §4.5, §4.6](../design/04-data-and-storage.md),
  [05 §5.7, §5.8](../design/05-ble-contract.md)

Complete the sync engine on the firmware:

- forward and backward directions,
- `min_seq`/`max_seq`/`generation` snapshots,
- `status=gap` when the cursor is outside the ring,
- zero-record terminator,
- busy/cancel behavior,
- one transfer at a time,
- no blocking of live notifications.

Add host tests for wrap, gap, generation change, and a disconnect mid-batch.

**Done when.** The app can sync 30 days and then the rest of the ring; every
termination is unambiguous.

---

### A3.1 app: local database and DAO

- **blocked-by:** T0.5 · **verify:** H · **board:** no
- **design:** [04 §4.7](../design/04-data-and-storage.md)

Implement the SQLite schema (`bridge`, `sample`, `gap`), migrations, bulk insert
in one transaction, range queries, min/max, count, and deletion by date. Add an
in-memory DB for tests.

**Done when.** 10,000 records insert/query/delete in tests; duplicate seq is
idempotent; a relaunch reads the same data.

---

### A3.2 app: repository and two-phase sync

- **blocked-by:** A3.1, F3.1, A2.4 · **verify:** H/P · **board:** no / phone
- **design:** [04 §4.5](../design/04-data-and-storage.md)

Implement:

- read `stats`/status,
- backward recent-first sync (last 24 h),
- background backward backfill to `min_seq`,
- forward catch-up from the local max,
- per-request transactions, resume at the last stored seq,
- generation change: keep old data, start a new segment,
- gap: store it, reset cursor, continue.

Add a sync status model (idle/syncing/partial/complete/error) and tests for
every branch.

**Done when.** A fake device with a 30-day ring syncs recent-first, then
backfills; a seeded 338,400-record ring (host) completes and resumes without
duplicates; a disconnect mid-batch resumes without duplicates; a log whose first
record is `seq 0` is fully fetched (the backward cursor is exclusive, not a stop
sentinel).

---

### A3.3 app: full History chart and decimation

- **blocked-by:** A3.2 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.6](../design/06-app.md)

Implement range presets (1h/6h/24h/7d/All) plus custom range in one labelled
filter card, probe filters, crosshair with a pinned tooltip, pinch and
mouse-wheel/scroll zoom, drag/pan, double-tap fit, zoom controls, `Now`, LTTB and
min/max envelope, gap splitting with reasons, estimated-time labelling,
latest-point dots, current/min/max summary sorting and detected past cooks.
Summary sorting includes `Since cook started`: detect the active cook from the
newest recorded sample timestamps, fall back to the most recent past cook when
none is active, and sort probes that have reported since that start. Mark the
active cook `In progress` in Past cooks so it is not confused with a closed
session. Past cooks open their historical graph in a dedicated view so the
History tab keeps its current-cook state. SQL-bucket large ranges; keep the chart
under a few thousand points. The full-screen chart is a dedicated,
precision-scrubbing view; it never forces landscape, and fills the screen in
either orientation.

**Done when.** A 30-day, four-series fake DB renders within one frame budget on
the target phone; filters, gaps and detached probes are correct; tapping a past
cook opens the historical view without changing the current History range; no
fake zeros; a chart with no data in the selected range says so and offers one
next action.

---

### A3.4 app: connection health and stale states

- **blocked-by:** A2.4 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.3, §6.8](../design/06-app.md)

Implement the 110 s watchdog, stale vs offline, bounded reconnect, app
resume/pause behavior, pull-to-refresh, and the "Can’t reach the bridge" actionable
state. Map every platform exception to a named state.

**Done when.** Walking out of range, killing the app, and power-cycling the
bridge each produce the intended state and recover without a manual app restart.

---

### A3.5 app: data use and explicit deletion

- **blocked-by:** A3.1, A3.2 · **verify:** H/P · **board:** no / phone
- **design:** [04 §4.8](../design/04-data-and-storage.md), [06 §6.7](../design/06-app.md)

Implement the History & storage settings: phone readings/date range/DB size,
bridge log readings/capacity, one deletion flow for older than 30/90 days or
everything, and clear bridge log. Confirm with the exact range/count. Never
delete on generation change, factory reset, or low storage.

**Done when.** Deletion tests cover boundaries and trim/remove overlapping `gap`
rows; the UI says what is local vs bridge; nothing deletes automatically.

---

### A3.6 app: History/data empty and error states

- **blocked-by:** A3.3, A3.4 · **verify:** H · **board:** no
- **design:** [06 §6.8](../design/06-app.md)

Implement and test the empty/error states for no history, no history in a
selected range, no probes, bridge offline with/without cache, sync failure,
storage unavailable, and protocol mismatch. Each has one next action.

**Done when.** A widget test covers each row in 06 §6.8; no raw exception text
is rendered.

---

### V3.1 Bench: full history and resume

- **blocked-by:** A3.3, A3.4, A3.5, F3.1 · **verify:** P · **board:** yes
- **design:** [10 §10.3 B3](../design/10-test-and-release.md)

On the real bridge and phone:

1. Record ≥ 2 h of data. Full-ring timing uses the seeded 338,400-record host
   fixture, or an accelerated test partition if the bench build supports one.
2. Sync; close the app; reopen; confirm no duplicates and the full History view.
3. Disconnect mid-sync; reconnect; confirm resume.
4. Let the bridge record while the phone is away for 30+ minutes; reconnect;
   confirm catch-up.
5. Delete older than 30 days on a seeded DB; confirm only the intended range.
6. Force a bridge clear/factory reset; confirm the app keeps old data and starts
   a new segment.

**Done when.** The history report and screenshots are committed; timing for 24 h
and full-ring sync is recorded, with the negotiated MTU noted.
