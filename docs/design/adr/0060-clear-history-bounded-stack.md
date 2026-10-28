# 0060 — Clear-history scanning is bounded-stack

**Status:** accepted (T55)

## Context

`log_flash_core.c` erases a raw `samples` ring by reading each 4 KB sector and
skipping blank ones, so a power cut mid-clear resumes instead of restarting.
The original implementation used `uint8_t buf[SAMPLE_LOG_SECTOR_SIZE]`.

Clear-history runs from the reply-first `esp_timer` action callback
(`CONFIG_ESP_TIMER_TASK_STACK_SIZE = 3584`), and pending-clear recovery runs on
the main task (`CONFIG_ESP_MAIN_TASK_STACK_SIZE = 3584`). A 4096-byte array
overflows both. The T55 bench first clear crashed with
`InstrFetchProhibited` (PC `0x1000`); every following boot repeated the
overflow, because `clear_pending` sent the same sweep through the main task.
The unit host tests passed: they run on a large host stack and cannot see this
class of fault.

## Decision

1. Scan a sector in `CLEAR_SCAN_CHUNK` (256 B) reads. The IDF adapter's
   one-sector cache means only the first chunk is a flash read.
2. Keep the sweep inside `log_flash_core.c` and the `log_io` seam; no heap
   allocation and no new platform API.
3. Treat this as a stack-budget rule for the whole sample-log path: clear,
   pending-clear recovery and any future whole-ring walk must fit in the 3.5 KB
   timer/main stacks. A sector-sized stack buffer is not allowed.
4. The real-bridge retest (clear, mid-action kill, reboot after clear) is the
   regression gate, because the host suite cannot detect stack overflow by
   construction.

## Consequences

- Clear takes the same number of sector reads/erases; only the per-read buffer
  shrinks. The T55 retest cleared ~2,500 records and started a new log at
  `seq=0` without a panic.
- `erase_nonblank_sectors()` is now a thin loop over `sector_is_blank()`; host
  tests keep covering partial-clear resume and erase-failure handling.
- Do not raise `CLEAR_SCAN_CHUNK` back toward 4 KB, and do not move the sweep to
  a larger stack without updating this ADR and the task-budget table.
