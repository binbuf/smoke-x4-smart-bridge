# The slim firmware (`firmware/`)

The firmware at [`firmware/`](../firmware/) is the **BLE-only slim build**. It
replaces the full bridge archived at `firmware.old/` (git-ignored, reference
only). This page is the entry point; the full image's design notes (03, 05, 07,
08, 15) still describe the archived behaviour and are history, not this build.

## What it does

One job, well: receive the Smoke X4 over LoRa, record it to flash, draw it on
the OLED, and serve it over **Bluetooth**. There is no Wi-Fi, no HTTP/WebSocket
API, no MQTT, no OTA, and no device-tier alarm engine on this image.

| Kept | Dropped |
| --- | --- |
| `smoke_x`, `app_lora`, `cook_store`, `app_config`, `app_time`, `app_power` | `app_net` (Wi-Fi STA/AP, mDNS, DNS shim) |
| `app_ble` (device_info, device_control, live_state, history_preview, result, history_ctrl, history_data) | `app_api` (HTTP + WebSocket) |
| `app_ui` (Probes, Trends, **Bluetooth**, Radio, System) | `app_mqtt`, `app_ota`, `app_alarm` |
| `bridge_event`, `protocol/gen` codecs | the `net_status`/`wifi_*` GATT characteristics |

The shipped Flutter app (`app/`) uses only the kept characteristics, so the
wire contract it depends on is unchanged.

## Boot and tasks

- 11 boot steps: NVS → boot reason → config → event loop → power → UI →
  cook_store → smoke_x init → smoke_x start → time → BLE. LoRa comes up before
  BLE; only NVS and the event loop are fatal.
- 6 task rows (`main/tasks.h`), 22 KB of application stacks: `lora_rx` (core 1),
  `smoke_x`, `cook_store`, `app_ui`, `app_power`, `ble_push`.
- Partitions (`partitions.csv`): the old `www` carve-out is gone and `cooks`
  spans 0x2E0000 (2.875 MB). Dual OTA slots are retained for a future wired
  update.

## Reset and recovery (rethought for a networkless device)

The full image's only real recovery was double-reset → Wi-Fi AP mode. With no
Wi-Fi, recovery lives entirely on the device:

- **Double RST within 10 s** enters the recovery flow (main consumes the
  RTC-SRAM token).
- **Holding PRG through the post-boot splash** (≈3 s of the 5 s window) enters
  the same flow.
- The flow is **hold-to-confirm**: hold ~3 s, *release to reset*, release early
  to cancel. Committing wipes **bonds + config + recorded cooks**, then reboots.
  The archived reset forgot the `cooks` store entirely — this build fixes that
  (`cook_store_wipe_all`).

The button otherwise keeps its two meanings: **tap** = next page (wakes the
display), **hold** = power off (commit on release), and **hold ≥5 s from sleep**
= power on.

## Build and test

Host unit tests (no hardware; needs gcc + cmake + ninja):

```
cd firmware/test
cmake -S . -B build-local -G Ninja -DCMAKE_C_COMPILER=gcc
cmake --build build-local && ctest --test-dir build-local
```

Firmware (ESP-IDF v6.0.2):

```
idf.py -B build-local \
  -DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3 build
# flash a board (needs a USB-UART present):
idf.py -B build-local -p COMx flash monitor
```

Status at the time of writing: the image builds (≈643 KB, 75 % of the app slot
free) and **21/21 host suites pass** on gcc 16. It has **not been flashed to a
board** (no USB-UART was attached during the port), so the on-hardware rows —
OLED pages, the recovery gesture, BLE bonding, LoRa guard-time — are owed a
bench sitting.

## Owed

- A bench sitting on a real board: pages legible, the recovery gesture wipes
  and reboots, BLE bonds + history stream, LoRa RX cadence.
- OLED goldens for the new **Bluetooth** page (its content is covered by the
  render-all-pages test, not yet by a byte golden).
- Decide the update path: USB-only for MVP, or a BLE OTA later.
- Prune the now-inert config keys (`net/*`, `mqtt/*`, `alarms/*`, the AP PSK)
  from `app_config_store.h` and its host test when convenient.