# T13 — sx_radio: RX loop and parameters

## Goal
`sx_radio` owns the SX1262, configures the exact Smoke X LoRa parameters, and runs a receive task that publishes each raw payload with RSSI/SNR to the parser seam. The task never blocks on flash or BLE, so recording cannot stall on a slow peripheral.

## Context (read first)
- [02 §2.1](../design/02-smoke-x-protocol.md) — physical layer: SF9, bandwidth index 4 (125 kHz), CR 4/5, preamble 10, sync word `0x12`, CRC on, 902–928 MHz.
- [03 §3.3](../design/03-firmware-architecture.md) — the `radio_rx` task's stack, priority, core, and polling model.
- [01 §1.2](../design/01-hardware.md) — SX1262 pins on the Heltec V3.
- `firmware/components/sx_radio/` — driver wrapper, parameter block, and radio task.
- `firmware/vendor/esp-idf-sx126x/` — T12-vendored `ra01s` driver; only `sx_radio` may include it.
- `protocol/fixtures/lora/x4-t10-25min.loralog` — real X4 capture for the
  host-injected seam test (sync, ACKs, 41 state frames, detach/reattach,
  °F/°C). T14 owns the parser that consumes it.
- `firmware/main/tasks.h` — the single task table that declares stack/priority/core.
- **Verification:** H/B. **Board:** no for the host seam; yes for B.
- Depends on T12.
- The board currently runs the T10 capture probe. The board check cannot run
  until the product image is flashed over it.

## Scope
- [ ] Implement the `radio_rx` task with the declared budget from [03 §3.3](../design/03-firmware-architecture.md): 4096-byte stack, priority 6, core 1.
- [ ] Configure the SX1262 parameter block:
  - spreading factor **9**,
  - bandwidth **driver index 4** (125 kHz),
  - coding rate **4/5**,
  - preamble **10** symbols,
  - sync word **`0x12`**,
  - **CRC on**,
  - **TCXO 3.3 V LDO**,
  - frequency from persisted config when paired, otherwise the scan path owned by T16.
- [ ] Poll the driver with `vTaskDelay(1)` per [03 §3.3](../design/03-firmware-architecture.md); DIO1 is optional.
- [ ] Publish each received raw payload plus RSSI and SNR to a host-injectable parser seam.
- [ ] Keep the payload buffer fixed (the observed maximum is ~120 bytes; use a 128-byte buffer) and allocate nothing per packet.
- [ ] Never block the radio task on flash or BLE; hand off through a bounded interface.
- [ ] Add a host test that injects a payload without a radio and reaches the parser seam.
- [ ] On the board, confirm a real X4 packet reaches the log.

## Out of scope
- Payload parsing, device-ID checks, unit conversion, and fixture vectors → T14.
- Pairing FSM, sync-beacon handling, frequency validation, retuning, and the ACK TX path → T16.
- Record encoding and ring writes → T17/T18/T19.
- Parser → log → UI pipeline wiring → T21.
- BLE advertising, notifications, and sync → Phase 3 BLE tasks (T27–T38).
- Wi-Fi/HTTP/OTA and any other RF transmit path: outside MVP; no task owns it.
- Billows TX/control: outside MVP; M5 (T56–T60) is observation only.

## Design notes
- Pins from [01 §1.2](../design/01-hardware.md): NSS GPIO8, SCK GPIO9, MOSI GPIO10, MISO GPIO11, RST GPIO12, BUSY GPIO13, DIO1 GPIO14 (optional because the driver polls).
- The radio task is pinned to core 1, away from the BLE host on core 0.
- The parameter block is a single source of truth; do not scatter magic numbers through the task.
- Incoming packets are untrusted bytes: the radio layer publishes length + payload + RSSI/SNR and does not interpret the CSV.
- The task must not call NVS, flash, or BLE from the RX path.
- A single packet per ~30 s is the design cadence; correctness beats throughput. DIO1 interrupt handling is a post-MVP optimization.
- Frequency selection is constrained to 902–928 MHz; retuning for pairing is T16's responsibility, not an unchecked caller's.

## Done when
- [ ] The host test injects a payload without a radio and observes it at the parser seam.
- [ ] On the board, a real X4 packet appears in the log.
- [ ] The `radio_rx` task matches the 4096/6/core-1 budget in `tasks.h`.
- [ ] The RX path performs no heap allocation and never blocks on flash or BLE.
- [ ] The parameter block matches [02 §2.1](../design/02-smoke-x-protocol.md) exactly.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
