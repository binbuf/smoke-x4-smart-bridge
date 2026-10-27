# T14 — sx_protocol: port and extend the parser

## Goal
A pure-C parser turns Smoke X4 state and sync payloads into validated values: canonical °F tenths, detached sentinels, preserved alarm/Billows bits, and explicit counters for rejected or foreign packets. It is host-testable with no ESP-IDF dependency and rejects malformed input without producing a partial sample.

## Context (read first)
- [02 §2.5](../design/02-smoke-x-protocol.md) — state-message layout, header fields, per-probe groups, sentinels, units, and canonical storage.
- [02 §2.9](../design/02-smoke-x-protocol.md) — the validation corpus and fixture locations.
- `legacy/firmware/components/smoke_x/smoke_x_parser.c` and `include/smoke_x_parser.h` — the MIT-licensed parser to port.
- `firmware/components/sx_protocol/` — the new pure-C component.
- `protocol/fixtures/lora/` — new fixture location; do not edit the legacy fixtures.
- **Verification:** H (host/CI). **Board:** no.
- Depends on T03 and T13.

## Scope
- [x] Port `smoke_x_parser.c` into `firmware/components/sx_protocol/`, retaining the MIT notice and the `smoke_x_types.h` shape where it still fits.
- [x] Keep `strtok_r`, strict numeric parsing, no heap allocation, and explicit units in every API.
- [x] Add device-ID comparison against the paired ID and a mismatch counter; foreign IDs are dropped and counted.
- [x] Map a detached probe (`state == 3`) to `TEMP_DETACHED` (`INT16_MIN`), never to the frozen numeric temperature.
- [x] Convert Celsius input to canonical °F tenths with `F10 = (C10 × 9) / 5 + 320`; record `source_celsius` for provenance only.
- [x] Parse the Billows-attached field and the Billows target fields; expose the target only after validation (the target relation is validated in M5).
- [x] Preserve `new_alarm` from the trailing field; there is no alarm feature in the MVP.
- [x] Reject wrong comma counts and any trailing garbage.
- [x] Accept the X4 26-comma state shape; accept the X2 16-comma shape defensively without adding X2 product acceptance.
- [x] Add all fixture vectors under `protocol/fixtures/lora/` with the raw capture and a short report (time, radio settings, what changed).

## Out of scope
- Radio receive, parameter configuration, and RSSI/SNR publishing → T13.
- Pairing FSM, sync ACK, frequency validation, and retuning → T16.
- Record encoding and CRC → T17.
- Ring writes, flash, and boot recovery → T18/T19.
- Billows target validation and observation UI → M5 Billows (T56–T60); no Billows TX/control path exists in the MVP.
- Alarm handling, buzzer, or phone notifications: outside MVP; no task owns them.
- App-side parsing or display → Phase 3 app tasks (T27–T37 and later M3 history tasks T39–T46).

## Design notes
- Message classes are disjoint by comma count ([02 §2.2](../design/02-smoke-x-protocol.md)):

  | Message | Commas | Direction |
  |---|---:|---|
  | Sync beacon | 6 | Smoke X4 → all |
  | Sync ACK | 2 | bridge → Smoke X4 |
  | State, X2 | 16 | Smoke X4 → all |
  | State, X4 | 26 | Smoke X4 → all |

- X4 state shape: 4 header fields, 4 × 5 probe fields, then `billows_attached,new_alarm,`.
- Per-probe group: `state,temp_x10,alarm,max,min`; `state == 3` means detached.
- Header `field1` and `field3` are diagnostics only. Preserve them; do not reinterpret them without a capture.
- `new_alarm` is the trailing `−1` field; header field 3 is not `new_alarm`.
- Detached probes freeze the last temperature on the X4; the parser must ignore that value and emit `TEMP_DETACHED`.
- Canonical storage is tenths of °F; the `source_celsius` flag is provenance, not a second value.
- Billows attached is the trailing `−2` field. A target from probe 4 `max` is unvalidated; expose it only behind a validation flag, otherwise unknown.
- Reject as a whole: no partial record, no partially updated output on failure.
- No dynamic allocation; the payload is at most ~128 bytes and all buffers are fixed/stack.
- Counters to keep visible to diagnostics: valid state packets, parse/CRC failures, foreign device IDs, sync beacons seen, ACK attempts.

