# ADR 0029 — The sample pipeline publishes the snapshot after the log append

- **Status:** accepted
- **Date:** 2026-10-26
- **Task:** T21

## Context

Design 03 §3.6 shows `sample_pipe` branching to the live snapshot, the log
queue and (later) BLE, but the ring assigns the record sequence only when the
log writer appends. The live snapshot carries that sequence for sync and for
the app's `live` view. Two bounded queues exist on the path (radio seam and
sample→writer), and a full queue must never block the radio or the writer. The
UI must be marked dirty only after a new snapshot exists.

## Decision

- **One parser, one record builder.** `sample_pipe.c` consumes the raw radio
  seam, calls `sx_protocol_parse_state()` with the persisted ID, and builds the
  18-byte record and the snapshot sample from the same canonical values. It
  validates the record with `sample_log_record_validate()` before queueing.
  Detached probes are forced to `SX4_TEMP_DETACHED` even though the parser
  already does so.
- **The sample task never waits for flash.** The queue to `log_writer` is a
  static FreeRTOS queue of fixed size 8. Enqueue is zero-tick; false means
  `dropped_samples++` and the sample is dropped. The dropped sample publishes
  no snapshot, so a later FIFO completion cannot replace newer live values with
  older ones.
- **Snapshot publication happens at append completion.** `log_writer` calls
  `sample_pipe_complete()` after `sample_log_append()`: set the sequence, call
  `bridge_state_update()`, then `ui_mark_dirty()`. A failed append publishes the
  live values with the previous sequence and counts `log_write_failures`, so the
  UI still shows live data in `READ_ONLY`. The writer also calls
  `bridge_state_tick()` after a successful append until T24 owns the periodic
  clock cadence.
- **Probe learning is idempotent.** When the loaded pairing's `num_probes`
  differs from the first parsed state frame, the pipeline calls a
  `save_probe_count` callback that rewrites the full `bridge_config` pairing.
  The T16 FSM normally persists the same value; the pipeline does not depend on
  that ordering.
- **Counters have one owner per field.** Sample/parse/foreign/sync/drop counts
  live in `sample_pipe`; CRC/header and ACK-attempt counters come from
  `sx_protocol`, which already has a single writer. `last_packet_age_s` is
  derived from the monotonic clock at read time.

## Consequences

- T22 consumes `ui_dirty_take()`; it renders the snapshot, never the queue.
- T24/T27 can call `sample_pipe_counters()` for stats; they must not reset the
  parser counters mid-run.
- T27 adds the BLE enqueue as a second branch in the writer or the sample task;
  it must remain best-effort and must not make recording depend on a link.
- The board gate (real packet reaching ring and snapshot) is deferred to T37;
  the host replay of `x4-t10-25min.loralog` (41 records) is the current gate.
