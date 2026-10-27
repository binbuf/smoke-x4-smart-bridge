# T39 — ble_service: full sync cursor, gap, and generation

## Goal
Complete the firmware sync engine so the app can pull the whole ring in both directions, resume safely, and always know why a transfer ended. This makes a 30-day recent-first sync followed by a full backfill possible without ambiguous or duplicated data.

## Context (read first)
- Design: [04 §4.5, §4.6](../design/04-data-and-storage.md), [05 §5.7, §5.8](../design/05-ble-contract.md)
- Verification: **H/B** (host/CI plus bench/board) · Board required: **no / B**
- Depends on T31.
- Read [04 §4.3](../design/04-data-and-storage.md) for the generation and ring-rotation rules the cursor must respect.
- **Post-T36 status:** the SX1262 sync-word/TCXO fix now lets real X4 frames
  reach the ring (four frames at ~30 s cadence, stored and synced); T37 has the
  evidence. T39 still owns the full cursor, gap/generation and two-direction
  transfer; the real packets do not implement those.

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

**Landed.** `firmware/components/ble_service/ble_sync.c` now completes the sync
cursor semantics:

- forward window `seq > cursor` with `next_seq = last_seq + 1`; `gap` iff
  `min_seq > 1 && cursor < min_seq - 1`, restarting at `min_seq`;
- backward highest records below the cursor, emitted ascending, with
  `next_seq = first_seq`; `gap` iff `cursor > max_seq + 1`, restarting at
  `max_seq + 1` (64-bit arithmetic);
- drained direction `count = 0`, `start_seq = next_seq = cursor_seq`,
  `status = ok`; empty log `status = empty`, `count = 0`,
  `min_seq = max_seq = 0xFFFFFFFF`;
- one extent snapshot per response: `generation`/min/max in START and min/max in
  END; mid-transfer writes appear only in the next request;
- `next_seq` advances on `ok`/`gap`, stays at the request cursor on `error`;
- `max_records` normalised 1..64 (0 → 32) in the parser and the builder;
- `cmd` 0/1/2, busy/cancel policy and the separate live path are unchanged
  (status/cancel allowed while busy, other reads ignored).

Host tests add both gap edges, `min_seq = 0/1`, the last 24-bit seq without
overflow, a generation change with a mid-transfer write, `frame_seq` wrap, a
disconnect mid-batch followed by a clean re-request, a 90,000-record ring
covering 30 days then the rest down to `seq 0`, and builder max_records
normalisation.

**Deviation.** END is a fixed 13 B payload (status, next_seq, min_seq, max_seq)
and has no generation field, so generation is reported only in START; END
repeats the same snapshot's min/max. Adding a field would break the fixed wire
contract and the app codec. ADR 0044 records this and the rest of the cursor
rules.

**Checks.** Host: `ctest --test-dir firmware/test/build --output-on-failure` →
21/21 passed (ble-sync ~0.11 s). Firmware: ESP-IDF 6.0.2 Heltec build →
`Project build complete`, image guard ok, `sx4_bridge.bin` 0x91A00 bytes (72%
free). No board run (verification B deferred to T41/T55 as appropriate).

**Next task must know.** App-side persistence/resume is T41; it must stop on
`count = 0` (not `next_seq == 0`), treat `gap` as a permanent missed range,
reset cursors on a generation change, and re-request on `error`/frame holes.
Record sequences are 24-bit on the wire even though sync fields are u32. See
`docs/progress/T39.md` for gotchas and commands.
