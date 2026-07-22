# 01 — Hardware

Target board: **Heltec WiFi LoRa 32 (V3)** — sold as *"ESP32 LoRa V3 Development Board + 3000 mAh
Battery Set, Integrated WiFi Bluetooth SX1262 CP2102 0.96-inch OLED Display"*. Heltec part
`HTIT-WB32LA`. The V4 (`WiFi LoRa 32 V4`) shares the chip, radio, and GPIO map and should run the
same firmware unchanged; treat it as untested.

## 1.1 Silicon and memory

| | |
| --- | --- |
| MCU | **ESP32-S3FN8** — dual-core Xtensa LX7 @ up to 240 MHz |
| SRAM | **512 KB** internal, + 16 KB RTC SRAM, 384 KB ROM |
| **PSRAM** | **None.** The FN8 package is flash-only. This is the dominant constraint on the whole design |
| Flash | **8 MB** SiP, DIO |
| Radio (LoRa) | Semtech **SX1262**, 863–928 MHz band as sold for US (902–928 MHz), TX up to 21 ±1 dBm, RX sensitivity to −137 dBm |
| Radio (2.4 GHz) | Wi-Fi 802.11 b/g/n + **Bluetooth LE 5 only — no Bluetooth Classic** (ESP32-S3 has no BR/EDR) |
| Display | 0.96" 128×64 SSD1306 OLED, I²C |
| USB | Type-C via **CP2102** UART bridge (GPIO43/44); ESP32-S3 native USB also broken out (GPIO19/20) |
| Battery | SH1.25-2 (JST-SH 2-pin) connector, onboard Li-ion charger + protection |

> **The no-PSRAM fact drives three decisions.** NimBLE over Bluedroid (D6), streamed responses
> instead of a JSON DOM (D7), and a hard ceiling on concurrent HTTP/WebSocket clients (see
> [06](06-device-api.md)). Every design doc that allocates memory must justify it against §1.4.

## 1.2 GPIO map

Compiled from the Heltec V3 schematic/pinmap, the reference firmware's
`sdkconfig.defaults.heltec-v3`, and community pinouts. **Entries marked ⚠ must be confirmed on the
bench before firmware depends on them** — see §1.6.

### Reserved by onboard peripherals

| GPIO | Function | Notes |
| --- | --- | --- |
| 0 | **PRG button** | Strapping pin. Active LOW. Boot-mode select at reset, free for app use afterwards. Our only user input ([07](07-display-and-controls.md)) |
| 1 | **VBAT sense (ADC1_CH0)** | Through a resistor divider gated by GPIO37 ⚠ |
| 8 | SX1262 `NSS` | SPI2 chip select |
| 9 | SX1262 `SCK` | |
| 10 | SX1262 `MOSI` | |
| 11 | SX1262 `MISO` | |
| 12 | SX1262 `RST` | |
| 13 | SX1262 `BUSY` | |
| 14 | SX1262 `DIO1` | IRQ line. **The vendored `ra01s` driver polls rather than using DIO1** — see §1.5 |
| 17 | OLED `SDA` | I²C0 |
| 18 | OLED `SCL` | I²C0 |
| 21 | OLED `RST` | |
| 35 | **White LED** | Active HIGH, PWM-capable. Used for alarm signalling |
| 36 | **Vext control** | **Active LOW** (P-channel MOSFET). Must be driven LOW to power the OLED rail |
| 37 | **ADC_Ctrl** ⚠ | Drive LOW to enable the battery divider. See the conflict note below |
| 43 / 44 | UART0 TX/RX | CP2102 console — keep free for logs and Improv-Serial |
| 19 / 20 | USB D− / D+ | Native USB |
| 45 / 46 | Strapping | Avoid |

> ⚠ **GPIO37 conflict.** Several published pinouts list GPIO33–38 as "SPI flash / SubSPI — do not
> use". That guidance is for ESP32-S3 parts with **octal** PSRAM, which claim those pins. The FN8
> on this board has no PSRAM, and Heltec's own Arduino battery example uses GPIO37 as `ADC_CTRL`.
> Our design follows Heltec. Confirm with a scope/DMM before shipping: toggle GPIO37 and watch
> GPIO1's reading change.

