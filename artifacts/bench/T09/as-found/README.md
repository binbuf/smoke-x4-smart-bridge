# T09 — as-found board state (before `erase-flash`)

Captured 2026-10-26 on COM5, board `ac:a7:04:38:82:74`.

## Identity and build

| Field | Value |
|---|---|
| Chip | ESP32-S3 (QFN56), revision v0.2 |
| Flash | 8 MB, GD (manufacturer `c8`, device `4017`), quad, 3.3 V |
| Crystal | 40 MHz |
| Base MAC | `ac:a7:04:38:82:74` |
| BLE MAC | `ac:a7:04:38:82:76` |
| Bootloader | ESP-IDF v6.0.2 second-stage, built Oct 11 2026 11:16:34 |
| Project / version | `smoke_bridge` / `1.0.0` |
| App compile time | Oct 11 2026 11:16:17 |
| App ELF SHA-256 | `098ca6ea8fa2094571b096c9e4aadb8b60cc24d5175457122b1b921099ec5135` |
| App image validation hash | `8e867adffc77635ae33ba47c3dd0e16e74526bd8187f8e7b052b6b560fa207c7` |
| Running slot | `ota_0` (otadata seq 1 points at `ota_0`) |
| Boot banner | `Smoke X4 Smart Bridge — BLE-only slim build` |
| Legacy pairing | 1 BLE bond stored; `sx_pair` holds `{918500000, 4c4d58435b5c0000, 4}` |

The legacy source tree under `legacy/` is gitignored and carries no `.git`
metadata, so the as-found image has no embedded git commit. The build was
identified by its app descriptor + ELF SHA-256 above. The local
`legacy/firmware/build-local/smoke_bridge.bin` is **not** byte-identical to the
image on the board (`185085199bc9fe6fb84abcd2c09bf7816a9b1dd0b5b1a87e0ed991b261b36566`
vs the dumped app), so it is not used as proof of the as-found build.

## As-found partition table (decoded)

```
nvs,data,nvs,0x9000,24K
otadata,data,ota,0xf000,8K
phy_init,data,phy,0x11000,4K
coredump,data,coredump,0x12000,56K
ota_0,app,ota_0,0x20000,2560K
ota_1,app,ota_1,0x2a0000,2560K
cooks,data,littlefs,0x520000,2944K
```

This is the legacy OTA-capable layout, not the new no-OTA T04 layout.

## Artifact inventory

| File | What |
|---|---|
| `flash-id.txt` | full `esptool flash-id` output |
| `partition-table-0x8000.bin` | raw partition table as found |
| `nvs-0x9000.bin` | raw 24 KiB NVS partition (the archive) |
| `nvs-dump-all.txt` | full NVS entry dump (written + erased) |
| `nvs-dump-minimal.txt` | live namespace/key view |
| `nvs-integrity.txt` | NVS page CRC check |
| `otadata-0xf000.bin` | OTA selection state |
| `app-ota_0-0x20000.bin` | 1 MiB app-slot read (0x20000..0x11ffff) |
| `app-image-info.txt` | `esptool image-info` on the dumped app |
| `pairing-entry.txt` | decoded legacy Smoke X4 pairing record |
| `pairing-entry-0x3080.bin` | the 16-byte pairing blob at NVS offset 0x3080 |
| `cooks-littlefs-0x520000.bin` | raw legacy cooks LittleFS partition (best effort; optional) |
| `SHA256SUMS.txt` | digests of every artifact above |

**Sensitive bytes:** the NVS blob necessarily contains the legacy Wi-Fi AP PSK
and NimBLE bond keys as they were on the board. It is archived as forensic
evidence only. Do not flash it back, do not reuse those credentials, and do not
copy the bond records into the new `bridge_config`; the new firmware has no
read path for this data.

## Raw evidence

Boot banner captured by resetting with RTS at 115200 baud:

```
I (394) smoke_bridge: Smoke X4 Smart Bridge — BLE-only slim build
I (394) smoke_bridge: task stack budget: 22016 B declared across 6 tasks
I (434) smoke_bridge: config store version 1
I (434) app_power: battery up: GPIO37 HIGH gates divider (V1.3), eFuse-calibrated ADC
I (594) app_ui: display up: SSD1306 @400 kHz, 5 pages, 20 ms button, LED on GPIO35
I (604) cook_store: /cooks mounted: 12 KB used of 2944 KB
I (1024) app_ble: NimBLE up: SmokeBridge-8274, 1 bond(s) stored
I (1024) smoke_bridge: boot complete: 11/11 steps
```
