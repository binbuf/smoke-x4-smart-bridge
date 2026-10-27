# Hardware Verification

Results for the new build. Every row starts `⏳`; replace it with a dated result
and an artifact link. Do not leave a row silently blank.

**Board:** Heltec WiFi LoRa 32 V3 (confirm model/serial) · **Phone:** TBD ·
**Date started:** TBD

## Board identity and bring-up

| Check | Result | Evidence |
|---|---|---|
| Board is Heltec WiFi LoRa 32 V3, ESP32-S3FN8, 8 MB flash, SX1262, SSD1306 | ⏳ | |
| As-found image, version and partition layout recorded before flashing | ⏳ | |
| Legacy pairing/NVS state archived before the wipe | ⏳ | |
| `erase-flash` completed; follow-up partition-table read is clean | ⏳ | |
| Antenna fitted before first power | ⏳ | |
| Battery pack polarity metered before connection | ⏳ | |
| OLED Vext (GPIO36 LOW) and I²C bus order | ⏳ | |
| PRG (GPIO0) debounce after boot | ⏳ | |
| Battery divider: GPIO37 HIGH enables, ratio ≈ 4.9 | ⏳ | |

## Power

| Check | Result | Evidence |
|---|---|---|
| Deep-sleep wake by hold-PRG, USB attached, 20/20 | ⏳ | |
| Deep-sleep wake by hold-PRG, USB detached, 20/20 | ⏳ | |
| Early release returns to sleep | ⏳ | |
| Current: on + advertising + OLED asleep | ⏳ | |
| Current: on + connected + OLED awake | ⏳ | |
| Current: deep sleep | ⏳ | |
| Runtime: 24 h on the 3000 mAh pack | ⏳ | |

## Radio and storage

| Check | Result | Evidence |
|---|---|---|
| Real X4 pairs; stock receiver keeps updating | ⏳ | |
| Unpair/re-pair; stock receiver unaffected | ⏳ | |
| Four probes, detached probe, °F/°C flip | ⏳ | |
| Power cut mid-cook; earlier records survive | ⏳ | |
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
