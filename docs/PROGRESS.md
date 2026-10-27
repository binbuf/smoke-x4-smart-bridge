# Progress notes

<!-- symphony:digest:start -->
## Key facts (maintained by symphony — do not edit)

- **T01 — Workspace scaffold and ignore rules**: Root tree beside `legacy/`: `firmware/`, `protocol/` (`fixtures/`, `fixtures/lora/`,; Empty directories are tracked with `.gitkeep` (one per scaffold directory) so a
- **T02 — Protocol contract and codegen**: `protocol/records.yaml`: sample_rec (18 B), sector_header (16 B), temperature; `protocol/ble.yaml`: service UUID, all 8 characteristic slots with
- **T03 — Host test harness and fixtures**: `firmware/test` plain CMake/C11 project; `ctest` is the entry point.; `records` compiles `protocol/test/test_records.c` directly against
- **T04 — Firmware skeleton and partition table**: ESP-IDF 6.0.2 project root `firmware/CMakeLists.txt` targeting `esp32s3`.; `firmware/main/`:

## Task notes (maintained by symphony — do not edit)

- [T01](progress/T01.md) — Root tree beside `legacy/`: `firmware/`, `protocol/` (`fixtures/`, `fixtures/lora/`,
- [T02](progress/T02.md) — `protocol/records.yaml`: sample_rec (18 B), sector_header (16 B), temperature
- [T03](progress/T03.md) — `firmware/test` plain CMake/C11 project; `ctest` is the entry point.
- [T04](progress/T04.md) — ESP-IDF 6.0.2 project root `firmware/CMakeLists.txt` targeting `esp32s3`.
<!-- symphony:digest:end -->

Shared index for the symphony run. Each task session writes its own note file under the progress/
directory ("TNN.md") with what later tasks need to know: real paths, commands that work, contract
deviations, gotchas. Facts, not narrative. The harness keeps a generated "Key facts" digest and a link
to each task note in this file (between the symphony:digest markers); do not edit that block by hand.
