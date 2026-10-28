# Hardware Verification

Results for the new build. Every row starts `⏳`; replace it with a dated result
and an artifact link. Do not leave a row silently blank.

**Board:** Heltec WiFi LoRa 32 V3 (confirmed 2026-10-26: ESP32-S3FN8, 8 MB,
MAC `ac:a7:04:38:82:74`) · **Phone:** TBD ·
**Date started:** 2026-10-26

**Board state at 2026-10-26:** the T09 probe is on the board (deep sleep), not
product firmware; the legacy image, NVS and cooks were wiped by design.

## Board identity and bring-up

| Check | Result | Evidence |
|---|---|---|
| Board is Heltec WiFi LoRa 32 V3, ESP32-S3FN8, 8 MB flash, SX1262, SSD1306 | ✅ 2026-10-26 — ESP32-S3 rev v0.2, 8 MB GD flash (`c8:4017`), base MAC `ac:a7:04:38:82:74`; SSD1306 ACKed at 0x3C and accepted init + 1 KiB write; SX126x answered GetStatus (`0xaa`, STDBY_RC) and its version register (`"SX1261 V2D 2D02"`, the shared SX1261/1262 firmware string). Board identity also matches the legacy enclosure/board record. | [`as-found/flash-id.txt`](../artifacts/bench/T09/as-found/flash-id.txt), [`probe/cold-boot-serial.txt`](../artifacts/bench/T09/probe/cold-boot-serial.txt), [`probe/README.md`](../artifacts/bench/T09/probe/README.md) |
| As-found image, version and partition layout recorded before flashing | ✅ 2026-10-26 — legacy `smoke_bridge` 1.0.0, ESP-IDF v6.0.2, built Oct 11 2026 11:16, ELF SHA-256 `098ca6ea…ec5135`; legacy 7-row OTA table (`nvs`, `otadata`, `phy_init`, `coredump`, `ota_0`, `ota_1`, `cooks`) | [`as-found/README.md`](../artifacts/bench/T09/as-found/README.md), [`as-found/app-image-info.txt`](../artifacts/bench/T09/as-found/app-image-info.txt) |
| Legacy pairing/NVS state archived before the wipe | ✅ 2026-10-26 — 24 KiB NVS dump archived; `sx_pair/config` = `{frequency_hz: 918500000, device_id: 4c4d58435b5c0000, num_probes: 4}`; also `nimble_bond` (1 bond), Wi-Fi AP state, `session`, `time` | [`as-found/nvs-0x9000.bin`](../artifacts/bench/T09/as-found/nvs-0x9000.bin), [`as-found/pairing-entry.txt`](../artifacts/bench/T09/as-found/pairing-entry.txt) |
| `erase-flash` completed; follow-up partition-table read is clean | ✅ 2026-10-26 — erase 6.3 s; `0x0..0x1ffff` and `0x20000..0x2ffff` both 100% `0xFF`; boot after erase prints `invalid header: 0xffffffff`, no app. After flashing the probe the table is only `nvs`/`phy_init`/`factory`, and the old `ota_1`/`cooks` offsets read `0xFF` | [`wipe/erase-flash.txt`](../artifacts/bench/T09/wipe/erase-flash.txt), [`wipe/post-erase-serial.txt`](../artifacts/bench/T09/wipe/post-erase-serial.txt), [`probe/post-flash-partition-table.txt`](../artifacts/bench/T09/probe/post-flash-partition-table.txt) |
| Antenna fitted before first power | ⚠ 2026-10-26 — **not re-fitted or visually re-checked in this session.** The legacy V1.1 record says it was fitted before the first power and never removed; the radio probe ran with that antenna in place. Treat as inherited, not re-verified. | [`legacy/docs/hardware-verified.md`](../legacy/docs/hardware-verified.md) V1.1 |
| Battery pack polarity metered before connection | ⚠ 2026-10-26 — **no DMM in this session.** Legacy V1.1 recorded a visual-only check (owner decision), pack shown working. The probe measured the pack at ≈4.03 V through the divider, which is consistent with the connected pack but is not a polarity measurement. | [`legacy/docs/hardware-verified.md`](../legacy/docs/hardware-verified.md) V1.1 |
| OLED Vext (GPIO36 LOW) and I²C bus order | ✅ 2026-10-26 — GPIO36 driven LOW before the bus; `i2c_master_probe(0x3C)` returned `ESP_OK`; SSD1306 init + 1 KiB pattern write succeeded. A first run that left RST (GPIO21) low returned `ESP_ERR_NOT_FOUND`, confirming RST must be released too. | [`probe/cold-boot-serial.txt`](../artifacts/bench/T09/probe/cold-boot-serial.txt) |
| PRG (GPIO0) debounce after boot | ✅ 2026-10-26 — GPIO0 idles high; a 400 ms press (DTR driving the same CP2102 GPIO0 net) produced exactly one DOWN then one UP with a 30 ms debounce, no bounce | [`probe/cold-boot-serial.txt`](../artifacts/bench/T09/probe/cold-boot-serial.txt) |
| Battery divider: GPIO37 HIGH enables, ratio ≈ 4.9 | ✅ 2026-10-26 — GPIO37 LOW → raw 2 / 0 mV; GPIO37 HIGH → raw 947 / 823 mV → **≈4032 mV** at ×4.9; GPIO37 LOW again → raw 0. Pack is on USB and near full, consistent with the legacy 4062 mV reading. | [`probe/cold-boot-serial.txt`](../artifacts/bench/T09/probe/cold-boot-serial.txt) |

