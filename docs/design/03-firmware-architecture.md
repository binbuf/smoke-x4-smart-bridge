# 03 — Firmware Architecture

## 3.1 Principles

1. **Recording is the product.** The radio, parser, and flash writer come up
   before BLE and the UI. A BLE failure never stops a sample from being stored.
2. **Host-testable logic has no ESP-IDF dependency.** Protocol parsing, record
   encoding, ring geometry, sync framing, and config validation build and test
   with a plain C compiler.
3. **No dynamic allocation on the sample path.** The payload is at most ~128 B;
   all buffers are fixed or stack.
4. **One owner per resource.** NVS belongs to `bridge_config`; flash belongs to
   `sample_log`; the SX1262 belongs to `sx_radio`; the GATT server belongs to
   `ble_service`.
5. **No hidden transmissions.** The only LoRa TX call path is the pairing ACK.
   There is no Billows transmit path; post-MVP Billows RF work is receive-only.

## 3.2 Component map

```
firmware/
├── main/
│   ├── main.c                 app_main: wiring only
│   ├── boot.c                 ordered, failure-tolerant boot
│   ├── tasks.h                every task's stack/priority/core in one table
│   └── CMakeLists.txt
├── components/
│   ├── sx_protocol/           pure C: payload parsing, sample conversion
│   ├── sx_radio/              SX1262 driver wrapper + pairing state machine
│   ├── sample_log/            pure C geometry + IDF flash adapter
│   ├── bridge_config/         typed NVS config, pairing, bonds metadata
│   ├── bridge_state/          live snapshot, clock, counters
│   ├── ble_service/           NimBLE GATT server, advertising, security
│   ├── ui/                    SSD1306 driver, pages, button, power
│   └── board/                 pin definitions, battery ADC, Vext, watchdogs
├── vendor/
│   └── esp-idf-sx126x/        pinned ra01s driver
├── test/                      plain CMake host tests
├── partitions.csv
├── sdkconfig.defaults
├── sdkconfig.defaults.heltec-v3
└── Makefile
```

`BLE service` and `ui` are ESP-IDF components; their **models and renderers**
are pure C and host-tested. `sample_log` splits into `log_core.c` (pure ring
geometry and record encoding), `log_flash_core.c` (pure boot recovery, pending
clear and storage state), `log_flash.c` (raw `esp_partition` read/write/erase)
and `sample_log.c` (the firmware singleton and public API).

### What is reused from `legacy/`

- `smoke_x_parser.c` / `smoke_x_types.h` shape and MIT notice, reworked for the
  new record format and strict X4 handling.
- The pinned `ra01s` SX1262 driver and radio parameter block.
- The proven GATT security model (passkey + bonding + encrypted/authenticated
  characteristics) and the chunked-notification pattern.
- The hardware facts in [01](01-hardware.md).

No app UI, session model, alarm engine, network stack, or design system is
carried over. See [09](09-legacy-audit.md).

## 3.3 Tasks

One table, compiled into an assert that the declared stack total stays under
budget. The table lives in `firmware/main/tasks.h`; the declared total is
22,528 B and `SX4_TASK_STACK_BUDGET_BYTES` is 24 KiB. Editing the table without
revisiting the budget fails the firmware build and the host `task-budget` test.


| Task | Stack | Prio | Core | Role |
|---|---:|---:|---|---|
| `radio_rx` | 4096 | 6 | 1 | Poll SX1262; hand payload + RSSI/SNR to `sx_radio` |
| `sample_pipe` | 4096 | 5 | 0 | Parse, build record, publish live state, enqueue log write |
| `log_writer` | 4096 | 4 | 0 | Append records, erase/rotate sectors, update counters |
| `ble_host` | NimBLE | 5 | 0 | NimBLE host/controller task (created by the stack) |
| `ble_tx` | 3072 | 4 | 0 | Serialize live/sync notifications; one writer at a time |
| `ui` | 4096 | 3 | 0 | Button scan, page render, display sleep |
| `housekeeping` | 3072 | 2 | 0 | Battery sample, watchdog feed, stats snapshot, clock persistence |

Total application stacks: ~22.5 KB. With no Wi-Fi and no HTTP server, the
firmware should keep ≥ 120 KB free heap after BLE is up; measure it in V0.

The radio task is pinned to core 1, away from the BLE host on core 0. The
SX1262 driver polls with `vTaskDelay(1)`; at one packet per 30 s this is a
correctness-first choice, not a throughput design. A DIO1 interrupt path is a
post-MVP optimization.

## 3.4 Boot sequence

