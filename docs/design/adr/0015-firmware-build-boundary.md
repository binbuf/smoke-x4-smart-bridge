# 0015 — Firmware build boundary, task budget, and image guard

Status: accepted (T04)

## Context

The MVP is BLE-only, updates over USB, and must not carry Wi-Fi, an IP stack,
HTTP, or OTA update code (ADR 0001, ADR 0006). ESP-IDF builds every component in
the IDF tree unless a project limits the set, and an unreviewed `REQUIRES` line
can silently reintroduce a network component. Separately, the task table in
design 03 §3.3 is a memory budget; it must fail the build, not just a review,
when stacks grow.

ESP-IDF 6 has two stock dependencies that matter here: `esp_partition` privately
requires `app_update` (only `esp_ota_get_running_partition` is pulled in), and
the `bt` component requires `esp_wifi` — even for a NimBLE-only build. Neither
can be removed without patching IDF.

## Decision

- The firmware project sets `set(COMPONENTS main espcoredump)` before
  `project()`. Only `main`, the panic coredump handler and their transitive
  requirements are built. Adding a component is an explicit edit to that list.
- `firmware/tools/check_image.py` runs as a post-`POST_BUILD` step and fails the
  build if `build/project_description.json` contains a network, HTTP, or OTA
  update component (`esp_wifi`, `lwip`, `esp_netif`, `esp_http_*`,
  `esp_https_ota`, `tcp_transport`, `esp-tls`, …), if the target is not
  `esp32s3`, or if `partitions.csv` contains an OTA slot.
- `app_update` is not on the forbidden list: it is a mandatory baseline
  dependency of `esp_partition`. The no-OTA guarantee is the partition table
  (no OTA slot) plus the absence of every update component above it. The linked
  `app_update` code is 188 B (running-partition lookup only).
- `main/tasks.h` is one X-macro table. `SX4_TASK_STACK_TOTAL` (22,528 B) is
  compared to `SX4_TASK_STACK_BUDGET_BYTES` (24 KiB) with `_Static_assert`, and
  the host `task-budget` test re-checks the table at CTest time.
- `bt` is intentionally not in the build yet. T27 must add it together with a
  decision about its `esp_wifi` requirement; the guard should not simply be
  loosened.
  *(T27: resolved by ADR 0034 — `bt` is in the build, a local header-only
  `esp_wifi` override compiles no Wi-Fi code, and the guard checks linked
  objects instead of component names.)*

## Consequences

- `idf.py build` is the verification: the guard and the static assert fail the
  same command that produces the image.
- Later tasks that need an IDF component must add it to `COMPONENTS` (or as a
  `REQUIRES` of a listed component) and keep the guard green. Adding Wi-Fi,
  HTTP, or OTA is a deliberate ADR-level change, not an incidental dependency.
- The declared application stacks exclude the NimBLE host/controller task; its
  memory stays in the heap budget of design 03 §3.12.
- The guard is a build-time check; it does not inspect a flashed board.
