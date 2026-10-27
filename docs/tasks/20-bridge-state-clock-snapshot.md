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
- [x] Implement the clock state: `unix_s` (0 = unknown), `clock_valid`, and `last_anchor_uptime_s` for monotonic advancement.
- [x] Persist the clock anchor to NVS every **10 minutes**; do not write NVS per sample.
- [x] On boot, restore the persisted anchor plus elapsed uptime/deep-sleep time when known, and mark it **estimated** until the app sets it.
- [x] Keep a live snapshot with temperatures, sequence, flags, Billows state, packet age, battery, and RSSI.
- [x] Update the snapshot on every valid sample.
- [x] Expose the time setter for T29's future BLE `set_time` path; do **not** wire BLE yet.
- [x] Ensure records written while the clock is unknown carry `unix_s = 0` and `clock_valid = 0`.
- [x] Never adjust sample time backwards; a clock correction affects future records only.

## Out of scope
- BLE `set_time` op, `control` characteristic, and connection lifecycle → Phase 3 BLE tasks (T27–T37).
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
- [x] Records written while the clock is unknown carry `unix_s = 0`.
- [x] A reboot restores an estimated anchor from the persisted `{unix_s, uptime}` pair.
- [x] The snapshot updates on every valid sample.
- [x] The anchor is persisted every 10 minutes, not per sample.
- [x] The setter exists and is callable by the future BLE task; no BLE code is added here.
- [x] A clock correction never changes past records or moves time backwards.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off

**Landed (2026-10-26).**

- `firmware/components/bridge_state/` — `bridge_state.c` is the plain-C clock
  and snapshot core over an injected monotonic millisecond source and
  `bridge_config`; `bridge_state_esp.c` installs `esp_timer_get_time()` and is
  wired in `boot.c` after `bridge_config_init`. Public API in
  `include/bridge_state.h`: `bridge_state_now`, `set_time`, `tick`, `update`,
  `snapshot`, `stamp_record`, device-flag/battery setters.
- Clock: `unix_s = 0` when unknown; a stored anchor restores `valid = true,
  estimated = true`; the first app set clears `estimated`. `set_time` refuses a
  time earlier than the current clock; `stamp_record` writes 0/cleared while
  unknown and clamps so record timestamps never decrease.
- Anchor persistence: `bridge_config` now stores the `{clock_anchor_s,
  clock_uptime_s, clock_valid}` pair. `bridge_state_tick()` writes at most once
  per 10 minutes, retries a failure after 60 s, and `update()` never writes NVS.
  The first app set persists immediately.
- Snapshot: sequence, four temperatures, attached mask, billows attached/target,
  battery mV/%, LoRa RSSI/SNR, plus device flags. `snapshot()` copies under a
  C11 sequence lock and computes `age_s`, the 90 s `SMOKE_LIVE` bit and the
  clock-valid bit at read time. Unknown battery defaults to 255.
- Tests: `firmware/test/test_bridge_state.c`, CTest `bridge-state` (9 tests).
  Covers unknown-clock records, first-set persistence, cadence with 120 samples
  and zero NVS writes, reboot restore, uptime-survives-wake and known-sleep
  advancement, backward correction refusal, snapshot fields/liveness, arguments,
  and factory reset of the anchor pair.
- Docs: design 03 §3.6/§3.8, design 04 §4.4, ADR 0028.

**Deviations / decisions.**
- `bridge_config` gained the additive `clock_uptime_s` key (u64) so the persisted
  pair is real. This is additive; `config_version` stays 1 and the old two-field
  clock getter/setter still work with `uptime_s = 0`.
- Deep-sleep off-time is not known by the current ESP timer; the restored anchor
  advances only from reboot unless a known `elapsed_sleep_s` is passed. The
  persisted pair already supports a future RTC-backed uptime source.
- There is no periodic board caller for `bridge_state_tick()` yet. T21 must call
  it from the writer (cheap, writes only when due) or T24's housekeeping must own
  the cadence.

**Checks.**
- `cmake -S firmware/test -B firmware/test/build -G Ninja` + build: OK.
- `ctest --test-dir firmware/test/build --output-on-failure`: 12/12 passed,
  including `bridge-state` and the unchanged `bridge-config`.
- `idf.py ... build`: project build complete; image guard ok (esp32s3, 69
  components, no Wi-Fi/HTTP/OTA); `sx4_bridge.bin` 0x3c050 bytes, 88% free.

**Next task must know.** T21 calls `bridge_state_stamp_record()` before append,
then `bridge_state_update(&sample)` for every accepted packet, and
`bridge_state_tick()`. T29 maps `unix_ms / 1000` to `bridge_state_set_time()` and
must surface `BRIDGE_STATE_ERR_TIME` as a refusal; `tz_offset_min` is not stored.
T24 calls `bridge_state_set_battery()`. No BLE code was added here.