```
app_main
  1  nvs_flash_init()                          fatal on failure
  2  bridge_config_init()                      load config/pairing/counters
     bridge_state_init()                       restore clock anchor + snapshot
  3  board_power_init()                        Vext, battery ADC, rails
  4  ui_init()                                 splash + version
  5  sample_log_init()                         mount raw partition, recover ring
  6  sx_protocol_init()                        static validation tables
  7  sx_radio_init()                           SX1262 reset/config
  8  sx_radio_start()                          paired: tune + RX
                                                unpaired: 915/920 scan
  9  ble_service_start()                       advertising begins
 10  housekeeping_start()
 11  ui_start()                                first page
```

Ordering rationale: samples can be captured before BLE is ready. If BLE init
fails, the bridge still records and displays. If the log mount fails, the bridge
still shows live temperatures but announces "storage unavailable" on the OLED
and in `stats`; it does not pretend to record.

`ui_init` must be before `sample_log_init` only because the display is the
diagnostic surface for a log failure. It is not a data dependency.

## 3.5 Runtime state

### 3.5.1 Power state

```
BOOT → ON_IDLE (advertising) ⇄ CONNECTED
  │          │                     │
  │          └──── hold PRG ────────┘
  │                    │
  │                    ▼
  └─────────────► POWER_OFF (deep sleep)
                       │ hold PRG
                       └──────► BOOT
```

`app power_off` can also move `CONNECTED` or `ON_IDLE` to `POWER_OFF`; the app
sends the op, the device answers, then sleeps.

`ON_IDLE` means on, not connected. `CONNECTED` means the single active BLE
central is connected. Advertising is active in `ON_IDLE`; it stops in
`CONNECTED` and restarts on disconnect.

### 3.5.2 BLE link state

`ADVERTISING → CONNECTED → SECURED → SUBSCRIBED → STREAMING`

- `CONNECTED` but not `SECURED`: only `info` is readable; `live`, `stats`,
  `sync_*`, and `control` reject with Insufficient Encryption (0x0F) or
  Insufficient Authentication (0x05), depending on the link state.
- `SECURED`: bond complete.
- `SUBSCRIBED`: the app has enabled `live` notifications.
- `STREAMING`: a sync response is in flight; live notifications still flow.

A sync request from an unsecured link is refused, not queued.

### 3.5.3 Smoke X link state

`UNPAIRED → SYNC_RECEIVED → CONFIRMED (PAIRED) → LOST → PAIRED`

`LOST` is a UI/status state, not an unpair. It is entered after 10 minutes
without a valid state packet. The radio stays tuned; a returning packet moves
back to `PAIRED`. `PAIRED` or `LOST` → `UNPAIRED` happens only through the
app's `unpair_smoke_x` op; a reboot does not clear pairing.

Implementation (T16, ADR 0024): the FSM is `sx_radio_pair.c`, pure C11 with
callback seams for tune, NVS load/save/clear and ACK transmit. `sx_radio.c`
installs the `bridge_config` and SX1262 adapters and feeds every received frame
to `sx4_radio_pair_on_packet()` before publishing it to the sample seam;
`sx4_radio_pair_tick()` drives the 3.3 s scan and the 10-minute timeout. The
pairing ACK is the only LoRa transmission and the sync handler is its only call
path.

### 3.5.4 Storage state

`OK → NEAR_FULL → READ_ONLY` (unrecoverable flash error) or `OK → ROTATING`.

Rotation is normal and must not be surfaced as an error. `NEAR_FULL` is
practically unreachable because the ring always frees the oldest sector; keep it
as a diagnostic.

T19 exposes the state as `sample_log_storage_state()` and
`sample_log_storage_ok()`. `OK` means the ring mounted and accepts appends;
`NEAR_FULL` means the live count is within one sector of capacity and still
records; `READ_ONLY` means the mount failed or any `esp_partition`
read/write/erase failed. `READ_ONLY` is persistent until reboot, rejects further
appends, and maps to `stats.flags.storage_ok = 0` / `live.flags.storage_ok = 0`.
A bad record (`SAMPLE_LOG_ERR_LAYOUT`/`ARGUMENT`) is not a storage failure and
does not change the state.

## 3.6 Sample pipeline

```
SX1262 packet
  │
  ▼
radio_rx
  │  payload[128], rssi, snr
  ▼
sx_radio (pairing/ID/frequency validation)
  │  parsed state, UTC now
  ▼
sample_pipe
  ├─► bridge_state_update(live snapshot)
  ├─► log_writer queue (fixed 18-byte record)
  └─► ble_tx queue (20-byte live notification)
        │
        ▼
      ui marks dirty
```