### Free for expansion

`2, 3, 4, 5, 6, 7` (all ADC1 + touch capable), `47`, `48`.

Reserve **GPIO47 = NEXT** and **GPIO48 = SELECT** in the input abstraction so the optional
three-button variant is a config change rather than a rewrite (D3 / [07](07-display-and-controls.md)).
A piezo buzzer on GPIO7 (LEDC PWM) is the other obvious add-on; the firmware exposes a
`buzzer_enabled` config flag that is a no-op when unfitted.

**ADC2 is unusable while Wi-Fi is active.** All analogue expansion must stay on ADC1 (GPIO1–7).

## 1.3 Battery measurement

Reading procedure:

```c
gpio_set_level(ADC_CTRL_GPIO /*37*/, 0);   // enable divider
esp_rom_delay_us(200);                      // let it settle
// oversample ADC1_CH0 (GPIO1), 12 dB atten, ~64 samples, use esp_adc_cal / calibration scheme
gpio_set_level(ADC_CTRL_GPIO, 1);           // disable (saves the divider's quiescent draw)
v_batt = v_adc * VBAT_DIVIDER_RATIO;
```

**The divider ratio is disputed in public sources and must be calibrated:**

| Source | Claimed factor |
| --- | --- |
| Heltec community forum (390 kΩ / 100 kΩ, `VBAT = 100/(100+390) × VADC`) | **×4.9** |
| ESPHome device profile for this board | **×2.0** |

Do not hard-code either. Store `vbat_cal_num` / `vbat_cal_den` in NVS, default to ×4.9, and expose
a one-point calibration command (`POST /api/v1/config/device {"vbat_actual_mv": 4020}`) that
solves for the ratio against a DMM reading. State-of-charge is then a lookup against a Li-ion
discharge curve, not a linear map — a linear map reads "50%" for most of the cook and then falls
off a cliff.

## 1.4 RAM budget

Free heap at boot on a bare ESP32-S3FN8 app is ~380 KB. Planned allocation:

| Consumer | Estimate | Notes |
| --- | --- | --- |
| Wi-Fi driver (AP or STA) | 50–70 KB | Trim `CONFIG_ESP_WIFI_STATIC_RX_BUFFER_NUM` / dynamic TX buffers; we move tens of KB, not megabits |
| lwIP | 20–30 KB | |
| NimBLE host + controller | 35–45 KB | Bluedroid would be ~140 KB. Non-negotiable (D6) |
| `esp_http_server` | 8 KB + ~6 KB per open connection | Cap at 4 concurrent, 2 of them WebSocket |
| LittleFS (2 mounts) | 8–16 KB | Cache/lookahead sizes are tunable; larger cache = faster, more RAM |
| mDNS | ~4 KB | |
| Application task stacks | ~26 KB | lora_rx 4K, smoke_x 4K, cook_store 4K, ui 4K, alarm 3K, ble_app 4K, net 3K |
| Live sample ring (2 h @ 30 s) | 3.9 KB | 240 × 16 B |
| Scratch buffers | ≤ 6 KB | Streaming keeps these small by construction |
| **Total** | **~160–210 KB** | Leaves ~170–220 KB headroom |

Headroom is real but not generous. Rules that follow from it:

1. **No whole-history structures in RAM, ever.** History streams from flash in ≤ 2 KB chunks.
2. **No `cJSON` DOM larger than one status object.** Response bodies for lists are chunk-streamed.
3. Every task declares its stack in one table (`firmware/main/tasks.h`) so the total is auditable.
4. CI runs a heap watermark check: log `esp_get_minimum_free_heap_size()` and
   `uxTaskGetStackHighWaterMark()` per task once a minute at debug level; fail the soak test if
   free heap dips below 80 KB.

## 1.5 Radio configuration

The reference firmware's working SX1262 settings, which we inherit verbatim:

