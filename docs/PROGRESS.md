# Progress notes

<!-- symphony:digest:start -->
## Key facts (maintained by symphony — do not edit)

- **T01 — Workspace scaffold and ignore rules**: Root tree beside `legacy/`: `firmware/`, `protocol/` (`fixtures/`, `fixtures/lora/`,; Empty directories are tracked with `.gitkeep` (one per scaffold directory) so a
- **T02 — Protocol contract and codegen**: `protocol/records.yaml`: sample_rec (18 B), sector_header (16 B), temperature; `protocol/ble.yaml`: service UUID, all 8 characteristic slots with
- **T03 — Host test harness and fixtures**: `firmware/test` plain CMake/C11 project; `ctest` is the entry point.; `records` compiles `protocol/test/test_records.c` directly against
- **T04 — Firmware skeleton and partition table**: ESP-IDF 6.0.2 project root `firmware/CMakeLists.txt` targeting `esp32s3`.; `firmware/main/`:
- **T05 — App skeleton**: Production entrypoint: `app/lib/main.dart` → `app/lib/app/bootstrap.dart`.; `app/lib/app/bridge_controller.dart` is now the single
- **T06 — UI baseline and view-model seam**: Production view state in `app/lib/app/view_state.dart`: immutable; Screens and shared widgets now render view state: Live, History, full-screen
- **T07 — BLE fake and app test seam**: Production BLE seam: `app/lib/data/ble/ble_client.dart` with `BleClient`,; `BridgeController` and `createBridgeController` accept an optional `BleClient`.
- **T08 — CI**: `.github/workflows/ci.yml` — six separately named jobs, all on every pull; `tools/ci/check_forbidden_deps.py`: rejects forbidden app packages in
- **T09 — Board identity, bench rig, deep-sleep gate**: **Date:** 2026-10-26 · **Board:** Heltec WiFi LoRa 32 V3, ESP32-S3FN8, 8 MB,; Board identity confirmed without a human: ESP32-S3 rev v0.2, 8 MB GD flash,

## Task notes (maintained by symphony — do not edit)

- [T01](progress/T01.md) — Root tree beside `legacy/`: `firmware/`, `protocol/` (`fixtures/`, `fixtures/lora/`,
- [T02](progress/T02.md) — `protocol/records.yaml`: sample_rec (18 B), sector_header (16 B), temperature
- [T03](progress/T03.md) — `firmware/test` plain CMake/C11 project; `ctest` is the entry point.
- [T04](progress/T04.md) — ESP-IDF 6.0.2 project root `firmware/CMakeLists.txt` targeting `esp32s3`.
- [T05](progress/T05.md) — Production entrypoint: `app/lib/main.dart` → `app/lib/app/bootstrap.dart`.
- [T06](progress/T06.md) — Production view state in `app/lib/app/view_state.dart`: immutable
- [T07](progress/T07.md) — Production BLE seam: `app/lib/data/ble/ble_client.dart` with `BleClient`,
- [T08](progress/T08.md) — `.github/workflows/ci.yml` — six separately named jobs, all on every pull
- [T09](progress/T09.md) — **Date:** 2026-10-26 · **Board:** Heltec WiFi LoRa 32 V3, ESP32-S3FN8, 8 MB,
<!-- symphony:digest:end -->

Shared index for the symphony run. Each task session writes its own note file under the progress/
directory ("TNN.md") with what later tasks need to know: real paths, commands that work, contract
deviations, gotchas. Facts, not narrative. The harness keeps a generated "Key facts" digest and a link
to each task note in this file (between the symphony:digest markers); do not edit that block by hand.
