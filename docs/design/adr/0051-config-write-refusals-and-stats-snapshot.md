# 0051 — Config writes refuse with ATT application errors; stats is one live snapshot

**Status:** Accepted (T47)

## Context

`config` (0007) is a full-struct Read/Write characteristic with no companion
notification, so a rejected write has no result-characteristic path like
`control`. `stats` (0008) is a read-only snapshot whose fields come from several
owners (sample log, bridge_state, battery, BLE link, heap, sample pipe). The app
already reads `stats` after secure connect; firmware must not mix two extent
reads or cache values across reads.

## Decision

- A `config` write is validated as one 80-byte struct by pure `ble_config.c`.
  Refusals reuse the result-status names from 05 §5.6 but are carried as ATT
  application errors (`0x80 | status`): `0x81` invalid, `0x82` unsupported
  (nonzero `billows_mode`), `0x87` storage. A refused body changes nothing.
- `device_name` follows the NVS rules: 1–15 UTF-8 bytes, no control bytes, NUL
  inside the 16-byte field. The reserved target and bytes 23–79 are ignored on
  write and zero on read.
- Accepted values are persisted with a single `bridge_config_set_device()`.
  A boot-installed callback then applies the display timeout to the UI sleep
  state and marks the next snapshot dirty; units are read from NVS by the next
  UI snapshot. No reboot is required.
- `stats` uses one extent snapshot for count/min/max/generation, then reads the
  min/max records for the two unix times. Every read builds a fresh view;
  reserved bytes and `billows_control` are always zero. The sample-pipe drop
  counter is published into the live snapshot so stats needs no extra
  component dependency.

## Consequences

- The app's config editor (T51) must map GATT status 0x81/0x82/0x87 to the
  named invalid/unsupported/storage copy; it must not blind-retry.
- Host tests pin the full 80/60-byte vectors, every refusal and Read Blob
  reassembly at MTU 23 without NimBLE.
- A future partial-write or per-field editor requires a new contract version;
  the device never merges a partial struct.
