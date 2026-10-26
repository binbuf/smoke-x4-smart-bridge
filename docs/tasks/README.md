# Task Plan — MVP

This is the execution plan for the new build. It follows the design in
[`../design/`](../design/README.md). Every task names its design section, its
verification tier, and whether it needs the board.

## Milestones

| Milestone | File | Outcome |
|---|---|---|
| **M0 — Contract & harness** | [M0-contract-and-harness.md](M0-contract-and-harness.md) | Repo, protocol contract, host tests, firmware/app skeletons, bench rig, deep-sleep answer |
| **M1 — Firmware core** | [M1-firmware-core.md](M1-firmware-core.md) | Real X4 → ring log → OLED; pairing; power; host-green |
| **M2 — BLE + app slice (V0)** | [M2-ble-and-app-slice.md](M2-ble-and-app-slice.md) | Phone pairs, sees live four temps and the last 15 minutes; **first deployable end-to-end** |
| **M3 — History** | [M3-history-and-graph.md](M3-history-and-graph.md) | Full sync, resume, local archive, History chart, deletion, health |
| **M4 — Settings & actions** | [M4-settings-and-power.md](M4-settings-and-power.md) | App controls units/display/time, forget, factory reset, power off |
| **M5 — Billows (late)** | [M5-billows.md](M5-billows.md) | Observation always; setpoint only through the B5.0 gate; not a V0–V4 dependency |
| **M6 — Field hardening** | [M6-field-hardening.md](M6-field-hardening.md) | 24 h soak, real cook, release, handoff |

## Task format

```
### F1.3 sx_protocol: port and extend the parser

- **blocked-by:** F1.2 · **verify:** H · **board:** no
- **design:** [02 §2.5](../design/02-smoke-x-protocol.md)

**Why.** ...
**Do.** ...
**Done when.** ...
```

| Field | Values |
|---|---|
| `blocked-by` | task ids, or `—` |
| `verify` | **H** host/CI · **B** bench/board · **P** phone + board · **C** real cook |
| `board` | yes/no — board time is serialized; batch the `yes` tasks |

A task is done only when the stated verification has run and its evidence is
committed or recorded in the named file. “Code written” is not done.

## Execution order

```
M0  contract, host harness, skeletons, bench rig, deep-sleep gate
 │
M1  radio/parser/pairing ─► ring log ─► OLED/PRG/power
 │
M2  BLE live ─► app scan/bond/live ─► recent sync ─► V0 bench gate
 │
M3  full sync ─► local DB ─► History ─► reconnect/deletion ─► bench gate
 │
M4  config ─► settings UI ─► device actions ─► bench gate
 │
M5  Billows (late) B5.0 gate ─► observation ─► control (if chosen) ─► bench gate
 │
M6  soak ─► field cook ─► release
```

**Billows is deliberately late.** Observation and the control-path decision both
land in M5, after the bridge/app core (M0–M4). V0–V4 must not depend on it: the
app renders the Billows card only when `caps.billows_observe` is set. The B5.0
capture is bench-only; no cook is required. The control path is still a gate, so
no release claims "set target" until B5.0 is signed.

Two lanes can run concurrently:

- **Lane F** — firmware/radio/storage.
- **Lane A** — app against a BLE fake; no board required.

The BLE fake is the decoupling point. Build it in M0, before the app screens.

V2.2 is the first intentional field-data checkpoint: a normal cook on the V0
build feeds the cadence/gap assumptions, connectivity behavior, and the roadmap.
Repeat that loop at V6.3 rather than adding a separate capture phase.

## Exit gates

| Gate | Must be true |
|---|---|
| **M0** | Contract files and generated C/Dart compile; host tests run in CI; BLE fake works; board identity confirmed; deep-sleep wake answer recorded |
| **M1** | Real X4 pairs; stock receiver unaffected; samples survive a power cut; OLED/PRG work; host suite green |
| **M2 (V0)** | Fresh phone scans, pairs with the OLED code, sees four live temps, and shows the last 15 minutes in History; reconnect works |
| **M3** | Full ring syncs, resumes after disconnect, survives app relaunch, renders gaps honestly, and deletion is explicit |
| **M4** | Every app-controlled setting/action works on the real bridge; factory reset returns the app to setup |
| **M5** | Billows observation verified with a real unit; control decision **signed** in `docs/billows-decision.md`; if control, safety tests pass; if C, owner sign-off is recorded |
| **M6** | 24 h soak and one overnight cook pass; release checklist complete; README works from blank |

## Status board

All tasks start `[ ]`. Update this table as work lands; do not mark a task done
without its verification.

| Milestone | Tasks | Done |
|---|---:|---:|
| M0 | 10 | 0 |
| M1 | 15 | 0 |
| M2 | 12 | 0 |
| M3 | 8 | 0 |
| M4 | 8 | 0 |
| M5 | 5 | 0 |
| M6 | 7 | 0 |
| **Total** | **65** | **0** |

## Open decisions that block tasks

| # | Decision | Blocks |
|---|---|---|
| Q1 | Exact board is Heltec V3 | T0.8, T0.9, F1.2, F1.11 |
| Q2 | Billows control path (A/B/C) | B5.2, A5.1 control mode, V5.1 |
| Q3 | GPIO0 deep-sleep wake works | F1.12, V1.2, V6.2 |
| Q4 | Billows target is probe 4 `max` | B5.1, A5.1 |
| Q5 | BLE throughput acceptable | M2/M3 bench, A3.2 |

These are design questions, not implementation choices. If an implementer hits
one, stop and record the evidence; do not pick silently.

## Anti-tasks

Nothing in this plan builds:

- Wi-Fi/AP/STA, HTTP, WebSocket, mDNS, MQTT/Home Assistant, captive portal.
- OTA or a browser installer.
- Cook sessions, names, marks, phases, presets, cook clock, ETA, stall/lid.
- Alarms, buzzers, phone notifications, foreground service, quiet hours.
- CSV/JSON export, share sheets, cloud sync, accounts.
- Multi-bridge, iOS, web, desktop.
- On-device factory reset gestures or a boot-time button menu.
- A local web UI or debug HTTP server.
- Any LoRa transmission other than the pairing ACK, unless B5.0 explicitly
  selects and approves the narrow Billows RF path.

If a task seems to need one of these, the design is wrong or the request has
changed. Raise it; do not add it quietly.
