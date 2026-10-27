# ADR 0028 — bridge_state owns the clock anchor and publishes one seqlock snapshot

- **Status:** accepted
- **Date:** 2026-10-26
- **Task:** T20

## Context

Design 03 §3.8 fixes the clock fields but not how the anchor pair is stored or
how a reader sees the live snapshot while the sample pipeline updates it. The
board has no RTC, uptime resets on a power cycle, and `bridge_config` is the only
component allowed to open NVS. T21, T22, T24, T28 and T29 all consume parts of
this state.

## Decision

- **Split a pure core from the timer adapter.** `bridge_state.c` is plain C11
  over an injected monotonic millisecond source and the `bridge_config` typed
  clock API. `bridge_state_esp.c` installs `esp_timer_get_time()` and runs from
  the boot sequence after `bridge_config_init`.
- **Persist the `{unix_s, uptime_s}` pair, not just UTC.** `bridge_config` gains
  the additive `log/clock_uptime_s` key (u64, default 0). `clock_set_full()` /
  `clock_get_full()` replace nothing: the old getter/setter remain and report /
  store `uptime_s = 0`, so T15 callers and the factory-reset table keep working.
- **Restore as estimated, advance only when the uptime pair is trustworthy.**
  On boot the stored anchor is restored as `estimated = true`. Elapsed time is
  added when `now_uptime >= stored uptime` (the monotonic source survived a deep
  sleep) or when the platform supplies a known `elapsed_sleep_s`; after a power
  cycle with a reset timer, no interval is invented. An app `set_time` clears
  `estimated`.
- **One write per ten minutes.** `bridge_state_tick()` persists when due and
  retries a failed write after 60 s. The first app `set_time` writes the anchor
  immediately; later corrections inside the window keep the RAM clock and are
  persisted at the next cadence. `bridge_state_update()` never touches NVS.
- **Backward corrections are refused.** `set_time()` returns `ERR_TIME` when the
  requested UTC is earlier than the current clock. `stamp_record()` also clamps
  to the previous record timestamp as a belt-and-braces guard, so no record can
  be placed before an earlier one. Unknown time writes `unix_s = 0` and clears
  the clock-valid flag.
- **The snapshot is a copy, not a pointer.** Writers publish under a C11
  sequence lock; readers retry, so UI/BLE never sees a torn set of temperatures
  or flags. `age_s`, the 90 s `SMOKE_LIVE` bit and the clock-valid bit are
  computed at read time; temperatures, sequence, billows state, battery and RSSI
  are stored on `bridge_state_update()`.

## Consequences

- T21 must call `bridge_state_update()` for every accepted state packet and
  `bridge_state_stamp_record()` before appending the record. It should call
  `bridge_state_tick()` from the writer or housekeeping path; until T24 owns the
  housekeeping loop, no periodic caller exists on the board.
- T24 calls `bridge_state_set_battery()`; T28/T29 read `bridge_state_snapshot()`
  and `bridge_state_now()`. T29's `set_time` maps `unix_ms / 1000` UTC seconds
  into `bridge_state_set_time()`; `tz_offset_min` is not stored (the bridge is
  UTC-only).
- T27's storage/display/sync flags use the dedicated setters, not direct struct
  writes. NVS writes stay serialized on the single housekeeping/setter path;
  the core assumes one writer per field.
- Deep-sleep off-time remains unknown to the current adapter (`elapsed_sleep_s
  = 0`). A future RTC-backed uptime source can use the persisted pair without a
  schema change.
