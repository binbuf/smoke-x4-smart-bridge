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
- [ ] Cold-launch with the saved Bridge in range: confirm no setup screen,
      no passkey prompt, and automatic Live + History.
- [ ] Cold-launch with the saved Bridge out of range: confirm last-known Live,
      `Looking for the Bridge…` and a manual Connect after 10 s.
- [ ] Disconnect mid-sync, reconnect, and confirm resume.
- [ ] Let the Bridge record while the phone is away for 30+ minutes, then reconnect and confirm catch-up.
- [ ] Confirm the quiet 30 s forward sync keeps History current without
      duplicating rows and without showing the sync card.
- [ ] Delete older than 30 days on a seeded database and confirm only the intended range is removed.
- [ ] Force a Bridge clear/factory reset and confirm the app keeps old data and starts a new segment.
- [ ] Walk the History states in 13 §13.4: ranges, custom range, filters, gaps, estimated, overwritten, empty, offline cache, Cooks, and the Cook view.
- [ ] Check 320 dp, dark/light, and screen-reader output on the target phone.
- [ ] Re-check the post-T36 connection chain, X4 warning dialog and Live
      change window at 320 dp.
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
- [ ] A cold launch with the saved Bridge reaches Live without Setup, and an
      absent Bridge leaves the user on last-known Live with a manual Connect.
- [ ] Timing for 24 h and full-ring sync is recorded, with the negotiated MTU noted.
- [ ] The History UI matches the approved contract in both themes.
- [ ] Hand-off below filled in.

## Hand-off

Report: [docs/progress/T46.md](../progress/T46.md). Evidence manifest:
[artifacts/bench/T46/README.md](../../artifacts/bench/T46/README.md).

- Real 6.43 h / 696-record archive on the Pixel 11 Pro Fold; saved-Bridge cold
  launch with no Setup/passkey, absent-Bridge last-known + manual Connect,
  mid-sync resume (96 → 629 rows, no duplicates), quiet 30 s sync, and a 9.7 min
  forward catch-up (one 411 B frame, not a re-read). MTU 247.
- Seeded 117-day archive walked every 13 §13.4 History state; full-ring first
  paint 2.65 s; 30-day deletion removed 252,023 rows and left 82,426.
- **Blocked, not waived:** real clear/factory reset (T48/T49/T52), a true 30+
  minute absence and a true 24 h radio transfer (T61/T55), and the amber
  paired-lost X4 dialog (T54/T55). The owner shortened the absence window.
- **Findings routed:** offline probe tiles say “updated live” (A), Live
  sparklines do not backfill from the archive (B), offline header leaks the
  `A4F2` fixture ID (C), the sync card stays up while Bluetooth is blocked (D),
  Bridge `stats` shows 0 of 0 (E), gap bands use `detected_ms` and the
  `Not synced` label did not render (F), full-ring Cooks/sort are archive-wide
  (G), a Bridge reboot can leave a stale Connected state (H), 320 dp truncates
  labels (I), the permanent-loss banner is archive-wide (J), and the 1 min
  Live change window reverted to 5 min after relaunch (K).
- Phone left on the real archive, physical 1080×2342, theme System, 5 min Live
  change window, TalkBack disabled.