Rules:

- The parser rejects malformed input; counters increment; no partial record is
  written.
- T20 provides the pipeline's state boundary: `bridge_state_stamp_record()`
  applies the clock to the record (unknown time writes `unix_s = 0`), then
  `bridge_state_update()` publishes the live snapshot. The snapshot carries no
  pointer to mutable state; readers get a consistent copy and compute `age_s` at
  read time.
- Device ID mismatch is dropped and counted.
- Pairing owns sync/state acceptance: the radio task passes each frame to the
  pairing FSM first (T16), which may retune and ACK a sync beacon, learn the
  probe count and persist the pairing. The same raw frame still goes through
  the seam to `sample_pipe`; there is no second TX path.
- Detached probes become `TEMP_DETACHED` before the record is built.
- Celsius packets are converted to canonical °F tenths before the record is
  built; `source_celsius` is provenance only. Billows `max` remains a
  candidate target until M5 validates the relation.
- The log write is queued; if the queue is full, the sample is dropped and
  `dropped_samples` increments. At 30 s cadence this should never happen; if it
  does, it is visible.
- Live notification is best-effort. A missed notification is recovered by sync;
  it is not a data-loss path.

Implementation (T21): `firmware/components/sample_pipe/`.

- `sample_pipe.c` is the pure core. It classifies a frame by comma count (2 =
  ACK, ignored; 6 = sync beacon, counted; 16/26 = state), loads the persisted
  pairing through a callback, and parses only a paired state frame. It builds
  the 18-byte record and the `bridge_state_sample_t` together, stamps the
  record, and calls `sample_log_record_validate()` before handing the pending
  pair to the log queue. No partial record exists on any reject path.
- `sample_pipe_esp.c` owns a static FreeRTOS queue of
  `SAMPLE_PIPE_LOG_QUEUE_DEPTH` (8) pending samples, the `sample_pipe` task
  (4096/5/core 0) and the `log_writer` task (4096/4/core 0). The sample task
  drains `sx4_radio_rx_take()`; `enqueue_log` uses a zero-tick `xQueueSend`, so
  a full queue is a counted drop, never a wait. The writer appends through
  `sample_log_append()`, then calls `sample_pipe_complete()`.
- The live snapshot is published at completion, when the ring sequence is
  known: `bridge_state_update()` first, then `ui_mark_dirty()`. A failed append
  still publishes live values but keeps the previous live sequence and
  increments `log_write_failures`. A dropped sample publishes nothing, so FIFO
  completions can never overwrite newer live values with older ones.
- The learned probe count is persisted once through `bridge_config_set_pairing()`
  when the first paired state frame's comma count differs from the stored value.
  The pairing FSM normally does this too; the pipeline call is idempotent.
- Counters: valid state packets, parse failures, foreign IDs, sync beacons and
  drops are owned by `sample_pipe`; CRC/header failures and ACK attempts are
  aggregated from `sx_protocol` (the radio CRC branch now calls
  `sx_protocol_note_crc_failure()`). `last_packet_age_s` is computed on read.
- `ui_mark_dirty()` / `ui_dirty_take()` are the cross-task dirty flag; T22 owns
  rendering and display sleep.

## 3.7 Configuration

`bridge_config` is the only component that opens NVS. It exposes a typed,
versioned struct and change notifications.

| Namespace | Keys |
|---|---|
| `pair` | device_id, frequency_hz, num_probes, paired_at |
| `device` | units, display_timeout_s, device_name; `billows_mode`/`billows_target_f10` are reserved and unwritten in the MVP |
| `log` | generation, clear_pending, clock_anchor_s, clock_valid (the sequence is recovered from flash) |
| `stats` | boot_count, last_reset_reason, packets_ok, packets_bad |
| `meta` | config_version (layout metadata, kept across factory reset) |
| BLE bonds | NimBLE's own NVS namespace (documented exception) |

Rules:

- `config_version` gates forward migrations.
- Writes are validated before they are persisted; a bad app write returns
  `invalid` and changes nothing.
- Factory reset erases all namespaces **and** calls NimBLE's bond store clear.
- `generation` is a **new random value** on any log clear/factory reset/whole-log
  corruption; it is the app's signal that its cursor is invalid. A single bad
  sector does not change it. `clear_pending` records an interrupted clear so the
  boot path can finish the erase and ignore old-generation sectors.
- Pairing data is independent of log data: forgetting phones does not unpair the
  Smoke X4; clearing the log does not unpair.

Implementation (T15, ADR 0023):

