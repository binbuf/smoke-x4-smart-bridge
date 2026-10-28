# T55 bench evidence — all settings and actions

**Status:** partial pass, 2026-10-28 (continuation 1 adds the seeded History
recheck). Everything that can be driven from the phone/PC is recorded here. Two
release-blocking defects were found and fixed (clear-history stack overflow,
sentinel scan preview); the remaining physical gaps are listed under **Not
completed** and are owned by a follow-up T55 run.

Report: [`docs/progress/T55.md`](../../../docs/progress/T55.md).

## Run conditions

| Field | Value |
|---|---|
| Phone | Pixel 11 Pro Fold, Android 17 / API 37, `adb-67021FDDJ000CF-zWIo1k._adb-tls-connect._tcp` |
| App | `com.binbuf.smoke_bridge` 0.1.0, **release** APK SHA-256 `2E095C5343D0D7350B574EE376A9E7D59963571745363296026ABD6B1505F28C` |
| Board | Heltec WiFi LoRa 32 V3, MAC `ac:a7:04:38:82:76`, COM5 |
| Firmware before run | T46 image `B3126D95…8289040`, 603,408 B (T49 image was not yet flashed) |
| Firmware during run / final | T49 + T55 fix, SHA-256 `02E2E2B4DA3013E14E3AED57A2D5505417B5214C263F2C7F43009ED3340F61F6`, 603,472 B |
| Pre-run backups | `backup/nvs-0x9000.bin` `9C72805F…DF7B39`; `backup/samples-0x220000.bin` `73382EAF…72EBD1`; `backup/factory-0x20000-1m.bin` `092C9B5A…6B54` (binaries are local-only; hashes in `backup/SHA256SUMS.txt`) |
| Screen sizes | 390 dp (native) and 320 dp (`wm density 540`), dark and light |
| Final state on the board | X4 pairing, generation, log and phone bond restored from the backup; phone re-paired on the release image |

The webcam (`00-webcam-test2.jpg`) returns a black frame, so the OLED could not
be photographed. OLED evidence is the `config applied: units … timeout … name …`
serial line plus the app read-back; the panel itself was not readable in this
sitting.

## Evidence by acceptance item

