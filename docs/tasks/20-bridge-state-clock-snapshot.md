# T20 — bridge_state: clock and live snapshot

## Goal
`bridge_state` maintains the UTC/estimated clock and a live snapshot of temperatures, sequence, flags, Billows state, age, battery, and RSSI. The clock anchor is persisted at most every 10 minutes, unknown time stays explicitly unknown, and the setter is ready for the future BLE `set_time` wiring.

## Context (read first)
- [04 §4.4](../design/04-data-and-storage.md) — time without an RTC, `unix_s = 0`, the 10-minute anchor, and no backward time adjustment.
- [03 §3.8](../design/03-firmware-architecture.md) — `unix_s`, `clock_valid`, and `last_anchor_uptime_s`.
- [03 §3.6](../design/03-firmware-architecture.md) — the live snapshot is updated on every sample.
- `firmware/components/bridge_state/` — clock, snapshot, and counters.
- **Verification:** H (host/CI). **Board:** no.
- Depends on T15.

## Scope
- [ ] Implement the clock state: `unix_s` (0 = unknown), `clock_valid`, and `last_anchor_uptime_s` for monotonic advancement.
- [ ] Persist the clock anchor to NVS every **10 minutes**; do not write NVS per sample.
- [ ] On boot, restore the persisted anchor plus elapsed uptime/deep-sleep time when known, and mark it **estimated** until the app sets it.
- [ ] Keep a live snapshot with temperatures, sequence, flags, Billows state, packet age, battery, and RSSI.
- [ ] Update the snapshot on every valid sample.
- [ ] Expose the time setter for T29's future BLE `set_time` path; do **not** wire BLE yet.
- [ ] Ensure records written while the clock is unknown carry `unix_s = 0` and `clock_valid = 0`.
- [ ] Never adjust sample time backwards; a clock correction affects future records only.

## Out of scope
- BLE `set_time` op, `control` characteristic, and connection lifecycle → Phase 3 BLE tasks (T27–T38).
- Battery ADC sampling and SoC curve → T24; this task only carries the resulting mV/% in the snapshot.
- UI rendering of snapshot fields → T22.
- Record encoding and flash writes → T17/T19.
- Parser and radio ownership → T14/T13.
- Server-side time, time zones, DST, or NTP: outside MVP; no task owns it. The bridge stores UTC.
- Alarms/notifications based on age: outside MVP; no task owns them.

## Design notes
- The board has no RTC and no battery-backed clock ([04 §4.4](../design/04-data-and-storage.md)).
- `clock_valid` is false until an app `set_time` or a restored anchor is available; a restored anchor is **estimated**, not exact.
- The app sets the clock on every connect when the delta exceeds **2 s** (wiring is Phase 3).
- Persist `clock_anchor_s` / `clock_valid` every 10 minutes via `bridge_config`; no per-sample NVS traffic.
- `seq` is the ordering source of truth; time is placement. Never renumber or reorder to hide a clock correction.
- Snapshot fields are read by the UI and later by BLE `live`; keep one struct and update it atomically from the pipeline.
- Age is relative to the last valid state packet, used by the UI's 90 s liveness rule.
- Unknown battery is `SOC_UNKNOWN (255)` from T24 and must render as `—`, not 0%.

## Done when
- [ ] Records written while the clock is unknown carry `unix_s = 0`.
- [ ] A reboot restores an estimated anchor from the persisted `{unix_s, uptime}` pair.
- [ ] The snapshot updates on every valid sample.
- [ ] The anchor is persisted every 10 minutes, not per sample.
- [ ] The setter exists and is callable by the future BLE task; no BLE code is added here.
- [ ] A clock correction never changes past records or moves time backwards.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