- The core is plain C11 over a byte-oriented key/value seam; the ESP-IDF
  adapter is the only code that calls `nvs_open()`/`nvs_get_blob()`. Host tests
  use a RAM backend.
- ESP-IDF key names are limited to 15 characters, so three logical keys have
  physical aliases: `display_timeout_s` → `disp_timeout_s`,
  `last_reset_reason` → `last_reset`, `billows_target_f10` →
  `billows_tgt_f10`. Values are little-endian blobs; strings have no NUL.
- Version 0/absent is the unversioned layout. Migration keeps valid values,
  scrubs wrong-sized ones, ensures `generation` exists, then writes version 1.
  A newer version is refused without modifying anything.
- Validation: frequency 902–928 MHz, probes 2 or 4, printable-ASCII device ID,
  valid UTF-8 name of 1–15 bytes, timeout in {0, 30, 60, 120}, units 0/1, and a
  valid clock must have a non-zero anchor.
- `begin_log_clear()` writes the new generation **then** `clear_pending = 1`,
  before the ring erase starts. `regenerate_generation()` is only for a wholly
  unusable log; `set_generation()` only restores a generation recovered from a
  sector header (T19).
- `bridge_config_factory_reset_steps()` is the single list of reset work:
  new generation, pending clear, every key, then the NimBLE bond clear.
  `clear_bonds()` forgets phones only; `clear_pairing()` re-pairs the radio and
  keeps bonds and the log.
- `billows_mode`/`billows_target_f10` have no setter and are never read from
  NVS; the getter returns the MVP constants 0/0.


## 3.8 Clock

The board has no RTC. `bridge_state` keeps:

- `unix_s` — current best wall clock (0 = unknown),
- `clock_valid` — true after an app `set_time` or a persisted anchor,
- `last_anchor_uptime_s` — for monotonic advancement.

On boot, load the last persisted `unix_s` plus the elapsed deep-sleep/off time if
known; mark it `estimated`. The app sets the clock on every connect when the
delta exceeds 2 s. Records written while the clock is unknown carry `unix_s = 0`
and `clock_valid = 0`; the app can still place them relative to `seq`.

Persist the clock anchor every 10 minutes to NVS. Do not write NVS per sample.

Implementation (T20, ADR 0028):

- `bridge_state` is a plain-C core over an injected monotonic millisecond source
  and `bridge_config`; `bridge_state_esp.c` installs `esp_timer_get_time()`.
  `bridge_state_core_init()` loads the anchor after `bridge_config_init`.
- `bridge_config` stores the anchor as `{clock_anchor_s, clock_uptime_s,
  clock_valid}`; `clock_uptime_s` is an additive u64 key (0 = unknown). The
  typed `bridge_config_clock_get_full()`/`set_full()` carry the pair; the older
  getter/setter keep their two-field contract.
- A restored anchor is `estimated = true`. Elapsed time is added only when the
  uptime source survived the sleep (`now >= stored uptime`) or the platform
  passes a known sleep interval; a power cycle with a reset timer restores the
  anchor unchanged rather than inventing an interval.
- `bridge_state_set_time()` is the T29 seam. It refuses a time earlier than the
  current clock (`ERR_TIME`) and clears `estimated`. It has no BLE dependency.
- `bridge_state_tick()` writes at most once per ten minutes and retries a failed
  write after 60 s; the first app set writes immediately. `bridge_state_update()`
  never writes NVS.
- `bridge_state_stamp_record()` writes `unix_s = 0` and clears the clock-valid
  bit while unknown, and clamps to the previous record timestamp so a correction
  can never move sample time backwards.
- `bridge_state_snapshot()` copies the live values under a sequence lock and
  computes `age_s`, the 90 s `SMOKE_LIVE` bit and the clock-valid bit at read
  time. Temperature, sequence, billows target, battery and RSSI are stored by
  `bridge_state_update()` / the device setters.

## 3.9 BLE service

NimBLE, one custom GATT service. The contract is in
[05 — BLE Contract](05-ble-contract.md).

- Advertising starts at boot when not connected and restarts on disconnect,
  failed connect, and advertising timeout.
- `info` is open; everything else requires encryption; `control` and `config`
  writes require an authenticated (passkey) bond.
- A six-digit passkey is generated when bonding starts and shown on the OLED.
- Max 4 bonds, one active connection. `info.bonds_free` is published so the app
  can refuse a bond before the OS prompt when the store is full.
- Request ATT MTU 247. The fixed **notification** payload (`live`) is 20 B, so
  live telemetry works even at the default MTU 23; larger reads use Read Blob
  and `config` writes use queued writes.
- Sync uses a framed byte stream that works at any MTU (see 05 §5.7–§5.8).