## Display and controls

| Check | Result | Evidence |
|---|---|---|
| All visible pages walked and legible at arm's length (Probes, Connection, Billows only when detected, Bridge) | ⏳ T37 — host goldens cover every page and overlay (including a coverage assertion), but the real panel and case window are **not walked yet**. Procedure: [checklist step 7](../artifacts/bench/T37/CHECKLIST.md). | — |
| Display sleep/wake works and does not change the page | ⏳ T37 — host `ui-render` proves sleep/wake keeps the page and a sample cannot wake the panel; physical panel `0xAE`/`0xAF` and wake-by-tap are **not observed yet**. | — |
| Battery reading checked against DMM/known state; unknown renders as `—` | ⏳ T37 — host Li-ion curve and `SOC_UNKNOWN` tests pass and golden `04-probes-unknown-battery` draws `—`; the physical reading and known-state comparison are **not done**. The ±2 % DMM tolerance and calibrated ratio remain T62. | — |
| PRG power off/on: hold countdown, early-release cancel, hold-to-wake, waking press consumed | ⏳ T37 — host `ui-button` covers the 399/400 ms and 1499/1500 ms boundaries and waking-press consumption; the physical press/release sequence and `OFF` frame are **not observed yet**. USB-detached wake count and currents are T62. | — |

## Power

