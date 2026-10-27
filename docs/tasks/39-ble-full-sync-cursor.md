# T39 — ble_service: full sync cursor, gap, and generation

## Goal
Complete the firmware sync engine so the app can pull the whole ring in both directions, resume safely, and always know why a transfer ended. This makes a 30-day recent-first sync followed by a full backfill possible without ambiguous or duplicated data.

## Context (read first)
- Design: [04 §4.5, §4.6](../design/04-data-and-storage.md), [05 §5.7, §5.8](../design/05-ble-contract.md)
- Verification: **H/B** (host/CI plus bench/board) · Board required: **no / B**
- Depends on T31.
- Read [04 §4.3](../design/04-data-and-storage.md) for the generation and ring-rotation rules the cursor must respect.

## Scope
- [ ] Implement forward direction: return records with `seq > cursor_seq`, lowest first, with `next_seq = last_seq + 1`.
- [ ] Implement backward direction: return the highest `count` records with `seq < cursor_seq`, emitted in ascending `seq` order, with `next_seq = first_seq` as the exclusive cursor for the next backward request.
- [ ] Return `min_seq`, `max_seq`, and `generation` snapshots in both START and END payloads; snapshot them at START so records written during the transfer appear in the next request.
- [ ] Return `status = gap` when the cursor is outside the ring:
  - forward: `min_seq > 0` and `cursor_seq < min_seq - 1`, starting from `min_seq`;
  - backward: `cursor_seq > max_seq + 1`, starting from `max_seq + 1`.
- [ ] Never compute `min_seq - 1` when `min_seq = 0`; `seq = 0` is a valid first record.
- [ ] Implement the zero-record terminator: `count = 0`, `start_seq = cursor_seq`, END status `ok` when the direction is drained; an empty whole log returns `status = empty`, `count = 0`, `min_seq = max_seq = 0xFFFFFFFF`.
- [ ] Implement `sync_ctrl` `cmd = 0` (status), `cmd = 1` (read), and `cmd = 2` (cancel).
- [ ] Implement busy/cancel behavior: one transfer at a time; status and cancel are allowed while busy; other reads are ignored while busy.
- [ ] Enforce `max_records` in the range 1–64, with `0` reading as 32.
- [ ] Do not block live notifications during a sync transfer.
- [ ] Add host tests for wrap, gap, generation change, and a disconnect mid-batch.

## Out of scope
- App-side cursor persistence, two-phase sync, and resume — owned by T41.
- GATT service, advertising, passkey, and live notify — owned by T27/T28/T30.
- App History chart, Summary, and Cooks — owned by T42.
- History deletion and retention UI — owned by T44.
- Server/cloud sync and export/share — outside MVP; no task owns them.
- Alarms and phone notifications — outside MVP; no task owns them.
- Billows control — outside MVP; Billows is observation-only in T56–T60.

## Design notes
- The wire format is fixed by [04 §4.5](../design/04-data-and-storage.md) and [05 §5.7–§5.8](../design/05-ble-contract.md): START payload 20 B, `count × 18` B of records, END payload 13 B, carried in a framed notification stream with a 4 B frame header.
- Frame header: `ver = 1`, `frame_seq` wrapping 0–255, `flags` with b0 START, b1 END, b2 ERROR, and `len ≤ 240` and `≤ MTU − 3 − 4`. Records are always ascending in the payload, even for a backward request.
- Status values are `0 ok`, `1 gap`, `2 error`, `3 busy`, `4 empty`. The END payload carries the final status, `next_seq`, `min_seq`, and `max_seq`.
- A backward response with `count = 0` means the direction is drained; `next_seq = 0` is a cursor, not a stop sentinel. The app must still be able to fetch record `seq 0`.
- `generation` is a random 32-bit value, not a counter. It changes only on a deliberate clear or a wholly unusable log; never remap sequence numbers across generations, and never let a stale generation resurrect records.
- The device snapshots extent at START. A transfer is flow-controlled by the app sending the next `sync_ctrl` only after END; no ACK notification is needed.
- If the link drops, the device forgets the partial transfer. The app resumes from its last fully stored record.
- Use 32-record batches for predictable latency by default; 64 records is roughly 1,152 B of records.
- Keep the transfer cooperative so `live` notifications are never delayed behind a long read.

## Done when
- [ ] Host tests cover wrap, gap, generation change, and a disconnect mid-batch.
- [ ] The app can sync 30 days and then the rest of the ring.
- [ ] Every termination is unambiguous: `ok`, `gap`, `error`, `busy`, `empty`, and a drained `count = 0` direction.
- [ ] `ctest` passes for the host test build.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