## 3.10 UI and power

- Pages and gestures are specified in [07](07-display-and-controls.md).
- The UI task samples PRG at 20 ms with a 30 ms debounce.
- Display timeout default 60 s; the panel and I²C traffic stop when asleep.
- Hold-to-power-off shows a countdown and commits on release. Deep sleep turns
  Vext off and sleeps the SX1262.
- The app can request power-off; the device answers first, then sleeps.

## 3.11 Reliability

- Task watchdog subscribed by all application tasks (5 s).
- Brownout detector enabled above the flash-write-unsafe threshold.
- Panic handler writes a coredump to the coredump partition; the next boot logs
  a one-line summary and preserves it for USB retrieval. The MVP does not add a
  separate phone notification or fault screen.
- Log recovery after power loss is described in [04 §4.3](04-data-and-storage.md).
- The radio task and log writer must not block on BLE. Use bounded queues and
  drop-with-counter rather than blocking the sample path.

## 3.12 Memory budget

| Consumer | Estimate |
|---|---:|
| NimBLE host/controller | 80–110 KB |
| Application stacks | ~22.5 KB |
| UI framebuffer + font | ~3 KB |
| Radio buffers + driver | ~4 KB |
| Log write/read buffers | ~8 KB |
| GATT/sync scratch | ~4 KB |
| FreeRTOS objects, NVS, misc | ~20 KB |
| **Expected free heap after boot** | **≥ 120 KB** |

If free heap is below 80 KB with a phone connected, the build is not releaseable.
Measure `heap_free` / `heap_min` in `stats` and during the 24 h soak.

## 3.13 Build and flash

ESP-IDF 6.0.x, target `esp32s3`, NimBLE, no Wi-Fi, no HTTP server, no OTA.

```bash
# host tests: no ESP-IDF required
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# or: make host-test

# firmware
idf.py -B build -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
idf.py -B build -p COMx flash monitor
```

CI runs the host tests and `idf.py build` for the Heltec target. A release is a
merged image plus a version string; the app displays the version but cannot
update it.

The project is a whitelist build: `firmware/CMakeLists.txt` sets
`set(COMPONENTS main espcoredump)` so IDF does not build its whole component
tree. After linking, `firmware/tools/check_image.py` checks
`project_description.json` for Wi-Fi/IP/HTTP/OTA components, checks the target
and the partition table, and fails `idf.py build` on a match (ADR 0015). `app_update` is a stock
`esp_partition` dependency and is allowed; it contributes only the
running-partition lookup because there is no OTA slot or update component. The
application task stacks are asserted in `firmware/main/tasks.h` (22,528 B
declared against a 24 KiB budget) and re-checked by the host `task-budget` test.


## 3.14 Test seams

- `sx_protocol` is pure C and takes a payload string. The host corpus reader
  and `parser-vectors.tsv` live under `protocol/fixtures/lora/`; tests never
  read `legacy/`. The API is `include/sx_protocol.h` (types in
  `include/sx_protocol_types.h`); `sx_protocol_parse_state()` infers 2/4 probes
  from 16/26 commas, filters a foreign paired ID before parsing further, emits
  canonical `temp_f10`, and publishes output only after the whole payload
  validates. `firmware/test/test_sx_protocol.c` is the product-parser suite
  (`sx-protocol` CTest) and replays every corpus vector and real capture.
- `sample_log` core takes a `log_io` interface (`read`, `write`, `erase`) so a
  RAM-backed fake can simulate wrap, torn writes, and corruption. Header
  recovery, generation filtering, append/rotation and sequence bookkeeping live
  in `log_core.c` (`log_ring_*`); the seam is
  `firmware/components/sample_log/include/log_io.h`, and the fake plus failure
  injection are in `firmware/test/support/ram_log_io.*`.
- `bridge_state` takes a clock function.
- `ble_service` payload encoders are pure functions; the NimBLE callbacks are
  thin.
- `sx_radio` publishes raw RX frames through the pure-C seam
  `firmware/components/sx_radio/include/sx_radio_rx.h`: a fixed 128-byte
  payload plus RSSI/SNR in a bounded SPSC queue. Publish never blocks and never
  allocates; a full queue drops the newest frame and increments a counter. The
  host test `test_sx_radio_rx` injects a real X4 fixture packet without a radio.
  The radio task reads the SX1262 FIFO with a fixed scratch buffer rather than
  the allocating `ra01s` `LoRaReceive()` helper (ADR 0021).
- `ui` renderers take a snapshot struct and write a 1 KB framebuffer; host tests
  compare framebuffer goldens.
