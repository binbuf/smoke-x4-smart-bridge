# ADR 0049 — Counted explicit deletion over two separate copies

**Status:** Accepted (T44)

## Context

T36 rendered the approved History & storage shell with simulated counts. T40
added the durable `sample`/`gap` archive and `deleteRange`; T41 added cursors for
the current generation. T44 must show the phone and Bridge copies truthfully and
delete either one only after an explicit, counted confirmation. Generation
changes, launches and low storage must never delete anything.

## Decision

- `HistoryDeletionService` (`app/lib/data/history/history_deletion.dart`) is the
  only phone-deletion path. It builds a half-open plan (`now - 30/90 days` or all
  readings), counts it, and records the actual first/last reading in the plan.
  The UI shows that count and span, then passes the same plan to `delete`; a
  later clock tick cannot widen the loss.
- A reading exactly on the 30/90-day cutoff is kept. The phone copy spans every
  saved Bridge and generation; no Bridge-side value is merged into it.
- An empty plan is named (`No readings in this range`) and never calls
  `deleteRange`. There is no timer, background sweep or automatic cleanup.
- `deleteRange` removes or trims `gap` rows inside the deleted date/sequence
  extent. The right-trim path updates the gap in place so a kept tail is not
  swept away by the same transaction.
- After deletion the current generation's cursors are recomputed from its
  remaining rows; if it has none, both are cleared. Older generations stay
  readable. `historyRevision` is bumped so History reloads.
- History & storage reads Bridge `stats` (records, capacity, oldest/newest,
  generation) over the encrypted characteristic. Missing figures render `—`;
  they are never substituted from the phone archive.
- Bridge clear keeps its existing explicit confirmation and keeps phone history.
  The actual `clear_history` command/generation state machine stays T49/T52;
  T44 only owns the separate-copy outcome and copy.

## Consequences

- Deletion always has a stable, user-visible count and range. A failed or empty
  plan is a no-op.
- Storage used is an estimate (72 B per reading, the 04 §4.9 midpoint), not a
  file-size query; it is observation only.
- Bridge stats can lag by one 30 s quiet sync. A confirmed clear resets the
  displayed Bridge figures locally; the next device outcome is owned by T49.
- Widget tests use a fake DAO; boundary and gap/cursor behaviour is proved
  against the real in-memory SQLite DAO.
