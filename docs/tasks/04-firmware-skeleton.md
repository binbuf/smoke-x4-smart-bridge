# T04 — Firmware skeleton and partition table

## Goal
Create the ESP-IDF project skeleton for `esp32s3` with the no-OTA partition
table and an enforced task-stack budget, so firmware feature work starts from a
buildable image that provably contains no networking or OTA components.

## Context (read first)
- Design: [01 §1.8](../design/01-hardware.md),
  [03 §3.3](../design/03-firmware-architecture.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T01.

## Scope
- [x] Create the ESP-IDF project with `main.c`, `boot.c`, and `tasks.h`.
- [x] Add component stubs.
- [x] Add `sdkconfig.defaults` and `sdkconfig.defaults.heltec-v3`.
- [x] Add the no-OTA partition table.
- [x] Add the task-stack budget assert.
- [x] Build for `esp32s3`.

## Out of scope
- Radio, parser, pairing, ring log, OLED/PRG behaviour — M1.
- Protocol codegen — owned by T02 (this task only consumes component stubs).
- BLE product service — M2.
- Wi-Fi/HTTP/OTA — no task; outside MVP (the image must not contain them).
- Board identity and bench confirmation — owned by T09.

## Design notes
- Target is `esp32s3`; the board-specific defaults file is
  `sdkconfig.defaults.heltec-v3`.
- The partition table is **no-OTA**; there is no OTA slot.
- Task-stack sizes live in `tasks.h`; totals are asserted at build/test time so
  the budget cannot silently regress.
- `boot.c` owns boot sequencing, `main.c` the entry point, `tasks.h` the task
  definitions and stack budget.
- The built image must contain no Wi-Fi, HTTP, or OTA components.
- Hardware details follow [01 §1.8](../design/01-hardware.md); architecture
  rules follow [03 §3.3](../design/03-firmware-architecture.md).

## Done when
- [x] `idf.py build` succeeds.
- [x] `tasks.h` totals are asserted.
- [x] The image contains no Wi-Fi/HTTP/OTA components.
- [x] Hand-off below filled in.

## Hand-off

### What landed

- ESP-IDF 6.0.2 project `firmware/` for `esp32s3`:
  `CMakeLists.txt`, `partitions.csv`, `sdkconfig.defaults`,
  `sdkconfig.defaults.heltec-v3`, `main/`, eight component stubs
  (`sx_protocol`, `sx_radio`, `sample_log`, `bridge_config`, `bridge_state`,
  `ble_service`, `ui`, `board`) and `tools/check_image.py`.
- `main.c` is the entry point; `boot.c` runs the design 03 §3.4 order with NVS
  fatal and every other step failure-tolerant; `tasks.h`/`tasks.c` hold one
  X-macro task table. Declared application stacks: 22,528 B against a 24 KiB
  `SX4_TASK_STACK_BUDGET_BYTES`, enforced by `_Static_assert` and the host
  `task-budget` test.
- No-OTA partition table: `nvs` 24K, `phy_init` 4K, `coredump` 56K, `factory`
  2M, raw `samples` 6016K (data subtype `0x40`), filling 8 MiB.
- Build whitelist `set(COMPONENTS main espcoredump)` plus a post-build guard that
  fails `idf.py build` if `project_description.json` contains a Wi-Fi/IP/HTTP/OTA
  update component, the target is not `esp32s3`, or `partitions.csv` has an OTA
  slot. `espcoredump` is linked so panic dumps use the coredump partition.
- ADR 0015; design 03 §3.3/§3.13 updated; `firmware/test/test_tasks.c` and
  `task-budget` added; T04 notes in `docs/progress/T04.md`.

### Deviations / decisions

- `app_update` remains in the linked component set: `esp_partition` privately
  requires it and only `esp_ota_get_running_partition` is linked (~188 B). The
  guard treats it as baseline; the no-OTA guarantee is the partition table and
  the absence of every OTA update component above it. Documented in ADR 0015.
- NimBLE is not linked in T04. ESP-IDF 6's `bt` component requires `esp_wifi`,
  which would put a Wi-Fi component in the image and fail the guard. T27/T30
  must add `bt` and record how that conflict is resolved; `sdkconfig.defaults`
  does not enable BT yet so the config is not silently dead.
- `housekeeping_start()` is not called: no component owns it yet. The task row
  is already in `tasks.h` and `boot.c` has a `TODO(T20/T24)` at the reserved
  boot step. The rest of the design 03 §3.4 order is implemented.
- Component stubs are intentionally `ESP_OK` no-ops; no radio, parser, storage,
  BLE or UI behaviour is implemented. `log_io.h` from T03 is unchanged.
- Partition `samples` uses numeric subtype `0x40`; IDF 6's CSV parser does not
  accept the literal `custom` subtype.

### Checks run

```text
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# 100% tests passed, 4/4 (records, lora-corpus, log-io-ram, task-budget)
make host-test
# 100% tests passed, 4/4

# ESP-IDF 6.0.2, clean firmware/sdkconfig and firmware/build
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete.
# image guard: ok (esp32s3, 61 components, no Wi-Fi/HTTP/OTA, no-OTA partition table)
# sx4_bridge.bin 0x2ad00 bytes, 92% of the 2M factory slot free

python firmware/tools/check_image.py --build-dir firmware/build \
  --partitions firmware/partitions.csv
# image guard: ok (...)

# negative probes (temp files): esp_wifi in build_components -> exit 1;
# an ota_0 partition row -> exit 1
```

On this bench activate IDF with
`$env:IDF_PYTHON_ENV_PATH='C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env'`
before `D:\esp\esp-idf\export.ps1`; the default py3.12 env has an outdated
esp-idf-monitor. Build from `firmware/` so artifacts stay under
`firmware/build/` (ignored).

### Next task must know

- Read `docs/progress/T04.md`: it has the exact IDF environment, whitelist,
  `app_update` and `bt`/`esp_wifi` caveats, partition-subtype gotcha and the
  follow-up list (T27/T30, T08, T12/T13, T20/T24, T09).
- Do not weaken `check_image.py` to add an HTTP/OTA component; that requires an
  ADR change. Adding a legitimate IDF component means adding it to
  `COMPONENTS` or a `REQUIRES` line and keeping the guard green.
- `tasks.h` is pure C and host-tested; edit the X-macro list, not a second
  table. Keep `sample_log/include/log_io.h` when implementing T19.
