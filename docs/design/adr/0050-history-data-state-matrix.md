# 0050 — History/data failure states use approved copy, one action, no invented values

**Status:** Accepted (T45)

## Context

The V0 screens already rendered the no-history, no-history-in-range,
offline-with-cache, offline-without-cache, no-X4, sync-failure and
storage-failure states. T37 found two gaps: after the reconnect budget expired
the History banner said `Can’t reach the Bridge` even while the cached chart was
visible, and several failure surfaces had no next action. The no-probe-data,
no-probes and protocol-mismatch rows also needed explicit coverage.

## Decision

- A History/data failure is one of a closed set of named states. Each renders
  the approved [06 §6.8](../06-app.md#68-error-and-empty-states) copy and one
  next action; raw exceptions, stack traces and platform strings never render.
- Cached data changes the failure's name: a failed or offline link with saved
  readings says `Showing saved readings · last reading …` on Live and
  `Showing saved readings` / `Last reading …` in the History banner. Only a
  failure with no cached rows says `Can’t reach the Bridge`.
- `Bridge disconnected · nothing saved yet` is the Live notice for an offline
  phone with no archive. Probe values are `—` in that state; the Billows
  set-point may still show as last known because it is not a probe reading.
- A filtered probe with no readings in the window is the probe-specific
  in-range state: no chart line, `No data`/`—` in Summary, and `Show all probes`.
  A whole window with no saved reading at all keeps the honest
  `Show all saved history` action; `Show all probes` cannot recover an empty
  range.
- `No probes connected` has the `Bridge details` action. The no-X4 state stays
  a single amber X4-node warning whose dialog uses `No data from Smoke X4` and
  `Pairing steps`; it never implies the Bridge link is offline.
- Protocol-major mismatch remains the Setup-owned page
  (`Update the app to use this Bridge`, `Update app`, saved history + learn
  more); it is asserted in the T45 matrix rather than duplicated on Live.

## Consequences

- The state inventory in 06 §6.8 and 13 §13.4 is exhaustive and testable:
  `app/test/data_state_matrix_test.dart` drives every row.
- Future copy changes must update the approved table first; the matrix test
  asserts literal labels so a dead end or fake zero is caught.
- A future launch-time protocol mismatch on a saved Bridge needs a named
  surface (T50-era Settings/Bridge details or a launch composition task); today
  it resolves to the cached/offline path.
