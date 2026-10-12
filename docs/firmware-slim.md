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

## Headless lifecycle (reset, pairing, advertising)

The device is deliberately headless: its button has exactly two meanings, and
everything else happens in the app.

- **Tap** = next info page (wakes the display).
- **Hold** = power off (commit on release); **hold ≥5 s from sleep** = power on.
- **Nothing else.** There is no on-device factory-reset gesture. The full
  image's double-reset → Wi-Fi AP mode and the slim build's short-lived
  double-RST / boot-hold recovery are both gone. Factory reset, reboot, and
  power-off are `device_control` ops the app drives over BLE
  (`BRIDGE_CONTROL_OP_FACTORY_RESET`, `REBOOT`, `POWER_OFF`).

Pairing is **Just Works + bonding + Secure Connections** (no MITM): any phone
that scans the device bonds and encrypts automatically, with no passkey to
read off the glass. `device_info` is open; every other characteristic needs
the encrypted link a bond provides, and `device_control` needs only that bond
(not an MITM-protected key). This is the trade the MVP makes for a device with
one button and no passkey display — a phone in BLE range can bond and read
recorded cooks.

The radio is **always advertising unless connected**: advertising starts on
host sync and restarts on disconnect, failed connect, and adv-complete. A
newly freed device is discoverable within one advertising interval, so the app
can find and (re)connect with no device interaction.

## Device administration (v1.2)

Because the bridge owns no controls, the settings its OLED once kept private are
exposed to the app (`device_info.caps` b7 `admin`):

- `device_stats` (read) — uptime, heap, storage, LoRa radio + packet counts,
  bonds: the System/Radio pages as data.
- `device_config` (read) — the current probe names/roles/targets and the
  display/LED/buzzer/retention preferences, so the app can show values before
  editing them.
- `set_probe` / `set_device_prefs` control ops — the writes.

The app surfaces these under **Settings** (Device preferences, Device stats)
and a **Probes** editor.

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

## Update path (decided)

**USB-only for the MVP.** An update is a `firmware/` rebuild flashed over the
USB-UART with `idf.py -p COMx flash`; there is no over-the-air or BLE update
path on this build. The dual OTA slots are retained so a wired update can
later write the inactive slot, but the BLE `app_ota` characteristic and the
Wi-Fi OTA flow are gone. The OLED **Bluetooth** page has a committed byte
golden (`page-bluetooth-{connected,advertising}.fb`), and the `net/*`, `mqtt/*`,
`alarms/*` and AP-PSK config keys have been pruned.

## Owed

- A bench sitting on a real board: pages legible, Just Works pairing + bond,
  history stream, LoRa RX cadence, and the app driving factory reset over BLE.