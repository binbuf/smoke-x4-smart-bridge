# T09 — bench artifacts, 2026-10-26

Board: Heltec WiFi LoRa 32 V3 · ESP32-S3FN8 · 8 MB · MAC
`ac:a7:04:38:82:74` · port COM5 · ESP-IDF 6.0.2.

| Directory | What |
|---|---|
| [`as-found/`](as-found/) | state before the wipe: legacy image descriptor, partition table, NVS archive, decoded Smoke X4 pairing, cooks partition |
| [`wipe/`](wipe/) | `erase-flash` log, post-erase blank reads and serial evidence |
| [`probe/`](probe/) | bench probe image, cold-boot log, 20 wake cycles, post-flash clean checks |

The findings and their caveats live in
[`docs/hardware-verified.md`](../../../docs/hardware-verified.md); the design
decision is [ADR 0020](../../../docs/design/adr/0020-gpio0-ext1-deep-sleep-wake.md).
Every binary here is a bench snapshot, not a release artifact.
