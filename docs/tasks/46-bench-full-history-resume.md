# T46 — Bench: full history and resume

## Goal
Prove the complete history path on the real Bridge and target phone: full-ring sync timing, relaunch, mid-sync resume, catch-up after absence, explicit deletion, generation boundaries, and the entire approved History state matrix. This is the M3 bench evidence that the archive is complete and honest.

## Context (read first)
- Design: [10 §10.3 B3](../design/10-test-and-release.md)
- Verification: **P** (phone plus board) · Board required: **yes**
- Depends on T42, T43, T44, and T39.
- Bring the M3 implementation plus the seeded 338,400-record host fixture; the UI contract is [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory).

## Scope
- [ ] Record at least 2 h of data on the real Bridge. Use the seeded 338,400-record host fixture for full-ring timing, or an accelerated test partition if the bench build supports one.
- [ ] Sync, close the app, reopen, and confirm no duplicates and the full History view.
- [ ] Disconnect mid-sync, reconnect, and confirm resume.
- [ ] Let the Bridge record while the phone is away for 30+ minutes, then reconnect and confirm catch-up.
- [ ] Delete older than 30 days on a seeded database and confirm only the intended range is removed.
- [ ] Force a Bridge clear/factory reset and confirm the app keeps old data and starts a new segment.
- [ ] Walk the History states in 13 §13.4: ranges, custom range, filters, gaps, estimated, overwritten, empty, offline cache, Cooks, and the Cook view.
- [ ] Check 320 dp, dark/light, and screen-reader output on the target phone.
- [ ] Record the negotiated MTU and the timing for 24 h sync and full-ring sync.
- [ ] Commit the History bench report and screenshots.

## Out of scope
- Fixing product behavior found during the walk — record the defect and route it to the owning task (T39–T45); this task is evidence.
- Settings, units, appearance, and device actions — M4 (T47–T55).
- Billows observation — M5 (T56–T60).
- 24 h soak, release builds, field cook, and final acceptance — M6 release hardening (T61–T67); the post-MVP passive RF survey is T68.
- Server/cloud sync and export/share — outside MVP; no task owns them.
- Automatic deletion — outside MVP; no task owns it.

## Design notes
- Bench values from [04 §4.1, §4.9](../design/04-data-and-storage.md): 30 s nominal cadence, 2,880 readings/day, 86,400 readings/30 days, 338,400 readings/full ring (6,160,384 B). A 24 h sync is about 52 KB raw; the full ring is about 6.09 MB raw.
- Use the real Bridge and target phone for steps 2–8. Use the seeded host fixture for the full-ring timing when the bench build does not support an accelerated partition.
- Record the timing for both 24 h and full-ring syncs, the negotiated MTU, the phone model/Android version, and the test partition used.
- For the mid-sync disconnect, disconnect after at least one stored batch; on reconnect the repository must resume from the last fully stored `seq` with no duplicates.
- For the 30+ minute absence, the reconnect path must use forward catch-up from the local max, not a full 24 h re-read.
- For the deletion step, verify the count and date range in the confirmation before accepting, then inspect the remaining local range.
- For the clear/factory-reset step, verify the old local segment is still readable and the new generation starts a new segment; phone history must not be deleted.
- Walk every History state with real data where possible; for overwritten-before-sync, use the seeded/gapped fixture if the ring cannot be rotated live.
- Dark/light screenshots and screen-reader output are required evidence, not optional notes.

## Done when
- [ ] The history report and screenshots are committed.
- [ ] Timing for 24 h and full-ring sync is recorded, with the negotiated MTU noted.
- [ ] The History UI matches the approved contract in both themes.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
