# T56 bench evidence — passive Billows capture

**Status:** pass, 2026-10-28. Receive-only capture with a real Billows on a
real Smoke X4; no firmware change, no reflash, no transmitter.

Report: [`protocol/fixtures/lora/x4-billows-225-250-275.report.md`](../../../protocol/fixtures/lora/x4-billows-225-250-275.report.md)
and [`docs/progress/T56.md`](../../../docs/progress/T56.md).

## Run conditions

| Field | Value |
|---|---|
| Board | Heltec WiFi LoRa 32 V3, COM5 |
| Firmware | T55 release image, SHA-256 `02E2E2B4DA3013E14E3AED57A2D5505417B5214C263F2C7F43009ED3340F61F6`, not reflashed |
| X4 | `LMXC[\`, operating channel 918,500,000 Hz |
| Billows | real unit on channel 4, air probe at room temperature, fan unobstructed, no cook |
| Capture | `serial-t56.log`, product `sx4.radio` payload lines at ~30 s cadence |
| TX | none; no SYNC gesture and no pairing ACK in this session |

## Evidence

| File | Contents |
|---|---|
| `serial-t56.log` | raw console log: 17 state frames, `billows_attached` 0→1→0, probe 4 `max` 225/250/275 |
| [`../../protocol/fixtures/lora/x4-billows-225-250-275.loralog`](../../../protocol/fixtures/lora/x4-billows-225-250-275.loralog) | converted `loralog v1` fixture used by the host parser |

Result: the target is probe 4 `max` (not `max − 25`, not the midpoint);
`min` is `0` in fan mode. On detach `billows_attached` clears and probe 4
returns to the non-fan defaults `160`/`32`.
