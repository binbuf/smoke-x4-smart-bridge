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
| SH1.25-2 pack polarity vs board silkscreen (meter BEFORE connecting) | ⚠ 2026-07-22 — **visually verified only** (red wire aligned with the `+` silkscreen; owner decision to skip metering, no DMM used). The pack works, but this row is downgraded, not green: meter any *replacement* pack before its first connection. |
| LoRa antenna fitted before first power | ✅ fitted before the first power-up and never removed |
| Board boots on battery | ✅ 2026-07-22 — USB pulled with the pack connected; OLED and LED stayed alive; recovered cleanly on replug |

## V1.3 — GPIO37 gate and battery divider (retires R6, gates F12)

| Check | Result |
| --- | --- |
| GPIO37 LOW gates the VBAT divider (ADC divider_ON vs divider_OFF differ) | ✅ 2026-07-22 — the gate works, **but the sense is inverted vs the bench's assumption: GPIO37 HIGH enables the divider**, LOW disconnects (reads 0 mV). F12 must drive it HIGH to sample. |
| Divider ratio at pack voltage #1 (DMM ÷ `adc_divider_ON`) | ✅ adc=788 mV with the pack connected → pack ≈ 3.86 V at ×4.9. No DMM used: the verdict comes from Li-ion range arithmetic (×2.0 would put the pack at 1.58 V, impossible; ×4.9 lands mid-charge). |
| Divider ratio at pack voltage #2 | ⏳ unresolved — no second charge state measured. F12 self-calibrates against the 4.2 V full-charge plateau instead; a DMM point can refine later. |
| Verdict: ×4.9 (Heltec forum) or ×2.0 (ESPHome) or other | ✅ **×4.9** |

R6 is retired: GPIO37 is usable (with the HIGH-enable sense above) and
battery reporting is possible.

## V1.4 — button, LED, Vext, OLED I²C

| Check | Result |
| --- | --- |
| GPIO0 PRG reads reliably after boot; debounce survives boot strapping | ✅ 2026-07-22 — three presses logged cleanly (held 319/210/180 ms), no bounce artifacts, no phantom events |
| GPIO35 LED is active-HIGH and dims under LEDC PWM | ✅ visually confirmed fading both directions on the 5 s bench cycle |
| GPIO36 LOW required for the OLED rail (`vext-gate` line: off=NO_ACK, on=ACK) | ✅ off=NO_ACK, on=ACK + full SSD1306 init. **Gotcha for F11:** the I²C pull-ups hang off the switched rail — probing with the rail off wedges the `i2c_master` controller; recreate the bus after powering Vext (fixed in bench.c, applies to app_ui). |
| OLED I²C @ 400 kHz stable with Wi-Fi AP active (`i2c` line: err count after ≥10 min) | ✅ 1,160 transfers / **0 errors** over >10 min with the soft-AP up |
| OLED I²C stable with **BLE** active | **deferred → M3** (no BLE stack yet) |

## V1.5 — current draw and brownout

| Check | Result |
| --- | --- |
| AP mode, OLED on (est. ~145 mA) | **unresolved** — no current meter available; estimates stand |
| STA mode, modem sleep (est. ~70 mA) | **unresolved** — same |
| Real runtime on the 3000 mAh pack | ⏳ deferred — pack verified working; a full runtime soak is a future unattended run (pairs naturally with M6's V3 24 h soak) |
| Brownout when Wi-Fi AP starts on a depleted pack? | **unresolved** — needs a deliberately depleted pack; retest at M6 hardening |

## Deferred to later milestones (V1.6 table — do not close here)

| Deferred check | Why | Closes at |
| --- | --- | --- |
| Free heap ≥ 150 KB with AP + NimBLE + httpd + both LittleFS mounts | Our stack doesn't exist yet | F9 / F10 (M2–M3) |
| LoRa RX with BLE advertising **and** a WebSocket client streaming | Same | V3 (M3) |
| OLED I²C stable with BLE active | Reference has no BLE | M3 |

## M1 exit gate (F3.9, F5.11) — verified on the board 2026-07-22

| Check | Result |
| --- | --- |
| F3.9 pair → unpair → re-pair, stock receiver unaffected | ✅ Full cycle under our firmware: (1) flash-over-reference **adopted the existing pairing via the F7.2 v0→v1 migration** (booted CONFIRMED on 918.5 MHz, no re-sync); (2) erase = unpair; (3) fresh sync → single 15 B ACK **sent only after retuning** → CONFIRMED on first state message. Stock ThermoWorks receiver confirmed updating before, between, and after. |
| F5.11 session resumes across a real power cut | ✅ USB pulled mid-cook; on replug the §4.5 ladder reopened **the same session** (`store event RESUMED, session 00000001`, 416 ms into boot), wrote the `power restored` auto-mark, and continued appending. Evidence dumped off the flash via esptool+littlefs: [`protocol/fixtures/board/f511-power-cut.smk`](../protocol/fixtures/board/f511-power-cut.smk) — t monotonic `0..61 → 91..241` across the cut, marks at the seam, zero >45 s gaps. |
| Board-found bug (the reason F5.11 exists) | The first power-cut run exposed a uint32 underflow: post-resume `t` was computed as `uptime − started_uptime`, but uptime restarts with the boot → `t ≈ 4.29e9`. Fixed with an anchored resume base (`cook_session_resume_base_t`), host-tested, re-verified on the board in the committed evidence above. |

## V2 — capture campaign results

| Capture | Status |
| --- | --- |
| V2.2 sync beacon (6-comma) + our ACK | ✅ 2026-07-21 → [`x4-events-10min.loralog`](../protocol/fixtures/lora/x4-events-10min.loralog): sync field0=`000000` (not the X2's `020001`), freq 918.5 MHz decoded, our `SUCCESS` ACK captured |
| V2.1 X4 state traffic (26-comma), overnight | ⏳ overnight pending. 10-min event choreography done 2026-07-21: 37 state packets, hot-water curve, 2 real dropouts, cadence wobble during menu use |
| Stock ThermoWorks receiver still works after our pairing | ✅ 2026-07-22 — confirmed updating after the reference ACK (V2.2) and re-confirmed three times through our firmware's adopt/erase/re-pair cycle (F3.9 above) |
| Q1 / Q4 / Q8 / units manipulations performed | ✅ 2026-07-21 — Q1 never left `30`; Q4 detach `state=3` **freezes last temp, does not zero** (reattach jumps straight 3→0; shorted-jack state still uncaptured); Q8 trailing `new_alarm` is **edge-triggered**, one packet per alarm event; units flip confirms field 2 (1=°F, 0=°C), temps in tenths of active unit, alarm bands in whole degrees of active unit |
