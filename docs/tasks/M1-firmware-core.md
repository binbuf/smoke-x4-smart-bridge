# M1 — Firmware Core

**Exit gate:** a real Smoke X4 pairs, the stock receiver keeps working, every
valid state packet lands in the ring log, a power cut leaves earlier records
intact, and the OLED/PRG/power path works. BLE may still be a skeleton.

**Design:** [02](../design/02-smoke-x-protocol.md), [03](../design/03-firmware-architecture.md),
[04](../design/04-data-and-storage.md), [07](../design/07-display-and-controls.md)

---

### F1.1 sx_radio: vendor the SX1262 driver

- **blocked-by:** T0.4 · **verify:** H · **board:** no
- **design:** [01 §1.2](../design/01-hardware.md), [02 §2.1](../design/02-smoke-x-protocol.md), [09 §9.5](../design/09-legacy-audit.md)

Pin the known-good `ra01s` driver (the same one the legacy tree used) under
`firmware/vendor/`. Wire it as an ESP-IDF component. Record the commit and
licence.

**Done when.** A clean build includes the driver; no network fetch at build time.

---

### F1.2 sx_radio: RX loop and parameters

- **blocked-by:** F1.1 · **verify:** H/B · **board:** no (host seam), yes for B
- **design:** [02 §2.1](../design/02-smoke-x-protocol.md), [03 §3.3](../design/03-firmware-architecture.md)

Implement the radio task and parameter block: SF9, bandwidth index 4, CR 4/5,
preamble 10, sync word `0x12`, CRC on, TCXO 3.3 V LDO, frequency from config or
scan. Publish raw payload + RSSI/SNR to the parser seam.

**Done when.** A host test injects a payload without a radio; on the board, a
real X4 packet appears in the log. The task never blocks on flash/BLE.

---

### F1.3 sx_protocol: port and extend the parser

- **blocked-by:** T0.3, F1.2 · **verify:** H · **board:** no
- **design:** [02 §2.5, §2.9](../design/02-smoke-x-protocol.md)

Port `smoke_x_parser.c` with the MIT notice. Keep `strtok_r`, strict numeric
parsing, no heap, and explicit units. Extend:

- device-ID comparison and mismatch counter,
- detached → `TEMP_DETACHED`,
- Celsius → canonical °F tenths,
- Billows attached + target fields,
- preserve `new_alarm`,
- reject wrong comma counts and trailing garbage.

**Done when.** All fixture vectors pass, including the real X4 captures and the
malformed cases.

---

### F1.4 sx_radio: pairing state machine and TX guard

- **blocked-by:** F1.2, F1.5 · **verify:** H/B · **board:** no / B
- **design:** [02 §2.4, §2.5, §2.7](../design/02-smoke-x-protocol.md)

Implement `UNPAIRED → SYNC_RECEIVED → CONFIRMED/PAIRED` and the lost state.
Persist `{device_id, frequency_hz, num_probes}`. The only TX call path is the
sync handler; validate 902–928 MHz before retuning. No automatic re-pair to a
different unit.

**Done when.** A host test asserts no other path reaches TX; an out-of-band
frequency never transmits. On the board, a real X4 pairs and the stock receiver
keeps updating.

---

### F1.5 bridge_config: typed NVS store

- **blocked-by:** T0.4 · **verify:** H · **board:** no
- **design:** [03 §3.7](../design/03-firmware-architecture.md)

Implement the namespaces and typed getters/setters: pairing, device config
(including `device_name`), log generation/clear-pending/clock anchor, boot
counters. The sample sequence is recovered from flash, not stored in NVS. Add
`config_version` migrations. NimBLE's bond namespace is the only documented
exception; wrap its clear call.

**Done when.** Every key round-trips; a bad write changes nothing; factory-reset
keys are enumerated in one place.

---

### F1.6 sample_log: record codec

- **blocked-by:** T0.2 · **verify:** H · **board:** no
- **design:** [04 §4.2](../design/04-data-and-storage.md)

Implement the 18-byte record encode/decode: 24-bit sequential, UTC seconds,
four i16 temperatures, flags, CRC16. Validate sentinel/attachment consistency.
Expose `record_size`, not `sizeof`, to readers.

**Done when.** Round-trip, CRC failure, detached, Celsius-source, and
attach-bit/flag-mismatch tests pass.

---

### F1.7 sample_log: ring geometry

- **blocked-by:** F1.6 · **verify:** H · **board:** no
- **design:** [04 §4.3](../design/04-data-and-storage.md)

Implement the pure ring core over a `log_io` seam: sector headers, append,
wrap, oldest-sector erase, `min_seq`/`max_seq`/`generation`, capacity arithmetic,
and recovery scan. Simulate torn tails, dual-header recovery, empty, full, and
full-wrap.

**Done when.** The RAM fake passes all scenarios; the capacity assert matches
338,400 records.

---

