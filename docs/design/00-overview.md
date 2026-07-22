# 00 — Overview, Scope, and Decisions

## What this is

**Smoke X4 Smart Bridge** is a monorepo containing:

1. **Firmware** for a Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262) that passively receives the
   915 MHz LoRa transmissions from a ThermoWorks Smoke X2/X4 base station, decodes them,
   **persists a full multi-day cook history to flash**, and serves that data over Wi-Fi (HTTP +
   WebSocket) and Bluetooth LE.
2. **A Flutter app** (Android first) that discovers the bridge, provisions its network mode over
   BLE, and shows live probe temperatures, a long-cook graph, alarms, and cook history.

The bridge is a **listener**, not a replacement receiver. The stock ThermoWorks receiver keeps
working; so does every other paired receiver. The bridge transmits exactly one LoRa packet in its
entire lifetime — the pairing acknowledgement (see [02 — Smoke X Protocol](02-smoke-x-protocol.md)).

## Why build it

The Smoke X hardware is excellent (accurate, ~1 mile LoS range, no cloud dependency) but the
receiver only shows _now_. The upstream open-source project
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver) (MIT, vendored read-only at
`docs/reference/smoke-x-receiver`) solves the "get the data off the air" half beautifully and we
reuse its protocol work wholesale. What it does not solve:

