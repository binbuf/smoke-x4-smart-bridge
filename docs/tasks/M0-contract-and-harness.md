# M0 — Contract & Harness

**Exit gate:** the protocol contract and generated codecs build; host tests run
in CI; the app has a BLE fake; the board identity is confirmed; the deep-sleep
wake question has an answer. No product feature is expected yet, but every later
task has a place to land.

**Design:** [00](../design/00-product.md), [01](../design/01-hardware.md),
[02](../design/02-smoke-x-protocol.md), [04](../design/04-data-and-storage.md),
[05](../design/05-ble-contract.md), [10](../design/10-test-and-release.md)

---

### T0.1 Workspace scaffold and ignore rules

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [00 §0.3](../design/00-product.md), [09](../design/09-legacy-audit.md)

Create the new tree beside `legacy/`:

```
firmware/    ESP-IDF project
app/         Flutter project
protocol/    records.yaml, ble.yaml, fixtures/, gen/
tools/       codegen, BLE fake host, bench scripts
docs/        design + tasks + hardware-verified.md
```

`legacy/` is read-only reference. Add `.gitignore` entries for build outputs,
`.dart_tool`, `build/`, `sdkconfig` local overrides, and generated files that are
not committed. Do not delete or move legacy files.

**Done when.** A clean clone can see the tree, and no new build output is
untracked.

---

### T0.2 Protocol contract and codegen

- **blocked-by:** T0.1 · **verify:** H · **board:** no
- **design:** [04 §4.2](../design/04-data-and-storage.md), [05](../design/05-ble-contract.md)

Write `protocol/records.yaml` (sample record, sentinels, flags, constants) and
`protocol/ble.yaml` (service UUID, characteristic slots, payload layouts,
control ops, result statuses). Generate:

- `protocol/gen/records.h` and `records.c` (C),
- `protocol/gen/records.dart` (Dart),
- a `--check` mode that fails if committed output drifts.

Use the legacy `records.yaml` as a shape reference only; the new layouts are in
the design docs. Include CRC16/CCITT-FALSE and the 24-bit sequence codec.

**Done when.** `make protocol` regenerates; `make protocol-check` is clean; a
host test encodes/decodes the `live` example vector in
[05 §5.4](../design/05-ble-contract.md).

---

### T0.3 Host test harness and fixtures

- **blocked-by:** T0.1 · **verify:** H · **board:** no
- **design:** [10 §10.2](../design/10-test-and-release.md)

Create a plain CMake host project under `firmware/test` that links the pure-C
components. Add:

- real X4 capture fixtures copied from `legacy/protocol/fixtures/lora/` into
  `protocol/fixtures/lora/` with the reports,
- X2-era parser vectors (defensive only),
- malformed/foreign-ID/detached/Celsius vectors,
- a RAM-backed `log_io` fake for ring tests,
- a test runner invoked by `ctest`.

**Done when.** `ctest` runs green on a machine with only gcc/cmake/ninja; the
fixtures are committed with provenance.

---

### T0.4 Firmware skeleton and partition table

- **blocked-by:** T0.1 · **verify:** H · **board:** no
- **design:** [01 §1.8](../design/01-hardware.md), [03 §3.3](../design/03-firmware-architecture.md)

Create the ESP-IDF project: `main.c`, `boot.c`, `tasks.h`, component stubs,
`sdkconfig.defaults`, `sdkconfig.defaults.heltec-v3`, and the no-OTA partition
table. Add the task-stack budget assert. Build for `esp32s3`.

**Done when.** `idf.py build` succeeds; `tasks.h` totals are asserted; the image
contains no Wi-Fi/HTTP/OTA components.

---

### T0.5 App skeleton

- **blocked-by:** T0.1 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-app.md)

Create the Flutter app: Android-only, Material 3 shell with Live/History/Settings
placeholders, a `BridgeController`, a repository seam, and a DB open path. Add
`flutter analyze` and a first widget test.

**Done when.** `flutter analyze` and `flutter test` pass; the app launches to an
empty Live tab on an emulator/device.

---

### T0.6 BLE fake and app test seam

- **blocked-by:** T0.2, T0.5 · **verify:** H · **board:** no
- **design:** [06 §6.10](../design/06-app.md), [05](../design/05-ble-contract.md)

Implement `BleClient` as an interface and `FakeBleClient` with scripted
advertisements, connect/bond states, MTU, reads/writes/notifications. Add a
`FakeBridge` that serves `info`, `live`, `config`, `stats`, and a small sync
stream using the generated codecs.

**Done when.** A widget test can drive scan → connect → bond → subscribe → one
live sample with no radio, and a disconnect moves the UI to the right state.

---

### T0.7 CI

- **blocked-by:** T0.2, T0.3, T0.4, T0.5 · **verify:** H · **board:** no
- **design:** [10 §10.1](../design/10-test-and-release.md)

Add CI jobs:

1. protocol generate + drift check,
2. C host tests,
3. firmware build,
4. Flutter analyze/test,
5. no-network/no-OTA dependency guard (fail if `http`, `web_socket`, MQTT, or
   OTA packages are added to the app/firmware).

**Done when.** A pull request runs all five and fails on drift.

---

### T0.8 Board identity, bench rig, and deep-sleep gate

- **blocked-by:** T0.4 · **verify:** B · **board:** yes
- **design:** [01 §1.4, §1.9](../design/01-hardware.md), [07 §7.7](../design/07-display-and-controls.md)

One bench sitting:

1. Confirm the board is the Heltec WiFi LoRa 32 V3, 8 MB flash, SX1262,
   SSD1306.
2. Fit the antenna; verify Vext/OLED, PRG, battery divider.
3. Flash a **bare BLE advertising + deep-sleep test image** (an IDF example,
   not the product service) and confirm advertising, then sleep.
4. Test hold-PRG wake 20 times with USB attached and detached.
5. Measure on/advertising/sleep current; run the pack for 24 h if time allows.
6. Record every result in `docs/hardware-verified.md`.

**Done when.** The board identity and the GPIO0 wake answer are written down. If
wake enters ROM download, record the fallback decision before any power-feature
work.

---

### T0.9 Baseline capture

- **blocked-by:** T0.8 · **verify:** B · **board:** yes
- **design:** [02 §2.9](../design/02-smoke-x-protocol.md)

With a real Smoke X4, on the bench (not during a live cook):

- pair the reference/legacy firmware or a capture build,
- record 30+ minutes of state traffic with all four probes, a detach/reattach,
  a °F/°C flip, and an alarm edge if practical,
- capture the sync beacon and the ACK.

Room-temperature probes are valid; the X4 broadcasts the same state whether it
is cooking or sitting on the bench. No cook is required.

Commit the logs and a short report under `protocol/fixtures/lora/`.

**Done when.** The new parser can replay the captures in a host test.

This is a bench sitting, not a staged cook. Ongoing field evidence is gathered
by V2.2; Billows-specific evidence is gathered in M5.

---

### T0.10 Deep-sleep and power decision record

- **blocked-by:** T0.8 · **verify:** B · **board:** yes
- **design:** [01 §1.4](../design/01-hardware.md)

Write the decision in `docs/hardware-verified.md`:

- Does hold-PRG wake work reliably?
- If not, what is the fallback (RST wake, external latch, or drop hold-to-on)?
- What is the measured deep-sleep current and expected pack runtime?

**Done when.** The firmware power tasks can proceed without re-litigating the
wake mechanism.
