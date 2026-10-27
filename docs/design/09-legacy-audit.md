# 09 — Legacy Audit

`legacy/` contains a substantially larger, Wi-Fi-capable product with a cook
session model, alarm engine, history app, OTA, and a long design history. It is
useful as a protocol/hardware reference and as a list of failure modes. It is
**not** the starting codebase for this MVP.

This audit records what is kept, what is left behind, and why. It is the answer
to "confirm what we're leaving behind".

## 9.1 What the legacy tree actually contains

| Area | Legacy reality |
|---|---|
| Firmware | ESP-IDF, C, Heltec V3. A "slim" BLE-only build exists, but it has never been flashed to a board. |
| Protocol | Real X4 captures, a host-tested ASCII parser, sync/pairing knowledge, and a 16-byte session-record format. |
| BLE | A custom GATT service with passkey bonding, live notify, chunked history, config, and control ops. |
| App | Flutter, BLE-only in the slim build, with Live/Graph/History, a connection sheet, a cook clock, settings, and a drift cache. |
| Full-product docs | Wi-Fi AP/STA, HTTP/WebSocket, MQTT/Home Assistant, OTA, alarms, notifications, multi-bridge, sessions/marks/CSV. |
| Hardware | Verified pin map, Vext/OLED order, battery divider, button, enclosure; deep-sleep wake still unproven. |
| Tests | Host C tests for parser/cook store; Flutter tests; no real-board history sync proof. |

The legacy `ROADMAP.md` already cut the product to a BLE-only slim build. This
MVP goes further: it removes the cook-session model and the history app as well,
because the brief asks for a continuous graph of whatever was collected, not
named cooks.

## 9.2 Kept

### Protocol and radio knowledge

- The LoRa physical parameters (SF9, 125 kHz, CR 4/5, sync word `0x12`, CRC on).
- The sync beacon/ACK handshake and its invariant: **one ACK per pairing**.
- The X4 state message layout, detached-probe semantics, units conversion, and
  device-ID filtering.
- The real capture corpus in `legacy/protocol/fixtures/lora/`, used as test
  input (copied into the new `protocol/fixtures/`, not read from `legacy/` at
  runtime).
- The Billows field hypothesis and the questions that must be answered with a
  real unit. Control is not inherited; the MVP is observation-only.

### Code patterns that may be reused

These are communication-level, not product-level:

- `smoke_x_parser.c` / `smoke_x_types.h` — pure C, no heap, `strtok_r`, strict
  numeric parsing. Reuse with the MIT notice and extend for the new record.
- The pinned `ra01s` SX1262 driver integration and the parameter block.
- The BLE security pattern: passkey + bonding + encrypted/authenticated
  characteristics, and the chunked-notification reassembly approach.
- The idea of a host-testable flash core behind a small I/O seam.

“Reuse” means copy the minimum, retain the licence, and adapt it to the new
contract. Do not copy the legacy `app_ble` service wholesale; its characteristic
set and payloads are different.

### Hardware facts

- GPIO map, Vext/OLED power order, GPIO37 battery-divider polarity, button
  debounce, battery divider ratio.
- The enclosure dimensions and the 3000 mAh pack fit.
- The deep-sleep/GPIO0-strap risk, which remains open and is a V0 gate.

### Tests and fixtures

- Parser vectors, detached-probe vector, Celsius vector, alarm-edge vector.
- The principle that the host test suite runs without ESP-IDF or hardware.

## 9.3 Dropped

| Legacy area | Evidence | Why it is dropped |
|---|---|---|
| Wi-Fi AP/STA, mDNS, HTTP REST, WebSocket, captive portal | `legacy/docs/design/05-connectivity-and-provisioning.md`, `06-device-api.md`; the current slim `legacy/firmware/components/` no longer contains `app_net`/`app_api`, so this is design history | BLE-only MVP; the network stack is most of the RAM, security, and failure surface. |
| MQTT / Home Assistant | `legacy/docs/design/05 §5.7a` (legacy A16) | No cloud/automation in the brief. |
| OTA / browser installer | `legacy/docs/firmware-slim.md §Update path`, legacy task `F14.9` | USB-only MVP. OTA adds partitions, rollback, and brick risk. |
| Cook sessions, headers, names, marks, pinning, retention policy | `legacy/docs/design/04-storage-and-history.md`, `legacy/firmware/components/cook_store` | The brief asks for a continuous graph, not named cooks. Sessions caused the sync-completeness bugs the new cursor design eliminates. |
| History list, session detail, CSV export, share sheet | `legacy/app/lib/features/history`, `docs/new-app.md` | Graph tab replaces the history list; no export in MVP. |
| Cook clock, guided cooks, presets, ETA, stall/lid detection | `legacy/docs/design/09-alarms-and-insights.md`, `legacy/app/lib/features/cook` | Not in the brief. |
| Alarm engine, buzzer/LED alarm patterns, phone notifications, foreground service, quiet hours | `legacy/docs/design/09-alarms-and-insights.md`, `legacy/docs/tasks/M5-alarms-display-insights.md` (the slim firmware has no `app_alarm`) | The Smoke X4's own alarm remains the alarm. The bridge is a recorder. |
| Multi-bridge picker/switcher | `legacy/docs/design/00 D12` | One bridge per app install. |
| Four-tab shell, setup machine (~34 states), design system, custom fonts, golden UI suite | `legacy/docs/current-app.md` (archived app.old), `legacy/docs/design/13`, `14`; `legacy/app/lib/design` | The brief asks for a custom, thin app; inheriting this UI/UX would carry the old product's shape and debt. |
| Novelty log, raw packet ring, diagnostics console, power log, battery saver, calibration UI | `legacy/docs/design/02 §2.7`, `legacy/docs/design/06 §6.4`, `legacy/app/lib/features/settings` | Useful for protocol work, not for the MVP user. Keep only counters/stats. |
| Wi-Fi scan, AP PSK, network mode, provisioning races, mDNS address cache | Legacy docs 05/06 and app transport work | No network. |
| HTTP transport, mock HTTP sim, network binder | `legacy/docs/design/06`, `legacy/tools/sim`; the BLE layer at `legacy/app/lib/data/ble` is the only app transport kept for reference | No HTTP. The app's test seam is a BLE fake. |
| X2-specific UI/acceptance | Legacy parser supports X2 | X4 is the target; parser may defensively accept X2, nothing more. |
| Legacy app's visual language and copy | `legacy/docs/design/13`, `14`, `newui/` | Explicitly out: build a new, simple UI. |

