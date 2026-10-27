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
- **T13 — sx_radio: RX loop and parameters**: **Date:** 2026-10-26 · **Board:** Heltec WiFi LoRa 32 V3 · COM5 · IDF 6.0.2; `firmware/components/sx_radio/sx_radio.c` — real SX1262 bring-up and the
- **T14 - sx_protocol: parser port and canonical conversion**: **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done; `firmware/components/sx_protocol/include/sx_protocol_types.h` - the
- **T15 — bridge_config: typed NVS store**: **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done; `firmware/components/bridge_config/include/bridge_config.h` — the typed API:
- **T16 — sx_radio: pairing state machine and TX guard**: **Date:** 2026-10-26 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/sx_radio/include/sx_radio_pair.h` — pure-C pairing API:
- **T17 - sample_log: record codec**: `firmware/components/sample_log/include/log_core.h` / `log_core.c`:; `SAMPLE_LOG_RECORD_SIZE` (18) and `sample_log_record_size()`;
- **T18 — sample_log: ring geometry**: `firmware/components/sample_log/include/log_core.h`; geometry constants: 4,096 sector, 32 header (two 16-byte copies), 225
- **T19 — sample_log: flash adapter and boot recovery**: `firmware/components/sample_log/include/sample_log.h` — firmware API:; `include/log_storage.h` — pure-C `sample_log_storage_state_t`
- **T20 — bridge_state: clock and live snapshot**: **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done; `firmware/components/bridge_state/include/bridge_state.h` — public API:
- **T21 — sample_pipe: parser → log → UI**: **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done; `firmware/components/sample_pipe/include/sample_pipe.h` — pure-C pipeline
- **T22 - ui: pages, renderer, and display sleep**: **Date:** 2026-10-26 - **Verification:** host + firmware build - **Result:** done; `firmware/components/board/include/board.h` + `board.c`
- **T23 - ui: PRG gestures and deep sleep**: **Date:** 2026-10-26 - **Verification:** host + firmware build - **Result:** done; `firmware/components/ui/include/ui_button.h` + `ui_button.c`
- **T24 - board: battery ADC and power stats**: **Date:** 2026-10-26 - **Verification:** host + firmware build - **Result:** done; `firmware/components/board/include/board_battery.h`
- **T25 — Bench prep: pair, stock receiver, power cut**: **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done; `artifacts/bench/T37/CHECKLIST.md` — the T37 procedure for real X4 pairing,
- **T26 — Bench prep: cadence and display**: **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done; `tools/bench/cadence_report.py` — parses a product serial capture
- **T27 — ble_service: GATT server and `info`**: **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/ble_service/include/ble_info.h`, `ble_info.c` — pure C11
- **T28 — ble_service: live notify**: **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/ble_service/include/ble_live.h`, `ble_live.c` — pure C11
- **T29 — ble_service: control, result, and the clock**: **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/ble_service/include/ble_control.h`, `ble_control.c` —
- **T30 — ble_service: security, passkey, and advertising**: **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/ble_service/include/ble_adv.h`, `ble_adv.c` — pure C11
- **T31 — ble_service: sync status and recent records**: **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/ble_service/include/ble_sync.h`, `ble_sync.c` — pure C11:
- **T32 - app: BLE client and scan**: **Date:** 2026-10-27 · **Verification:** host/CI + Android debug build · **Result:** done; `app/lib/data/ble/ble_client.dart`
- **T33 — app: setup and passkey flow**: **Date:** 2026-10-27 · **Verification:** host/CI · **Result:** done; `app/lib/features/setup/setup_flow.dart`
- **T34 — app: Live screen**: **Date:** 2026-10-27 · **Verification:** host/CI widget tests · **Result:** done; `app/lib/app/view_state.dart`: `LiveViewState` gained
- **T35 — app: link procedures and time sync**: **Date:** 2026-10-27 · **Verification:** host/CI (`flutter test`, `flutter analyze`) · **Result:** done; `app/lib/data/ble/bridge_protocol.dart`
- **T36 — app: recent History (V0)**: **Date:** 2026-10-27 · **Verification:** host/CI (`flutter analyze`, `flutter test`) · **Result:** done; `app/lib/data/recent_history_store.dart` — `RecentHistoryStore` implements
- **T37 — Bench: V0 residual physical gate**: **Date:** 2026-10-27 · **Verification:** real Pixel 11 Pro Fold + Heltec V3 +; Phone: Pixel 11 Pro Fold, Android 17 / API 37, wireless ADB
- **T39 — ble_service: full sync cursor, gap, and generation**: **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done; `firmware/components/ble_service/ble_sync.c`:

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
- [T13](progress/T13.md) — **Date:** 2026-10-26 · **Board:** Heltec WiFi LoRa 32 V3 · COM5 · IDF 6.0.2
- [T14](progress/T14.md) — **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done
- [T15](progress/T15.md) — **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done
- [T16](progress/T16.md) — **Date:** 2026-10-26 · **Verification:** host/CI + firmware compile · **Result:** done
- [T17](progress/T17.md) — `firmware/components/sample_log/include/log_core.h` / `log_core.c`:
- [T18](progress/T18.md) — `firmware/components/sample_log/include/log_core.h`
- [T19](progress/T19.md) — `firmware/components/sample_log/include/sample_log.h` — firmware API:
- [T20](progress/T20.md) — **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done
- [T21](progress/T21.md) — **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done
- [T22](progress/T22.md) — **Date:** 2026-10-26 - **Verification:** host + firmware build - **Result:** done
- [T23](progress/T23.md) — **Date:** 2026-10-26 - **Verification:** host + firmware build - **Result:** done
- [T24](progress/T24.md) — **Date:** 2026-10-26 - **Verification:** host + firmware build - **Result:** done
- [T25](progress/T25.md) — **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done
- [T26](progress/T26.md) — **Date:** 2026-10-26 · **Verification:** host/CI (no board) · **Result:** done
- [T27](progress/T27.md) — **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done
- [T28](progress/T28.md) — **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done
- [T29](progress/T29.md) — **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done
- [T30](progress/T30.md) — **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done
- [T31](progress/T31.md) — **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done
- [T32](progress/T32.md) — **Date:** 2026-10-27 · **Verification:** host/CI + Android debug build · **Result:** done
- [T33](progress/T33.md) — **Date:** 2026-10-27 · **Verification:** host/CI · **Result:** done
- [T34](progress/T34.md) — **Date:** 2026-10-27 · **Verification:** host/CI widget tests · **Result:** done
- [T35](progress/T35.md) — **Date:** 2026-10-27 · **Verification:** host/CI (`flutter test`, `flutter analyze`) · **Result:** done
- [T36](progress/T36.md) — **Date:** 2026-10-27 · **Verification:** host/CI (`flutter analyze`, `flutter test`) · **Result:** done
- [T37](progress/T37.md) — **Date:** 2026-10-27 · **Verification:** real Pixel 11 Pro Fold + Heltec V3 +
- [T39](progress/T39.md) — **Date:** 2026-10-27 · **Verification:** host/CI + firmware compile · **Result:** done
<!-- symphony:digest:end -->

Shared index for the symphony run. Each task session writes its own note file under the progress/
directory ("TNN.md") with what later tasks need to know: real paths, commands that work, contract
deviations, gotchas. Facts, not narrative. The harness keeps a generated "Key facts" digest and a link
to each task note in this file (between the symphony:digest markers); do not edit that block by hand.