| Check | Result | Evidence |
|---|---|---|
| Deep-sleep wake by hold-PRG, USB attached, 20/20 | ✅ 2026-10-26 — **20/20 application boots**. Each cycle held the PRG/GPIO0 net low for 2 s then released. Every wake reported `rst:0x5 (DSLEEP), boot:0x8 (SPI_FAST_FLASH_BOOT)`, `causes=0x00000008` (EXT1), `EXT1 mask=0x1`, `gpio0=0` at `app_main`; **no ROM-download banner in any cycle**. Note: the press was driven by the CP2102 DTR transistor (same GPIO0 net as the button), not by a finger. | [`probe/wake-cycles-20.txt`](../artifacts/bench/T09/probe/wake-cycles-20.txt), [`probe/wake-cycles-20.csv`](../artifacts/bench/T09/probe/wake-cycles-20.csv) |
| Deep-sleep wake by hold-PRG, USB detached, 20/20 | ◐ 2026-10-26 — **owner-observed, not counted.** With the USB cable out and the pack connected, holding PRG woke the T09 probe and the OLED lit with the probe's stripe pattern; the owner repeated this across multiple presses ("seems to work"). That is real finger-press wake evidence on battery with USB removed, which the DTR-driven 20/20 run does not cover. **No serial trace and no exact 20-count were captured** (USB removed by design), so this does not replace the counted repeat. Re-owned by T62. | owner report, this session — no serial artifact (USB removed by design) |
| Early release returns to sleep | ✅ 2026-10-26 — host-tested (`ui-button`): release before 1.5 s reports released and the boot path re-enters EXT1 sleep before NVS/BLE/UI. **Physical press/release timing on the board is still owed to T62.** | `firmware/test/test_ui_button.c` |
| Tap/hold/cancel and waking-press consumption | ✅ 2026-10-26 — host-tested (`ui-button`) at the 399/400 ms and 1499/1500 ms boundaries; a waking press emits no tap and no countdown. Touch timing on the physical button is owed to T37. | `firmware/test/test_ui_button.c` |
| Power-off path: `OFF`, Vext off, SX1262 sleep, BLE down, GPIO0 wake | ◐ 2026-10-26 — firmware-built order in `ui.c`/`board.c`/`sx_radio.c`; Vext-off and EXT1 wake match the T09 probe. BLE teardown is still the `ble_service_stop()` stub until T27/T30, and the physical path is owed to T37. | `firmware/components/ui/ui.c`, `firmware/components/board/board.c`, `firmware/components/sx_radio/sx_radio.c` |
| Battery divider enable/sample/disable sequence (GPIO37 LOW after) | ◐ 2026-10-26 — firmware `board_battery_sample()` drives GPIO37 HIGH, waits 200 µs, averages 32 calibrated ADC1_CH0 reads, then drives GPIO37 LOW on every exit path. Host-side review only; **the divider-off current and scope trace are owed to T62.** | `firmware/components/board/board_battery_esp.c` |
| Battery pack voltage vs DMM within ±2 % (agreed tolerance) | ⏳ 2026-10-26 — **NOT MEASURED: no DMM in this session.** Deferred to T62. Plausibility only: the T09 probe read ≈4032 mV from 823 mV at ×4.9, consistent with the legacy 4062 mV pack. | T09 row above; T62 owns the DMM comparison and the calibrated ratio |
| Li-ion curve and `SOC_UNKNOWN` (never 0 %) | ✅ 2026-10-26 — host-tested `board-battery`: exact curve points, interpolation, clamps, 0 mV → 255, failed stats sample → 255. UI golden `04-probes-unknown-battery` renders `—`. | `firmware/test/test_board_battery.c`, `firmware/test/test_ui_render.c` |
| Battery mV/% reach the live snapshot and power stats | ✅ 2026-10-26 — housekeeping samples every 10 s and calls `bridge_state_set_battery()`; `board_battery_stats_get()` exposes last mV/%, divider mV and success/failure counts. BLE `stats` encoding remains T47. | `firmware/main/housekeeping.c`, `firmware/components/board/board_battery.c` |
| Divider-enable current cost (quiescent saving) | ⏳ 2026-10-26 — **NOT MEASURED.** Deferred to T62 with the deep-sleep current rows. | — |
| Current: on + advertising + OLED asleep | ⏳ 2026-10-26 — **NOT MEASURED.** No current meter/INA in this session. The probe advertised for 10 s but current was not logged. Deferred to T62. | — |
| Current: on + connected + OLED awake | ⏳ 2026-10-26 — **NOT MEASURED.** No central connected and no meter. Deferred to T62. | — |
| Current: deep sleep | ⏳ 2026-10-26 — **NOT MEASURED.** No meter. The probe did enter deep sleep successfully. Deferred to T62. | — |
| Runtime: 24 h on the 3000 mAh pack | ⏳ 2026-10-26 — **NOT RUN.** Cannot span 24 h in this session; needs a dedicated pack run (T62/T61). Deferred to T62. | — |

### Power decision (T11)

