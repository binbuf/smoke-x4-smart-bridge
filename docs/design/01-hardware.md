# 01 — Hardware

## 1.1 Target board

**Heltec WiFi LoRa 32 (V3)** — `HTIT-WB32LA`, the board named in the brief and
used by the legacy build and enclosure.

| | |
|---|---|
| MCU | ESP32-S3FN8, dual-core Xtensa LX7, 240 MHz |
| SRAM | 512 KB internal, no PSRAM |
| Flash | 8 MB SiP |
| LoRa | Semtech SX1262, 902–928 MHz (US) |
| BLE | Bluetooth LE 5, NimBLE host |
| Display | 0.96" 128×64 SSD1306, I²C |
| USB | USB-C via CP2102 UART bridge; native USB also broken out |
| Battery | SH1.25-2 Li-ion connector, onboard charger/protection |
| Extras | PRG button (GPIO0), white LED (GPIO35), Vext gate (GPIO36) |

**Do not power the board without the 915 MHz antenna fitted.** Transmitting into
an open port can damage the SX1262 PA. The default MVP transmits only the
pairing ACK; if B5.0 option A is approved, the one additional transmission is
the narrow Billows target-set frame. The antenna stays on whenever powered.

The V4 board is not a supported target. It may share the pin map; it is untested
and must not be assumed.

## 1.2 Pin map

| GPIO | Function | Direction / note |
|---|---|---|
| 0 | **PRG button** | Active LOW; strapping pin at reset; use after boot |
| 1 | Battery ADC (`ADC1_CH0`) | Divider output; see §1.3 |
| 8 | SX1262 NSS | SPI2 CS |
| 9 | SX1262 SCK | SPI2 |
| 10 | SX1262 MOSI | SPI2 |
| 11 | SX1262 MISO | SPI2 |
| 12 | SX1262 RST | Output |
| 13 | SX1262 BUSY | Input |
| 14 | SX1262 DIO1 | Input; the vendored driver polls, so this is optional |
| 17 | OLED SDA | I²C0 |
| 18 | OLED SCL | I²C0 |
| 21 | OLED RST | Output |
| 35 | White LED | Active HIGH, PWM-capable; unused by default in the MVP |
| 36 | Vext gate | **Active LOW** — drive LOW to power the OLED rail |
| 37 | Battery divider enable | **Active HIGH on this board revision** — drive HIGH to sample, then LOW |
| 43/44 | UART0 TX/RX | CP2102 console; keep available for flashing/logs |
| 19/20 | USB D−/D+ | Native USB |
| 45/46 | Strapping | Avoid |

Free pins: 2–7, 47, 48. They are reserved for a future Billows inline
controller or a second button; nothing in the MVP uses them. **GPIO3 is also a
strapping/JTAG strap on the ESP32-S3**, so verify the board schematic and the
boot state before using it as an output; 47/48 are the safer expansion pins.

### Verified hardware facts worth keeping

The legacy bench work established these; re-check them on the first new-board
sitting, but do not re-derive them from community pinouts:

- GPIO37 **HIGH enables** the battery divider; LOW disconnects it (the opposite
  of the legacy doc's first assumption, and the board-verified result).
- GPIO36 **LOW** powers the OLED rail. The I²C pull-ups live on that switched
  rail; power Vext before creating the I²C bus, or the controller can wedge.
- GPIO0 reads cleanly as a user button after boot with a ~30 ms debounce.
- The battery divider ratio is approximately **×4.9**; calibrate against a DMM
  when a second charge state is available.
- The OLED runs at 400 kHz with no observed errors while Wi-Fi/BLE are active;
  the new build only has BLE, so this is lower risk, not higher.

## 1.3 Battery measurement

The board has no fuel gauge and no charge-status line. The MVP reports voltage
and an estimated state of charge; it does not claim to know whether the pack is
charging.

Sampling procedure:

```c
gpio_set_level(ADC_CTRL_GPIO /*37*/, 1);   // enable divider on this board
esp_rom_delay_us(200);                      // settle
// oversample ADC1_CH0 (GPIO1), 12 dB atten, ~32 samples, calibrated
gpio_set_level(ADC_CTRL_GPIO, 0);           // disable to save quiescent current
v_batt = v_adc * 4.9f;                      // default; replace with calibrated ratio
```

Report:

- millivolts (integer),
- percent from a Li-ion discharge curve, not a linear map,
- `SOC_UNKNOWN (255)` until the first valid sample or if the divider is disabled.

The app and OLED must render unknown as "—", never 0%.

### USB vs battery

There is no reliable charge-detect pin. The MVP does **not** report USB or
charging state; it reports pack voltage/SoC only. Do not infer "charging" from
voltage, and do not make safety or power decisions from an inferred cable
state.

## 1.4 Power, on/off, and deep sleep

### On/off semantics

The board has no power switch. "Off" means **deep sleep**, not zero current:

- Vext off (OLED rail off),
- SX1262 put to sleep,
- BLE controller/host down,
- CPU in deep sleep with GPIO0 as the wake source.

"On" means wake from deep sleep and boot normally.

| Action | Behaviour |
|---|---|
| Hold PRG ≥ 1.5 s while on | Show a countdown; commit on release; enter deep sleep |
| Hold PRG ≥ 1.5 s while asleep | Wake; if still held at boot confirmation, stay on |
| Short press while asleep | Wake just long enough to confirm the hold, then return to sleep |
| Short press while on | Next OLED page; wakes the panel first |

The PRG hold must commit on **release**, not at the threshold. Releasing early
cancels. This is what makes a pocket press recoverable.

### The GPIO0 wake risk

GPIO0 is the ESP32-S3 ROM download strap. A wake press can, on some boot paths,
sample the strap and enter USB download mode instead of the application. The
legacy build recorded this as an unproven hardware risk. It is a **V0 gate**:

1. Wire the board, flash the application, and put it in deep sleep.
2. Hold PRG for 2 s and release.
3. Confirm the application boots, not the ROM downloader.
4. Repeat 20 times, including with USB attached and detached.
5. Record the result in `docs/hardware-verified.md` (new file).

If it fails, the fallback is the board's RST button for wake (and a documented
"hold RST" instruction), or a small external latch. Do not ship a power button
that sometimes bricks the boot.