### F1.8 sample_log: flash adapter and boot recovery

- **blocked-by:** F1.7 · **verify:** H/B · **board:** no / B
- **design:** [04 §4.3, §4.4](../design/04-data-and-storage.md), [01 §1.8](../design/01-hardware.md)

Bind the ring to the `samples` partition: read/write/erase, sector header
read-back, recovery on boot, `esp_partition` errors mapped to `storage_ok`.
Use the raw partition, not LittleFS.

**Done when.** A power cut during a cook leaves earlier records readable after
reboot; the writer resumes at the next valid sequence; boot recovery time is
measured. If a full 6 MB scan exceeds ~2 s, optimize to header + newest-sector
recovery before closing the task.

---

### F1.9 bridge_state: clock and live snapshot

- **blocked-by:** F1.5 · **verify:** H · **board:** no
- **design:** [04 §4.4](../design/04-data-and-storage.md), [03 §3.8](../design/03-firmware-architecture.md)

Implement the UTC/estimated clock, persist the anchor every 10 min, and the live
snapshot (temps, seq, flags, Billows, age, battery, RSSI). App `set_time` is not
wired yet; expose the setter for F2.3.

**Done when.** Clock-unknown records carry `unix_s=0`; a reboot restores an
estimated anchor; the snapshot updates on every sample.

---

### F1.10 sample_pipe: parser → log → UI

- **blocked-by:** F1.3, F1.8, F1.9 · **verify:** H/B · **board:** no / B
- **design:** [03 §3.6](../design/03-firmware-architecture.md)

Wire the pipeline: validate, build record, append, update live snapshot, count
packets. Add bounded queues and drop counters. Do not block the radio on flash.
Wire `sample_pipe` to the UI dirty flag.

**Done when.** A replay of a 30-minute capture produces exactly the expected
record count and live values; no allocation on the path.

---

### F1.11 ui: pages, renderer, and display sleep

- **blocked-by:** T0.8, F1.10 · **verify:** H/B · **board:** no / B
- **design:** [07 §7.1–§7.3, §7.6](../design/07-display-and-controls.md)

Implement Vext/I²C/SSD1306, the framebuffer, four pages (Probes, Link, Billows,
Device), passkey overlay, storage-failure overlay, and display timeout. Add
framebuffer goldens.

**Done when.** Host goldens match; the four pages are legible on the real OLED;
the panel sleeps and wakes without changing the page.

---

### F1.12 ui: PRG gestures and deep sleep

- **blocked-by:** F1.11, T0.10 · **verify:** H/B · **board:** no / B
- **design:** [07 §7.4, §7.5](../design/07-display-and-controls.md)

Implement 20 ms sampling/30 ms debounce, tap/hold state machine, power-off
countdown, commit on release, deep sleep with GPIO0 wake, and the boot hold
confirmation. Do not add a boot-time menu/reset gesture or on-device reset; the
hold-to-wake confirmation is the only boot-time hold.

**Done when.** Tap/hold unit tests pass; on the board, 20/20 wake cycles work
with USB attached and detached, and an early release cancels.

---

### F1.13 board: battery ADC and power stats

- **blocked-by:** T0.8 · **verify:** H/B · **board:** no / B
- **design:** [01 §1.3](../design/01-hardware.md)

Implement the GPIO37 enable/sample/disable sequence, oversampling, calibration
ratio, Li-ion SoC curve, and unknown sentinel. Expose mV/% in the snapshot and
stats. Do not invent charging status.

**Done when.** The host curve test matches the chosen points; on the board, the
reading tracks a DMM within the agreed tolerance; unknown renders as `—`.

---

### V1.1 Bench: pair, stock receiver, power cut

- **blocked-by:** F1.4, F1.8, F1.10 · **verify:** B · **board:** yes
- **design:** [10 §10.3 B1](../design/10-test-and-release.md)

Real hardware:

1. Pair the bridge with a real X4; confirm the stock receiver keeps updating.
2. Start recording; pull USB power mid-cook; reboot; confirm earlier records
   survive and the log resumes.
3. Detach a probe; confirm `---` on OLED and a sentinel in the log.
4. Flip °F/°C; confirm canonical °F storage.

The app-driven unpair/re-pair test is V4.1; the F1.4 FSM is host-tested here.

**Done when.** Results are written in `docs/hardware-verified.md`; a capture or
log excerpt is committed.

---

### V1.2 Bench: 30-minute cadence and display

- **blocked-by:** F1.11, F1.12, F1.13 · **verify:** B · **board:** yes
- **design:** [10 §10.3 B1/B2](../design/10-test-and-release.md)

Run 30+ minutes with all four probes and the OLED awake/asleep. Record packet
counts vs expected, RSSI, observed intervals, and any missed samples. Walk all
four pages; test display sleep/wake, battery reading, and PRG power off/on.

**Done when.** The cadence report is committed; any gap has a cause; the pages
are legible and the power cycle works.
