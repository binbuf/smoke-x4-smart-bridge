# T46 run notes — 2026-10-27

Chronological raw notes; the committed report is `docs/progress/T46.md`.

## Build / preflight (14:08–14:12 PDT)

- Board uptime 2 h 53 m, `seq 587..590`, RSSI −29 dBm before reflash.
- FIRMWARE: rebuilt ESP-IDF 6.0.2, `sx4_bridge.bin` SHA-256
  `B3126D95A431376705D8A344224D06F337B7EEBBFD67ACDA41D0ED1BD8289040`,
  0x91a00 bytes. Flashed app+bootloader+partition only; `samples` and NVS kept.
- Boot recovery: `gen 081936f6, seq 0..590, next 591, 591 records, state OK`
  in 905 ms → `01-post-flash-boot.log`.
- APP: debug APK SHA-256
  `AF53E0FB5CE4F2D17175236EBFC50E627D5960CFD09707F321A8144FFE7170CC`,
  installed 14:12:02, version 0.1.0. Pixel 11 Pro Fold, Android 17 / API 37.
- Old app DB was schema v1 (12,288 B, no saved Bridge) → first launch entered
  Setup, as expected. Paired to the existing OS bond without a code prompt;
  first sync stored `seq 0..596` (597 rows, no duplicates).
- `05-db-copy.db`: 597 records, generation 135870198 (0x081936f6),
  recorded span 2026-10-27 08:45:17 → 14:13:59 = **5.478 h**;
  cursors 596/0, device 0..596, no gaps.
- MTU **247**, protocol 1.0, firmware 0.1.0, phone bond count 1/4
  → `06-technical-details-scrolled.png/.xml`.

## History with real data

- Default 24 h / all probes: four series, Summary, Cooks in progress
  9:17 AM–2:15 PM, 4 h 58 m, four probes → `07-history-default.png`,
  `07-history-scrolled.png`.
- Cook view: app bar `Cook`, `Recorded history`, end 2:16 PM (not `Now`);
  back preserved the History scroll/range → `08-cook-view.png`,
  `08-cook-back-history.png`.
- Ranges: Last hour / Last 6 hours / Last 2 days captured (`09-range-*.png`).
- Custom range sheet: starts at all saved history, `5 hours, 32 minutes of
  history`, Start/End, quick picks, Cancel/Apply → `09-custom-range.png`.
  Cancel preserved the prior range; `Last 6 hours` + Apply set chip `Custom`.
- Probe filter: P2 single series, area fill, `Reset filters` appears only with
  an active filter → `10-probe-p2.png`.
- Full-screen chart, chart help (gap and estimated explanations), Summary sort
  (Probe order/Hottest/Highest/Latest reading/Since cook start)
  → `11-*.png`, `13-summary-*.png`.
- Real gaps in the 5.5 h capture: intervals >90 s at seq 4→9 (1814 s),
  49→55 (182 s), 265→266 (505 s), 589→596 (242 s). The chart draws all four
  bands; the 30-min hole after seq 4 is the wide left band in P2.

## Saved-Bridge cold launch, in range

- Force-stop → launcher: no Setup and no OS passkey prompt; Live in under
  2.5 s, Bridge Connected → `15-cold-launch-700.png` (Flutter splash),
  `15-cold-launch-2500.png` (Live).
- History after cold launch has the full archive (24 h / all probes)
  → `15-cold-launch-history.png`.
- Probe tile → History opened `1 hour` + that probe, as approved
  → `16-probe-tile-history.png`.

## Saved-Bridge absent / out of range

- Bridge held in reset (RTS→EN low; same scan outcome as out of range).
- Cold launch: no Setup, no passkey; `Looking for the Bridge…`, last-known
  Live, values dim, History still usable; manual `Connect` appears after 10 s
  → `17-cold-launch-absent-3s.*`, `17-cold-launch-absent-13s.*`.
- **Finding A (T43/T45/T54):** while offline the probe-tile semantics still say
  “updated live” even though the values are last-known/dim.
