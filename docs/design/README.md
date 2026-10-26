# Smoke X4 Smart Bridge — Design Set (MVP)

**Status:** implementation-ready · Billows is observation-only per
[`../billows-decision.md`](../billows-decision.md) · **Date:** 2026-10-26

This directory is the design baseline for the **new** firmware and Flutter app. It
does not describe the code in [`legacy/`](../../legacy); that tree is reference
material only and is audited in [09 — Legacy Audit](09-legacy-audit.md).

The product is deliberately small:

> A battery-powered ESP32 bridge listens to a ThermoWorks Smoke X4 over LoRa,
> records every probe reading to a rolling flash log, shows the readings on its
> OLED, and serves the live values and the whole log to an Android app over BLE.
> The app can configure the bridge, show Billows status and the target set on the
> Smoke X4, forget phones, and factory-reset the device. It cannot set the
> Billows target; that stays on the Smoke X4.

There is **no Wi-Fi, HTTP, WebSocket, MQTT, cloud, OTA, alarm engine, cook
session model, or notification stack** in this MVP.

## Document map

| Doc | Covers |
|---|---|
| [00 — Product & Scope](00-product.md) | Users, flows, MVP cut line, acceptance criteria, non-goals |
| [01 — Hardware](01-hardware.md) | Heltec WiFi LoRa 32 V3, pin map, power, battery, enclosure, bench checks |
| [02 — Smoke X Protocol](02-smoke-x-protocol.md) | LoRa parameters, sync/state packets, pairing, Billows fields |
| [03 — Firmware Architecture](03-firmware-architecture.md) | Components, tasks, boot, state machines, config, memory |
| [04 — Data, Storage & Sync](04-data-and-storage.md) | 18-byte record, flash ring, clock, BLE sync, app cache, retention |
| [05 — BLE Contract](05-ble-contract.md) | GATT service, payloads, security, advertising, procedures |
| [06 — Flutter App](06-app.md) | Architecture, navigation, screens, connection lifecycle, settings |
| [07 — Display & Controls](07-display-and-controls.md) | OLED pages, PRG gestures, pairing overlay, power off/on |
| [08 — Billows](08-billows.md) | Observation-only scope, target validation, deferred control, post-MVP RF survey |
| [09 — Legacy Audit](09-legacy-audit.md) | What is kept, what is left behind, and which defects are not inherited |
| [10 — Test & Release](10-test-and-release.md) | Test layers, bench matrix, soak, release checklist |
| [11 — UI/UX Refresh](11-ui-ux-refresh-proposal.md) | Approved Live/History/Settings refresh, naming and interaction decisions |

Task plans live in [`../tasks/`](../tasks/README.md). Bench evidence lives in
[`../hardware-verified.md`](../hardware-verified.md); the Billows scope decision
lives in [`../billows-decision.md`](../billows-decision.md).

## Decisions already made

