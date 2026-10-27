# 0019 - Six-job pull-request CI gate

Status: accepted (T08)

## Context

Phase 1 lands the protocol contract, host suite, firmware/app skeletons, the
approved UI baseline and the BLE fake. Until T08 those checks existed only as
local commands; a stale generated codec, a host regression, a broken Heltec
build, an app/golden regression or a forbidden network/OTA package could reach
`main` unnoticed. Bench time is scarce (design 10 §10.1); the no-hardware layers
must be green before anyone reaches for a board.

## Decision

`.github/workflows/ci.yml` runs six stable, separately-attributable jobs on every
pull request (and on `main` pushes):

1. **protocol generate + drift check** — regenerate `protocol/gen`, fail on any
   `git diff`, then run `make protocol-check` and the C/Dart codec vectors.
2. **C host tests** — CMake + Ninja + `ctest` on `firmware/test`, no ESP-IDF.
3. **firmware build** — ESP-IDF `v6.0.2` container, `esp32s3`, the documented
   `sdkconfig.defaults;sdkconfig.defaults.heltec-v3` build; the post-link image
   guard is re-run explicitly.
4. **Flutter analyze/test** — `flutter analyze`, then the named view-state and
   layout matrix files, then the full `flutter test` suite (including the BLE
   fake flow).
5. **UI screenshot/golden check** — `flutter test tool/ui_screenshots_test.dart`
   against `app/screenshots/`; intentionally runs on `windows-latest` with the
   pinned Flutter version so the baseline is compared on the host that produced
   it.
6. **no-network/no-OTA dependency guard** — `tools/ci/check_forbidden_deps.py`
   plus its unit tests. It rejects forbidden app packages (direct and resolved
   transitive), release Android network/notification/foreground permissions,
   forbidden ESP-IDF components in `idf_component.yml`/`CMakeLists.txt`, and
   enabled Wi-Fi/IP/HTTP/MQTT/OTA `sdkconfig.defaults` symbols.

`legacy/` is never built or scanned. The app and protocol jobs use Dart 3.13.7 /
Flutter 3.47.8 to match the committed codecs and golden baseline.

## Consequences

- A stale `protocol/gen` fails job 1 even though the job regenerates it: the
  `git diff` is the gate, so generated files stay reviewable.
- A UI change fails job 5 until `flutter test --update-goldens` is run and the
  new PNGs are reviewed in the PR.
- Adding `http`, a WebSocket/MQTT package, an OTA package or an ESP-IDF network
  component fails job 6 before the firmware build can explain it.
- T54 expands `app/test/ui_state_matrix_test.dart` into the full state/copy
  matrix; job 4 already names it so coverage cannot silently disappear.
- Upgrading Flutter or ESP-IDF is a deliberate change to this workflow plus a
  golden regeneration; do not float either version.
- Board/bench verification stays manual (T09/T10); CI proves only the
  no-hardware layers.
