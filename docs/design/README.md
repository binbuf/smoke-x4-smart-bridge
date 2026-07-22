# Smoke X4 Smart Bridge — Design

Design documents for a monorepo that extends the ThermoWorks Smoke X2/X4 wireless thermometer with
an ESP32-S3 + LoRa bridge and a Flutter app.

**Start with [00 — Overview](00-overview.md).** It carries the scope, the decision log, and the
system diagram; everything else expands one part of it.

| Doc                                                                     | Read it for                                                                                         |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| [00 — Overview](00-overview.md)                                         | What we're building, why, decisions D1–D10, glossary                                                |
| [01 — Hardware](01-hardware.md)                                         | Heltec V3 GPIO map, RAM/flash/power budgets, bench checklist                                        |
| [02 — Smoke X Protocol](02-smoke-x-protocol.md)                         | LoRa packet formats, pairing handshake, invariants, unknowns                                        |
| [03 — Firmware Architecture](03-firmware-architecture.md)               | Components, tasks, event bus, boot flow, partitions                                                 |
| [04 — Storage & History](04-storage-and-history.md)                     | Record formats, session lifecycle, crash safety, retention                                          |
| [05 — Connectivity & Provisioning](05-connectivity-and-provisioning.md) | AP/STA modes, BLE GATT service, handoff, Android traps                                              |
| [06 — Device API](06-device-api.md)                                     | HTTP REST + WebSocket contract                                                                      |
| [07 — Display & Controls](07-display-and-controls.md)                   | OLED pages, button gestures, LED patterns                                                           |
| [08 — Flutter App](08-flutter-app.md)                                   | App architecture, transport abstraction, screens, charting                                          |
| [09 — Alarms & Insights](09-alarms-and-insights.md)                     | Alarm rules, notifications, ETA/stall/lid-open analysis                                             |
| [10 — Repo, Tooling & Testing](10-repo-tooling-and-testing.md)          | Monorepo layout, simulator, CI, test strategy                                                       |
| [11 — Roadmap & Risks](11-roadmap-and-risks.md)                         | Milestones, two-track parallelism, ranked risks, working with one board                             |
| [12 — Task Planning Notes](12-task-planning-notes.md)                   | **Briefing for a future task-creation session** — epics, dependencies, task conventions, anti-tasks |

## The short version

- **Storage:** 8 MB flash, no SD card. A 24-hour cook is **45 KB**. The `cooks` partition holds
  **~54 days** of continuous 30-second samples — roughly 50 complete 24-hour cooks. The upstream
  project's 10-hour ceiling came from keeping history in RAM, not from storage capacity.
- **Two network modes:** _Hosted_ (the bridge runs its own Wi-Fi) and _Joined_ (it joins yours),
  switchable from the app over BLE, from the button, from the API, or via a post-boot recovery
  window.
- **BLE does real work:** provisioning, mode switching, pairing control, clock setting, **and live
  telemetry** — so the app shows probe temperatures with no Wi-Fi anywhere, and a failed Wi-Fi
  provision is recoverable without walking to the device.
- **One button, five pages.** Tap cycles pages, hold performs that page's action behind a
  release-to-cancel confirm, 10 seconds factory-resets. The Network page shows the AP's SSID and
  password when hosting, and the joined SSID, signal, and IP when a client.
- **It works alone.** The bridge logs to flash and sounds its own alarms with no phone present. The
  app is a convenience on top of a device that already does the job.

## What v1 deliberately leaves out

Decided, not forgotten — see the decision log in [00 — Overview](00-overview.md) and the deferred
list in [11 §11.2](11-roadmap-and-risks.md).

|                         | Status                                                                                                                                             |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| MQTT / Home Assistant   | Dropped (D2). Event bus shaped to accept it as one module later                                                                                    |
| Billows tile and alarms | Fields decoded and stored, no UI (D11) — no unit available to test against                                                                         |
| Multi-smoker UI         | One bridge (D12). Schema and discovery stay multi-capable                                                                                          |
| Device-served web UI    | Post-MVP call (D13). **512 KB partition reserved and left empty**, because adding it later would mean repartitioning and erasing every stored cook |
| iOS                     | Portable code, deferred                                                                                                                            |

## Provenance

Protocol decoding, the SX1262 driver integration, and the pairing handshake derive from
[`G-Two/smoke-x-receiver`](https://github.com/G-Two/smoke-x-receiver) (MIT © 2022 G-Two), vendored
read-only at [`docs/reference/smoke-x-receiver`](../reference/smoke-x-receiver). Not affiliated with
or endorsed by ThermoWorks.
</content>
