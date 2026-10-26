# Task Plan — MVP

This is the execution plan for the new build. It follows the design in
[`../design/`](../design/README.md). Every task names its design section, its
verification tier, and whether it needs the board.

> **UI baseline (2026-10-26).** The approved prototype in `app/` is complete and
> is the production UI contract: `flutter analyze` is clean, the 26-test widget
> suite is green, and the dark/light screenshot set is generated from the real
> widget tree. The production tasks below are still **not started**; their job is
> to replace the prototype's in-memory state with real business logic without
> rebuilding the approved screens. Read
> [13 — UI/UX Implementation Contract](../design/13-ui-implementation-contract.md)
> before any app task.

## Milestones

| Milestone | File | Outcome |
|---|---|---|
| **M0 — Contract & harness** | [M0-contract-and-harness.md](M0-contract-and-harness.md) | Repo, protocol contract, host tests, firmware/app skeletons, UI baseline/view-model seam, bench rig, deep-sleep answer |
| **M1 — Firmware core** | [M1-firmware-core.md](M1-firmware-core.md) | Real X4 → ring log → OLED; pairing; power; host-green |
| **M2 — BLE + app slice (V0)** | [M2-ble-and-app-slice.md](M2-ble-and-app-slice.md) | Phone pairs, sees live four temps and the last 15 minutes in the full History shell; **first deployable end-to-end** |
| **M3 — History** | [M3-history-and-graph.md](M3-history-and-graph.md) | Full sync, resume, local archive, History chart/Summary/Cooks, deletion, health |
| **M4 — Settings & actions** | [M4-settings-and-power.md](M4-settings-and-power.md) | App controls units/appearance/display/time, forget, factory reset, power off; full UI/a11y/copy gate |
| **M5 — Billows (late)** | [M5-billows.md](M5-billows.md) | Observation only; no setpoint control; not a V0–V4 dependency |
| **M6 — Field hardening** | [M6-field-hardening.md](M6-field-hardening.md) | 24 h soak, real cook, UI parity, release, handoff |

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

**Definition of ready for an app task:** the screen/state exists in
[13](../design/13-ui-implementation-contract.md), the copy is in
[12](../design/12-copy-and-label-review.md), stable test keys are known, the
fake/DB fixture exists, and the task names the golden/widget/manual evidence it
will produce. If one of those is missing, do that first; do not start the widget
work against a guess.

## Execution order

```
M0  contract, host harness, UI baseline/view models, bench rig, deep-sleep gate
 │
M1  radio/parser/pairing ─► ring log ─► OLED/PRG/power
 │
M2  BLE live ─► app scan/bond/live ─► recent sync in the History shell ─► V0 gate
 │
M3  full sync ─► local DB ─► History/Summary/Cooks ─► reconnect/deletion
 │   └─► bench gate
 │
M4  config ─► settings UI ─► device actions ─► UI state/a11y/copy gate
 │   └─► bench gate
 │
M5  Billows (late) B5.0 passive evidence ─► observation ─► bench gate
 │
M6  soak ─► field cook ─► UI parity ─► release
```

### UI delivery slices

| Slice | Screens/states | Tasks |
|---|---|---|
| Baseline | Theme/widgets/screens retained; view models replace fixtures | T0.5, T0.5a |
| Setup + Live | Connect, permission, scan, pair, first sync; Live states | A2.2–A2.4 |
| History shell | Filters/chart/Summary/Cooks shell with recent data | A2.5 |
| Full archive | All ranges/custom, Summary sorting, Cooks/Cook view, full-screen | A3.3 |
| States | Empty/error/offline/no-cache/no-X4/storage | A3.4, A3.6 |
| Quality gate | Every state, 320 dp, both themes, semantics, copy lint, goldens | A4.5 |
| Settings/actions | Root, Bridge details, storage, units, appearance, confirmations | A4.1–A4.4 |
| Billows | Status-only Live and Settings surfaces | A5.1 |
| Release | Lab gate, parity walk, final acceptance | V6.4, V6.7 |

A screen is not done because it “matches the mockup”. It is done when the real
state produces the approved UI and the empty/error/offline variants are tested.

