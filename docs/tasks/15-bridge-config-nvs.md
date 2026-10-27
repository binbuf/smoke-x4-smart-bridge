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
- [ ] Implement the namespaces and typed getters/setters:

  | Namespace | Keys |
  |---|---|
  | `pair` | `device_id`, `frequency_hz`, `num_probes`, `paired_at` |
  | `device` | `units`, `display_timeout_s`, `device_name`; `billows_mode` / `billows_target_f10` reserved and unwritten in the MVP |
  | `log` | `generation`, `clear_pending`, `clock_anchor_s`, `clock_valid` (the sample sequence is recovered from flash, not stored here) |
  | `stats` | `boot_count`, `last_reset_reason`, `packets_ok`, `packets_bad` |
  | BLE bonds | NimBLE's own namespace — documented exception only |

- [ ] Add `config_version` and forward migrations gated on it.
- [ ] Validate every write before persisting; a bad write returns `invalid` and changes nothing.
- [ ] Keep pairing data independent of log data: clearing the log does not unpair, and forgetting phones does not unpair.
- [ ] Make the generation a new random 32-bit value on a log clear, factory reset, or whole-log corruption; a single bad sector does not change it.
- [ ] Wrap NimBLE's bond-store clear call in this component; no other component opens the bond namespace directly.
- [ ] Enumerate all factory-reset keys in one place, including the bond-store clear.
- [ ] Add tests for every active key round-trip, bad UTF-8 `device_name`, reserved Billows fields ignored, factory reset, and pairing-store clear.

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
- [ ] Every active key round-trips through its typed getter/setter.
- [ ] A bad write (out-of-range, malformed UTF-8) changes nothing and returns `invalid`.
- [ ] Factory-reset keys are enumerated in one place and the bond store is cleared through the wrapper.
- [ ] Reserved Billows fields are ignored/unwritten in the MVP.
- [ ] A single bad log sector does not change `generation`.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
