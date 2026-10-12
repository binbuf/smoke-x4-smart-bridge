<div align="center">

# Smoke X4 Smart Bridge

**Give your ThermoWorks Smoke X2/X4 a memory, a graph, and a phone.**

A small ESP32 board quietly listens to your Smoke X4, records every cook to flash for
~54 days, and serves it to an Android app over **Bluetooth**. Your stock receiver keeps working —
the bridge never transmits except for the single pairing acknowledgement.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Board](https://img.shields.io/badge/board-Heltec%20WiFi%20LoRa%2032%20V3-orange)
![Firmware](https://img.shields.io/badge/firmware-C%20on%20ESP--IDF-informational)
![App](https://img.shields.io/badge/app-Flutter%20on%20Android-blue)
![Radio](https://img.shields.io/badge/LoRa-915%20MHz%20listen--only-success)

</div>

---

This is the **slim build**: a BLE-only bridge and a three-screen phone app. It does one job well.
The larger Wi-Fi/HTTP/MQTT/OTA product described in some of the older design docs was cut, and the
active plan is now [`ROADMAP.md`](ROADMAP.md).

## What it is

- **A listener.** The Smoke X4 already shouts probe temperatures over LoRa every 30 seconds so
  its handheld can display them. The bridge is another set of ears: it decodes the same broadcast,
  writes it to flash permanently, and puts it on your phone. It transmits exactly **one** packet in
  its entire life — the pairing acknowledgement.
- **A recorder.** An append-only log on flash holds roughly 54 days of continuous 30-second
  samples. A power blip costs you nothing.
- **A display.** A 128×64 OLED shows the current temperatures and the pairing passkey in your hand,
  with no phone required.
- **A Bluetooth server.** The app reads live temperatures and full history over BLE. There is no
  Wi-Fi, no HTTP, no MQTT, and no over-the-air update.

## How it works

```mermaid
flowchart LR
    subgraph TW["ThermoWorks — untouched"]
        PR["probes"] --> SMOKE X4["Smoke X4<br/>Smoke X4"]
        SMOKE X4 -->|"LoRa 915/920 MHz<br/>broadcast, every 30 s"| RX["stock handheld<br/>receiver"]
    end

    subgraph BR["The bridge — Heltec WiFi LoRa 32 V3 · ESP32-S3"]
        SX["SX1262 → parser"] --> BUS(["sample bus"])
        BUS --> FS[("LittleFS<br/>~54 days of cooks")]
        BUS --> OLED["128×64 OLED"]
        BUS --> GATT["BLE GATT notify"]
    end

    subgraph APP["Android app — BLE only"]
        LIVE["Live"]
        GRAPH["Graph"]
        HIST["History"]
    end

    SMOKE X4 ==>|"the same broadcast,<br/>nothing subscribed"| SX
    SX -.->|"one packet, ever:<br/>the pairing ack"| SMOKE X4
    GATT ==>|"live temps +<br/>full history"| APP
```

## The app

Three destinations, plus a connection sheet and a cook clock:

| Screen      | What it does                                                                                  |
| ----------- | --------------------------------------------------------------------------------------------- |
| **Live**    | The bridge's probes in jack order (two on an X2, four on an X4), each with temperature and freshness; the connection chip; the cook clock. |
| **Graph**   | The recorded samples for the selected session, split at gaps.                                  |
| **History** | Every recorded session, newest first; tap one for its detail and chart.                        |

The connection sheet (opened from the status chip) scans, bonds, and names the bridge. The cook
clock is a phone-owned timer that runs even when the link drops.

## Hardware

| Part                                            | Notes                                                                          |
| ----------------------------------------------- | ------------------------------------------------------------------------------ |
| Heltec WiFi LoRa 32 **V3**                      | ESP32-S3 + SX1262 + 128×64 OLED. V2 is a different radio and is not supported. |
| 915 MHz antenna                                 | **Fit it before first power-up.**                                              |
| ThermoWorks Smoke X2 or X4                      | X4 is the target; X2 falls out of the same parser.                             |
| USB-C cable · 3000 mAh SH1.25-2 pack (optional) | The pack is a UPS, not a power plan.                                           |

## Build and flash the bridge

The firmware is an ESP-IDF project. Host unit tests need only a C toolchain — no ESP-IDF, no
hardware:

```bash
make test-host     # C unit tests — gcc + cmake + ninja
```

Building and flashing the image needs ESP-IDF:

```bash
make build             # build the firmware
make flash-monitor     # build, flash, and open the serial monitor (PORT=COMx to pick a port)
```

> **Status:** the image builds and the host suites pass, but it has **not yet been flashed to a
> board**. The on-glass rows — OLED pages, the recovery gesture, BLE bonding, LoRa RX cadence — are
> still owed a bench sitting. See [`docs/firmware-slim.md`](docs/firmware-slim.md) and
> [`docs/hardware-verified.md`](docs/hardware-verified.md).

Once a release image exists, [`scripts/deploy.sh`](scripts/deploy.sh) writes it over USB with only
`esptool` — no compiler:

```bash
./scripts/deploy.sh doctor                     # what's installed, what's missing
./scripts/deploy.sh bridge --image <file.bin>  # write a released merged image at offset 0x0
```

## Install the app

Connect an Android phone (7.0+) with USB debugging enabled.

```bash
./scripts/deploy.sh app     # builds a release APK and installs it (needs Flutter + adb)
```

For development, run it with hot reload against a connected device:

```bash
make app.run                                   # cd app && flutter run
cd app && flutter analyze && flutter test      # the app's own gate
```

## Pairing

Pairing has two independent halves:

1. **Phone ↔ bridge (BLE).** On first run the bridge shows a six-digit passkey on its OLED. The
   phone's OS asks you to confirm it; read the digits off the bridge. The bond is remembered, so
   later connects are silent.
2. **Bridge ↔ Smoke X4 (LoRa).** On the Smoke X4, hold **SYNC** until the bridge's OLED confirms
   the pairing. This is the bridge's single LoRa transmission.

The [ROADMAP](ROADMAP.md) has the known gaps here: the app does not yet show or drive the
Smoke X4-pairing state (S1.2), and there is no guided first-run flow (S1.3).

## Honest limitations

- **Bluetooth only.** No Wi-Fi, HTTP/WebSocket API, MQTT / Home Assistant, or OTA. Updating the
  firmware means USB.
- **No device-side alarms, guided cooks, or CSV export.** The bridge records and displays; the app
  shows live, graph, and history.
- **The clock starts unset.** The bridge records sessions with no wall clock until a phone writes
  one, so early History rows show `—` timestamps. Setting the clock automatically on connect is
  [S1.1](ROADMAP.md).
- **Smoke X LoRa traffic is unencrypted and unauthenticated.** Anyone within roughly a mile with an
  SX1262 can read your probe temperatures. That is a property of the product, not of this bridge.
  The bridge never forwards raw LoRa frames anywhere.
- **Long cooks want USB power.** Runtime on the battery is not yet measured; run it from a wall
  adapter or a power bank, with the battery as a UPS.

## Repository map

```
firmware/   ESP-IDF project (ESP32-S3) + host-testable components + test/ (plain CMake)
app/        Flutter app (Android first), package smoke_bridge — BLE-only
protocol/   the contract: records.yaml, ble-gatt.md, fixtures/, gen/
tools/      protogen (codegen) · cookgen · flash · lora · oled · soak · sim (archived-HTTP)
scripts/    deploy.sh — the USB flash + app install path
docs/       design docs (mostly historic), task backlog, firmware-slim notes, roadmap
```

`protocol/` is the single source of truth. Byte layouts are generated from
[`records.yaml`](protocol/records.yaml) into **both C and Dart**, and CI fails if the committed
outputs drift — so a C struct and a Dart model cannot quietly disagree.

## Docs

- [`ROADMAP.md`](ROADMAP.md) — **the active plan** for the slim build.
- [`docs/firmware-slim.md`](docs/firmware-slim.md) — what the firmware does, and what it owes.
- [`docs/new-app.md`](docs/new-app.md) — the app's layout and commands.
- [`docs/hardware-verified.md`](docs/hardware-verified.md) — bench results.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contributor setup and the protocol-change flow.

[`docs/design/`](docs/design/README.md) and [`docs/tasks/`](docs/tasks/README.md) describe the
larger full-bridge product and are **historical** — read them for the protocol and hardware work
that still applies, not as the shipping plan.

## Provenance and attribution

Protocol decoding, the SX1262 driver integration, and the pairing handshake derive from
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver) (MIT © 2022 G-Two), vendored
read-only at [`docs/reference/smoke-x-receiver`](docs/reference/PROVENANCE.md). Files carried over
retain the upstream notice. `docs/reference/` is never edited.

**This project is not affiliated with or endorsed by ThermoWorks.** Smoke X is a trademark of its
owner; it is used here only to describe compatibility.

## License

MIT — see [LICENSE](LICENSE).