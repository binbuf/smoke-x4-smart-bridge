# T41 — app: repository and two-phase sync

## Goal
Build the repository that turns raw BLE sync batches into a durable, resumable local archive: recent readings first, older readings in the background, then forward catch-up. This is what lets History work immediately after pairing and survive disconnects, relaunches, ring rotation, and generation changes without duplicates.

## Context (read first)
- Design: [04 §4.5](../design/04-data-and-storage.md), [04 §4.6](../design/04-data-and-storage.md)
- Verification: **H/P** (host/CI plus phone) · Board required: **no / phone**
- Depends on T40, T39, and T35.
- The device contract is [05 §5.7, §5.8, §5.10](../design/05-ble-contract.md); the local schema is [04 §4.7](../design/04-data-and-storage.md).
- **Post-T36 status:** `BridgeLink` already runs a quiet forward sync every
  30 s from `localMaxSeq` and appends live notifications to the in-memory
  `RecentHistoryStore`. T41 replaces that store and cursor with the durable
  repository; keep one timer and one live-append path, do not add a second
  cadence.

## Scope
- [ ] Read `stats` and/or issue `sync_ctrl cmd = 0` to learn `generation`, `min_seq`, `max_seq`, and storage state.
- [ ] Implement backward recent-first sync for the last 24 h (2,880 records) before anything else.
- [ ] Implement background backward backfill to `min_seq` at lower priority.
- [ ] Implement forward catch-up from the local maximum `seq`.
- [ ] Use one transaction per request/batch and resume at the last fully stored `seq`.
- [ ] On a generation change, keep old data and start a new local segment with fresh cursors.
- [ ] On a gap, store it with its reason, reset the cursor, and continue from the device extent.
- [ ] Add a sync status model with `idle`, `syncing`, `partial`, `complete`, and `error`.
- [ ] Add tests for every sync branch, including zero-record termination and `seq 0`.
- [ ] Append live notifications by `seq` as they arrive.

## Out of scope
- History chart, Summary, Cooks, and their empty states — owned by T42 and T45.
- Connection health, stale/offline UI, reconnect backoff, and pull-to-refresh — owned by T43.
- History & storage deletion and confirmation UI — owned by T44.
- Firmware sync engine and gap detection on the device — owned by T39.
- BLE transport, scan, bond, and link procedures — owned by T32/T33/T35.
- Settings and device actions — M4 (T47–T55).
- Billows — M5 (T56–T60).
- Server/cloud sync and export/share — outside MVP; no task owns them.
- Automatic deletion — outside MVP; no task owns it.

## Design notes
- `cursor_after` is the highest contiguous `seq` stored locally; `cursor_before` is the lowest contiguous `seq`; both are `NULL` until the first data. `device_min_seq`/`device_max_seq` are `NULL` when the bridge log is empty.
- First sync: if the app has no data for this generation, request backward from `max_seq + 1` with `max_records = 32` until 2,880 records (24 h) are stored, then continue backward to `min_seq` in the background.
- Backward `next_seq = first_seq` is exclusive, so record `0` is reachable. Never treat `next_seq = 0` as a stop sentinel; stop only on `count = 0`.
- Empty log: `status = empty`, `min_seq = max_seq = 0xFFFFFFFF`. Show nothing recorded yet; do not create a gap.
- Forward catch-up starts from the local maximum `seq`, not from `max_seq + 1`. If the forward cursor is outside the ring, the device returns `status = gap` and the repository stores the missing range before continuing from `min_seq`.
- One transfer at a time. Send the next request only after END. Verify contiguous `frame_seq`; a missing frame discards the partial batch and re-requests it, never storing a stream with a hole.
- If the link drops, resume from the last fully stored record. The device does not remember a partial transfer.
- Key stored records by `(bridge_id, generation, seq)`: the same record arriving twice is a no-op. A generation change is an epoch boundary, not a delete, and the old rows stay readable.
- Gap reasons follow [04 §4.6](../design/04-data-and-storage.md): `No signal`, `Bridge off`, `Not synced`. Do not invent a reason.
- Map unknown device time to `unix_s = NULL`, `time_estimated = 1`, and the estimate in [04 §4.7](../design/04-data-and-storage.md). Never write an estimated time as exact.
- Product status copy while syncing is `Syncing saved readings` for the recent pass and `Loading saved readings` for background backfill; `backfill` is internal only.
- Every 30 s while connected, run a quiet forward catch-up; on reconnect, run it
  before enabling live display. The 30 s pass must not show the sync card, but
  must update `lastSyncedAt` and the stored cursor. This replaces the V0
  15-minute recent window with the durable recent-first path.

## Done when
- [ ] A fake device with a 30-day ring syncs recent-first, then backfills.
- [ ] A seeded 338,400-record ring (host) completes and resumes without duplicates.
- [ ] A disconnect mid-batch resumes without duplicates.
- [ ] A log whose first record is `seq 0` is fully fetched; the backward cursor is exclusive, not a stop sentinel.
- [ ] Repository tests cover every sync status branch and `flutter test` passes.
- [ ] `flutter analyze` passes.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
