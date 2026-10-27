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
- [ ] Create the ESP-IDF project with `main.c`, `boot.c`, and `tasks.h`.
- [ ] Add component stubs.
- [ ] Add `sdkconfig.defaults` and `sdkconfig.defaults.heltec-v3`.
- [ ] Add the no-OTA partition table.
- [ ] Add the task-stack budget assert.
- [ ] Build for `esp32s3`.

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
- [ ] `idf.py build` succeeds.
- [ ] `tasks.h` totals are asserted.
- [ ] The image contains no Wi-Fi/HTTP/OTA components.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