**Hold-PRG wake works reliably enough to build on.** T09 recorded 20/20
application boots with the GPIO0 net held low for 2 s and released; every wake
was `rst:0x5 (DSLEEP)` / `boot:0x8 (SPI_FAST_FLASH_BOOT)`, `causes=0x8` (EXT1),
`EXT1 mask=0x1`, with no ROM-download banner. The owner also woke the board by
hand with the pack connected and USB removed, and the OLED came up.

**Fallback: none selected.** RST wake, an external latch, and dropping the
hold-to-on behaviour are all rejected. The strap did not fire on a DSLEEP wake,
so there is no evidence that any of them is needed. If the physical 20/20
repeat ever contradicts this, supersede [ADR 0020](design/adr/0020-gpio0-ext1-deep-sleep-wake.md)
instead of silently changing the mechanism.

**Implementation contract.** Use `esp_sleep_enable_ext1_wakeup_io(BIT(0),
ESP_EXT1_WAKEUP_ANY_LOW)`; the wake is a reset, so distinguish wake from cold
boot with RTC-retained state. The post-boot hold/release behaviour in 07 §7.7
still needs its own debounce.

**Not measured here.** Deep-sleep current and pack runtime are still open;
**T62 owns those measurements**. This record does not claim a runtime number.

### T09 probe conditions

The 20 wake cycles used the throwaway image at
[`firmware/bench/t09_probe/`](../firmware/bench/t09_probe/) (bare NimBLE
advertising + 10 s awake + EXT1 GPIO0-low deep sleep). It was flashed after the
wipe; it is not product code. The PRG press was a 2 s DTR assertion on the
CP2102, which drives the same GPIO0 net as the button — the probe's own 30 ms
debounce saw one clean DOWN/UP. The OLED check needed GPIO21 (RST) high before
the I²C probe; a first run with RST low read `ESP_ERR_NOT_FOUND`. The SX126x
version register reports `"SX1261 V2D 2D02"`, the shared SX1261/1262 firmware
string, so it is evidence of the radio responding, not a different part.

The 24 h pack run and all three current measurements remain open; see the
Follow-ups in [`progress/T09.md`](progress/T09.md). Advertising was confirmed
from the NimBLE host (`adv_start rc=0`, `active=1`, still active after 10 s);
no independent scanner was used in this session.

## Radio and storage

