# ADR 0023 — bridge_config: KV seam, NVS key aliases and one reset table

- **Status:** Accepted
- **Date:** 2026-10-26
- **Task:** T15 (bridge_config)

## Context

`bridge_config` must be the only component that opens NVS (design 03 §3.1,
§3.7), yet the host suite may not link ESP-IDF. Design 03 names logical keys
such as `display_timeout_s`, `last_reset_reason` and `billows_target_f10`, but
ESP-IDF limits an NVS key name to 15 characters, so those names cannot be
stored literally.

## Decision

1. **Two-layer component.** `bridge_config.c` is plain C11 over a byte-oriented
   `bridge_config_kv_t` seam (`get`/`set`/`erase` with namespace and key
   strings). `bridge_config_nvs.c` is the ESP-IDF adapter and the only file that
   calls `nvs_open()`, `nvs_get_blob()`, `nvs_set_blob()` and `nvs_erase_key()`.
   Host tests run the same core against a RAM fake.
2. **Physical key aliases.** Logical names that fit stay unchanged. The three
   longer logical names map to: `display_timeout_s` → `disp_timeout_s`,
   `last_reset_reason` → `last_reset`, `billows_target_f10` →
   `billows_tgt_f10`. All values are little-endian blobs (strings are stored
   without their NUL). `_Static_assert`s in the core enforce the 15-character
   NVS limit.
3. **Version metadata.** `config_version` (u16, value 1) lives in the small
   `meta` namespace. It is layout metadata, not user data, so factory reset
   keeps it. Version 0/absent is the unversioned pre-T15 layout; migration
   scrubs wrong-sized values, keeps valid keys, ensures a generation exists,
   then writes version 1. A version greater than the compiled one returns
   `BRIDGE_CONFIG_ERR_VERSION` and writes nothing.
4. **Validate, then write.** Every setter validates the complete record first
   (frequency 902–928 MHz, probes 2 or 4, printable ASCII device ID, UTF-8
   device name ≤15 bytes, timeout in {0, 30, 60, 120}, units 0/1, valid clock
   requires a non-zero anchor). Validation failure returns
   `BRIDGE_CONFIG_ERR_INVALID` and changes neither NVS nor the cache. A
   multi-key write rolls back best-effort to the previous record on an I/O
   failure.
5. **Generation ordering and scope.** A new generation is a random 32-bit value
   (firmware: `esp_random()`), written before `clear_pending = 1` and before
   the caller erases. It changes only on `begin_log_clear`, factory reset, or
   an explicit `regenerate_generation()` for a wholly unusable log. A single
   bad sector must never call that API; `set_generation()` exists only so T19
   can adopt the generation recovered from a sector header.
6. **One factory-reset table.** `k_reset_steps[]` (exposed read-only as
   `bridge_config_factory_reset_steps()`) enumerates the generation step, the
   pending-clear step, every active/reserved key, and the final NimBLE bond
   store clear. It is the only enumeration of reset work.
7. **Bond-store wrapper.** A bond-clear hook is installed by the NVS adapter.
   With NimBLE linked it calls `ble_store_clear()`; no other component may open
   the bond namespace or call that function. `clear_bonds()` forgets phones
   without touching pairing; `clear_pairing()` re-pairs the radio without
   touching bonds or the log.
8. **Billows reserved fields.** `billows_mode` / `billows_target_f10` have no
   setter and no read path into NVS. `get_reserved_billows()` returns 0/0.

## Consequences

- T16 calls `set_pairing()` only after `CONFIRMED`; `clear_pairing()` is the
  re-pair path. T19 calls `begin_log_clear()` / `finish_log_clear()` and, only
  for whole-log corruption, `regenerate_generation()`; `clear_pending` is read
  from `get_log()`. T20 calls `clock_set()` at most every 10 minutes. T47 maps
  the BLE config struct onto the device getters/setters.
- Callers see typed results, not raw NVS keys. Adding a key requires updating
  the constants, validators, load/save code and the reset table together.
- `meta/config_version` is the only namespace outside the design table; it is
  documented here and in design 03 §3.7.
- The core cache is not locked. A single writer per field is assumed; T20/T47
  must serialize if writes move to different tasks.
