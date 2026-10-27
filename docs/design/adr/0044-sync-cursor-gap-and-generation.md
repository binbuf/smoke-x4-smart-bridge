# 0044 — Sync cursors report gaps on the live edge and snapshot one generation

**Status:** Accepted (T39, 2026-10-27)

## Context

T31 built the framed START/RECORDS/END sync stream and clamped a forward cursor
below `min_seq` silently. A reinstalled app, a rotated ring, or a long absence
then looked like continuous data even when the device had discarded records.
The app also needs an unambiguous terminator for each direction so a recent-first
30-day sync can continue into a full backfill without duplicates or a stop
sentinel colliding with the valid `seq = 0`.

The wire format is fixed by design 04 §4.5: START is 20 B (generation, min,
max, start, count, record size, status) and END is 13 B (status, next_seq, min,
max). There is no `generation` field in END.

## Decision

- Extent is snapshotted exactly once, before the first record read. `generation`,
  `min_seq`, and `max_seq` in START and `min_seq`/`max_seq` in END all come from
  that snapshot; records written during the transfer appear in the next request.
  `generation` is reported in START only because END has no field for it. The
  device keeps no cross-request generation state; a changed generation is
  visible on the next START and the app starts a new segment.
- Forward reads (`seq > cursor`, lowest first) report `gap` iff
  `min_seq > 1 && cursor_seq < min_seq - 1`, then restart at `min_seq`. The
  `min_seq - 1` expression is never formed at zero, so `seq = 0` is a valid first
  record.
- Backward reads (highest `count` below the cursor, emitted ascending) report
  `gap` iff `cursor_seq > max_seq + 1`, computed in 64 bits, then restart at
  `max_seq + 1`. `next_seq = first_seq` is an exclusive cursor; `0` is a cursor,
  not a stop sentinel.
- A drained direction returns `count = 0`, `start_seq = next_seq = cursor_seq`,
  `status = ok`. An empty whole log returns `status = empty`,
  `min_seq = max_seq = 0xFFFFFFFF`. `max_records` is normalised to 1..64
  (0 → 32) in both the parser and the builder.
- `next_seq` advances to the next record only on `ok` and `gap`. On `error` it
  stays at the request cursor so the app re-requests the truncated batch.
- Gap/terminator logic stays in the pure builder. The paced `sync_data` pump and
  the separate `ble_tx` live queue are unchanged, so a sync transfer never holds
  up live notifications.

## Consequences

- The app distinguishes `ok`, `gap`, `error`, `busy`, `empty`, and a drained
  `count = 0` direction without a wire change or an ACK.
- Host tests cover both gap edges, `min_seq = 0`, a full backward backfill to
  `seq 0`, a generation change with records written mid-transfer, `frame_seq`
  wrap, and a disconnect mid-batch with a clean re-request.
- A future wire revision that wants generation in END must bump the protocol
  version and regenerate both codecs; T39 deliberately does not extend the
  fixed 13 B END.