## Done when
- [x] All fixture vectors pass, including the real X4 captures, the real sync capture, alarm-edge, detached, Celsius, Billows-attached, X2 defensive vectors, and the malformed cases.
- [x] A foreign device ID is dropped and increments the mismatch counter.
- [x] Wrong comma counts, bad numeric fields, and trailing garbage are rejected.
- [x] Detached input yields `TEMP_DETACHED`, not a frozen temperature.
- [x] Celsius input yields canonical °F tenths and sets `source_celsius`.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off

**Landed.** `firmware/components/sx_protocol/` now contains the pure-C parser
and typed API:

- `include/sx_protocol_types.h` carries the reworked `smoke_x_types.h` shape:
  `sx_protocol_sync_t`, `sx_protocol_probe_t`, `sx_protocol_state_t`,
  `sx_protocol_counters_t`, canonical `temp_f10`, and the detached/invalid
  sentinels.
- `include/sx_protocol.h` + `sx_protocol.c` provide
  `sx_protocol_parse_sync()`, `sx_protocol_parse_state()`,
  `sx_protocol_format_ack()`, comma/probe helpers and counter snapshots.
  `strtok_r`, strict numeric parsing, a fixed 128-byte stack buffer, and no
  heap are retained from the legacy parser; the upstream MIT notice is kept in
  the source comments and `LICENSE`. Counters also expose a
  `sx_protocol_note_crc_failure()` hook for T13's CRC/header branch.
- State parsing infers 2 probes (16 commas) or 4 (26), requires a single
  trailing comma and no empty fields/trailing tokens, compares the ID against
  the paired ID before other fields (foreign frames are dropped and counted),
  maps `state == 3` to `TEMP_DETACHED` (`INT16_MIN`), converts Celsius with
  `F10 = (C10*9)/5 + 320` and sets `source_celsius`, preserves
  `billows_attached`/`new_alarm`, and exposes probe 4 `max` only as an
  unvalidated Billows target candidate (`billows_target_valid == false`).
  Failure leaves `*out` untouched.
- `firmware/test/test_sx_protocol.c` (`sx-protocol` CTest) replays all 21
  corpus vectors, every real capture and the malformed capture; it asserts the
  named X4 baseline/alarm/detached/Celsius/Billows/foreign/X2 vectors, atomic
  rejection, counters and ACK formatting. `parser-vectors.tsv` gained
  `billows-target-candidate`.
- Docs: design 02 §2.5/§2.9, design 03 §3.6/§3.14, ADR 0022,
  `docs/progress/T14.md`.

**Deviation.** Sync beacons have no paired-ID argument: sync is the discovery
path, so T16 owns the ID/frequency policy after `sx_protocol_parse_sync()`.
Billows `max` is parsed as a candidate but deliberately never marked valid;
M5/T56 owns the relation. `alarm_high_deg`/`alarm_low_deg` stay in the
packet's active unit because no record field stores them.

**Checks.**

```text
cmake -S firmware/test -B firmware/test/build -G Ninja   # configure ok
cmake --build firmware/test/build                        # ok
ctest --test-dir firmware/test/build --output-on-failure # 6/6 passed
make host-test                                           # 6/6 passed
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete; image guard ok; 0x36830-byte image
```

**Next.** T21 must call `sx_protocol_parse_state()` with the persisted ID and
map `temp_f10`/attached bits into the record; T16 must apply the 902–928 MHz
check after sync and use `sx_protocol_format_ack()`. M5 validates the Billows
target relation. No board check is required for T14.

