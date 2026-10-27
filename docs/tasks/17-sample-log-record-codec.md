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
- [ ] Define the packed 18-byte record once, matching [04 §4.2](../design/04-data-and-storage.md):

  ```c
  typedef struct __attribute__((packed)) {
      uint8_t  seq[3];      /* 0  monotonic sample id, u24 LE                 */
      uint32_t unix_s;      /* 3  UTC seconds; 0 = clock was not set           */
      int16_t  temp[4];     /* 7  tenths °F; TEMP_DETACHED / TEMP_INVALID      */
      uint8_t  flags;       /* 15 see below                                    */
      uint16_t crc16;       /* 16 CRC-16/CCITT-FALSE over bytes 0..15           */
  } sample_rec_t;           /* == 18 bytes                                      */
  ```

- [ ] Implement encode: 24-bit little-endian `seq`, little-endian `unix_s`, four `i16` temperatures, flags, and CRC16/CCITT-FALSE over bytes 0..15.
- [ ] Implement decode with CRC verification and bounds checking.
- [ ] Validate sentinel/attachment consistency on read and write: an `attached` flag of 0 must agree with `TEMP_DETACHED`; a mismatch is corrupt and rejected.
- [ ] Keep sentinels exact: `INT16_MIN` (−32768) = detached; `INT16_MIN + 1` (−32767) = present but invalid/unmapped.
- [ ] Implement flags:

  | Bit | Meaning |
  |---|---|
  | 0–3 | Probe 1–4 attached in this packet |
  | 4 | Billows attached per the Smoke X4 |
  | 5 | Clock was valid when this record was written |
  | 6 | Source packet was Celsius (provenance only; stored value is °F) |
  | 7 | `new_alarm` was set in this packet (preserved; no alarm feature) |

- [ ] Expose `record_size` (18) to readers; do not let callers use `sizeof(sample_rec_t)` as the wire size.
- [ ] Add tests for round-trip, CRC failure, detached, Celsius-source, and attach-bit/flag mismatch.

## Out of scope
- Ring geometry, headers, append/wrap, and recovery → T18.
- Raw partition read/write/erase and boot recovery → T19.
- Sample-pipeline wiring and counters → T21.
- BLE sync framing and `record_size` in the sync header → Phase 3 BLE tasks (T27–T38).
- App-side record codec and SQLite import → M2/M3 app tasks (T27–T38, T39–T46).
- Alarms/notifications: outside MVP; no task owns them.
- A Billows control path: outside MVP; M5 (T56–T60) is observation only.

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
- [ ] Encode/decode round-trip passes for attached, detached, invalid, Celsius-source, and alarm-edge records.
- [ ] A bad CRC is rejected.
- [ ] A detached probe decodes to `TEMP_DETACHED`, never a numeric temperature.
- [ ] An attach-bit/flag mismatch is rejected.
- [ ] `record_size` is 18 and is what readers use.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
