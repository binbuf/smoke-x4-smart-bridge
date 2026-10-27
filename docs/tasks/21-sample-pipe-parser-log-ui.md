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
- [ ] Wire the pipeline: validate the parsed state, build the record, append via `log_writer`, update `bridge_state`, and count the packet.
- [ ] Add bounded queues between the parser/radio and the log writer; on overflow, drop the sample and increment `dropped_samples`.
- [ ] Do not block the radio on flash. A full queue is a counted drop, not a stall.
- [ ] Count valid state packets, parse/CRC failures, foreign device IDs, sync beacons seen, ACK attempts, and last packet age.
- [ ] Wire `sample_pipe` to the UI dirty flag.
- [ ] Mark the UI dirty only after the snapshot is updated; rendering is owned by T22.
- [ ] Detect the first state packet after pairing and persist the learned probe count via T15.
- [ ] Translate detached probes to `TEMP_DETACHED` before building the record.
- [ ] Add a replay test for `protocol/fixtures/lora/x4-t10-25min.loralog` (41 state frames across ~22 min) that asserts the exact record count and live values.
- [ ] Assert no heap allocation occurs on the sample path.

## Out of scope
- Radio RX, parameter block, and parser internals → T13/T14.
- Ring geometry, record codec, and flash binding → T17/T18/T19.
- Clock policy and snapshot fields → T20.
- UI page rendering and display sleep → T22.
- BLE notification queue, `live` characteristic, and sync → Phase 3 BLE tasks (T27–T38). A missed notification is not a data-loss path and is recovered by sync later.
- App-side history import → M3 history tasks (T39–T46).
- Alarms/notifications and any Wi-Fi/HTTP/OTA path: outside MVP; no task owns them.
- Billows TX/control: outside MVP; M5 (T56–T60) is observation only.

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
- [ ] A replay of `x4-t10-25min.loralog` produces exactly the expected record count and live values.
- [ ] No allocation occurs on the sample path.
- [ ] A full log queue drops a sample, increments `dropped_samples`, and does not block the radio.
- [ ] The snapshot updates before the UI is marked dirty.
- [ ] Packet counters reflect valid, malformed, and foreign-ID inputs.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] On the board, a real X4 packet reaches both the ring and the live
      snapshot. **Deferred to T37** (human bench); the 30-minute capture replay
      is the gate now.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
