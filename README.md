# Smoke X4 Smart Bridge

A monorepo that extends the **ThermoWorks Smoke X2/X4** wireless thermometer with:

1. **Firmware** for a Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262) that passively receives the
   base station's 915 MHz LoRa broadcasts, decodes them, **persists full multi-day cook history
   to flash**, and serves it over Wi-Fi (HTTP + WebSocket) and Bluetooth LE.
2. **A Flutter app** (Android first) that discovers the bridge, provisions its network mode over
   BLE, and shows live probe temperatures, a long-cook graph, alarms, and cook history.

Start with the design docs: [`docs/design/README.md`](docs/design/README.md). The execution plan
lives in [`docs/tasks/`](docs/tasks/README.md).

## Three things you should know up front

- **The bridge is a listener, never a transmitter.** It transmits exactly **one** LoRa packet in
  its entire lifetime — the pairing acknowledgement — and that invariant is enforced in code and
  by unit test ([02 §2.5](docs/design/02-smoke-x-protocol.md)). The stock ThermoWorks receiver
  keeps working; pairing the bridge unpairs nothing.
- **Smoke X LoRa traffic is unencrypted and unauthenticated.** Anyone within roughly a mile with
  an SX1262 can read your probe temperatures, and could in principle forge packets. That is a
  property of the product, not of this bridge — but you deserve to know it. The bridge never
  forwards raw LoRa frames anywhere.
- **Long cooks should run on USB power.** A Wi-Fi AP cannot sleep; in hosted-AP mode the 3000 mAh
  pack lasts roughly 18 hours — less than a brisket. The supported long-cook setup is USB power
  (wall adapter or power bank) with the battery as a UPS ([01 §1.6](docs/design/01-hardware.md)).

## Repo map

```
firmware/    ESP-IDF v5.4 project (ESP32-S3) + host-testable components + test/ (plain CMake)
app/         Flutter app (Android first), package smoke_bridge
protocol/    ★ the contract: records.yaml, openapi.yaml, ble-gatt.md, fixtures/, gen/ (committed)
tools/       protogen (codegen) · cookgen (synthetic cooks) · sim (fake bridge) · lora · flash
docs/        design docs, task backlog, read-only reference snapshot (MIT © 2022 G-Two)
```

The `protocol/` directory is the single source of truth (decision D10). Byte layouts are
generated from [`protocol/records.yaml`](protocol/records.yaml) into both C and Dart by
`tools/protogen`; CI fails if the committed outputs drift.

## Quickstart (no hardware required)

```bash
# Host unit tests — C record codec, event guard, boot sequence (gcc + cmake, no ESP-IDF)
make test-host

# Dart suites — record parity, contract lint, cookgen, sim
dart pub get && dart test tools/bridge_protocol tools/protogen tools/cookgen tools/sim

# The fake bridge: serves the full device API from a synthesized 18-hour brisket
dart run sim --port 8080 --speed 60 --cook fixtures/brisket-18h.smk

# The app, against the simulator
cd app && flutter run
```

> The design docs spell the simulator command `dart run tools/sim …`; `dart run` takes a package
> name, so from the repo root the working spelling is `dart run sim …` (the pub workspace maps
> it). `make sim` does the same thing.

Firmware builds need ESP-IDF v5.4 (`make setup build`, or the `espressif/idf:release-v5.4`
container CI uses). Flashing the board: `make flash-monitor`.

## Status

M0 (foundations) — see [`docs/tasks/M0-foundations.md`](docs/tasks/M0-foundations.md). The
bench-verification and capture tasks (V1.x, V2.x) require the physical board and a real cook;
everything host-verifiable is built and tested here first.

## Open decisions

| # | Question | Needed by |
| --- | --- | --- |
| **Q-F** | **Public repo or private?** Affects licensing posture and whether the browser installer can live on GitHub Pages. Also tracked in [`docs/tasks/standing-work.md`](docs/tasks/standing-work.md). | before M6 / first release |

## Provenance and attribution

Protocol decoding, the SX1262 driver integration, and the pairing handshake derive from
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver) (MIT © 2022 G-Two),
vendored read-only at [`docs/reference/smoke-x-receiver`](docs/reference/PROVENANCE.md). Files
carried over retain the upstream notice. `docs/reference/` is never edited.

**This project is not affiliated with or endorsed by ThermoWorks.** Smoke X is a trademark of
its owner; it is used here only to describe compatibility.

## License

MIT — see [LICENSE](LICENSE).
