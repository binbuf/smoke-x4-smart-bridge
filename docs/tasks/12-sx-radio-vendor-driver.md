# T12 — sx_radio: vendor the SX1262 driver

## Goal
A known-good `ra01s` SX1262 driver is pinned under `firmware/vendor/`, built as a normal ESP-IDF component, and attributable to its upstream commit and licence. Later radio work can configure the SX1262 without any network access at build time.

## Context (read first)
- [01 §1.2](../design/01-hardware.md) — Heltec V3 pin map and the verified hardware facts for the SX1262.
- [02 §2.1](../design/02-smoke-x-protocol.md) — the LoRa physical-layer parameters this driver must support.
- [09 §9.5](../design/09-legacy-audit.md) — the legacy tree names `legacy/firmware/vendor/esp-idf-sx126x` as the source to pin.
- `legacy/firmware/vendor/esp-idf-sx126x` — the known-good driver used by the legacy build; do not rewrite it.
- `firmware/vendor/esp-idf-sx126x/` — the new vendored location.
- `firmware/components/sx_radio/` — the eventual consumer; this task only vendors and wires the driver.
- **Verification:** H (host/CI). **Board:** no.
- Depends on T04.

## Scope
- [ ] Copy/pin the known-good `ra01s` driver from `legacy/firmware/vendor/esp-idf-sx126x` into `firmware/vendor/esp-idf-sx126x/`.
- [ ] Wire the vendored directory as an ESP-IDF component (component `CMakeLists.txt`, include paths, and the firmware build's component search path or explicit dependency).
- [ ] Record the upstream commit and the MIT licence with the vendored files, for example in a README or `LICENCE` beside the driver.
- [ ] Keep the upstream file notices intact; no behavioural fork of the driver.
- [ ] Confirm the component is compiled into a clean build and is available to `sx_radio`.
- [ ] Confirm the build does not fetch the driver, any submodule, or any package over the network.

## Out of scope
- Radio task, parameter block, RX loop, RSSI/SNR publishing, and the host radio seam → T13.
- Pairing state machine, frequency validation, retuning, and the pairing ACK TX path → T16.
- Board bring-up, pin definitions, Vext, and battery ADC → T09/T24.
- Any OTA or network update path: outside MVP; no task owns it.
- Wi-Fi/HTTP/WebSocket/MQTT: outside MVP; no task owns it.

## Design notes
- The driver is vendored source, not a build-time dependency: a clean checkout with no network must build.
- The vendored path is `firmware/vendor/esp-idf-sx126x/`, matching [03 §3.2](../design/03-firmware-architecture.md).
- Pin the exact legacy commit in the provenance note; "latest upstream" is not a pin.
- The SX1262 is owned by `sx_radio`; the vendored driver only exposes the chip API. Do not let other components call it directly.
- The driver must support the parameter set in [02 §2.1](../design/02-smoke-x-protocol.md): LoRa, SF9, 125 kHz (driver bandwidth index 4), CR 4/5, preamble 10, sync word `0x12`, CRC on, TCXO 3.3 V LDO.
- The legacy driver polls `BUSY`; DIO1 is optional and may remain unused.

## Done when
- [x] A clean build includes the vendored driver with no network fetch at build time.
- [x] The upstream commit and MIT licence are recorded in the vendored tree.
      **Deviation:** the legacy snapshot has no submodule commit, so
      `PROVENANCE.md` records the upstream URL, source snapshot and MIT licence
      but says the exact commit is not recoverable from this tree.
- [x] The firmware target build succeeds with the pinned ESP-IDF 6.0.x, `esp32s3`, no Wi-Fi/HTTP/OTA:
  ```bash
  idf.py -B build -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
  ```
- [x] No other component includes the vendor headers directly.
- [x] Hand-off below filled in.

## Hand-off

**Landed.** `ra01s` is copied unchanged into
`firmware/vendor/esp-idf-sx126x/components/ra01s/`, with `LICENSE`,
`README.md` and `PROVENANCE.md`. The top-level `firmware/CMakeLists.txt` adds
`vendor/esp-idf-sx126x/components` to `EXTRA_COMPONENT_DIRS`, and `sx_radio`
now `REQUIRES ra01s` and includes the header. Heltec V3 pins are set through the
driver's own Kconfig options in `sdkconfig.defaults.heltec-v3` (SCLK 9, MOSI 10,
MISO 11, NSS 8, RST 12, BUSY 13, no TXEN/RXEN, SPI2, 915 MHz).

**Deviation.** The legacy tree contains a `.gitmodules` entry but no submodule
commit, so the exact upstream commit cannot be pinned from this snapshot.
`PROVENANCE.md` records that limitation; if the commit is recovered, re-vendor
rather than editing the driver.

**Build evidence.** Product image built with IDF 6.0.2 for `esp32s3`;
`ra01s` appears in `build_components`, and `build/compile_commands.json`
compiles the vendored `ra01s.c`. The post-build image guard passed; host suite
4/4 passed.

**Next task.** T13 configures the radio and adds the RX loop; it should call the
driver only from `sx_radio`.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
