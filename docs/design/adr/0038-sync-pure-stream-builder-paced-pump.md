# 0038 — Sync is a pure stream builder plus a paced frame pump

**Status:** Accepted (T31, 2026-10-27)

## Context

The bridge must answer `sync_ctrl` status and serve up to 64 records as a
START/RECORDS/END byte stream carried in 4-byte framed `sync_data`
notifications. The same logical stream has to work at MTU 23 (16 payload bytes,
so the 20-byte START spans two frames and a record can straddle a boundary) and
at MTU 247 (240 payload bytes). NimBLE callbacks cannot be host-tested, a write
callback must not spend tens of milliseconds pushing 75 notifications, and
`cmd = 2` cancel has to be accepted while a transfer is in flight.

## Decision

- `ble_sync.c` is plain C11 and owns the fixed 10-byte `sync_ctrl` parser, the
  busy policy (`ble_sync_plan`), the logical START/RECORDS/END builder and the
  frame splitter. It reaches the ring only through
  `ble_sync_source_t` callbacks (`get_extent`, `read_record`) and uses no heap,
  ESP-IDF or globals.
- Backward requests take the highest `max_records` sequences below the cursor
  and emit them ascending; forward requests take the next ascending window.
  `next_seq` is the first emitted sequence for backward and last + 1 for
  forward. T39 added gap reporting and the drained/empty terminators on this
  same builder (ADR 0044).
- A record read failure ends the batch before the bad record, sets the START/END
  status to `error`, truncates `count`, and marks the last frame ERROR. A
  partial stream never contains a hole.
- The builder snapshots generation/min/max at START and never re-reads them.
- Frame boundaries are pure byte offsets: START is set on the first frame, END
  (and ERROR when the batch failed) on the last. `len = min(240, MTU - 3 - 4)`.
  `frame_seq` restarts at 0 for every response, so a status response sent while
  a record transfer is in flight is a new response the client recognises by its
  START flag.
- `ble_service.c` builds the next response on the first timer tick and sends one
  frame per 15 ms one-shot `esp_timer` tick. The GATT write callback only
  parses, plans and arms the timer, so a cancel or status write can land
  between frames. One read transfer at a time; reads while busy are ignored.
  A mutex serialises frame notifications; a status response holds it for its
  three frames so it never interleaves inside a record response.
- `bridge_state_set_sync_active()` is set when a read transfer starts and
  cleared on end, cancel, unsubscribe or disconnect.

## Consequences

- MTU 23/247 reassembly, split START, split records, dropped `frame_seq`,
  forward/backward cursors, empty log and error truncation are host-tested
  without NimBLE or a board.
- At MTU 23 a 64-record batch takes ~1.1 s (75 frames × 15 ms). The app should
  request 32 for predictable latency; no ACK is required.
- The firmware keeps one static `BLE_SYNC_STREAM_MAX` (1,185 B) buffer. A future
  larger batch needs a chunked builder rather than a bigger buffer.
- T39 extends the same builder with gap/generation/resume semantics; it must not
  add a second sync stream format or a second writer.
