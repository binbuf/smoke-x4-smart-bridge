# ADR 0048 — History reads the durable archive through one bounded read model

**Status:** Accepted (T42)

## Context

T36 mounted the approved History shell on `RecentHistoryStore`, which only held
the current Bluetooth session's last 15 minutes in memory. T40/T41 added the
durable `sample`/`gap` archive and the two-phase sync. T42 must render a 30-day,
four-series archive without handing tens of thousands of points to a painter,
and Summary/Cooks must agree with the recorded timestamps rather than with the
decimated chart shape.

## Decision

- `HistoryArchive` (`app/lib/data/history/history_archive.dart`) is the only
  read model for the History screen. It queries `SampleDao`; screens still render
  the immutable `HistoryViewState`.
- A range with at most 4,000 raw rows is read row-for-row. Longer ranges are
  grouped by `recorded_ms` in SQL (`bucketedSamplesInRange`) to about 1,200
  buckets, with per-probe `AVG` values that stay `NULL` when no valid reading
  existed. No zero is ever substituted.
- `decimateHistorySeries` applies LTTB to about 800 points per series and adds
  the minimum and maximum real point of each bucket. Explicit `NULL` points and
  intervals wider than the source tolerance break the line; a decimated fixture
  is marked so the painter does not reapply the raw 90 s rule to bucket spacing.
- Summary is exact: `probeStatsInRange` computes latest/min/max/count over raw
  rows, independent of the chart's decimation.
- Gap bands come from the `gap` table (`No signal`, `Bridge off`,
  `Not synced`) plus inferred `No signal` holes; `HistoryFixture.allGaps` carries
  all of them and the painter draws a labelled band per gap.
- Cooks are detected by `CookDetection` over 5-minute activity buckets covering
  the whole archive. A run ends after 30 minutes without readings, must last at
  least 10 minutes, and is marked `missing readings` when a device gap overlaps
  it or an internal hole exceeds 10 minutes. The newest cook is `In progress`
  while its last recorded reading is within 15 minutes of now.
- `HistoryViewLoader` asynchronously loads the archive and reloads on filter,
  units, sort, revision or offline-cache changes. A controller without a DAO
  (review builds, fixtures) keeps the synchronous path, so the approved shell is
  unchanged there.

## Consequences

- Chart memory and paint work are bounded by the point target, not by archive
  age; the 30-day test asserts the bound.
- Zooming a very long range cannot recover detail below the SQL bucket width.
  A later task may re-query on zoom if the product needs it.
- `T44` deletion must invalidate `HistoryArchive` reads naturally by changing
  rows; `historyRevision` is bumped only by committed sync batches, so deletion
  should bump it or rebuild the screen.
- Cooks are read-only derived data. No cook table is introduced; names, marks
  and user sessions remain out of scope.
