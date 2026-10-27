# 0024 — Pairing FSM as a pure-C core behind callback seams

- **Status:** accepted
- **Date:** 2026-10-26
- **Task:** T16

## Context

The pairing rules in design 02 §2.7 need host tests (states, the 902–928 MHz
gate, probe learning, the 10-minute `LOST` timer) without an SX1262, NVS or a
board. At the same time the product has exactly one LoRa transmission, the
pairing ACK, and that rule must be enforceable rather than convention.

## Decision

`firmware/components/sx_radio/sx_radio_pair.c` is a pure-C11 state machine.
Radio tuning, NVS load/save/clear and the ACK transmit are callback seams
(`sx4_radio_pair_io_t`); time is a monotonic millisecond value passed in by the
caller. The host suite installs RAM/radio fakes; `sx_radio.c` installs the
`bridge_config` and SX1262 adapters.

The FSM's only transmit call is `s_pair.io.send_ack(...)` in the sync-beacon
branch of `sx4_radio_pair_on_packet()`. `sx_radio.c` keeps the only
`LoRaSend()` call in its private `pair_send_ack` adapter. The `sx-radio-pair`
host test asserts both facts by counting those call sites in the two source
files, in addition to exercising every non-sync public path at runtime.

A beacon is committed only after parse, range check, ACK formatting, retune and
a successful ACK. A failed ACK restores the previous tuning and leaves the FSM
unpaired. The first matching state packet learns the probe count and persists
the record; a failed save stays in `SYNC_RECEIVED` and retries on the next
packet.

## Consequences

- The pairing logic runs on the `radio_rx` task: it consumes the same frame the
  seam publishes for the sample pipeline. T21 must not create a second pairing
  or TX path.
- `LOST` never retunes or scans. The FSM keeps the persisted record and returns
  to `PAIRED` on the next valid state packet.
- `bridge_config` stays the only NVS owner; the FSM never touches a raw key.
- The FSM state is currently written only by `radio_rx`. A later BLE unpair
  call (M4) must serialize with that task or add a lock.
- Adding another LoRa transmit feature requires revisiting this ADR and the
  source-call-site test deliberately; TX cannot be added silently.