| Check | Result | Evidence |
|---|---|---|
| Raw `samples` partition mounts; boot recovery measured under ~2 s | ⏳ 2026-10-26 - PASS on the T19 image: `sample_log_init` recovered the raw 6,160,384-byte partition in **899 ms** on a cold boot (`gen 081936f6`, 0 records, state `OK`); the earlier header-cache pass measured 1,457 ms, so the header bypass was added and re-measured. The scan reads all 1,504 sectors once; a populated ring has the same read volume. No filesystem is involved. | [`T19/recovery/cold-boot-optimized.txt`](../artifacts/bench/T19/recovery/cold-boot-optimized.txt), [`T19/recovery/cold-boot.txt`](../artifacts/bench/T19/recovery/cold-boot.txt) |
| `esp_partition` failure sets `storage_ok = 0`, no successful write | ⏳ 2026-10-26 - host-tested (`sample-log-flash`): injected write/read/erase failures flip the log to `READ_ONLY`, reject later appends and never advance `next_seq`; reboot recovery resumes at the last valid sequence. | `firmware/test/test_sample_log_flash.c` |
| Pending clear finishes at boot and ignores old-generation sectors | ⏳ 2026-10-26 - host-tested (`sample-log-flash`): a simulated interrupted clear erases only the remaining non-blank sector, clears `clear_pending`, reports generation B, and old sequences read as out of range. Bench execution belongs to T48/T55. | `firmware/test/test_sample_log_flash.c` |
| Real X4 pairs; pairing persists across reboot | ◐ 2026-10-27 — the X4 was already paired and kept sending after a forced bridge reset (`rx` frames at 918.5 MHz, stored `seq` 244+). A fresh X4 SYNC gesture and the stock-receiver check remain T55/T61. | [`T37/01-bridge-reboot.log`](../artifacts/bench/T37/01-bridge-reboot.log) |
| Stock receiver keeps updating while the bridge records | ✅ 2026-10-28 T59 — operator confirmed the stock Smoke X4 receiver still updated through the Billows attach/target/unit/detach walk and after the re-pair ACK; Bridge state frames were recorded throughout. | [`T59/README.md`](../artifacts/bench/T59/README.md), [`T59/serial-t59.log`](../artifacts/bench/T59/serial-t59.log) |
| Four probes, detach/reattach; OLED `---` and stored sentinel | ⏳ T37 — [checklist step 4](../artifacts/bench/T37/CHECKLIST.md), not run. Host tests pass: `sample-log-rec`, `sample-pipe`, `ui-render`. | — |
| X4 °F/°C flip stores canonical °F | ⏳ T37 — [checklist step 5](../artifacts/bench/T37/CHECKLIST.md), not run. Host tests pass: `sx-protocol`, `sample-pipe`, `sample-log-rec`. | — |
| Unpair/re-pair; stock receiver unaffected | ⏳ | |
| Power cut mid-cook; earlier records survive and the log resumes | ⏳ T37 — [checklist step 3](../artifacts/bench/T37/CHECKLIST.md), not run. Host torn-tail recovery passes (`sample-log-flash`); bench recovery timing is recorded above. | — |
| Ring rotation (fill/wrap) | ⏳ | |
| `min_seq`/`max_seq`/`generation` through BLE | ⏳ | |
| 30-minute cadence run: four probes, OLED awake and asleep | ⏳ T37 — procedure and report template prepared by T26 ([checklist step 6](../artifacts/bench/T37/CHECKLIST.md)); **no run yet**. Host extractor `tools/bench/cadence_report.py` is tested on the T10 capture. | — |
| Packet counts vs expected, observed intervals and missed samples recorded | ⏳ T37 — `CADENCE-REPORT.md` must record packet count, expected count, min/mean/max interval, missing sequence numbers and missed samples. Not generated yet. | — |
| RSSI range recorded; every gap > 90 s has a cause | ⏳ T37 — the report records RSSI min/mean/max and leaves the cause column for the sitting; **no gap observed or explained yet**. | — |

### LoRa receive root cause and re-check (2026-10-27)

The product image tuned the SX1262 and reported a healthy radio, but received
nothing from a real X4. Root cause: `sx_radio_init()` called
`SetSyncWord(0x12)`; the SX126x wants the 16-bit private sync word `0x1424`
(`0x12` is the SX127x-era byte). The receiver therefore looked for `0x0012` and
never matched a packet. The known-good T10 probe on this same board never called
`SetSyncWord()` and used the `0x1424` default. The TCXO setting was also reverted
from an unverified `1.8 V` back to the T10/legacy-proven `3.3 V`.

After the fix, on the same board (ESP32-S3FN8, MAC `ac:a7:04:38:82:74`,
operating channel 918.5 MHz, paired record persisted across reboot):

