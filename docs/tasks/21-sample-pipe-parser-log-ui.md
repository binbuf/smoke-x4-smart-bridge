# T21 — sample_pipe: parser → log → UI

## Goal
The sample pipeline validates each packet, builds one 18-byte record, appends it to the ring, updates the live snapshot, counts packets, and marks the UI dirty. Bounded queues and drop counters keep the radio path non-blocking, and a replay of the committed `x4-t10-25min` capture produces exactly the expected records with no allocation on the path.

## Context (read first)
- [03 §3.6](../design/03-firmware-architecture.md) — the pipeline flow and its rules.
- [03 §3.3](../design/03-firmware-architecture.md) — `sample_pipe` stack 4096, priority 5, core 0; `log_writer` stack 4096, priority 4, core 0.
- [03 §3.11](../design/03-firmware-architecture.md) — bounded queues and drop-with-counter, never block on BLE.
- `firmware/main/main.c` — wiring only.
- `firmware/components/` — `sx_protocol`, `sample_log`, `bridge_state`, and the UI dirty flag.
- **Verification:** H/B. **Board:** no for the replay test; B on hardware.
- Depends on T14, T19, and T20.

## Scope
- [x] Wire the pipeline: validate the parsed state, build the record, append via `log_writer`, update `bridge_state`, and count the packet.
- [x] Add bounded queues between the parser/radio and the log writer; on overflow, drop the sample and increment `dropped_samples`.
- [x] Do not block the radio on flash. A full queue is a counted drop, not a stall.
- [x] Count valid state packets, parse/CRC failures, foreign device IDs, sync beacons seen, ACK attempts, and last packet age.
- [x] Wire `sample_pipe` to the UI dirty flag.
- [x] Mark the UI dirty only after the snapshot is updated; rendering is owned by T22.
- [x] Detect the first state packet after pairing and persist the learned probe count via T15.
- [x] Translate detached probes to `TEMP_DETACHED` before building the record.
- [x] Add a replay test for `protocol/fixtures/lora/x4-t10-25min.loralog` (41 state frames across ~22 min) that asserts the exact record count and live values.
- [x] Assert no heap allocation occurs on the sample path.

## Out of scope
- Radio RX, parameter block, and parser internals → T13/T14.
- Ring geometry, record codec, and flash binding → T17/T18/T19.
- Clock policy and snapshot fields → T20.
- UI page rendering and display sleep → T22.
- BLE notification queue, `live` characteristic, and sync → Phase 3 BLE tasks (T27–T37). A missed notification is not a data-loss path and is recovered by sync later.
- App-side history import → M3 history tasks (T39–T46).
- Alarms/notifications and any Wi-Fi/HTTP/OTA path: outside MVP; no task owns them.
- Billows TX/control: outside MVP; M5 (T56, T57, T59) is observation only.

## Design notes
- Pipeline from [03 §3.6](../design/03-firmware-architecture.md):
  ```text
  SX1262 packet → radio_rx → sx_radio (pairing/ID/frequency)
      → sample_pipe
          ├─► bridge_state_update(live snapshot)
          ├─► log_writer queue (fixed 18-byte record)
          └─► ble_tx queue (20-byte live notification)   /* later BLE task */
                └─► ui marks dirty
  ```
- At this milestone only the snapshot, log queue, counters, and UI dirty flag are wired; BLE enqueue is added by the BLE task.
- The parser rejects malformed input before a record exists; no partial record is written.
- Device-ID mismatch is dropped and counted by the parser; the pipeline does not retry or reinterpret it.
- The queue depth is fixed and bounded. Drop-with-counter is the only overflow behavior; never block the radio or log writer indefinitely.
- The sample path uses fixed/stack buffers only; no `malloc`, no `std::string`, no logging allocation.
- The live notification is best-effort in the BLE milestone; do not make recording depend on a connected phone.
- `sample_pipe` is pinned to core 0 with `log_writer`, away from the radio task on core 1.

## Done when
- [x] A replay of `x4-t10-25min.loralog` produces exactly the expected record count and live values.
- [x] No allocation occurs on the sample path.
- [x] A full log queue drops a sample, increments `dropped_samples`, and does not block the radio.
- [x] The snapshot updates before the UI is marked dirty.
- [x] Packet counters reflect valid, malformed, and foreign-ID inputs.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] On the board, a real X4 packet reaches both the ring and the live
      snapshot. **Deferred to T37** (human bench); the 30-minute capture replay
      is the gate now.