| Item | Evidence | Result |
|---|---|---|
| Units read-back + OLED source | `03-units-celsius.*`, `04-units-fahrenheit.*`, `serial-session.log` (`config applied: units 0/1`) | pass (app/read-back); OLED not photographed |
| Appearance | `08-appearance.*`, `09-appearance-dark.*`, `10-settings-dark.*`, `11-appearance-light.*`, `12-settings-light.*`, `32*`, `33*` | pass, 390 and 320 dp |
| Live change window | `05-change-window-sheet.*`, `06-change-window-10min.*`, `07-live-10min.*`, footer `10m` | pass |
| Bridge name | `14-name-dialog.*`, `20-bridge-name-t55.*`, `config applied: … name T55 Bench`, name restored after relaunch/reboot (`22-*`, `26-*`) | pass (NVS restore later reverted the name; not a defect) |
| Screen timeout + copy | `18-timeout-sheet.*`, `19-timeout-30sec.*`, `config applied: … timeout 30/60 s`, row `30 sec · screen turns off` / `1 min · screen turns off` | pass read-back; OLED not photographed |
| Settings/Bridge details connected | `02-*`, `13-*`, `27*`–`31*`: one Bridge section, one History & storage row, one Sync now/Disconnect, no save-all, no `Device log`, no lab entry in release | pass |
| Settings/Bridge details offline | `38-settings-offline.*`, `39-bridge-details-offline.*`, `40-bridge-actions-offline.*`: one banner, Reconnect/Connect, disabled reasons, forget still available | pass |
| History & storage | `48-history-storage.*`: two copies, counts, date ranges, capacity, percentage | pass |
| Clear history (normal) | `49-clear-confirm.*` (2,595 readings, date range, kept copy), `50-clear-sending.*`, `51-clear-result.*` (Bridge 0, phone 2,595), `serial-clear-fix.log` `stored seq=0` | pass after fix |
| Generation change | `57-reboot-after-clear.log`: `gen f2fed1b3, seq 0..1` vs old `081936f6` | pass |
| Clear history (app killed mid-action) | `serial-kill-mid-clear.log`: control op 5 `status 0`, app killed 150 ms later, bridge finished at `stored seq=0`, no panic; `58-*`, `59-after-kill-storage.*` (Bridge 2, phone 2,600) | pass |
| Forget this phone | `70-forget-confirm.*`, `71-forget-sending.*`, `72-setup-orphaned-history.*`, `serial-forget.log` (`forget: current peer bond removed, 0 bond(s) remain`, re-advertise), `73-orphaned-history.*` (2,611 readings kept) | pass |
| Wrong passkey | `77-android-passkey-dialog.*`, `78-wrong-code-entered.*`, `79-wrong-code-result.*` (`The code didn’t match`), `serial-pairing.log` (`pairing complete (status 4, 0 bond(s))`) | pass |
| Correct re-pair + bond survives reboot | `81-second-passkey-dialog.*`, `82-pairing-success.*`, `serial-pairing.log` (`status 0`, `link secured … 1 bond`), `23-bridge-reboot.log`, `57-reboot-after-clear.log` (no prompt) | pass on the T55 release image |
| Power off | `60-poweroff-confirm.*`, `61-poweroff-sending.*`, `62-bridge-is-off.*`, serial `deep sleep: Vext off, GPIO0 ANY_LOW wake armed`, SX1262 asleep, no advertising | pass |
| Hold-PRG wake | `63-prg-wake.log` (`deep-sleep wake: confirming PRG hold`, boot, advertise), `64-*`, `65-*`, `69-relaunch-after-wake.*` | pass (wake itself); app needed a relaunch to reconnect — follow-up |
| Factory reset | `90-factory-confirm.*` (all four losses + kept history), `91-factory-sending.*`, `92-setup-after-factory.*`, `93-reboot-after-factory.log` (`gen 0a4bd285`, 0 records, `0/4 bond slot(s)`), `94-orphaned-after-factory.*` (2,620 kept) | pass |
| Re-pair after factory reset | `95-pair-after-factory.*`, `serial-repair-after-factory.log` (`link secured … 1 bond`) | pass |
| Pairing cap | Host `ble-adv` (`check_bond_limit`: 4 allowed, 5th refused, no eviction); app setup widget tests (`full bond store is reported before the OS bond starts`) | pass by host test (no 5 physical phones) |
| T46a offline probe semantics | `37-live-blocked-offline.*`, `41-live-offline-cache.*`, `42-cold-launch-offline.*`: `last reading … ago, showing saved readings`; never `updated live` | pass |
| T46a saved-ID header | `38-*`, `39-*`, `42-*`: `Smoke X4 Bridge / Bridge 8276`, never `Bridge A4F2` | pass |
| T46a sparkline backfill | `42-cold-launch-offline.*`: sparkline and `flat over the last 10m` after cold launch | pass |
| T46a blocked sync card | `37-live-blocked-offline.*`: blocked banner, no sync card | pass |
| T46a `Showing saved readings` banner | `67-history-showing-saved.*` after power-off | pass |
| T46a Bridge-reboot recovery | `84-after-release-reflash.*` (X4 `Not paired` at 2 s), `85-…60s`, `86-…125s` (`Receiving readings`); 110 s watchdog recovered | pass (≈2 min) |
| T46a range-scoped Cooks | `87-history-24h.*`, `88-history-1h.*`, `89-history-1h-scrolled.*` (Cooks `In progress 7:17–8:16 AM` inside 1 h); seeded 24 h shows only the two in-range cooks, 1 h shows none (`seed-02-*`, `seed-03-*`) | pass |
| T46a `Not synced` gap label | Seeded debug archive on the real phone: `seed-01-history-24h-not-synced.*` (24 h), `seed-04-history-24h-320-not-synced.*` (320 dp) — dashed band labelled `Not synced` | pass |
| T46a permanent-loss banner, range-scoped | `seed-02-history-24h-loss-banner.*`: `Some readings were lost before they reached your phone` with the blank period; `seed-03-history-1h-range-scoped.*` shows no banner when the 14 h..6 h gap is outside the 1 h range | pass |
| Seeded recheck restored | `seed-05-restored-live.*`: real archive back (2,620 rows), release APK reinstalled, X4 `Receiving readings`, no `Not synced` band | pass |
| Smoke X4 re-pair from Settings | App path and copy checked by widget tests; `unpair_smoke_x` preserves the log/bonds by design | **not executed** — no physical SYNC gesture available; running it would leave the board without X4 data |

## Findings

