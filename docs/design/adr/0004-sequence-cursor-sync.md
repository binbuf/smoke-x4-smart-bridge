# 0004 — Sequence-cursor sync, not time or session cursors

## Status

Accepted

## Context

The device has no battery-backed RTC and reboots, clock changes and ring wrap
must not make sync ambiguous. Time-based or session-based cursors would depend on
clock correctness and a session model the product does not have.

## Decision

The device owns a monotonic 24-bit `seq`; the app stores a high-water `seq` per
bridge. Sync is cursor-based in both directions, with `min_seq`/`max_seq`/
`generation` snapshots and an explicit gap status when a cursor falls outside the
ring. `generation` changes on a log clear and starts a new archive segment.

## Consequences

The app can resume after disconnect or relaunch without duplicates, and a ring
wrap or clear is unambiguous. Sync must handle generation changes, wrap and gaps
explicitly. Time is display metadata, not the sync cursor.