- [x] Hand-off below filled in.

## Hand-off
**Landed (2026-10-26).**

- `firmware/components/sample_pipe/` — pure-C `sample_pipe.c` plus
  `sample_pipe_esp.c` adapters. Public API in `include/sample_pipe.h`:
  `sample_pipe_init`, `sample_pipe_process`, `sample_pipe_complete`,
  `sample_pipe_counters`, and the ESP-only `sample_pipe_start`.
- Flow: classify by comma count → load pairing → `sx_protocol_parse_state()` →
  build the 18-byte record **and** `bridge_state_sample_t` → stamp → validate →
  queue. ACKs are ignored; sync beacons are counted; unpaired state frames are
  ignored; foreign IDs are counted separately from parse failures.
- Queue: static FreeRTOS queue of 8 `sample_pipe_pending_t`. `enqueue_log` uses
  a zero-tick `xQueueSend`; a full queue increments `dropped_samples` and does
  not publish or block. `log_writer` (4096/4/core 0) appends through
  `sample_log_append()`, then `sample_pipe_complete()` updates the snapshot and
  only then calls `ui_mark_dirty()`. The writer calls `bridge_state_tick()` and
  refreshes `bridge_state_set_storage_ok()` after each append.
- `sample_pipe` task: 4096/5/core 0, drains `sx4_radio_rx_take()`. Boot order is
  `sx_radio_init` → `sample_pipe_start` → `sx_radio_start`.
- UI dirty flag added to `ui.h`/`ui.c` as an atomic bool:
  `ui_mark_dirty`, `ui_dirty_take`, `ui_dirty_pending`.
- Detached probes are forced to `SX4_TEMP_DETACHED`; Celsius is canonical
  `temp_f10` with the source bit; attached bits match the sentinels.
- First paired state frame persists the learned probe count through
  `bridge_config_set_pairing()` (idempotent with T16's own save).
- `sx_radio.c` now calls `sx_protocol_note_crc_failure()` on CRC/header errors.
- Test `firmware/test/test_sample_pipe.c` (CTest `sample-pipe`) replays all 44
  lines of `x4-t10-25min.loralog` and asserts exactly 41 records, the first /
  detached / Celsius / last record values, the final live snapshot
  (805/800/807/801, RSSI -31, SNR 10), snapshot-before-dirty ordering, counters,
  a full-queue drop, append-failure publication, and zero heap allocations via
  GNU ld `--wrap` of malloc/calloc/realloc/free.
- Docs: design 03 §3.6 implementation notes; ADR 0029.

**Deviations / decisions.**
- The snapshot is published at append completion, not in the sample task,
  because the ring assigns the record sequence at append. This keeps the live
  `seq` consistent with the log. The accepted cost is that live display waits
  for the writer's queue (bounded and normally milliseconds).
- A dropped sample publishes nothing. Emitting a snapshot immediately would let
  FIFO completions of older records overwrite newer live values after a burst.
- `log_write_failures` is a new counter; a failed append still publishes live
  values but keeps the previous live sequence. Storage health is taken from
  `sample_log_storage_ok()`, not from an append result alone.
- No BLE enqueue was added (T27–T37 own it).

**Checks.**
- `cmake -S firmware/test -B firmware/test/build -G Ninja` + build: OK.
- `ctest --test-dir firmware/test/build --output-on-failure`: 13/13 passed;
  `sample-pipe` 0.03 s with allocation wrapping active.
- `idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`:
  project build complete; image guard ok (esp32s3, 70 components, no
  Wi-Fi/HTTP/OTA); `sx4_bridge.bin` 0x3cfc0 bytes, 88% free.
- Board gate deferred to T37; the 30-minute replay is the current gate.

**Next task must know.** T22 consumes `ui_dirty_take()`; it must not render from
the queue. T24 should take over `bridge_state_tick()` cadence and expose
`sample_pipe_counters()` in stats (clamp `dropped_samples` to the 16-bit wire
field). T27 adds a best-effort live enqueue; recording must not depend on it.
Keep `bridge_state_update()` after the append.