## 9.4 Defects and traps not to inherit

These are recorded so the new implementation does not repeat them.

| Legacy issue | Why it happened | New design response |
|---|---|---|
| Session sync could re-fetch forever when `sample_count` was unreachable | Completion depended on a header count and a cursor that could start above a hole | Sequence cursor + explicit `min_seq`/`max_seq`; a request returns actual records, and `count = 0` terminates. |
| A cache starting mid-session left a permanent hole; the header lied | `fromT = cachedMax + 1` assumed a complete prefix | Backward recent-first sync plus forward catch-up; gaps are explicit and never silently filled with a straight line. |
| Two transports fighting / a stale cached HTTP address crashed the app | HTTP race, cached IP, uncaught socket exception | BLE only; one connection state machine; every platform exception maps to a named state. |
| Free heap fell to ~78 KB with Wi-Fi + BLE + HTTP | The full stack was too large for 512 KB/no PSRAM | No Wi-Fi/httpd; target ≥120 KB free after boot; 24 h soak with a floor. |
| GATT write error path passed an uninitialized buffer | A `!= 0` branch used `sizeof buf + 1` | Codecs validate length before unpack; host tests cover malformed writes. |
| Button gesture ladder / hidden reset gestures | Too many verbs on one button | Tap + hold only; factory reset is app-only; no boot-time menu/reset hold (the hold-to-wake confirmation is the sole boot-time hold). |
| GPIO0 deep-sleep wake possibly enters ROM download | Strapping pin sampled at reset | Explicit V0 bench gate; fallback documented before shipping. |
| Billows was decoded but never surfaced; target field unvalidated | No Billows unit was available | Observation is a first-class task. Control is not attempted: the Smoke X4 receiver cannot change set points, so the bridge cannot either. Target display waits for a passive T56 capture; extra RF telemetry is a post-MVP receive-only survey. |
| OLED pages described features the device did not own (cook clock, session) | Display copied app concepts | Four pages contain only what the device knows. |
| The app inherited a large design system and setup machine | The full product grew before the slim cut | New app starts at three destinations; no legacy UI code. |

## 9.5 What we still need from the old tree

| Need | Source | Action |
|---|---|---|
| Parser + MIT notice | `legacy/firmware/components/smoke_x/smoke_x_parser.c`, `include/smoke_x_parser.h` | Copy/adapt into `firmware/components/sx_protocol`, retain notice |
| SX1262 driver | `legacy/firmware/vendor/esp-idf-sx126x` | Pin the same known-good driver in the new tree |
| Real X4 captures | `legacy/protocol/fixtures/lora/*.loralog` | Copy the relevant captures + reports into new fixtures |
| BLE security/chunking patterns | `legacy/firmware/components/app_ble` | Read for approach; write new service against [05](05-ble-contract.md) |
| Hardware verified rows | `legacy/docs/hardware-verified.md` | Re-run the relevant rows; record in a new `docs/hardware-verified.md` |
| Enclosure | `enclosure/out/*.stl` | Reuse as-is unless Billows hardware changes the case |

Do not copy:

- `legacy/app/lib` UI, design system, router, setup machine, history/session UI.
- `legacy/firmware/components/app_alarm`, `app_api`, `app_net`, `app_ota`
  (if present in the full tree), `cook_store` session/retention logic.
- `legacy/protocol/openapi.yaml`, HTTP-era schemas.
- Any test that asserts the old session model.

## 9.6 Provenance

Protocol decoding, the SX1262 driver integration, and the pairing handshake
derive from [`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver)
(MIT © 2022 G-Two). Files carried over retain the upstream notice. The new
project is not affiliated with or endorsed by ThermoWorks. Smoke X is a
trademark of its owner and is used only to describe compatibility.

## 9.7 Audit conclusion

The legacy tree has already done the expensive, uncertain work: the radio
protocol, the pairing handshake, the pin map, and the BLE security pattern. It
has also accumulated a product shape the brief does not want.

The new build should take the **communication knowledge and the bench facts**,
not the product. The thinnest vertical slice is a listening bridge with a rolling
log and a BLE window into it; every legacy feature that does not serve that
sentence stays behind.
