# 0043 — Recent History is an in-memory V0 slice over the sync sink

**Status:** accepted

## Context

T35 already syncs the last 15 minutes into a `BridgeSyncSink` and T36 must mount
the approved History shell against real synced readings. The durable archive,
cursors, generation handling and older pages do not land until T39–T41, but V0
cannot ship a fixture-driven History or a second simplified screen.

## Decision

- `RecentHistoryStore` implements `BridgeSyncSink` and keeps the records this
  session synced, keyed by sequence.
- `BridgeController` owns one store and passes it to `BridgeLink` when the caller
  does not inject a test sink. Every accepted batch notifies the History view.
- The store builds a `HistoryFixture` for the requested range. The requested
  range is the real chart window; V0 has only the recent window, so a wider
  selection shows the same recent readings in the wider window. A selection with
  no readings yields empty series (`No readings in this range`), never another
  period's values.
- Probe temperatures come from the 18-byte record: a detached/invalid probe is
  `null` (absent), never 0 °F.
- Adjacent readings more than **90 s** apart break the line. `historySeriesSegments`
  is the single pure rule shared by the painter and the tests. The largest hole
  is also exposed as the chart's gap band.
- Offline with cache keeps the store's chart and the `Showing saved readings`
  label. Offline without cache yields empty series, even when the store still
  holds records in memory.
- When no batch has landed, History falls back to `BridgeContent` so the
  approved prototype/demo adapter still works in review builds; production uses
  `EmptyBridgeContent`, so there are no fixture values.

## Consequences

- T39–T41 replace the store rather than the screen: the controller/view-state
  seam and the `BridgeSyncSink` hand-off stay the same, and the store becomes the
  pre-archive source.
- Persistence across app restarts is explicitly not claimed in V0; the store is
  per controller/session. The durable archive owns that in M3.
- Only one gap band is labelled in V0; every hole still breaks the line. Multiple
  bands, cook detection and archive interactions belong to T42/T45.