**Billows is deliberately late.** Observation lands in M5, after the bridge/app
core (M0–M4). V0–V4 must not depend on it: the app renders the Billows card only
when `caps.billows_observe` is set. The B5.0 capture is bench-only, receive-only,
and no cook is required. Control is out of scope: the Smoke X4 receiver itself
cannot change set points or the Billows, so the listener cannot either. Post-MVP
RF work is a passive data survey, not a control path.

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
| **M0** | Contract files and generated C/Dart compile; host tests run in CI; BLE fake works; UI baseline/view-model seam is in place; board identity confirmed; deep-sleep wake answer recorded |
| **M1** | Real X4 pairs; stock receiver unaffected; samples survive a power cut; OLED/PRG work; host suite green |
| **M2 (V0)** | Fresh phone scans, pairs with the OLED code, sees four live temps, and shows the last 15 minutes in the full History shell; reconnect and offline-cache states work; no prototype chrome on product screens |
| **M3** | Full ring syncs, resumes after disconnect, survives app relaunch, renders gaps honestly, Summary/Cooks work, deletion is explicit, and the History UI matches the approved contract |
| **M4** | Every app-controlled setting/action works on the real bridge; factory reset returns the app to setup with saved history; Settings matches the approved contract; UI/a11y/copy gate green |
| **M5** | Billows observation verified with a real unit; target shown only if validated, else `—`; `billows_control = 0`; Option C recorded in `docs/billows-decision.md` |
| **M6** | 24 h soak and one overnight cook pass; UI parity/a11y/copy gate; release checklist complete; README works from blank |

## Status board

All production tasks start `[ ]`. The UI prototype is complete but is **not**
counted as production work; it is the contract those tasks implement. Update
this table as work lands; do not mark a task done without its verification.

| Milestone | Tasks | Done |
|---|---:|---:|
| M0 | 11 | 0 |
| M1 | 15 | 0 |
| M2 | 12 | 0 |
| M3 | 8 | 0 |
| M4 | 9 | 0 |
| M5 | 5 | 0 |
| M6 | 7 | 0 |
| **Total** | **67** | **0** |

UI baseline evidence: `flutter analyze` clean, 26 widget tests green, and the
dark/light screenshot set in `app/screenshots/` generated from the real widget
tree. These are reference artifacts, not production milestones.

## Open decisions that block tasks

| # | Decision | Blocks |
|---|---|---|
| Q1 | Exact board is Heltec V3 | T0.8, T0.9, F1.2, F1.11 |
| Q2 | Billows control path — **decided: observation only** | closed; no MVP task |
| Q3 | GPIO0 deep-sleep wake works | F1.12, V1.2, V6.2 |
| Q4 | Billows target relation (probe 4 `max` or derived) | B5.0, B5.1, A5.1 |
| Q5 | BLE throughput acceptable | M2/M3 bench, A3.2 |

These are design questions, not implementation choices. If an implementer hits
one, stop and record the evidence; do not pick silently.

## Anti-tasks

Nothing in this plan builds:

- Wi-Fi/AP/STA, HTTP, WebSocket, mDNS, MQTT/Home Assistant, captive portal.
- OTA or a browser installer.
- User-created cook sessions, names, marks, phases, presets, cook clock, ETA,
  stall/lid. Detected Cooks are read-only archive navigation and are required.
- Alarms, buzzers, phone notifications, foreground service, quiet hours.
- CSV/JSON export, share sheets, cloud sync, accounts.
- Multi-bridge, iOS, web, desktop.
- On-device factory reset gestures or a boot-time button menu.
- A local web UI or debug HTTP server.
- Any LoRa transmission other than the pairing ACK. There is no Billows TX path
  in the MVP; post-MVP Billows RF work is receive-only.
- A UI redesign, a new destination, a second chart, probe names/roles, or new
  prototype chrome while porting the approved mockup. The contract is
  [13](../design/13-ui-implementation-contract.md); update the design first if a
  real state is genuinely missing.
- Shipping the Experimental lab, fixture values, simulation buttons or fake OS
  prompts in a release build.

If a task seems to need one of these, the design is wrong or the request has
changed. Raise it; do not add it quietly.
