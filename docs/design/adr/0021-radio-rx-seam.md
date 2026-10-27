# 0021 - Radio RX seam: bounded queue and an allocation-free FIFO read

## Status
accepted (T13)

## Context
The vendored `ra01s` helper `LoRaReceive()` reaches `ReadBuffer()`, which
`malloc`s a buffer per packet. T13 also requires the `radio_rx` task to hand
packets to the parser without ever blocking on flash or BLE. A callback into an
unknown consumer would let a slow parser stall the radio, and copying into a
growable container would allocate per packet.

## Decision
- `radio_rx` publishes into a pure-C, fixed-depth single-producer/single-
  consumer queue in `firmware/components/sx_radio/include/sx_radio_rx.h`.
  Each slot is a 128-byte payload plus length/RSSI/SNR. `publish` never blocks
  and never allocates; on a full queue the newest packet is dropped and counted.
  The consumer takes frames with `sx4_radio_rx_take()`.
- The radio task reads the SX1262 FIFO with the driver's public primitives
  (`GetRxBufferStatus`, `spi_read_byte`, `GetPacketStatus`) and a fixed static
  scratch buffer, instead of calling the allocating `LoRaReceive()`.
- The driver stays vendored and unmodified, per `PROVENANCE.md`; radio policy
  belongs in `sx_radio`.
- The approved LoRa parameters live in one struct,
  `firmware/components/sx_radio/include/sx_radio_params.h`.

## Consequences
- T14 and T21 consume the queue; they cannot make the radio task wait.
- At the ~30 s cadence the three-slot capacity is effectively unbounded. A
  sustained burst drops the newest frame and is visible in a counter.
- The host test `firmware/test/test_sx_radio_rx.c` injects a real T10 X4
  payload through the same seam and observes it without a radio.
- T16 owns persisted-frequency tuning and the scan path. Until then the radio
  starts on the 915 MHz X4 sync channel.
