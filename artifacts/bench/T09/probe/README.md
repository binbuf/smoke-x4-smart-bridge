# T09 bench probe — results and method

Throwaway IDF 6.0.2 project at
[`firmware/bench/t09_probe/`](../../../../firmware/bench/t09_probe/). It is **not**
product code and is not referenced by `firmware/CMakeLists.txt`.

## What it does

1. On the first cold boot: reads the battery divider with GPIO37 off/on/off,
   drives Vext (GPIO36) low and probes the SSD1306 at 0x3C, reads the SX126x
   status/version register, watches GPIO0 for 8 s with a 30 ms debounce, then
   advertises as `SX4-T09-PROBE` over bare NimBLE for 10 s.
2. Enters deep sleep with an **EXT1 low-level wake on GPIO0**.
3. On each wake, prints `WAKE n` from RTC-retained counters, waits for the line
   to be released, and sleeps again. A recovery cold boot (after an EN reset)
   skips the long probe and returns to sleep.

Build/flash (from the repository root, ESP-IDF 6.0.2):

```powershell
$env:IDF_PYTHON_ENV_PATH='C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env'
& D:\esp\esp-idf\export.ps1
Set-Location firmware/bench/t09_probe
idf.py -B build build
idf.py -p COM5 -B build flash
```

Drivers (also in `firmware/bench/t09_probe/tools/`, run from the repo root):

```powershell
python firmware/bench/t09_probe/tools/cold_boot.py
python firmware/bench/t09_probe/tools/wake_cycles.py
```

`cold_boot.py` resets via RTS and drives one 400 ms DTR pulse during the PRG
window. `wake_cycles.py` holds DTR for 2 s per cycle, 20 times. **DTR is the
CP2102 auto-reset transistor's GPIO0 net** — the same electrical node the PRG
button pulls low, not a finger press.

## Results (2026-10-26, COM5)

| Item | Result |
|---|---|
| Battery divider | GPIO37 LOW → raw 2 / 0 mV; HIGH → raw 947 / 823 mV → **4032 mV** at ×4.9; LOW → raw 0 |
| Vext + OLED | GPIO36 LOW, RST high, `i2c_master_probe(0x3C)` = `ESP_OK`; SSD1306 init + 1 KiB pattern write = OK |
| SX126x | BUSY low immediately after reset; GetStatus `0xaa` (STDBY_RC); version register `"SX1261 V2D 2D02"` (shared SX1261/SX1262 string) |
| PRG | idle high; 400 ms DTR pulse → one DOWN at 772 ms, one UP at 1174 ms, no bounce |
| BLE | `adv_start rc=0`, `active=1`, name `SX4-T09-PROBE`; still active after 10 s |
| Deep sleep | entered, wake source EXT1 on GPIO0 (`ESP_OK`) |
| Hold-PRG wake, USB attached | **20/20 APP**; every cycle `rst:0x5 (DSLEEP)`, `boot:0x8 (SPI_FAST_FLASH_BOOT)`, `causes=0x8`, `EXT1 mask=0x1`, `gpio0=0` at `app_main` |
| ROM download | **0/20** — no `waiting for download` / `DOWNLOAD_BOOT` banner |

## Not measured / not run

- Physical finger press and USB-detached wake: no actuator and no serial
  channel on battery. The mechanism is the same GPIO0 net, but the row remains
  open in `docs/hardware-verified.md`.
- Current in any state: no current meter.
- 24 h pack runtime: out of session scope.

## Files

| File | What |
|---|---|
| `cold-boot-serial.txt` | full first-boot probe log (OLED OK, PRG pulse, BLE, sleep) |
| `wake-cycles-20.txt` | all 20 wake cycles, full serial per cycle |
| `wake-cycles-20.csv` | per-cycle classification |
| `post-flash-partition-table.txt` | decoded table after flashing the probe |
| `post-flash-old-cooks-0x520000-4k.bin` | old `cooks` offset after wipe (all `0xFF`) |
| `post-flash-old-ota1-0x2a0000-4k.bin` | old `ota_1` offset after wipe (all `0xFF`) |
| `t09_probe.bin`, `t09_probe-image-info.txt` | exact probe image and its app descriptor |
| `t09_probe-partition-table.bin` | the probe's partition table |
| `SHA256SUMS.txt` | digests of the files above |
