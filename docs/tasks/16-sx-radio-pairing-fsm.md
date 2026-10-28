# T16 — sx_radio: pairing state machine and TX guard

## Goal
The bridge pairs with one real Smoke X4 through the sync-beacon handshake, persists `{device_id, frequency_hz, num_probes}`, and treats the pairing ACK as the only LoRa transmit path. A lost link is shown as lost; the bridge never silently follows a different unit.

## Context (read first)
- [02 §2.4](../design/02-smoke-x-protocol.md) — sync ACK format and the rule that it is sent once on the operating frequency.
- [02 §2.5](../design/02-smoke-x-protocol.md) — state-message fields used to learn the probe count and confirm the link.
- [02 §2.7](../design/02-smoke-x-protocol.md) — the pairing state machine and its rules.
- [03 §3.5.3](../design/03-firmware-architecture.md) — `UNPAIRED → SYNC_RECEIVED → CONFIRMED (PAIRED) → LOST → PAIRED`.
- `firmware/components/sx_radio/` — FSM, frequency validation, and ACK path.
- `firmware/components/bridge_config/` — persisted pairing record (implemented by T15).
- **Verification:** H/B. **Board:** no for the FSM and TX-guard host tests; B on hardware.
- Depends on T13 and T15.

## Scope
- [x] Implement `UNPAIRED → SYNC_RECEIVED → CONFIRMED/PAIRED` and the `LOST` state.
- [x] While unpaired, alternate the sync scan between **915 MHz** and **920 MHz** every **3.3 s**.
- [x] On a sync beacon, parse the device ID and the four little-endian frequency bytes; decode the operating frequency (for example `160,50,191,54` → `918,500,000 Hz`).
- [x] Validate the decoded frequency against **902–928 MHz** before any retune or transmit.
- [x] Retune to the operating frequency and send exactly one ACK of the form `<device_id>,SUCCESS,` with a trailing comma.
- [x] Learn `num_probes` from the comma count of the first state message, not from the sync beacon.
- [x] Persist `{device_id, frequency_hz, num_probes}` only after `CONFIRMED`.
- [x] Enter `LOST` after **10 minutes** without a valid state packet; keep the radio tuned and return to `PAIRED` when packets resume.
- [x] Make the sync handler the only call path to the radio TX function.
- [x] Add a host test asserting no other path can reach TX and that an out-of-band frequency never retunes or transmits.
- [x] On the board, pair a real X4 and confirm the stock receiver keeps
      updating. **Deferred to T37**; the host FSM/TX-guard tests are the gate.

## Out of scope
- Sync/state parsing internals and fixture corpus → T14.
- NVS getters/setters and validation → T15.
- App-driven `unpair_smoke_x` / Re-pair action and its UI → M4 settings (T47–T55); its bench pass is a later app verification, not this task.
- BLE pairing/passkey and connection state → Phase 3 BLE tasks (T27–T37).
- Any LoRa TX other than the pairing ACK, including a Billows control path: outside MVP; no task owns it. M5 (T56, T57, T59) is receive-only observation.
- Automatic re-pair to a different unit after a lost link: deliberately excluded.
- OTA/Wi-Fi/HTTP: outside MVP; no task owns it.

## Design notes
- FSM rules from [02 §2.7](../design/02-smoke-x-protocol.md):
  1. After an accepted sync, ignore further sync beacons until an explicit unpair/re-pair.
  2. Probe count comes from the first state message.
  3. The ACK goes on the operating frequency, never the sync channel.
  4. Ten minutes of silence means `LOST`; do not scan for another unit and do not clear pairing.
  5. Unpairing clears pairing and restarts scanning; it does not affect the stock receiver or the log.
  6. A re-synced X4 on a new channel stays lost until the user re-pairs; the visible lost state is intentional.
- The ACK is the only LoRa transmission in the product. Keep it behind one private function and assert no other call sites.
- Frequency bytes are a little-endian `uint32` in Hz; reject malformed or out-of-range values before tuning.
- Validate before mutating state: a failed beacon leaves the FSM and radio tuning unchanged.
- `LOST` is a status state, not an unpair. A reboot never clears pairing.
- Pairing data is independent of log data: clearing the log or forgetting phones does not unpair the X4.

## Done when
- [x] The host test asserts that no path other than the sync handler reaches TX.
- [x] An out-of-band frequency never retunes and never transmits.
- [x] A real X4 pairs on the board and the stock receiver keeps updating.
      **Deferred to T37** (the first human bench gate). T16 is accepted on the
      host FSM/TX-guard evidence; the X4 is left on but is not put into SYNC
      during the unattended run.
- [x] A silent paired X4 enters `LOST` after 10 minutes and returns to `PAIRED`
      on the next valid packet. Host-test only; the real 10-minute wait is T37.
- [x] `{device_id, frequency_hz, num_probes}` survives a reboot.
      Host-test evidence: the fake store reloads the saved record into a fresh
      FSM, which tunes the stored frequency and stays `PAIRED`.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off
Landed:
- `firmware/components/sx_radio/include/sx_radio_pair.h` and
  `sx_radio_pair.c`: pure-C FSM (`UNPAIRED → SYNC_RECEIVED → PAIRED`, `LOST`),
  3.3 s 915/920 scan, 902–928 MHz validation, one-shot `<id>,SUCCESS,` ACK,
  probe learning from the first state message, persistence only on confirm,
  10-minute LOST timeout with the radio kept tuned, and unpair/scan restart.
  The transmit callback has exactly one call site, in the sync handler.
- `firmware/components/sx_radio/sx_radio.c`: `bridge_config` adapters, the only
  `LoRaSend()` call (private ACK adapter), boot-time pairing load/tune, and RX
  task wiring (`on_packet` + `tick`). The raw frame still reaches the seam.
- `firmware/test/test_sx_radio_pair.c` (`sx-radio-pair` CTest): 11 scenarios,
  including out-of-band no-tune/no-TX, reboot persistence, LOST/recovery and a
  source-level single-TX-call-site guard.
- Docs: design 02 §2.7, design 03 §3.5.3/§3.6, ADR 0024, progress T16.

Deviations:
- The real-X4 pairing and the real 10-minute wait stay deferred to T37 per the
  task file; host FSM evidence is the gate here.
- `paired_at` persists as 0 (unknown) because the radio task has no wall clock;
  no acceptance item needs it.

Checks:
- Host: `cmake -S firmware/test -B firmware/test/build -G Ninja`,
  `cmake --build firmware/test/build`, `ctest --test-dir firmware/test/build
  --output-on-failure` → 8/8 passed.
- Firmware: `idf.py -B build
  "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`
  → complete; image guard ok; `sx4_bridge.bin` 0x3aa70 bytes.

Remaining work:
- T37 bench: real X4 pair + stock-receiver continuity; real silence → LOST →
  packet → PAIRED.
- T21 must consume the raw seam and skip sync/ACK frames; it must not call the
  pairing FSM again.
- M4 (T47–T55) must serialize `unpair_smoke_x` with the radio task.

