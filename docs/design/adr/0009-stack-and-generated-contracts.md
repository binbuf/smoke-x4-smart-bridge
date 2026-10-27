# 0009 — ESP-IDF firmware, Flutter Android app, generated protocol contracts

## Status

Accepted

## Context

The bridge is an ESP32-S3 (Heltec V3) with a SX1262 radio and SSD1306 display.
The app must be a native Android BLE client. The C and Dart sides must agree on
record, BLE and control layouts without hand-maintained duplication.

## Decision

Build the firmware with ESP-IDF in C and the app with Flutter for Android. Keep
`protocol/records.yaml` and `protocol/ble.yaml` as the single source for record
and BLE layouts, and generate C and Dart codecs plus a drift check from them.

## Consequences

Firmware and app tasks cite the generated headers/sources rather than restating
byte layouts. Codegen drift fails CI. The repository keeps firmware, app,
protocol and tools in separate trees; `legacy/` remains read-only reference.
