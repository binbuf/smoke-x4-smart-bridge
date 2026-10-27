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

## Power

| Check | Result | Evidence |
|---|---|---|
| Deep-sleep wake by hold-PRG, USB attached, 20/20 | ✅ 2026-10-26 — **20/20 application boots**. Each cycle held the PRG/GPIO0 net low for 2 s then released. Every wake reported `rst:0x5 (DSLEEP), boot:0x8 (SPI_FAST_FLASH_BOOT)`, `causes=0x00000008` (EXT1), `EXT1 mask=0x1`, `gpio0=0` at `app_main`; **no ROM-download banner in any cycle**. Note: the press was driven by the CP2102 DTR transistor (same GPIO0 net as the button), not by a finger. | [`probe/wake-cycles-20.txt`](../artifacts/bench/T09/probe/wake-cycles-20.txt), [`probe/wake-cycles-20.csv`](../artifacts/bench/T09/probe/wake-cycles-20.csv) |
| Deep-sleep wake by hold-PRG, USB detached, 20/20 | ◐ 2026-10-26 — **owner-observed, not counted.** With the USB cable out and the pack connected, holding PRG woke the T09 probe and the OLED lit with the probe's stripe pattern; the owner repeated this across multiple presses ("seems to work"). That is real finger-press wake evidence on battery with USB removed, which the DTR-driven 20/20 run does not cover. **No serial trace and no exact 20-count were captured** (USB removed by design), so this does not replace the counted repeat. Re-owned by T62. | owner report, this session — no serial artifact (USB removed by design) |
| Early release returns to sleep | ✅ 2026-10-26 — host-tested (`ui-button`): release before 1.5 s reports released and the boot path re-enters EXT1 sleep before NVS/BLE/UI. **Physical press/release timing on the board is still owed to T62/T37.** | `firmware/test/test_ui_button.c` |
| Tap/hold/cancel and waking-press consumption | ✅ 2026-10-26 — host-tested (`ui-button`) at the 399/400 ms and 1499/1500 ms boundaries; a waking press emits no tap and no countdown. Touch timing on the physical button is owed to T37. | `firmware/test/test_ui_button.c` |
| Power-off path: `OFF`, Vext off, SX1262 sleep, BLE down, GPIO0 wake | ◐ 2026-10-26 — firmware-built order in `ui.c`/`board.c`/`sx_radio.c`; Vext-off and EXT1 wake match the T09 probe. BLE teardown is still the `ble_service_stop()` stub until T27/T30, and the physical path is owed to T37. | `firmware/components/ui/ui.c`, `firmware/components/board/board.c`, `firmware/components/sx_radio/sx_radio.c` |
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
| Real X4 pairs; stock receiver keeps updating | ⏳ | |
| Unpair/re-pair; stock receiver unaffected | ⏳ | |
| Four probes, detached probe, °F/°C flip | ⏳ | |
| Power cut mid-cook; earlier records survive | ⏳ Deferred to T37 (physical power cut). Host torn-tail recovery passes; bench recovery timing is recorded above. | |
| Ring rotation (fill/wrap) | ⏳ | |
| `min_seq`/`max_seq`/`generation` through BLE | ⏳ | |

## BLE and app

| Check | Result | Evidence |
|---|---|---|
| Passkey bond; wrong code rejected | ⏳ | |
| Bond survives reboot; reconnect has no prompt | ⏳ | |
| Negotiated MTU | ⏳ | |
| Live notifications at sample cadence | ⏳ | |
| Full sync and resume after disconnect | ⏳ | |
| Settings: units, probes, display timeout | ⏳ | |
| Forget this phone, factory reset, power off | ⏳ | |
| App: fresh install → live; relaunch → history | ⏳ | |

## Billows

See [`billows-decision.md`](billows-decision.md). These rows are filled during
the M5 bench work, not in V0. The MVP is observation-only; no cook is required.

| Check | Result | Evidence |
|---|---|---|
| T56 passive capture: `billows_attached`, probe 4 `max`/`min` at 225/250/275 °F | ⏳ | |
| Attach/detach changes `billows_attached` | ⏳ | |
| Raw `max`/`min` at three known targets; relation confirmed or marked unknown | ⏳ | |
| °F/°C target conversion | ⏳ | |
| App/OLED show target read-only, `—` when unknown, and "Set on the Smoke X4" | ⏳ | |
| No Billows TX path; only the pairing ACK is transmitted | ⏳ | |

## Soak and field

| Check | Result | Evidence |
|---|---|---|
| 24 h soak: no reboot/panic; heap/stack criteria | ⏳ | |
| Supervised cook | ⏳ | |
| Overnight cook with phone away ≥ 6 h | ⏳ | |
| Power cut during a cook | ⏳ | |
| Stock receiver throughout | ⏳ | |