### Current budget

| State | Estimate | Notes |
|---|---|---|
| On, BLE advertising, OLED asleep, LoRa RX | 25–45 mA | Dominated by CPU/radio; measure |
| On, BLE connected, OLED on | 35–60 mA | Live/History use |
| Deep sleep | 0.1–2 mA | Board regulator/CP2102 may dominate; measure |
| 3000 mAh pack, on, OLED sleep | ~70–100 h theoretical | Measure; do not publish until measured |

The 24 h target with BLE advertising and OLED sleeping is expected to pass; the
measurement is still a release gate.

## 1.5 OLED

- SSD1306, 128×64, I²C address `0x3C`.
- Vext (GPIO36) LOW before the bus is created.
- 1 KB page-ordered framebuffer, flushed only when dirty.
- 5×7 font for body, a 12×24 numeric face for the headline temperature and
  passkey.
- Display timeout default 60 s; configurable 30/60/120/never from the app.
- A button press wakes the panel but is consumed by the wake; it does not also
  change the page.

## 1.6 Enclosure

The existing `enclosure/out/case_v2_*.stl` case fits the Heltec V3, OLED window,
PRG button, USB-C, antenna, and a 3000 mAh pack. The MVP does not require a new
case. Two caveats:

- The case must not block the antenna or the battery connector.
- If Billows control is implemented as an inline fan controller, it needs a
  separate enclosure/connector; do not try to fit mains/12 V switching inside
  the existing case without a new design review.

## 1.7 Billows hardware

The Billows is a 12 V fan. It is powered through a fan adapter that plugs into
the Smoke X4's fan port. The Smoke X4 owns the fan control loop in the standard
product.

The bridge has **no proven electrical or RF control path** to the Billows. See
[08 — Billows](08-billows.md). The only hardware statement that can be made now:

- Do not connect 12 V to any ESP32 pin.
- Do not assume the fan adapter's control signal is a 3.3 V PWM input.
- Any inline controller needs a high-side switch, flyback protection, a fuse,
  and a separate 12 V ground/return review before it is connected to a fan.

## 1.8 Flash partition

The firmware uses a **no-OTA** layout: one application slot and one raw data
partition. This maximizes history for the MVP; USB is the update path.

| Name | Type | Offset | Size | Purpose |
|---|---|---|---|---|
| `nvs` | data/nvs | `0x9000` | 24 KB | config, bonds, counters |
| `phy_init` | data/phy | `0x11000` | 4 KB | RF calibration |
| `coredump` | data/coredump | `0x12000` | 56 KB | panic evidence |
| `factory` | app/factory | `0x20000` | 2 MB | application |
| `samples` | data/custom | `0x220000` | 5.875 MB | raw sample ring |

The `samples` partition is not a filesystem. It is a raw circular log with
4 KB sectors, described in [04](04-data-and-storage.md). Keeping it raw avoids
filesystem metadata and makes rotation a sector erase, not a file rewrite.

If the application outgrows 2 MB, shrink the data partition; do not add OTA
slots to the MVP.

## 1.9 Bench checklist (new build)

Do this once before firmware depends on the hardware:

- [ ] Confirm the board is the Heltec WiFi LoRa 32 V3 and the flash is 8 MB.
- [ ] Fit the 915 MHz antenna before power.
- [ ] Confirm battery pack polarity with a meter before connecting (the legacy
      pack was visually checked only; a replacement pack must be metered).
- [ ] GPIO37 HIGH enables the divider; GPIO1 tracks pack voltage; ratio ≈ 4.9.
- [ ] GPIO36 LOW powers the OLED; the I²C bus is created after Vext.
- [ ] GPIO0 reads as a button with 30 ms debounce after boot.
- [ ] OLED is legible at arm's length with the case fitted.
- [ ] LoRa RX works with BLE advertising and the OLED awake.
- [ ] Deep-sleep wake by PRG works 20/20 (the risk in §1.4).
- [ ] Measure on-current (advertising, OLED asleep), connected current, and
      deep-sleep current.
- [ ] Measure runtime on the 3000 mAh pack for at least 24 h.
- [ ] Record every result in `docs/hardware-verified.md`, not in a chat.