| Parameter | Value | Notes |
| --- | --- | --- |
| Driver | [`nopnop2002/esp-idf-sx126x`](https://github.com/nopnop2002/esp-idf-sx126x) (`ra01s`) | Vendored as a component. **Polling `LoRaReceive()`, not DIO1 interrupt-driven** |
| Spreading factor | 9 | |
| Bandwidth | index 4 = 125 kHz | SX126x driver uses an index, not Hz — unlike the SX1276 path |
| Coding rate | 1 = 4/5 | |
| Preamble | 10 symbols | |
| Sync word | 0x12 | Private-network sync word |
| CRC | on | |
| TX power | 22 dBm | Only ever used for the single pairing ACK |
| TCXO | 3.3 V, LDO regulator | `LoRaBegin(freq, 22, 3.3, 1)` |
| Frequency | 902–928 MHz, learned during pairing | X4 syncs on 915.0 MHz, X2 on 920.0 MHz |

Two consequences of the polling driver worth designing around:

- The RX task busy-loops with `vTaskDelay(1)` holding a radio semaphore. At the default 100 Hz tick
  that is ~100 wakeups/second — meaningful battery cost and it blocks any other radio access.
  **Improvement candidate:** move to DIO1-driven RX with a GPIO ISR + task notification, which also
  frees the CPU for Wi-Fi/BLE. Not on the v1.0 critical path; tracked in [11](11-roadmap-and-risks.md).
- Packets arrive at most every 30 s. There is no throughput pressure whatsoever — correctness and
  power, not speed, are the design axes.

> ⚠ **Never power the board with the LoRa antenna disconnected.** Transmitting into an open port
> can destroy the SX1262 PA. The bridge transmits only during pairing, but a mis-flash or a stray
> `POST /api/v1/radio/tx` could fire the radio. The firmware refuses any TX unless
> `pairing_mode == true`, and the antenna warning appears in the OLED first-boot screen.

## 1.6 Power budget

The headline question — *can it run a 24 hour cook on the 3000 mAh pack?* — depends entirely on
Wi-Fi mode.

Component draw (typical, from datasheets and comparable measurements; **all figures need bench
confirmation**):

| Component | Draw |
| --- | --- |
| ESP32-S3 @ 240 MHz, Wi-Fi **AP** beaconing (no sleep possible) | 100–130 mA avg |
| ESP32-S3 @ 240 MHz, Wi-Fi **STA** with `WIFI_PS_MIN_MODEM` | 40–70 mA avg |
| SX1262 continuous RX | ~5 mA |
| SSD1306 128×64, typical content | 7–15 mA |
| NimBLE advertising @ 1 s interval | 1–3 mA |
| Regulator + CP2102 quiescent | 3–6 mA |

Usable pack energy: 3000 mAh nominal, derate to ~2700 mAh after regulator loss and the
low-voltage cutoff.

| Scenario | Avg draw | Estimated runtime |
| --- | --- | --- |
| **AP mode, OLED always on** | ~145 mA | **~18.5 h — does not cover a 24 h cook** |
| AP mode, OLED sleeps after 60 s | ~133 mA | ~20 h |
| AP mode, OLED sleep + CPU 160 MHz + DFS | ~110 mA | ~24 h — marginal |
| **STA mode, modem sleep, OLED sleep** | ~70 mA | **~38 h** |
| STA mode, battery-saver profile | ~55 mA | ~49 h |

Design conclusions:

1. **A Wi-Fi AP cannot sleep** — it must stay awake to beacon and answer probes. AP mode is
   inherently the expensive mode. Say so in the app when the user picks it.
2. Note the reference firmware calls `esp_wifi_set_ps(WIFI_PS_NONE)` unconditionally — the
   worst case for battery. Our STA path uses `WIFI_PS_MIN_MODEM` and only disables power save when
   a WebSocket client is actively streaming.
3. **OLED auto-sleep after 60 s** (configurable, wake on button or alarm) is the cheapest single
   win and is in the v1.0 scope.
4. **Battery is for portability and ride-through, not for the whole cook.** The board charges over
   USB-C while running, so the supported long-cook setup is *USB power bank or wall adapter, with
   the pack as a UPS*. Document this prominently in the app's onboarding and in the README.
5. A `battery_saver` config profile (CPU 160 MHz, OLED 30 s, BLE adv 2 s, WebSocket push throttled)
   is exposed over the API and auto-engages below 20 % SoC, with a notification.

> ⚠ **SH1.25-2 polarity.** Heltec's battery connector polarity is not standardised across
> third-party packs. Reversed polarity destroys the board. Verify with a meter before the first
> connection; the "battery set" bundle should be correct but has been reported wrong.

## 1.7 Flash budget

| Region | Size | Contents |
| --- | --- | --- |
| App slots (×2) | 2.5 MB each | Estimated app image 1.6–1.9 MB (IDF base + Wi-Fi + BLE/NimBLE + httpd + LittleFS + mbedTLS for OTA). ~30 % headroom |
| `www` LittleFS | 512 KB | **Reserved, empty in v1** (D13). Would hold a gzipped fallback web UI; the reference's Vue bundle fits in ~200 KB gzipped |
| `cooks` LittleFS | 2.375 MB | Cook history. **~155,600 samples ≈ 1,290 h ≈ 54 days of continuous 30 s logging**, before ~10 % filesystem overhead |

Full table in [03 — Firmware Architecture §3.5](03-firmware-architecture.md).

Flash endurance is a non-issue at this cadence: ~46 KB of sample data per 24 h day, with LittleFS
metadata amplification realistically under ~100 KB/day of programmed bytes. Five years of daily
cooking is ~180 MB spread across a 2.375 MB wear-levelled partition — on the order of 100 erase
cycles per sector against a 100k-cycle rating.

## 1.8 Bench verification checklist

Run before any firmware depends on these. Record results in `docs/design/hardware-verified.md`.

- [ ] `GPIO37` LOW actually gates the VBAT divider; `GPIO1` reading tracks pack voltage
- [ ] Battery divider ratio, measured against a DMM at ≥ 2 pack voltages (resolves the ×4.9 vs ×2 conflict)
- [ ] `GPIO0` reads reliably as a user button after boot, with a debounce window that survives the boot strapping
- [ ] `GPIO35` LED brightness under LEDC PWM; confirm active-HIGH
- [ ] `GPIO36` LOW is required for the OLED to power up (matches the reference's `display_power_on()`)
- [ ] OLED I²C at 400 kHz is stable while Wi-Fi AP and BLE are both active
- [ ] Free heap at boot with Wi-Fi AP + NimBLE + httpd + both LittleFS mounts up — target ≥ 150 KB
- [ ] LoRa RX works with the OLED and BLE active (2.4 GHz / sub-GHz should not interact, but confirm)
- [ ] Measured current draw in each row of the §1.6 table, and real runtime on the 3000 mAh pack
- [ ] Charging while running: does the board brown out when Wi-Fi AP starts on a depleted pack?
- [ ] SH1.25-2 connector polarity on the supplied pack
- [ ] LoRa RX still functions with BLE advertising and a Wi-Fi client streaming over WebSocket

## Sources

- [Heltec WiFi LoRa 32 (V3) product page](https://heltec.org/project/wifi-lora-32-v3/)
- [Heltec WiFi LoRa 32 V3 wiki / datasheet](https://wiki.heltec.org/docs/devices/open-source-hardware/esp32-series/lora-32/wifi-lora-32-v3/)
- [espboards.dev pinout & specs](https://www.espboards.dev/esp32/heltec-wifi-lora-32-v3/)
- [Heltec community: VBAT read via GPIO1 / ADC_Ctrl GPIO37](http://community.heltec.cn/t/wifi-lora-32-v3-voltage-read-use-gpio1-vbat-read-question/12646)
- [ESPHome device profile — Heltec WiFi LoRa 32 V3](https://devices.esphome.io/devices/heltec-wifi-lora-32-v3/)
- [Community GPIO reference (boorker-watchdog)](https://github.com/SirPangolin/boorker-watchdog/blob/main/docs/hardware/heltec-v3-pinout.md)
- [`nopnop2002/esp-idf-sx126x`](https://github.com/nopnop2002/esp-idf-sx126x)
</content>
