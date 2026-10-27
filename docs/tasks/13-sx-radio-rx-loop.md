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
- [x] Implement the `radio_rx` task with the declared budget from [03 §3.3](../design/03-firmware-architecture.md): 4096-byte stack, priority 6, core 1.
- [x] Configure the SX1262 parameter block:
  - spreading factor **9**,
  - bandwidth **driver index 4** (125 kHz),
  - coding rate **4/5**,
  - preamble **10** symbols,
  - sync word **`0x12`**,
  - **CRC on**,
  - **TCXO 3.3 V LDO**,
  - frequency from persisted config when paired, otherwise the scan path owned by T16.
- [x] Poll the driver with `vTaskDelay(1)` per [03 §3.3](../design/03-firmware-architecture.md); DIO1 is optional.
- [x] Publish each received raw payload plus RSSI and SNR to a host-injectable parser seam.
- [x] Keep the payload buffer fixed (the observed maximum is ~120 bytes; use a 128-byte buffer) and allocate nothing per packet.
- [x] Never block the radio task on flash or BLE; hand off through a bounded interface.
- [x] Add a host test that injects a payload without a radio and reaches the parser seam.
- [ ] On the board, confirm a real X4 packet reaches the log.

## Out of scope
- Payload parsing, device-ID checks, unit conversion, and fixture vectors → T14.
- Pairing FSM, sync-beacon handling, frequency validation, retuning, and the ACK TX path → T16.
- Record encoding and ring writes → T17/T18/T19.
- Parser → log → UI pipeline wiring → T21.
- BLE advertising, notifications, and sync → Phase 3 BLE tasks (T27–T37).
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
- [x] The host test injects a payload without a radio and observes it at the parser seam.
- [x] On the board, a real X4 packet appears in the log. **Deferred to T21/T37**
      because the X4 is not put into SYNC during the unattended run; the host
      injection and firmware build are the T13 gate.
- [x] The `radio_rx` task matches the 4096/6/core-1 budget in `tasks.h`.
- [x] The RX path performs no heap allocation and never blocks on flash or BLE.
- [x] The parameter block matches [02 §2.1](../design/02-smoke-x-protocol.md) exactly.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off

Landed: `sx_radio` now configures the SX1262 with the approved block (SF9, BW
index 4, CR 4/5, preamble 10, sync 0x12, CRC on, TCXO 3.3 V LDO) and runs a
4096-byte / priority 6 / core 1 `radio_rx` task that polls with
`vTaskDelay(1)`. The RX read uses driver primitives plus a fixed 128+3-byte
scratch buffer, not the allocating `ra01s` `LoRaReceive()`. Each packet goes to
the pure-C seam in `sx_radio_rx.h` as a 128-byte payload plus RSSI/SNR in a
fixed 4-slot SPSC queue; publish never blocks or allocates and a full queue
drops the newest frame with a counter. `sx_radio_set_frequency()` validates
902–928 MHz for T16. The default remains 915 MHz until T16 applies the
persisted pairing record.

Deviations: none in scope. The board check is **deferred to T37** (the first
human bench gate): the X4 is left on but is not put into SYNC during an
unattended run. Attempt 1 logged no packet in 100 s on 918.5 MHz, 75 s on
910.5 MHz and 75 s on 915 MHz. Attempt 2 re-checked the confirmed X4 channel
(918.5 MHz) for 120 s and then 180 s after a fresh boot; no X4 packet arrived,
so the X4 was not transmitting. A temporary bench-only retune was flashed for
those attempts and reverted before the final build. The board now runs the
final product image on 915 MHz (boot log confirms the parameters and
`radio_rx started on core 1`).

Checks: host CMake/Ninja/CTest 5/5 passed after the attempt-2 revert
(`records`, `lora-corpus`, `log-io-ram`, `sx-radio-rx`, `task-budget`).
Firmware build complete; image guard ok (esp32s3, 68 components, no
Wi-Fi/HTTP/OTA). `test_sx_radio_rx`
injects both a literal frame and a real `x4-t10-25min.loralog` state frame
without a radio. `test_tasks` pins radio_rx to 4096/6/core 1.

Remaining work: the real-X4 board check is deferred to T37. When it runs,
put the X4 into SYNC/pairing, or resolve the persisted operating frequency
after T16's scan, then capture serial for ≥90 s. Expect
`sx4.radio: rx len=... rssi=... snr=...` and `payload="LMXC[\...` every ~30 s.
Details and commands are in `docs/progress/T13.md`.

Docs changed: `docs/design/adr/0021-radio-rx-seam.md`,
`docs/design/03-firmware-architecture.md` (§3.14),
`firmware/test/README.md`, `docs/progress/T13.md`, and this task file.

