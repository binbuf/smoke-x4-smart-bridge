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
- [ ] Port `smoke_x_parser.c` into `firmware/components/sx_protocol/`, retaining the MIT notice and the `smoke_x_types.h` shape where it still fits.
- [ ] Keep `strtok_r`, strict numeric parsing, no heap allocation, and explicit units in every API.
- [ ] Add device-ID comparison against the paired ID and a mismatch counter; foreign IDs are dropped and counted.
- [ ] Map a detached probe (`state == 3`) to `TEMP_DETACHED` (`INT16_MIN`), never to the frozen numeric temperature.
- [ ] Convert Celsius input to canonical °F tenths with `F10 = (C10 × 9) / 5 + 320`; record `source_celsius` for provenance only.
- [ ] Parse the Billows-attached field and the Billows target fields; expose the target only after validation (the target relation is validated in M5).
- [ ] Preserve `new_alarm` from the trailing field; there is no alarm feature in the MVP.
- [ ] Reject wrong comma counts and any trailing garbage.
- [ ] Accept the X4 26-comma state shape; accept the X2 16-comma shape defensively without adding X2 product acceptance.
- [ ] Add all fixture vectors under `protocol/fixtures/lora/` with the raw capture and a short report (time, radio settings, what changed).

## Out of scope
- Radio receive, parameter configuration, and RSSI/SNR publishing → T13.
- Pairing FSM, sync ACK, frequency validation, and retuning → T16.
- Record encoding and CRC → T17.
- Ring writes, flash, and boot recovery → T18/T19.
- Billows target validation and observation UI → M5 Billows (T56–T60); no Billows TX/control path exists in the MVP.
- Alarm handling, buzzer, or phone notifications: outside MVP; no task owns them.
- App-side parsing or display → Phase 3 app tasks (T27–T38 and later M3 history tasks T39–T46).

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
- [ ] All fixture vectors pass, including the real X4 captures, the real sync capture, alarm-edge, detached, Celsius, Billows-attached, X2 defensive vectors, and the malformed cases.
- [ ] A foreign device ID is dropped and increments the mismatch counter.
- [ ] Wrong comma counts, bad numeric fields, and trailing garbage are rejected.
- [ ] Detached input yields `TEMP_DETACHED`, not a frozen temperature.
- [ ] Celsius input yields canonical °F tenths and sets `source_celsius`.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