| Upstream limitation                      | Consequence                                                                                                                            | Our fix                                                                                             |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| History lives in a RAM `cJSON` array     | Power blip or reboot = entire cook lost                                                                                                | Append-only binary log on a 2.4 MB flash partition ([04](04-storage-and-history.md))                |
| `MAX_RECORDS 1200` @ 30 s cadence        | ~10 h ceiling                                                                                                                          | ~54 days of continuous samples on disk                                                              |
| `JSON_STR_LEN 16000` static print buffer | X4 (4 probes) overflows it around ~600 records (~5 h) and `GET /data` starts returning 500 — see [note below](#the-16-kb-json-ceiling) | Streamed binary/NDJSON responses, no whole-history DOM                                              |
| Samples have no timestamps               | A reception gap silently compresses the time axis; the graph lies                                                                      | Every sample carries seconds-since-session-start; wall clock derived                                |
| No concept of a "cook"                   | Can't compare, name, or export a session                                                                                               | First-class `CookSession` with header, marks, and stats                                             |
| Web UI only                              | No push alarms, no background monitoring, no phone-native UX                                                                           | Flutter app + Android foreground service ([08](08-flutter-app.md), [09](09-alarms-and-insights.md)) |
| Wi-Fi setup via serial/AP web form       | Awkward at a smoker in a yard                                                                                                          | BLE provisioning + AP/STA handoff from the phone ([05](05-connectivity-and-provisioning.md))        |
| Display is a static 7-line status dump   | Underuses a 128×64 OLED and the button                                                                                                 | Paged UI, sparkline, gesture-driven control ([07](07-display-and-controls.md))                      |

### The 16 KB JSON ceiling

Worth stating precisely because it is the single strongest argument for a rewrite of the data path
rather than a patch. In `main/smoke_x.c` the entire history is held as a `cJSON` DOM and serialized
into one preallocated buffer:

```c
#define MAX_RECORDS 1200
#define JSON_STR_LEN 16000
static char json_str[JSON_STR_LEN];
...
cJSON_PrintPreallocated(root, json_str, sizeof(json_str), false);
```

A serialized reading such as `84.8,` costs ~6 bytes. Four probes at 1200 records is
`4 × 1200 × 6 ≈ 28.8 KB` — comfortably past the 16 KB buffer, so `cJSON_PrintPreallocated`
returns false and `data_get_handler` replies `500`. By arithmetic an X4 starts failing at roughly
600 records ≈ 5 hours. (X2 squeaks under the limit at ~14.4 KB.) **Verify on hardware before
citing this as fact** — but the design does not depend on the outcome: streaming from flash is the
right shape regardless.

## Scope

### In scope (v1.0)

- Smoke X2 **and** X4 support (X4 is the target; X2 falls out of the same parser)
- Pair / unpair with the base station, survive reboots
- Persist every received sample to flash, indefinitely, with timestamps
- Two network modes — **Hosted AP** and **Joined STA** — selectable at boot, from the button, from
  BLE, or from the HTTP API
- BLE GATT control service: provisioning, mode switch, pairing control, clock set, **and live
  telemetry** so the app works with no Wi-Fi at all
- HTTP REST + WebSocket API, mDNS discovery, captive-portal shim for Android
- Flutter Android app: onboarding, live dashboard, multi-probe chart over 15 h+, session history,
  alarms via a foreground service, CSV/JSON export
- On-device alarm engine (fires without a phone present) and OLED/LED signalling
- OTA firmware update from the app

### Out of scope (v1.0, designed not to preclude)

- iOS build (the Flutter code is portable; the Android-specific network binding is isolated behind
  a platform channel — see [08](08-flutter-app.md))
- MQTT / Home Assistant publishing (**deliberately dropped** — see decision D2; the internal event
  bus is shaped so a publisher module drops in later without refactoring)
- Cloud sync, accounts, remote access outside the LAN
- Controlling the Billows fan (we _observe_ its state; the Smoke X owns control) — and per D11, even
  observation is decode-and-store only in v1, with no UI
- Multi-bridge / multi-smoker UI (D12) — the data model supports it, the screens don't
- The device-served fallback web UI (D13) — deferred, partition reserved
- Any attempt to impersonate a ThermoWorks receiver beyond the documented pairing handshake

## Decisions already made

| ID      | Decision                                                        | Rationale                                                                                                                                                                                                                                                                                                                                                           |
| ------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **D1**  | **Custom BLE GATT service**, not `wifi_provisioning`            | Espressif's manager only does STA credentials and then shuts down. We need AP/STA mode switching, pairing control, clock set, and — the real win — **live temperature notify**, so the phone still works at a smoker with no Wi-Fi in range. Details in [05](05-connectivity-and-provisioning.md).                                                                  |
| **D2**  | **No MQTT / Home Assistant in v1**                              | Removes TLS certs, cert-upload UI, discovery payloads, and a large config surface from both firmware and app. Re-addable as one module behind the event bus.                                                                                                                                                                                                        |
| **D3**  | **One button, gesture-driven**                                  | The board exposes exactly one usable button (PRG on GPIO0). No soldering, no enclosure work. Tap / double-tap / hold-2s / hold-10s / hold-at-boot. Layout in [07](07-display-and-controls.md).                                                                                                                                                                      |
| **D4**  | **Alarms via Android foreground service + local notifications** | Fully local, no server, no accounts. Backed by an on-device alarm engine so the bridge still signals when no phone is present.                                                                                                                                                                                                                                      |
| **D5**  | **ESP-IDF v5.4, C**                                             | Matches the reference so its parser and LoRa driver integration port directly. The vendored `ra01s` SX1262 driver is a known-good pairing with this board.                                                                                                                                                                                                          |
| **D6**  | **NimBLE, not Bluedroid**                                       | ~100 KB less RAM. With 512 KB SRAM and **no PSRAM**, and Wi-Fi + BLE + httpd + filesystem all resident, this is not optional.                                                                                                                                                                                                                                       |
| **D7**  | **Binary sample records, streamed**                             | 16 bytes/sample fixed-width. No DOM, no giant string buffer, seekable for range queries and stride decimation.                                                                                                                                                                                                                                                      |
| **D8**  | **Partition for OTA from day one**                              | Repartitioning later means a full reflash and history loss. 8 MB splits cleanly into 2×2.5 MB app + 512 KB web + 2.375 MB cooks.                                                                                                                                                                                                                                    |
| **D9**  | **Reuse the upstream parser under MIT**                         | `smoke_x_parser.c` is pure C, host-testable, and already has a real captured-packet test suite. Copy with the copyright notice intact; extend, don't rewrite.                                                                                                                                                                                                       |
| **D10** | **Protocol contract lives in `/protocol`**                      | One OpenAPI spec + record layout doc + GATT spec, from which both firmware constants and Flutter DTOs are generated or hand-verified. Prevents the classic drift between C structs and Dart models.                                                                                                                                                                 |
| **D11** | **Billows is parsed but not surfaced in v1**                    | An X4 is in hand; a Billows is not. The `billows_attached` flag and the overloaded `billows_target` field cost nothing to decode and are stored in every sample, so no data is lost — but there is no tile, no alarm rule, and no API concept in the MVP. Protocol questions [Q3/Q5](02-smoke-x-protocol.md#28-open-questions) stay open until a unit is available. |
| **D12** | **Single bridge, single smoker in the UI**                      | The storage schema, the `bridges` table, and mDNS discovery are all multi-device capable and stay that way. The app ships a one-device flow: no picker, no switcher, no aggregate view. Adding them later is UI work, not a migration.                                                                                                                              |
| **D13** | **Fallback web UI deferred; its partition is reserved now**     | Whether the device serves its own browser UI is a post-MVP call. The 512 KB `www` partition is declared and left unformatted regardless, because reclaiming it later is free and _adding_ it later means repartitioning — which erases every stored cook. Same reasoning as D8.                                                                                     |
| **D14** | **Default display unit is °F**                                  | Storage is canonical °F either way ([04 §4.2](04-storage-and-history.md)); this is only the initial display preference, switchable in the app and from the OLED Probes page.                                                                                                                                                                                        |

## System shape

```
   ┌───────────────────────── ThermoWorks (untouched) ──────────────────────────┐
   │  4× probes ──► Smoke X4 base station ──LoRa 915MHz──► stock receiver(s)    │
   │                       Billows ──►                                          │
   └───────────────────────────────┬────────────────────────────────────────────┘
                                   │  (broadcast, every 30 s)
                                   ▼
   ┌──────────────────── Heltec WiFi LoRa 32 V3 — "the bridge" ─────────────────┐
   │                                                                            │
   │  SX1262 ──► smoke_x parser ──► sample bus ─┬──► cook_store  (LittleFS)     │
   │                                            ├──► alarm engine ──► OLED/LED  │
   │                                            ├──► HTTP + WebSocket (Wi-Fi)   │
   │                                            └──► BLE GATT notify            │
   │                                                                            │
   │  Wi-Fi:  [AP  SmokeBridge-A4F2 / 192.168.4.1]  or  [STA  smokebridge.local]│
   └───────────────────────┬───────────────────────────┬────────────────────────┘
                           │ HTTP/WS (full fidelity)   │ BLE (live only, no Wi-Fi needed)
                           ▼                           ▼
   ┌────────────────────────── Flutter app (Android first) ─────────────────────┐
   │  BridgeTransport ── HttpTransport | BleTransport | MockTransport           │
   │  drift cache ──► dashboard · 15 h chart · sessions · alarms · export       │
   │  foreground service ──► local notifications while you sleep                │
   └────────────────────────────────────────────────────────────────────────────┘
```

## Document map

| Doc                                                                     | Covers                                                                            |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| [01 — Hardware](01-hardware.md)                                         | Board specifics, GPIO map, RAM/flash/power budgets, things to verify on the bench |
| [02 — Smoke X Protocol](02-smoke-x-protocol.md)                         | LoRa radio params, pairing handshake, packet formats, invariants, unknowns        |
| [03 — Firmware Architecture](03-firmware-architecture.md)               | Components, tasks, event bus, boot flow, partition table, build system            |
| [04 — Storage & History](04-storage-and-history.md)                     | Record formats, session lifecycle, retention, time handling, crash safety         |
| [05 — Connectivity & Provisioning](05-connectivity-and-provisioning.md) | AP/STA modes, BLE GATT spec, handoff choreography, mDNS, Android pitfalls         |
| [06 — Device API](06-device-api.md)                                     | HTTP REST + WebSocket contract, schemas, errors, versioning                       |
| [07 — Display & Controls](07-display-and-controls.md)                   | OLED page designs, button gesture state machine, LED patterns                     |
| [08 — Flutter App](08-flutter-app.md)                                   | App architecture, transport abstraction, screens, charting, caching               |
| [09 — Alarms & Insights](09-alarms-and-insights.md)                     | Alarm rules, notification plumbing, ETA/stall/lid-open analytics                  |
| [10 — Repo, Tooling & Testing](10-repo-tooling-and-testing.md)          | Monorepo layout, simulator, CI, test strategy                                     |
| [11 — Roadmap & Risks](11-roadmap-and-risks.md)                         | Milestones, MVP cut lines, ranked risks, open questions                           |

## Glossary

| Term               | Meaning                                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **Bridge**         | The Heltec board running our firmware                                                                                                     |
| **Base station**   | The ThermoWorks Smoke X2/X4 unit the probes plug into; the LoRa transmitter                                                               |
| **Receiver**       | ThermoWorks' own handheld display unit. We coexist with it, we don't replace it                                                           |
| **Pairing / sync** | The one-time handshake where the base station tells the bridge its device ID and operating frequency                                      |
| **Session / cook** | A bounded run of samples with a header, name, marks, and stats                                                                            |
| **Sample**         | One decoded state message: timestamp + up to 4 temperatures + flags. Nominally every 30 s                                                 |
| **Mark**           | A user-placed annotation on the timeline ("wrapped", "added wood")                                                                        |
| **Pit probe**      | The probe measuring cooker ambient temperature, as distinct from a food probe. A role the user assigns; the hardware does not distinguish |
| **Billows**        | ThermoWorks' fan controller. The base reports whether one is attached and its target temp                                                 |

## Attribution

Protocol decoding, the SX1262 driver integration, and the pairing handshake derive from
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver), MIT © 2022 G-Two. Files
carried over retain that notice. This project is not affiliated with or endorsed by ThermoWorks.
</content>
</invoke>