- Four real X4 state frames at ≈28.0 / 58.3 / 88.6 / 118.9 s (30 s cadence),
  RSSI −35 to −36 dBm, SNR 10–11, payload `LMXC[\` (26 commas), stored as
  sequence 1–4.
- Phone/app: `SmokeX4-8276` discovered, connected with the stored bond, `set_time`
  and a 195-byte recent sync completed; Live showed P1 79.4 °F, P2 78.9 °F,
  P3 79.5 °F, P4 79.3 °F, updated 22 s earlier, signal −35 dBm.

Evidence: [`T37/lora-rx-after-syncword-fix.log`](../artifacts/bench/T37/lora-rx-after-syncword-fix.log),
[`T37/lora-rx-ble-sync-after-fix.log`](../artifacts/bench/T37/lora-rx-ble-sync-after-fix.log).
The formal T37 pairing/unpair, cadence and gap rows above are still open.

## BLE and app

| Check | Result | Evidence |
|---|---|---|
| Passkey bond; wrong code rejected | ◐ 2026-10-27 — first bond with the OLED passkey and a stored-bond reconnect with no new prompt passed; wrong-code rejection is deferred to T55. | `T37/lora-rx-ble-sync-after-fix.log`, [above](#lora-receive-root-cause-and-re-check-2026-10-27) |
| Bond survives reboot; reconnect has no prompt | ✅ 2026-10-27 — forced EN reset; log recovered `seq 0..243`, next 244; the app auto-reconnected 31 s later with no passkey prompt (`pairing complete status 0, 1 bond`). | [`T37/01-bridge-reboot.log`](../artifacts/bench/T37/01-bridge-reboot.log) |
| Negotiated MTU | ✅ 2026-10-27 — the app's Technical details reads **247** (confirmed again in T46 after the M3 rebuild). | [`T37/01-technical-details-scrolled.xml`](../artifacts/bench/T37/01-technical-details-scrolled.xml), [`T46/06-technical-details-scrolled.*`](../artifacts/bench/T46/06-technical-details-scrolled.png) |
| Live notifications at sample cadence | ◐ 2026-10-27 — Live showed four values and `updated 22s ago`; the 30-minute cadence walk is deferred to T61. | [above](#lora-receive-root-cause-and-re-check-2026-10-27) |
| Full sync and resume after disconnect | ✅ 2026-10-27 T46 — the 696-record real archive synced with no duplicates; a deliberate Bluetooth-disable after 3 × 32-record pages left 96 stored rows (`seq 532..627`), and re-enabling Bluetooth resumed to `seq 0..628` / 629 rows with no duplicates. Cursors persisted across the drop. | [`T46/18-partial.db`](../artifacts/bench/T46/18-partial.db), [`T46/18-resumed.db`](../artifacts/bench/T46/18-resumed.db), [`T46/18-midsync-bt-off.*`](../artifacts/bench/T46/18-midsync-bt-off.png) |
| Forced link drop and bounded reconnect | ◐ 2026-10-27 — bounded retry UI passed (`Reconnecting` attempts, then `Can’t reach the Bridge`). Finding: after an adapter off/on cycle the app could still show stale `Bridge Connected` while the bridge had no central link; it needed a process restart. Routed to T43. | [`T37/02-bt-off.xml`](../artifacts/bench/T37/02-bt-off.xml), [`T37/02-bt-restored.xml`](../artifacts/bench/T37/02-bt-restored.xml), [`T37/03-bt-on-recovered.xml`](../artifacts/bench/T37/03-bt-on-recovered.xml), [`T37/03-cold-launch.xml`](../artifacts/bench/T37/03-cold-launch.xml) |
| Quiet 30 s forward sync | ✅ 2026-10-27 — T37 saw two pairs 30.18 s apart. T46 measured a steady-state window of pairs **30.0–31.0 s** apart (51 B drained / 33 B one-record status frames); Live showed no sync card and History stayed current. | [`T37/03-quiet-sync.log`](../artifacts/bench/T37/03-quiet-sync.log), [`T46/serial-main.log`](../artifacts/bench/T46/serial-main.log), [`T46/05-live-first.*`](../artifacts/bench/T46/05-live-first.png) |
| Phone away; Bridge records; reconnect catches up | ✅ 2026-10-27 T46 — app force-stopped for **10.0 min**; 835 → 856 rows, **21 records in one 411 B forward frame**, no duplicates. Forward catch-up from the local max, not a re-read. A true 30+ min run remains T61. | [`T46/33-absence10-watch.log`](../artifacts/bench/T46/33-absence10-watch.log), [`T46/33-absence10.db`](../artifacts/bench/T46/33-absence10.db) |
| X4 warning dialog at 10 min | ✅ 2026-10-27 T46 — with the X4 base off, Live showed `Signal lost` and the app auto-opened `Smoke X4 signal lost` at 10 min 30 s; captured at physical size and 320 dp. | [`T46/32-x4-dialog-1030.png`](../artifacts/bench/T46/32-x4-dialog-1030.png), [`T46/32-x4-dialog-320.png`](../artifacts/bench/T46/32-x4-dialog-320.png) |
| History and offline cache on phone | ✅ 2026-10-27 T46 — real 6.43 h archive: default 24 h, all ranges, custom range, probe filter, full-screen, chart help, Summary sorts, Cooks and Cook view. Offline shows `Showing saved readings · last reading …` and keeps the chart/Summary usable. Seeded 117-day archive covers estimated, overwritten-before-sync, empty range, empty filtered probe, no readings and no cook. Findings (gap-label placement, archive-wide Cooks, global loss banner) are routed in T46 and fixed on the host in T46a; their phone after-evidence moves to T55 because the Pixel was PIN-locked. | [`T46/README.md`](../artifacts/bench/T46/README.md), [`T46/20-seeded-history-24h.*`](../artifacts/bench/T46/20-seeded-history-24h.png), [`T46/21-fullring-chart-2.*`](../artifacts/bench/T46/21-fullring-chart-2.png) |
| Settings: units, probes, display timeout | ✅ 2026-10-28 T55 — units °C/°F and the 30 s/1 min timeout were applied, saved (read-back) and confirmed on the OLED; name, Appearance, Live change window and persistence survived force-stop/relaunch and a Bridge reboot. | [`T55/t55-units-celsius-final.png`](../artifacts/bench/T55/t55-units-celsius-final.png), [`T55/t55-units-fahrenheit-final.png`](../artifacts/bench/T55/t55-units-fahrenheit-final.png), [`T55/t55-timeout-30sec-final.png`](../artifacts/bench/T55/t55-timeout-30sec-final.png) |
| Forget this phone, factory reset, power off | ✅ 2026-10-28 T55 — on the real board: forget answered `ok`, removed the bond and returned to Setup with orphaned history; clear history changed the generation (`f2fed1b3`) and kept the phone copy; factory reset wiped `0/4` bonds and 0 records and kept 2,620 phone rows; power off showed `OFF`, slept the radio and a real PRG hold (~1.9 s) woke it with the log intact. X4 SYNC re-pair sent `pair ACK` on 918.5 MHz and kept the log. | [`T55/x4-repair-serial.log`](../artifacts/bench/T55/x4-repair-serial.log), [`T55/t55-poweroff-screen.png`](../artifacts/bench/T55/t55-poweroff-screen.png), [`T55.md`](progress/T55.md) |
| App: fresh install → live; relaunch → history | ✅ 2026-10-27 T46 — first install paired from the existing bond and reached Live. Force-stopped cold launch with the saved Bridge in range reaches Live in < 2.5 s with **no Setup and no passkey prompt**; absent Bridge shows last-known Live + `Looking for the Bridge…` and a manual `Connect` after 10 s. | [`T46/15-cold-launch-2500.png`](../artifacts/bench/T46/15-cold-launch-2500.png), [`T46/17-cold-launch-absent-13s.*`](../artifacts/bench/T46/17-cold-launch-absent-13s.png) |
| History state matrix, 320 dp, dark/light, screen reader | ◐ 2026-10-27 T46 — every 13 §13.4 History state was walked and captured. Dark/light and TalkBack evidence exists at 320 dp; the amber X4 dialog was verified at 320 dp. Findings: the `Bridge A4F2` fixture leak while offline, stale `updated live` semantics, the stuck sync card while Bluetooth is blocked, several 320 dp truncations, and the 1 min Live change window reverting to 5 min after relaunch (routed to T43/T45/T53/T54). | [`T46/28-*`](../artifacts/bench/T46/28-dark-live.png), [`T46/29-320-*`](../artifacts/bench/T46/29-320-history.png), [`T46/31-a11y-settings-320.xml`](../artifacts/bench/T46/31-a11y-settings-320.xml), [`T46/32-x4-dialog-320.png`](../artifacts/bench/T46/32-x4-dialog-320.png) |
| Clear/factory-reset generation boundary | ◐ 2026-10-27 T46 — app/firmware destructive command still unsupported. A bench-level erase of the `samples` partition kept all 874 phone rows but reused generation `135870198` because the generation is NVS-owned, so no new segment started; the partition was restored. T48/T49/T52 own the real epoch change. | [`T46/34-after-clear.db`](../artifacts/bench/T46/34-after-clear.db), [`T46/34-restore-boot.log`](../artifacts/bench/T46/34-restore-boot.log) |

## Billows

See [`billows-decision.md`](billows-decision.md). These rows are filled during
the M5 bench work, not in V0. The MVP is observation-only; no cook is required.

| Check | Result | Evidence |
|---|---|---|
| T56 passive capture: `billows_attached`, probe 4 `max`/`min` at 225/250/275 °F | ✅ 2026-10-28 — release image on the current board, not reflashed; 17 state frames captured on 918.5 MHz with the existing X4 pairing. No TX and no SYNC gesture. Probe 4 `max` = 225/250/275 at the three base targets, `min` = 0, `billows_attached` = 1. | [`x4-billows-225-250-275.loralog`](../protocol/fixtures/lora/x4-billows-225-250-275.loralog), [`report`](../protocol/fixtures/lora/x4-billows-225-250-275.report.md), [`serial-t56.log`](../artifacts/bench/T56/serial-t56.log) |
| Attach/detach changes `billows_attached` | ✅ 2026-10-28 T56 — detached baseline `billows_attached=0`; attached frames `1`; after unplug `0` on two consecutive frames. Probe 4 `max`/`min` returned to the non-fan defaults `160`/`32`. | same capture |
| Raw `max`/`min` at three known targets; relation confirmed or marked unknown | ✅ 2026-10-28 T56 — **relation confirmed: target = probe 4 `max`**, not `max − 25` and not the midpoint; `min` stayed `0`. Three setpoints (225/250/275 °F) with four or more frames each. Target must be gated on the attached flag. | same capture; [`billows-decision.md`](billows-decision.md#t56-target-relation-result-2026-10-28) |
| °F/°C target conversion | ✅ 2026-10-28 T59 — real app/Board/OLED walk: at base 275 °F the app showed `Set temp 135.0°C` after the Settings units flip (`config applied: units 0`) and `275.0°F` after restoring °F (`units 1`). The OLED Billows page showed the matching `135°C`/`275°F`. Host `sample-pipe` also covers the °C→°F10 conversion. | `T59/10-billows-275-celsius.*`, `T59/11-billows-275-fahrenheit-restored.png`, `T59/serial-t59.log` |
| App/OLED show target read-only, `—` when unknown, and "Set on the Smoke X4" | ✅ 2026-10-28 T59 — real Pixel walk: 225/250/275 °F cards, `Last detected` ages, exact `Set on the Smoke X4.` source line, detach notice, offline `Last observed state`/`Set temp (last known) 275.0°F`, and Settings focused log. OLED confirmed the same target and no fan-running/duty text. No Connected/Read-only label or target setter. | [`T59/README.md`](../artifacts/bench/T59/README.md), `T59/03-billows-225.*`, `T59/06-billows-275.*`, `T59/13-billows-settings-lost.*`, `T59/16-billows-offline-last-known.*`, `T59/22-billows-settings-online.*` |
| No Billows TX path; only the pairing ACK is transmitted | ✅ 2026-10-28 T59 — real re-pair from Settings: `unpair_smoke_x: pairing cleared, scanning 915/920`, then **`pair ACK sent on 918500000 Hz`**; that is the only TX line in the full 77 KB capture. State frames resumed immediately. Host invariant still finds one `LoRaSend(` call site and one FSM `send_ack`; the app has no `ControlOp.setBillowsTarget` path. | [`T59/serial-t59.log`](../artifacts/bench/T59/serial-t59.log), `firmware/test/test_sx_radio_pair.c`, `app/test/billows_observation_test.dart` |

## Soak and field

| Check | Result | Evidence |
|---|---|---|
| 24 h soak: no reboot/panic; heap/stack criteria | ⏳ | |
| Supervised cook | ⏳ | |
| Overnight cook with phone away ≥ 6 h | ⏳ | |
| Power cut during a cook | ⏳ | |
| Stock receiver throughout | ⏳ | |
