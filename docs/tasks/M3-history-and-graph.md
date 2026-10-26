# M3 — History

**Exit gate:** the app syncs the full ring, resumes after a disconnect, survives
an app relaunch, draws gaps honestly, and never deletes data without an explicit
user action. The Bridge rotation and phone archive are visibly separate. History,
Summary, Cooks and the Cook view match the approved UI contract, including
empty/offline/estimated/overwritten states.

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

### A3.3 app: full History chart, Summary and Cooks

- **blocked-by:** A3.2 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.6](../design/06-app.md),
  [13 §13.4](../design/13-ui-implementation-contract.md#history)

Complete the approved History screen:

- range trigger `1 hour`, `6 hours`, `24 hours`, `2 days`, `Custom`; menu
  `Last hour`, `Last 6 hours`, `Last 24 hours`, `Last 2 days`, `Custom range…`;
- custom range sheet starting with all saved history, exact date/time, validation
  and quick picks (`All saved history`, `Today`, `Yesterday`, `Last 6 hours`);
  apply only on `Apply`, and `Cancel` restores the previous range and viewport;
- probe filter `All probes`/`P1`–`P4`, disabled options labelled `No data`;
  reset icon only with an active filter; range/probe/sort persist across tabs and
  resume;
- crosshair with a pinned tooltip, pinch/scroll zoom, drag/pan, double-tap fit,
  zoom controls, `Now`, latest-point dots, single-probe area fill;
- LTTB + min/max envelope, SQL bucketing, gap splitting with reasons
  (`No signal`, `Bridge off`, `Not synced`), estimated-time label;
- `Summary` with `Latest`/`Min`/`Max` and no deltas; sort options `Probe order`,
  `Hottest`, `Highest`, `Latest reading`, `Since cook start`; disabled cook sort
  shows `No cook detected yet`;
- `Cooks` card with the latest three detected cooks, `In progress` on the live
  cook, `View all`, and a dedicated `Cook` view with `Recorded history` and the
  cook end time instead of `Now`; closing it leaves History unchanged;
- chart help sheet (`Reading the chart`) and the dedicated full-screen chart,
  portrait or landscape, with a close action;
- empty states for no readings at all, no readings in range, no probe data, and
  offline with no cache.

**Done when.** A 30-day, four-series fake DB renders within one frame budget on
the target phone; filters, custom range, gaps, estimated times and detached
probes are correct; Summary sorting and Cooks work from recorded timestamps;
tapping a Cook opens the historical view without changing the current History
range; no fake zeros; a range with no data says so and offers one next action;
the approved UI is intact at 320 dp.

---

### A3.4 app: connection health and stale states

- **blocked-by:** A2.4 · **verify:** H/P · **board:** no / phone
- **design:** [06 §6.3, §6.8](../design/06-app.md),
  [13 §13.5](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows)

Implement the 110 s watchdog, BLE-vs-X4 state separation, stale vs offline,
bounded reconnect, app resume/pause behavior, pull-to-refresh, and the
`Can’t reach the Bridge` actionable state. Map every platform exception to a
named state. Offline with cache keeps last-known values dimmed and labelled;
offline without cache shows no current probe values and one next action.

**Done when.** Walking out of range, killing the app, and power-cycling the
bridge each produce the intended state and recover without a manual app restart;
no cached value is presented as live; the no-cache state has no fake probe
readings.

---

### A3.5 app: data use and explicit deletion

- **blocked-by:** A3.1, A3.2 · **verify:** H/P · **board:** no / phone
- **design:** [04 §4.8](../design/04-data-and-storage.md), [06 §6.7](../design/06-app.md)

Implement the approved History & storage screen: `History on this phone`
(readings/date range/storage used), `History on the Bridge` (readings/capacity/
percentage/oldest/newest), one deletion flow for older than 30/90 days or
everything, and `Clear history on the Bridge…`. Confirm with the exact range and
count. Never delete on generation change, factory reset, or low storage. Use
`readings`, not `records`.

**Done when.** Deletion tests cover boundaries and trim/remove overlapping `gap`
rows; the UI says what is local vs Bridge; the two copies stay separate; nothing
deletes automatically; the approved copy is used.

---

### A3.6 app: History/data empty and error states

- **blocked-by:** A3.3, A3.4 · **verify:** H · **board:** no
- **design:** [06 §6.8](../design/06-app.md),
  [13 §13.4](../design/13-ui-implementation-contract.md#live)

Implement and test the empty/error states for no history, no history in a
selected range, no probe data, no probes, Bridge offline with/without cache, no
X4 data, sync failure, storage unavailable, and protocol mismatch. Each has one
next action and the exact copy from 12. The no-cache state must not render fake
probe values.

**Done when.** A widget test covers each row in 06 §6.8 and every relevant state
in 13 §13.4; no raw exception text is rendered; the no-cache and no-X4 notices
are honest.

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
7. Walk the History states in 13 §13.4: ranges, custom, filters, gaps, estimated,
   overwritten, empty, offline cache, Cooks and the Cook view.
8. Check 320 dp, dark/light and screen-reader output on the target phone.

**Done when.** The history report and screenshots are committed; timing for 24 h
and full-ring sync is recorded, with the negotiated MTU noted; the History UI
matches the approved contract in both themes.
