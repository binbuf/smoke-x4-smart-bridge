# T15 — bridge_config: typed NVS store

## Goal
`bridge_config` is the single owner of NVS and exposes typed, validated getters/setters for pairing, device settings, log state, clock anchor, and boot counters. Bad writes change nothing, migrations are versioned, and the one documented foreign namespace (NimBLE bonds) is wrapped rather than touched directly.

## Context (read first)
- [03 §3.7](../design/03-firmware-architecture.md) — namespaces, keys, versioning, factory reset, and generation rules.
- [03 §3.1](../design/03-firmware-architecture.md) — one owner per resource; NVS belongs to `bridge_config`.
- `firmware/components/bridge_config/` — the typed store.
- `firmware/components/sample_log/` — recovers the sample sequence from flash; NVS does not store it.
- **Verification:** H (host/CI). **Board:** no.
- Depends on T04.

## Scope
- [x] Implement the namespaces and typed getters/setters:

  | Namespace | Keys |
  |---|---|
  | `pair` | `device_id`, `frequency_hz`, `num_probes`, `paired_at` |
  | `device` | `units`, `display_timeout_s`, `device_name`; `billows_mode` / `billows_target_f10` reserved and unwritten in the MVP |
  | `log` | `generation`, `clear_pending`, `clock_anchor_s`, `clock_valid` (the sample sequence is recovered from flash, not stored here) |
  | `stats` | `boot_count`, `last_reset_reason`, `packets_ok`, `packets_bad` |
  | BLE bonds | NimBLE's own namespace — documented exception only |

- [x] Add `config_version` and forward migrations gated on it.
- [x] Validate every write before persisting; a bad write returns `invalid` and changes nothing.
- [x] Keep pairing data independent of log data: clearing the log does not unpair, and forgetting phones does not unpair.
- [x] Make the generation a new random 32-bit value on a log clear, factory reset, or whole-log corruption; a single bad sector does not change it.
- [x] Wrap NimBLE's bond-store clear call in this component; no other component opens the bond namespace directly.
- [x] Enumerate all factory-reset keys in one place, including the bond-store clear.
- [x] Add tests for every active key round-trip, bad UTF-8 `device_name`, reserved Billows fields ignored, factory reset, and pairing-store clear.

## Out of scope
- Ring geometry, record encoding, and flash recovery → T17/T18/T19.
- Clock policy and the live snapshot → T20.
- BLE bond creation/security and the NimBLE host → Phase 3 BLE tasks (T27–T38).
- Factory-reset/clear-history UI and command handling → M4 settings (T47–T55).
- Billows mode/target behavior → M5 Billows (T56–T60); the fields are reserved and unwritten here.
- Any Wi-Fi/HTTP/OTA configuration: outside MVP; no task owns it.

## Design notes
- `bridge_config` is the only component that opens NVS ([03 §3.1](../design/03-firmware-architecture.md)). Callers use typed APIs, never raw keys.
- Forward-compatible migrations: read `config_version`, migrate known older layouts, then persist the new version. Never guess at an unknown future version.
- Validation includes range checks (`frequency_hz` 902–928 MHz, display timeout in the allowed set, valid UTF-8 name) before any NVS write.
- A failed write must leave the previous value intact; do not erase first and validate later.
- `generation` is random, not a counter. It is written to NVS before an erase begins, so a power cut mid-clear cannot resurrect old-generation sectors.
- `clear_pending` records an interrupted clear for the boot path to finish.
- `billows_mode` and `billows_target_f10` are reserved: reading them must not create behavior, and nothing in the MVP writes them.
- The NimBLE bond namespace is the only documented exception; wrap its clear call here so factory reset has one entry point.
- NVS is not written per sample; clock persistence is at most every 10 minutes (T20).

## Done when
- [x] Every active key round-trips through its typed getter/setter.
- [x] A bad write (out-of-range, malformed UTF-8) changes nothing and returns `invalid`.
- [x] Factory-reset keys are enumerated in one place and the bond store is cleared through the wrapper.
- [x] Reserved Billows fields are ignored/unwritten in the MVP.
- [x] A single bad log sector does not change `generation`.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Hand-off below filled in.

## Hand-off

**Landed.** `bridge_config` is now a two-layer component: plain-C11 core
(`bridge_config.c`) over a byte-oriented `bridge_config_kv_t` seam, plus the
ESP-IDF adapter (`bridge_config_nvs.c`) that is the only file opening NVS.
Typed getters/setters cover `pair` (device_id, frequency_hz, num_probes,
paired_at), `device` (units, display_timeout_s, device_name; reserved Billows
keys never written), `log` (generation, clear_pending, clock_anchor_s,
clock_valid), `stats` (boot_count, last_reset_reason, packets_ok, packets_bad),
and `meta/config_version` (v1, kept across factory reset). Every setter
validates the complete record before writing; invalid input returns
`BRIDGE_CONFIG_ERR_INVALID` and changes neither NVS nor the cache. v0/absent
layout migrates forward, future versions are refused untouched.

Generation is random (firmware `esp_random()`), written before
`clear_pending = 1` and before any erase; it changes only on a log clear,
factory reset, or `regenerate_generation()` for a wholly unusable log.
`set_generation()` exists for T19 header recovery; a single bad sector does not
change it. `bridge_config_factory_reset_steps()` is the single reset
enumeration (new generation, pending clear, every key, bond clear), and
`bridge_config_factory_reset()` walks it. `clear_bonds()` forgetting phones
and `clear_pairing()` re-pairing the radio are independent; neither clears the
log. NimBLE's bond store is cleared only through the adapter's
`ble_store_clear()` hook (compiled when `CONFIG_BT_NIMBLE_ENABLED` exists).

**Deviation.** ESP-IDF limits NVS key names to 15 characters, so three logical
keys have physical aliases: `display_timeout_s` → `disp_timeout_s`,
`last_reset_reason` → `last_reset`, `billows_target_f10` →
`billows_tgt_f10` (the last never written). `config_version` lives in a new
`meta` namespace because design 03's table had no home for layout metadata.
Values are little-endian blobs and strings have no NUL. The component has no
change-notification hook yet; T47 should add one with the BLE config mapping.
The core cache is unlocked (single-writer assumption).

**Checks.**

```text
cmake -S firmware/test -B firmware/test/build -G Ninja   # configure ok
cmake --build firmware/test/build                        # ok
ctest --test-dir firmware/test/build --output-on-failure # 7/7 passed
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
# Project build complete; image guard ok; 0x393b0-byte image, 89% free
```

**Next.** T16 writes pairing only after `CONFIRMED` and uses
`clear_pairing()` to re-pair. T19 reads `clear_pending`, finishes the ring
erase, then calls `finish_log_clear()`; it uses `begin_log_clear()`,
`regenerate_generation()` (whole-log only) and `set_generation()` (header
recovery) as documented in `docs/progress/T15.md`. T20 persists the clock with
`clock_set()` at most every 10 minutes. T27/T30 must keep `ble_store_clear()`
inside `bridge_config_nvs.c`. No board check is required for T15.

**Docs.** Design 03 §3.7; ADR 0023; `docs/progress/T15.md`.

