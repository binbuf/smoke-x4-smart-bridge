# T31 — ble_service: sync status and recent records

## Goal
The bridge answers `sync_ctrl` status and serves up to 64 records in either direction as a framed START/RECORDS/END stream, so V0 can show the last 15 minutes of history. It works at both MTU 23 and MTU 247 without assuming one record per notification.

## Context (read first)
- [05 §5.7, §5.8](../design/05-ble-contract.md) — `sync_ctrl` fields, `sync_data` frame header, and reassembly rules.
- [04 §4.5](../design/04-data-and-storage.md) — logical START/RECORDS/END stream, record size, and sync semantics.
- [04 §4.1, §4.2](../design/04-data-and-storage.md) — 18-byte record and 30 s nominal cadence.
- Design: [05](../design/05-ble-contract.md), [04 §4.5](../design/04-data-and-storage.md).
- Verify tier: **H/B**. Board: **no / B**.
- Depends on T27, T18, and T19.

## Scope
- [x] Parse the fixed 10-byte `sync_ctrl` write: `ver`, `cmd` (0 status, 1 read, 2 cancel), `direction` (0 forward, 1 backward), `cursor_seq` u32, reserved, `max_records` u16.
- [x] Implement `cmd = 0` status: return a START/END pair with `count = 0`, plus the current generation and extent; `status = empty` when the log has no records.
- [x] Implement `cmd = 1` read in both directions for up to **64** records (`0` reads as `32`), with records emitted ascending by `seq`.
- [x] Implement `cmd = 2` cancel, allowed while a transfer is in flight.
- [x] Emit the framed `sync_data` stream: 4-byte frame header (`ver`, `frame_seq`, `flags` with START/END/ERROR, `len`) followed by payload.
- [x] Emit START (20 B), RECORDS (`count × 18` B), and END (13 B) exactly as 04 §4.5 defines.
- [x] Keep `len ≤ 240` and `len ≤ MTU − 3 − 4`; at MTU 23 that is 16 B, so the 20 B START spans two frames.
- [x] Snapshot `generation`, `min_seq`, and `max_seq` at START; records written during the transfer appear in the next request.
- [x] Allow only one record transfer at a time; a second status or cancel is allowed while busy, other reads are ignored.
- [x] Handle negotiated MTU 23 and MTU 247; never assume one notification per record and never require an ACK.
- [x] Add host tests: a split frame at MTU 23, a multi-frame batch at MTU 247, and a record split across frames.

## Out of scope
- Full cursor/gap/generation-change/resume logic and long backfill → T39 (M3).
- App-side cursor state, local database, two-phase sync, and gap storage → T40/T41.
- The V0 app sync sequence and reconnect catch-up → T35.
- Deletion, clearing, and history retention → T44/T48.
- `config`/`stats` → T47/T51 (M4).
- Wi-Fi/HTTP/OTA transfer paths — outside MVP; no task owns it.

## Design notes
- Record size is fixed at **18 bytes** (`seq` u24, `unix_s` u32, `temp[4]` i16, `flags` u8, `crc16`). `seq` is monotonic and survives reboots; the log is one continuous ring with no sessions.
- Frame header (05 §5.8): `ver` @0, `frame_seq` u8 wrapping @1, `flags` @2 (b0 START, b1 END, b2 ERROR), `len` @3. `len` is at most **240** and at most `MTU − 3 − 4`.
- START payload (20 B): `generation` u32 @0, `min_seq` @4, `max_seq` @8, `start_seq` @12 (first record in this response, or the next cursor if none), `count` u16 @16, `record_size = 18` @18, `status` @19.
- END payload (13 B): `status` @0, `next_seq` exclusive cursor @1, `min_seq` @5, `max_seq` @9.
- START/END status values: `0 ok`, `1 gap`, `2 error`, `3 busy`, `4 empty`.
- Backward returns the highest `count` records with `seq < cursor_seq` but emits them ascending; `next_seq = first_seq` so record `0` is still reachable. Forward returns `seq > cursor_seq` ascending and sets `next_seq = last_seq + 1`.
- Empty log: `status = empty`, `count = 0`, `min_seq = max_seq = 0xFFFFFFFF`; this is "nothing recorded yet", not a gap.
- No records in this direction: `count = 0`, `start_seq = cursor_seq`, END status `ok`; the client treats it as drained and switches to forward catch-up.
- V0 only needs the last 15 minutes (about 30 records at the 30 s cadence), so one `max_records` request can cover it. M3 extends the same stream with the full cursor/resume behaviour.
- The device does not remember a partial transfer; after a link drop the app resumes from its last fully stored record.
- `max_records = 64` is 1,152 B of records — roughly 6–7 notifications at MTU 247 and ~74 at MTU 23; the app should prefer 32 for predictable latency.

## Done when
- [x] A host test reassembles a START/record stream split across frames at MTU 23 (including the 20 B START spanning two frames).
- [x] A host test reassembles a multi-frame batch at MTU 247.
- [x] A record split across frame boundaries is reassembled correctly, and non-contiguous `frame_seq` is detectable by the client.
- [x] `cmd = 0` returns generation/extent and `empty` for an empty log.
- [x] A backward request returns records ascending, and the app can read the last 15 minutes in one request.
- [x] Hand-off below filled in

## Hand-off

Implemented. `ble_sync.h`/`ble_sync.c` are the pure C11 seam (exact 10 B
`sync_ctrl` parse, busy plan, START/RECORDS/END builder over `get_extent` +
`read_record` callbacks, and the MTU-bounded framer). `ble_service.c` binds the
callbacks to `sample_log_get_info` / `sample_log_read_seq`, routes `sync_ctrl`,
tracks the `sync_data` CCCD, and pumps one frame per 15 ms one-shot timer tick
so `status`/`cancel` can land mid-transfer. `sync_active` is raised for the
duration. ADR 0038 records the seam; design 04 §4.5 and 05 §5.7/5.8 are updated.

Deviations:
- Forward requests clamp to `min_seq` without a `gap` status; full gap/resume
  logic stays in T39 as scoped.
- A record read failure truncates the batch before the bad record and sets the
  START/END `status = error` (ERROR flag on the final frame). No hole is ever
  emitted.
- `frame_seq` restarts at 0 per response. A status response sent during a read
  is therefore a fresh response identified by its START flag; the client must
  reset its reassembly on START.
- Writes with `len != 10` return `ATT Invalid Attribute Value Length`; malformed
  `ver`/`cmd`/`direction` are silently ignored (no state change).
- `max_records` above 64 clamps to 64 (0 still reads as 32).

Checks:
- `ctest --test-dir firmware/test/build --output-on-failure` → 100%, 21/21
  (new `ble-sync` suite covers split START at MTU 23, 3-frame MTU 247 batch,
  75-frame 64-record batch, split records, dropped `frame_seq`, empty status,
  backward ascending last-15-min, forward, error truncation and buffer refusal).
- ESP-IDF 6.0.2 build → `Project build complete`; image guard ok (84 components,
  no Wi-Fi/lwIP/netif, no HTTP/OTA); `sx4_bridge.bin` 0x91470 B, 72% free.

Next: T35/T39 must subscribe to `sync_data` before the first read, treat any
START as a reassembly reset, and re-request on a `frame_seq` hole. T39 extends
the same builder with gap/generation/resume rather than adding a second stream.
Board/phone verification (real notification pacing, cancel latency) is T37.

