# T17 — sample_log: record codec

## Goal
A pure-C codec encodes and decodes the fixed 18-byte sample record with sequence, UTC seconds, four canonical temperatures, flags, and CRC16. Readers get an explicit `record_size`, so the format can grow without `sizeof` coupling, and corrupt or inconsistent records are rejected.

## Context (read first)
- [04 §4.2](../design/04-data-and-storage.md) — record layout, sentinels, flags, and the reason for 18 bytes.
- [04 §4.10](../design/04-data-and-storage.md) — record version lives in the sector header; readers use `record_size`, not `sizeof`.
- `protocol/records.yaml` — the single definition generated into C and Dart.
- `firmware/components/sample_log/` — `log_core.c` owns the codec; `log_flash.c` is T19.
- **Verification:** H (host/CI). **Board:** no.
- Depends on T02.

## Scope
- [x] Define the packed 18-byte record once, matching [04 §4.2](../design/04-data-and-storage.md):

  ```c
  typedef struct __attribute__((packed)) {
      uint8_t  seq[3];      /* 0  monotonic sample id, u24 LE                 */
      uint32_t unix_s;      /* 3  UTC seconds; 0 = clock was not set           */
      int16_t  temp[4];     /* 7  tenths °F; TEMP_DETACHED / TEMP_INVALID      */
      uint8_t  flags;       /* 15 see below                                    */
      uint16_t crc16;       /* 16 CRC-16/CCITT-FALSE over bytes 0..15           */
  } sample_rec_t;           /* == 18 bytes                                      */
  ```

- [x] Implement encode: 24-bit little-endian `seq`, little-endian `unix_s`, four `i16` temperatures, flags, and CRC16/CCITT-FALSE over bytes 0..15.
- [x] Implement decode with CRC verification and bounds checking.
- [x] Validate sentinel/attachment consistency on read and write: an `attached` flag of 0 must agree with `TEMP_DETACHED`; a mismatch is corrupt and rejected.
- [x] Keep sentinels exact: `INT16_MIN` (−32768) = detached; `INT16_MIN + 1` (−32767) = present but invalid/unmapped.
- [x] Implement flags:

  | Bit | Meaning |
  |---|---|
  | 0–3 | Probe 1–4 attached in this packet |
  | 4 | Billows attached per the Smoke X4 |
  | 5 | Clock was valid when this record was written |
  | 6 | Source packet was Celsius (provenance only; stored value is °F) |
  | 7 | `new_alarm` was set in this packet (preserved; no alarm feature) |

- [x] Expose `record_size` (18) to readers; do not let callers use `sizeof(sample_rec_t)` as the wire size.
- [x] Add tests for round-trip, CRC failure, detached, Celsius-source, and attach-bit/flag mismatch.

## Out of scope
- Ring geometry, headers, append/wrap, and recovery → T18.
- Raw partition read/write/erase and boot recovery → T19.
- Sample-pipeline wiring and counters → T21.
- BLE sync framing and `record_size` in the sync header → Phase 3 BLE tasks (T27–T37).
- App-side record codec and SQLite import → M2/M3 app tasks (T27–T37, T39–T46).
- Alarms/notifications: outside MVP; no task owns them.
- A Billows control path: outside MVP; M5 (T56, T57, T59) is observation only.

## Design notes
- The struct is packed and little-endian with no padding. The wire size is **18 bytes**; assert it at compile time.
- `seq` is a 24-bit integer (max 16,777,215) stored in three bytes, but all in-memory code uses `uint32_t`.
- `unix_s = 0` means the clock was unknown; combine it with `flags` bit 5. Do not invent a timestamp.
- Temperatures are canonical tenths of °F. The Celsius-source bit records provenance only; the stored number is always °F.
- The attach bits duplicate the sentinel for fast filtering. They must agree; the record is rejected when they do not.
- The record version is **not** in each record; it is carried in the sector header ([04 §4.10](../design/04-data-and-storage.md)).
- No heap and no host-endian assumptions; encode/decode explicitly byte by byte.
- A failed decode returns an error and does not expose a partially filled record.

## Done when
- [x] Encode/decode round-trip passes for attached, detached, invalid, Celsius-source, and alarm-edge records.
- [x] A bad CRC is rejected.
- [x] A detached probe decodes to `TEMP_DETACHED`, never a numeric temperature.
- [x] An attach-bit/flag mismatch is rejected.
- [x] `record_size` is 18 and is what readers use.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off
Landed:
- `firmware/components/sample_log/include/log_core.h` and `log_core.c`: the
  firmware-facing 18-byte record codec. It wraps the generated
  `sx4_sample_rec_encode`/`_decode` (single byte definition from
  `protocol/records.yaml`) and adds:
  - `SAMPLE_LOG_RECORD_SIZE` / `sample_log_record_size()` = 18, with
    compile-time asserts tying it to `SX4_RECORD_SIZE` and the packed struct;
  - symmetric sentinel/attach-bit validation on encode and decode
    (`attached=0` requires `TEMP_DETACHED`; `attached=1` requires a non-detached
    value, with `TEMP_INVALID` allowed);
  - decode that checks length and CRC into a local and copies out only on
    success, so a bad record is never partially exposed;
  - status codes distinguishing argument, short buffer, bad CRC and layout
    corruption.
- `firmware/components/protocol_gen/CMakeLists.txt`: thin ESP-IDF component
  that compiles the committed `protocol/gen/records.c` once; `sample_log` now
  requires it. No generation at build time, no copied wire constants.
- `firmware/test/test_sample_log_rec.c` + `sample-log-rec` CTest: wire layout
  byte-by-byte, CRC-16/CCITT-FALSE, u24 LE edges (0, `0xFFFFFF`), round-trips
  for attached/detached/invalid/Celsius-source/alarm-edge records, bad CRC
  rejection, detached sentinel never numeric, per-probe attach-bit mismatch in
  both directions, short buffers/null arguments, trailing bytes and no partial
  output on failure.
- ADR `docs/design/adr/0025-log-core-record-semantics.md`; design 04 §4.2
  now names `log_core` as the firmware boundary.

Deviations:
- The task says `log_core.c` owns the codec, but design 04 §4.2 and ADR 0013
  make the generated codec the sole byte/CRC owner. `log_core` therefore owns
  the record *semantics* and delegates bytes to `sx4_sample_rec_*`; this avoids
  a second layout definition. See ADR 0025.
- Added the `protocol_gen` IDF wrapper (small, outside the stated scope) because
  the firmware previously had no way to link the committed generated codec.

Checks:
- Host: `cmake -S firmware/test -B firmware/test/build -G Ninja`,
  `cmake --build firmware/test/build`,
  `ctest --test-dir firmware/test/build --output-on-failure` -> 9/9 passed
  (`sample-log-rec`, `records`, and the seven existing suites).
- Firmware: `idf.py -B build
  "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`
  -> complete; image guard ok (69 components, no Wi-Fi/HTTP/OTA);
  `sx4_bridge.bin` 0x3aa70 bytes.
- `record_size`: asserted 18 at compile time and in the test.

Remaining work:
- T18 must call `sample_log_record_encode`/`_decode` and advance by
  `sample_log_record_size()`; sector headers may use the generated
  `sx4_sector_header_*` codec directly.
- T19/T21 must not call `sizeof(sx4_sample_rec_t)` as a wire size.
- No blockers.