| ID | Decision | Why |
|---|---|---|
| **D1** | **BLE only.** No Wi-Fi, HTTP, WebSocket, mDNS, MQTT, or cloud. | The phone is always the user interface. Removing the network stack removes provisioning, security, discovery, and a large RAM budget from the product. |
| **D2** | **One continuous rolling log; no cook/session model.** | The requirement is "collect whenever the bridge is on and the Smoke X4 is sending" and "graph whatever was collected". A session lifecycle is a feature the user did not ask for, and it creates the exact sync-completeness bugs the legacy build fought. Gaps are explicit; that is enough. |
| **D3** | **18-byte fixed record, raw circular flash partition.** | Compact enough for ~117 days at 30 s cadence, fixed-width for seek/stream, per-record CRC for power-loss recovery. |
| **D4** | **Sequence-cursor sync, not time/session cursors.** | The device owns a monotonic `seq`; the app stores a high-water `seq`. Reboots, clock changes, and wrap are unambiguous. |
| **D5** | **One button, up to four information pages.** | Tap cycles pages; hold powers off/on. The Billows page appears only after detection. No menus, gestures, or on-device settings. |
| **D6** | **LE Secure Connections + passkey + bonding.** | The bridge displays a six-digit code; the phone's OS asks for it. This is the only pairing flow. |
| **D7** | **Firmware update is USB only.** | OTA is a large, risky subsystem with no MVP user. USB is acceptable for a bench product and keeps the partition simple. |
| **D8** | **Billows is observation-only.** The app shows attached/status and a validated target; it never sets the target. | ThermoWorks documents that a Smoke X4 receiver cannot change set points or the Billows; only the base can. The bridge sees the same one-way broadcast. Signals has an app; Smoke X4 does not. See [08](08-billows.md) and [`../billows-decision.md`](../billows-decision.md). |
| **D9** | **No alarms, notifications, cook timers, marks, CSV export, multi-bridge, or diagnostics console.** | Not in the requested feature set. The OLED and app still expose live health and storage. |
| **D10** | **Reuse only communication/protocol code and hardware facts from `legacy/`.** | The parser, SX1262 integration, pairing knowledge, and low-level BLE patterns are valuable. The UI, session model, alarm engine, network stack, and app architecture are not. |
| **D11** | **The device rotates old data automatically; the app never deletes data without a user action.** | Matches the requirement exactly. The app is the durable archive; the device is the rolling buffer. |
| **D12** | **Smoke X4 only.** | The X2 parser shape may be accepted defensively, but no X2-specific UI or acceptance work is in scope. |
| **D13** | **The phone is the clock source.** | The board has no battery-backed RTC. The app sets time on connect; records made before the first clock sync are marked estimated. |
| **D14** | **Single bridge per app install.** | No picker or switcher. "Forget device" is the reset path. |
| **D15** | **The Android app is the only client.** | iOS, web, desktop, and a local web UI are out. |
| **D16** | **Probe identity is `P1`–`P4` and colour.** No probe names, roles or tags in the MVP app, OLED or config. | Removes a fake taxonomy, 52 bytes of config, and a whole editor that the MVP does not need. |
| **D17** | **Live shows per-probe sparklines; no aggregate graph.** | Live answers “what is happening now?” and “which way is it moving?”. History is the only multi-probe chart, so there is one chart destination and one filter state. |
| **D18** | **History is a first-class archive.** | Range and probe filters, crosshair, zoom/pan, summary sorting and day groups make the continuous log usable without inventing cook sessions. |
| **D19** | **Settings is object-based.** | Units are top-level and immediate; destructive actions live with the object they affect; there is no `Actions` screen or save-all bar. |
| **D20** | **Prototype chrome is lab-only.** | Theme switches, simulation buttons and fake OS prompts belong in the scenario lab, not on product screens. |

## Open decisions

These are tracked because they change implementation, not because the design is
undecided about the product:

| # | Question | Blocks | Needed by |
|---|---|---|---|
| **Q1** | Is the board exactly the **Heltec WiFi LoRa 32 V3** (ESP32-S3 + SX1262 + SSD1306)? The brief says "ESP32 LoRa V3"; the enclosure and legacy code assume Heltec V3. | Pin map, partition size, radio driver | M0 bench |
| **Q2** | ~~Does a safe Billows setpoint command path exist?~~ **Answered: no documented receiver-side path; Option C, observation only.** | Closed; no MVP task | Recorded 2026-10-26 |
| **Q3** | Does holding **GPIO0** through a deep-sleep wake ever enter the ROM download strap? | Power on/off feature | M0/M1 bench |
| **Q4** | Is the Billows target probe 4's `alarm_high` field, `max − 25`, or another relation? | Billows target display | M5 B5.0 passive capture |
| **Q5** | Is BLE throughput sufficient to sync the full ring in a reasonable time on the target phone? | Full-history UX | M2/M3 bench |

## Invariants

1. **The bridge never disrupts the stock ThermoWorks receiver.** Its only LoRa
   transmission is the pairing acknowledgement. There is no Billows TX path in
   the MVP; post-MVP Billows RF work is receive-only.
2. **A detached probe is never `0 °F`.** It is a null/sentinel from parser to
   History.
3. **The device records without the phone.** BLE is a read/control path, never
   the reason recording happens.
4. **The app never presents stale data as live.** Freshness is visible.
5. **The app never deletes user history automatically.** The device rotates;
   the phone keeps what it has until the user chooses otherwise.
6. **A failed action has a named state and a next step.** No spinner that never
   resolves, no silent no-op.

## Reading order

1. [00 — Product & Scope](00-product.md)
2. [02 — Smoke X Protocol](02-smoke-x-protocol.md) and [04 — Data](04-data-and-storage.md)
3. [05 — BLE Contract](05-ble-contract.md)
4. [03 — Firmware](03-firmware-architecture.md) and [06 — App](06-app.md)
5. [07 — Display](07-display-and-controls.md), [08 — Billows](08-billows.md)
6. [10 — Test & Release](10-test-and-release.md), then the task plan