1. **`clear_history` crashed the bridge and boot-looped (fixed, T55).**
   `erase_nonblank_sectors()` used a 4,096 B stack buffer; clear runs on the
   3,584 B `esp_timer` task and pending-clear recovery on the 3,584 B main task.
   The first clear panicked (`InstrFetchProhibited`, PC `0x1000`) and every boot
   repeated the overflow (`serial-session.log`). The scan now reads in 256 B
   chunks (`log_flash_core.c`, ADR 0060). Retested: clear, mid-action kill and a
   reboot after clear all succeed.
2. **Setup scan row printed sentinels (fixed, T55).**
   A Bridge with no sample yet advertised `pit_temp_f10 = -32767` and battery
   `255`; the row showed `P4 -3277°F · 255%` (`75-scan-results.*`). The preview
   now omits an invalid/detached temperature and unknown battery
   (`bridge_codecs.dart`, `setup_codec_test.dart`).
3. **No reconnect after power-off wake or after Bluetooth returns.** The app
   stayed `Offline` after the wake button and after `svc bluetooth enable`;
   force-stop/relaunch reconnected. The link is not restarted from those two
   transitions. Owning area: T43/T46a. Workaround for the bench: relaunch.
4. **Stale bond after a restored NVS backup is not named.** This is a bench
   artifact (the phone and NVS backups no longer shared a key); normal forget and
   factory reset clear both sides. No product action was taken. Cleaning it
   needed Android's “Forget device” confirmation plus a one-time bond-store
   clear on the bridge; the final state is 1 bond and a working link.
5. The webcam is black, so OLED copies (`°F/°C`, timeout, off/reset overlays)
   are not photographed in this sitting.
6. **320 dp History offline banner truncates.** In the seeded run at 320 dp the
   offline banner reads `Turn Bluetooth on to find your ...` and the range /
   probe chips read `24 ho...` / `All pro...` (`seed-04-*`). Settings rows were
   already rechecked at 320 dp and are fine; this is History copy, not the
   Settings walk. Follow-up for T54/T50.
7. **T46 seeded fixture overlays two gaps.** `tools/bench/t46_seed_db.py` deletes
   the whole of yesterday *and* the 14 h..6 h `Not synced` period, so both band
   labels draw at the same x and the label is unreadable on the phone. The T55
   run used a local variant with only the `Not synced` gap (procedure below);
   the shared tool is unchanged because T46 evidence cites it.

## Not completed (follow-up T55 run)

- Photograph/read the real OLED for units, screen timeout, `OFF`/`RESETTING`
  overlays (needs a working camera or a person at the bench).
- Re-pair the Smoke X4 from Settings on a real X4, including the new-channel
  SYNC and “log preserved” checks (needs physical SYNC mode).
- Five physical phones for the 4-slot cap (host-tested here, which the task
  explicitly allows).

## Command / file notes

- Serial capture:
  `python firmware/bench/t10_probe/tools/capture.py --port COM5 --out artifacts/bench/T55/<step>.log`
  (never `--reset` unless the step is a reset; the helper keeps DTR/RTS low).
- Reset the board without touching GPIO0: RTS pulse; see `t55_reboot2.py`
  pattern in the run notes.
- PRG wake: hold DTR (GPIO0) low for 2.0 s, then release; `63-prg-wake.log`.
- The release APK is debug-signed in this repo; `adb install -r` keeps data.
- The temporary `BENCH passkey` log line and the one-time bond clear used while
  restoring the board were reverted before the final build; the committed
  firmware hash above is the release image.
- **Seeded History recheck (continuation 1).** Build/install the debug APK over
  the release app (`adb install -r app/build/app/outputs/flutter-apk/app-debug.apk`;
  the release APK is debug-signed, so data/bonds are kept), force-stop, then
  `adb exec-out run-as com.binbuf.smoke_bridge cat databases/smoke_bridge.db >
  artifacts/bench/T55/backup/phone-archive-pre-seed.db`, push the seeded DB to
  `/data/local/tmp/`, and `run-as ... cp` it over `databases/smoke_bridge.db`
  after deleting `-wal`/`-shm`. Run with Bluetooth off so the app opens on the
  saved archive. Restore by copying the archive back, reinstalling
  `app-release.apk` and enabling Bluetooth; `seed-05-restored-live.*` is the
  after-state.
- **Screenshots on the fold.** `adb shell screencap -p` warns about two displays
  and can capture the stale inner display. Use the outer SurfaceFlinger id from
  `adb shell dumpsys SurfaceFlinger --display-id`
  (`screencap -p -d 4619827677550801153 /sdcard/s.png`), then `adb pull`.
  PowerShell `>` corrupts the PNG (UTF-16) — write on the device and pull.
