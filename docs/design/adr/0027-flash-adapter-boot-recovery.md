# ADR 0027 — The raw-partition adapter owns boot recovery and persistent READ_ONLY

- **Status:** accepted
- **Date:** 2026-10-26
- **Task:** T19

## Context

T18 left a pure ring over `log_io` plus an NVS generation owned by
`bridge_config`. T19 must bind it to the raw `samples` partition, recover before
the writer starts, finish an interrupted clear, measure the boot scan against the
~2 s budget, and make flash failures visible instead of pretending to record.

Two choices are not fixed by design 04: where the recovery policy lives, and
what a failed mount/append does to the rest of the boot.

## Decision

- **Split pure policy from the ESP-IDF adapter.** `log_flash_core.c` owns
  generation resolution, the pending-clear sweep, append/read routing and the
  storage state; it is plain C11 over `log_io` plus an NVS hook seam.
  `log_flash.c` only wraps `esp_partition_read/write/erase_range` and
  `bridge_config`; `sample_log.c` is the singleton. Host tests exercise the
  policy with a RAM partition.
- **Read once, header-first.** The adapter caches one 4 KB sector. Sector-header
  reads (32 bytes at a sector base) bypass the cache so mount's header pass does
  not pull every sector twice; the record pass then loads each sector once.
  Measured cold boot is 899 ms for all 1,504 sectors, so no newest-sector-only
  fast path is needed yet. Re-measure if the partition or scan grows.
- **Pending clear completes at boot.** When `clear_pending` is set, erase every
  non-blank sector, then call `finish_log_clear()`, then mount. Blank sectors are
  skipped, which is what makes an interrupted clear resumable. This is safe
  because the writer has not started, so no current-generation records exist.
  Steady-state generation changes without a pending clear stay lazy (ADR 0026).
- **Storage failure is terminal until reboot.** Any `esp_partition` or NVS hook
  failure sets `READ_ONLY` (`ready = false`, `storage_ok = 0`), and no append is
  reported successful. A failed torn-header repair read-back fails the mount;
  T19 does not erase-and-reclaim that sector implicitly.
- **NEAR_FULL is a writable diagnostic.** It is reported when the live count is
  within one sector of full capacity. Only `READ_ONLY` makes `storage_ok` false.

## Consequences

- A pending clear can spend seconds erasing at boot; the UI progress state
  (T48/T55) must tolerate `sample_log_init()` being slow. Normal boots scan only
  and stay under the budget.
- `bridge_config` must have loaded before `sample_log_init`; a failed NVS leaves
  the log READ_ONLY unless a sector header can restore the generation.
- One writer is assumed: the adapter and ring have no lock. T21 must keep all
  appends on the log-writer task.
- T27/T39 read `min_seq`/`max_seq`/`generation` from `sample_log_get_info()` and
  `storage_ok` from `sample_log_storage_ok()`; do not infer it from append
  return codes alone.
