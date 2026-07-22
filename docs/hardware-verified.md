# Hardware verification results — Heltec WiFi LoRa 32 V3

Results of the [01 §1.8](design/01-hardware.md) bench checklist (tasks V1.1–V1.6).
**Template status: every box below is ⏳ until a measured number or an explicit
outcome replaces it.** No box may be silently blank (V1.6).

How to measure: flash the bench diagnostic (`make bench-flash`, or
`idf.py -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec-v3;sdkconfig.bench" build flash monitor`
from `firmware/`) and transcribe its `BENCH`-prefixed log lines. The capture
runbook lives at [`tools/lora/README.md`](../tools/lora/README.md).

## V1.1 — battery connector and first power-up

| Check | Result |
| --- | --- |
| SH1.25-2 pack polarity vs board silkscreen (meter BEFORE connecting) | ⏳ |
| LoRa antenna fitted before first power | ⏳ |
| Board boots on battery | ⏳ |

## V1.3 — GPIO37 gate and battery divider (retires R6, gates F12)

| Check | Result |
| --- | --- |
| GPIO37 LOW gates the VBAT divider (ADC divider_ON vs divider_OFF differ) | ⏳ |
| Divider ratio at pack voltage #1 (DMM ÷ `adc_divider_ON`) | ⏳ V= adc= ratio= |
| Divider ratio at pack voltage #2 | ⏳ V= adc= ratio= |
| Verdict: ×4.9 (Heltec forum) or ×2.0 (ESPHome) or other | ⏳ |

If GPIO37 turns out unusable: record that outcome here explicitly — battery
reporting degrades to unavailable and nothing else breaks.

## V1.4 — button, LED, Vext, OLED I²C

| Check | Result |
| --- | --- |
| GPIO0 PRG reads reliably after boot; debounce survives boot strapping | ⏳ |
| GPIO35 LED is active-HIGH and dims under LEDC PWM | ⏳ |
| GPIO36 LOW required for the OLED rail (`vext-gate` line: off=NO_ACK, on=ACK) | ⏳ |
| OLED I²C @ 400 kHz stable with Wi-Fi AP active (`i2c` line: err count after ≥10 min) | ⏳ |
| OLED I²C stable with **BLE** active | **deferred → M3** (no BLE stack yet) |

## V1.5 — current draw and brownout

| Check | Result |
| --- | --- |
| AP mode, OLED on (est. ~145 mA) | ⏳ measured / unresolved (needs a current meter) |
| STA mode, modem sleep (est. ~70 mA) | ⏳ measured / unresolved |
| Real runtime on the 3000 mAh pack | ⏳ |
| Brownout when Wi-Fi AP starts on a depleted pack? | ⏳ |

## Deferred to later milestones (V1.6 table — do not close here)

| Deferred check | Why | Closes at |
| --- | --- | --- |
| Free heap ≥ 150 KB with AP + NimBLE + httpd + both LittleFS mounts | Our stack doesn't exist yet | F9 / F10 (M2–M3) |
| LoRa RX with BLE advertising **and** a WebSocket client streaming | Same | V3 (M3) |
| OLED I²C stable with BLE active | Reference has no BLE | M3 |

## V2 — capture campaign results

| Capture | Status |
| --- | --- |
| V2.2 sync beacon (6-comma) + our ACK | ✅ 2026-07-21 → [`x4-events-10min.loralog`](../protocol/fixtures/lora/x4-events-10min.loralog): sync field0=`000000` (not the X2's `020001`), freq 918.5 MHz decoded, our `SUCCESS` ACK captured |
| V2.1 X4 state traffic (26-comma), overnight | ⏳ overnight pending. 10-min event choreography done 2026-07-21: 37 state packets, hot-water curve, 2 real dropouts, cadence wobble during menu use |
| Stock ThermoWorks receiver still works after our pairing | ⏳ visually confirm and record here |
| Q1 / Q4 / Q8 / units manipulations performed | ✅ 2026-07-21 — Q1 never left `30`; Q4 detach `state=3` **freezes last temp, does not zero** (reattach jumps straight 3→0; shorted-jack state still uncaptured); Q8 trailing `new_alarm` is **edge-triggered**, one packet per alarm event; units flip confirms field 2 (1=°F, 0=°C), temps in tenths of active unit, alarm bands in whole degrees of active unit |