- **Finding B (T34/T42/T46):** Live sparklines show `No history yet` after a
  cold launch even though the durable archive has 5.5 h; the Live tiles use
  the in-memory recent store, not the archive.
- **Finding C (T43/T45/T54):** the saved-Bridge details header shows the
  fixture default `Bridge A4F2` while offline; it returns to `Bridge 8276`
  after connecting. `BridgeController.deviceId = 'A4F2'` is the default.
- Manual Connect after the Bridge returned: connected in ~2 s, no prompt,
  details returned to `Bridge 8276` → `17-manual-connect-recovered.*`,
  `17-bridge-details-online.xml`.

## Mid-sync disconnect and resume

- Cleared local `sample` rows and both cursors; kept the saved `bridge` row.
- Launch sync wrote 3 × 32-record pages (609 B frames), then Bluetooth was
  disabled → `18-midsync-bt-off.*`.
- Partial DB: 96 rows, `seq 532..627`, `cursor_after=627`,
  `cursor_before=532`, device 0..627, no duplicates → `18-partial.db`.
- **Finding D (T43/T45):** with Bluetooth off/blocked the sync card stays at
  `Syncing saved readings` ~10 %; the blocked state and the sync card are
  shown at the same time.
- Bluetooth on: reconnect + resume filled `seq 0..628`; final DB 629 rows,
  `count(distinct seq)=629`, cursors 628/0, no gaps, no duplicates
  → `18-resumed.db`, `18-resume-10s.*`.

## Quiet 30 s forward sync

- `sync transfer ended` pairs in `serial-main.log` are 30.0–31.0 s apart for
  the steady-state window (14:20:22…14:25:32); the 141 s outlier is the
  deliberate board reset. Drained status frames are 51 B; one-record passes
  are 33 B. No sync card on Live.

## 30-minute absence

- App force-stopped 14:31:26 PDT; local max `seq 628`, device at `seq 629`.
- Pending: relaunch after ≥31 min and verify forward catch-up only.

## Host full-ring fixture

- `flutter test test/archive_sync_test.dart --plain-name
  "a seeded 338,400-record ring completes and resumes without duplicates"`:
  test body `00:07`, wall 10.5 s including Flutter startup; 338,400 records,
  mid-ring resume, no duplicates.

## Seeded phone archive (for the remaining History states)

- `artifacts/bench/T46/seeded-phone.db`: 335,049 rows, 44.96 MB,
  full ring 338,400 seq extent, generation 42.
  - 1-day `Yesterday` hole (`Bridge off`) → empty-range state.
  - 3-hour `Not synced` gap 6 h ago → overwritten-before-sync label at 24 h.
  - Last hour contains only a 5-min estimated block (11 rows); P3 is NULL in
    the last hour → estimated + no-cook + empty-filtered-probe states.
  - Older than 30 days: **251,999** rows; deleting that scope should leave
    83,050 rows.
- `artifacts/bench/T46/empty-phone.db`: same schema/identity, zero rows,
  NULL cursors → `No readings yet`.

## Follow-up run 16:11-17:14 PDT

- X4 base switched off 16:21:05; Live showed Signal lost at 9:30/10:00 and
  auto-opened the amber Smoke X4 signal lost dialog at 16:31:40 (10 min 30 s).
  Captured at physical size and 320 dp (32-x4-dialog-*).
- Clean 10.0 min absence 16:48:45-16:58:45: 835 -> 856 rows, 21 records in one
  411 B forward frame, no duplicates (33-absence10-*).
- Bench-level clear: backed up and erased the samples partition (6,160,384 B,
  SHA-256 A79190FB...B881D9). The reboot reused generation 135870198 because the
  generation is NVS-owned; the app kept all 874 rows and started no new segment.
  Partition restored; boot read gen 081936f6, seq 0..874, 875 records, state OK.
  Evidence 34-*; finding L routed to T48/T49/T52.
- Final phone archive after restore/catch-up: 877 rows, seq 0..876.
