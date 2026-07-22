# 12 — Notes for a Task-Creation Pass

**Audience: a future session whose job is to turn these design documents into a task backlog.**
Not a plan itself — a briefing on how to write one, what is already decided, and where the
estimates will be wrong.

## 12.1 How to use this

Suggested opening for that session:

> Read `docs/design/12-task-planning-notes.md` first, then the docs it points you at. Produce a task
> backlog for milestone M0 and M1 following the conventions in §12.5. Do not relitigate anything in
> the decision log (§12.3) — if you think a decision is wrong, raise it as a question, don't quietly
> plan around it.

Then, per milestone. **Do not try to write the whole backlog at once.** M0 and M1 are well
understood and can be planned in detail today; M4–M6 depend on facts that don't exist yet (real
packet formats, measured RAM headroom, how Android behaves on the actual phone). Planning them now
produces fiction that later gets rewritten.

## 12.2 Reading order

| Order | Doc                                        | Why                                                                      |
| ----- | ------------------------------------------ | ------------------------------------------------------------------------ |
| 1     | [00 — Overview](00-overview.md)            | Scope and the D1–D14 decision log. Everything else assumes these         |
| 2     | [11 §11.1, §11.6](11-roadmap-and-risks.md) | Milestone structure, two-track parallelism, the single-board constraints |
| 3     | This doc §12.4–§12.9                       | Epics, conventions, anti-tasks, uncertainty                              |
| 4     | The doc for the epic being planned         | Deep detail only when writing that epic's tasks                          |

Docs 01–10 are references, not sequential reading. Load them per epic — §12.4 says which.

## 12.3 Settled — do not reopen

The decision log lives in [00 §Decisions](00-overview.md); the short version, so a planner never
writes a task that contradicts it:

|     |                                                                |
| --- | -------------------------------------------------------------- |
| D1  | Custom BLE GATT service, **not** `wifi_provisioning`           |
| D2  | No MQTT / Home Assistant in v1                                 |
| D3  | One button, gesture-driven; input layer abstracted for three   |
| D4  | Android foreground service + local notifications for alarms    |
| D5  | ESP-IDF v5.4, C                                                |
| D6  | NimBLE, not Bluedroid                                          |
| D7  | Fixed-width binary records, streamed — no JSON DOM for history |
| D8  | OTA partitions from day one                                    |
| D9  | Reuse the upstream parser under MIT, with attribution          |
| D10 | Protocol contract lives in `/protocol`                         |
| D11 | Billows decoded and stored, no UI                              |
| D12 | Single bridge in the UI; schema stays multi-capable            |
| D13 | Fallback web UI post-MVP; **partition reserved and empty**     |
| D14 | °F default display unit                                        |

Also settled and easy to accidentally re-plan:

- **Hardware:** one Heltec WiFi LoRa 32 V3. No second board. No Billows. X4 in hand, no X2.
- **"Hold PRG at boot" is impossible** — GPIO0 is the boot strapping pin. Recovery is the 3-second
  post-boot window plus double-reset ([03 §3.4.1](03-firmware-architecture.md)). Any task that says
  "boot-time mode select via button hold at reset" is wrong.

## 12.4 Epics

Four tracks. **F** and **A** run in parallel ([11 §11.1](11-roadmap-and-risks.md)); **P** and **T**
front-load into M0 because both other tracks depend on them.

### P — Protocol contract (M0)

| Epic   | Scope                                                                         | Design ref                                                                       | Blocks     |
| ------ | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ---------- |
| **P1** | `protocol/records.yaml` + `tools/protogen` → `record_gen.h`, `records.g.dart` | [10 §10.2](10-repo-tooling-and-testing.md), [04 §4.2](04-storage-and-history.md) | F5, A3, A4 |
| **P2** | `openapi.yaml`, fixture conventions, error model                              | [06](06-device-api.md)                                                           | F9, A5, T3 |
| **P3** | `ble-gatt.md` — UUIDs, payload tables, security profile                       | [05 §5.6](05-connectivity-and-provisioning.md)                                   | F10, A6    |

### T — Tooling (M0, then ongoing)

| Epic   | Scope                                                         | Design ref                                               | Notes                                                                       |
| ------ | ------------------------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------- |
| **T1** | Repo skeleton, Makefile, CI workflows, lint/format/pre-commit | [10 §10.1, §10.6, §10.7](10-repo-tooling-and-testing.md) |                                                                             |
| **T2** | `tools/cookgen` — synthetic cooks from a thermal model        | [10 §10.3](10-repo-tooling-and-testing.md)               | Feeds T3 and A-track tests                                                  |
| **T3** | `tools/sim` — full HTTP+WS+mDNS fake bridge, all scenarios    | [10 §10.3](10-repo-tooling-and-testing.md)               | **Highest-leverage item in M0.** Unblocks the entire A track from the board |
| **T4** | `tools/lora` — `pull.py`, `replay.py`, fixture normalization  | [10 §10.4](10-repo-tooling-and-testing.md)               | One cook → unlimited fixtures                                               |
| **T5** | `tools/flash`, merged-binary build, esp-web-tools installer   | [10 §10.8](10-repo-tooling-and-testing.md)               | M6                                                                          |

### F — Firmware

| Epic    | Scope                                                                             | Design ref                                                     | Depends on      |
| ------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------- | --------------- |
| **F1**  | IDF skeleton, partitions, sdkconfig, boot sequence, `bridge_event` bus, `tasks.h` | [03](03-firmware-architecture.md)                              | T1              |
| **F2**  | `app_lora` — vendored `ra01s`, params, RX loop, TX guard                          | [01 §1.5](01-hardware.md), [02 §2.1](02-smoke-x-protocol.md)   | F1              |
| **F3**  | `smoke_x` — parser port (MIT attribution), pairing state machine, NVS             | [02](02-smoke-x-protocol.md)                                   | F1, F2          |
| **F4**  | **Novelty log + debug packet ring + `/api/v1/debug/*`**                           | [02 §2.7](02-smoke-x-protocol.md)                              | F3              |
| **F5**  | `cook_store` — records, sessions, LittleFS, torn-write recovery, retention        | [04](04-storage-and-history.md)                                | F1, P1          |
| **F6**  | `app_time` — clock arbitration, header back-patching, monotonic floor             | [04 §4.4](04-storage-and-history.md)                           | F5              |
| **F7**  | `app_config` — typed NVS, change notifications, migrations                        | [03 §3.6](03-firmware-architecture.md)                         | F1              |
| **F8**  | `app_net` — AP/STA state machine, backoff retry, mDNS, DNS hijack, captive shim   | [05 §5.3–5.5, §5.8.1](05-connectivity-and-provisioning.md)     | F1, F7          |
| **F9**  | `app_api` — httpd, REST, **streamed** history, WebSocket fan-out                  | [06](06-device-api.md)                                         | F5, F8, P2      |
| **F10** | `app_ble` — NimBLE, GATT service, bonding, OLED passkey                           | [05 §5.6](05-connectivity-and-provisioning.md)                 | F1, F7, F11, P3 |
| **F11** | `app_ui` — SSD1306 extensions, pages, button gesture machine, LED                 | [07](07-display-and-controls.md)                               | F1              |
| **F12** | `app_power` — battery ADC, calibration, SoC curve, saver profile                  | [01 §1.3, §1.6](01-hardware.md)                                | F1, V1          |
| **F13** | `app_alarm` — rules, latching, hysteresis, lid-open grace                         | [09 §9.2](09-alarms-and-insights.md)                           | F5, F11         |
| **F14** | OTA + rollback health gate                                                        | [03 §3.7](03-firmware-architecture.md), [06](06-device-api.md) | F9              |

### A — Flutter app

| Epic    | Scope                                                                 | Design ref                                     | Depends on                       |
| ------- | --------------------------------------------------------------------- | ---------------------------------------------- | -------------------------------- |
| **A1**  | Flutter skeleton, riverpod, go_router, theme, error boundary          | [08 §8.2–8.3](08-flutter-app.md)               | T1                               |
| **A2**  | `domain/` — entities + analysis (rate, ETA, stall, lid-open, LTTB)    | [09 §9.4](09-alarms-and-insights.md)           | — (pure Dart, start immediately) |
| **A3**  | `BridgeTransport` interface + `MockTransport` + binary record parsing | [08 §8.1](08-flutter-app.md)                   | P1                               |
| **A4**  | drift schema, DAOs, delta-sync engine                                 | [08 §8.5](08-flutter-app.md)                   | A3                               |
| **A5**  | `HttpTransport` — REST + WebSocket                                    | [08 §8.1](08-flutter-app.md)                   | A3, T3                           |
| **A6**  | `BleTransport` — flutter_blue_plus + GATT                             | [05 §5.6](05-connectivity-and-provisioning.md) | A3, P3, F10                      |
| **A7**  | `ConnectionManager` — racing discovery, cache, manual entry, backoff  | [08 §8.4](08-flutter-app.md)                   | A5                               |
| **A8**  | Onboarding wizard — scan, bond, passkey, mode choice, handoff         | [05 §5.7](05-connectivity-and-provisioning.md) | A6, A7                           |
| **A9**  | Dashboard, probe tiles, session controls                              | [08 §8.6](08-flutter-app.md)                   | A4, A7                           |
| **A10** | Chart — LTTB, gaps, min/max envelope, overlays, pan/zoom              | [08 §8.7](08-flutter-app.md)                   | A2, A4                           |
| **A11** | Sessions list, detail, stats, export                                  | [08 §8.6](08-flutter-app.md)                   | A4, A10                          |
| **A12** | Settings — probes, alarms, network, device, advanced, OTA             | [08 §8.6](08-flutter-app.md)                   | A5                               |
| **A13** | Foreground service, notification channels, quiet hours                | [09 §9.5–9.6](09-alarms-and-insights.md)       | A5, A9                           |
| **A14** | `platform/network_binder` (Kotlin), permissions flow, manifest        | [05 §5.8](05-connectivity-and-provisioning.md) | A1                               |
| **A15** | Golden tests + `integration_test` against `tools/sim`                 | [08 §8.9](08-flutter-app.md)                   | A9, A10, T3                      |

### V — Verification (spans milestones)

| Epic   | Scope                                            | Design ref                                 |
| ------ | ------------------------------------------------ | ------------------------------------------ |
| **V1** | Bench checklist → `docs/hardware-verified.md`    | [01 §1.8](01-hardware.md)                  |
| **V2** | Capture campaign — opportunistic, ongoing        | [10 §10.4](10-repo-tooling-and-testing.md) |
| **V3** | 24-hour soak: heap, stacks, counters, reconnects | [10 §10.5](10-repo-tooling-and-testing.md) |
| **V4** | On-target release checklist                      | [10 §10.5](10-repo-tooling-and-testing.md) |

## 12.5 Task-shaping conventions

**Size.** One task ≈ one focused session's work. Anything that can't be described in a sentence
without "and" is two tasks.

**Naming.** `<Epic>.<n> <component>: <imperative>` — e.g. `F5.3 cook_store: recover torn append on open`.

**Every task carries four fields:**

| Field        | Values                                                                                           | Why                                                                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `blocked-by` | task ids                                                                                         | §12.4's dependency columns are epic-level; task-level is finer                                                               |
| `verify`     | **H** host test · **S** sim/integration · **B** bench, board required · **C** real cook required | Determines when it can actually be closed                                                                                    |
| `board`      | yes / no                                                                                         | The board is a serialized resource ([11 §11.6](11-roadmap-and-risks.md)); a planner should be able to pack all the `no` work |
| `design`     | doc + section                                                                                    | So the implementer doesn't re-derive decisions                                                                               |

**Definition of done**, by verify tier:

- **H** — host unit tests pass in CI, including the failure cases named in
  [10 §10.5](10-repo-tooling-and-testing.md)
- **S** — passes against `tools/sim` including the relevant adverse scenario (`flaky`, `base-lost`,
  `detached`, …), not just the happy path
- **B** — verified on the board and the result written into `docs/hardware-verified.md`
- **C** — observed across a real cook, with the artifact (novelty log, session file, screenshot)
  committed to `protocol/fixtures/` or the PR

**Bias toward H.** Roughly 60 % of the interesting firmware logic is in ESP-IDF-free components
([03 §3.1](03-firmware-architecture.md)) precisely so it can be closed without the board. A task
that could be **H** but is written as **B** wastes the scarcest resource in the project.

## 12.6 Sequencing rules

1. **T3 (`tools/sim`) before any A-track UI work.** It is what decouples the app from the board.
2. **F4 (novelty log) lands in M1, early.** Every cook before it exists is evidence thrown away, and
   six of the eight open protocol questions ([02 §2.8](02-smoke-x-protocol.md)) close by themselves
   once it is running.
3. **A2 can start on day one.** Pure Dart, no dependencies, and it front-loads the analysis work
   that is easiest to get subtly wrong.
4. **F11 before F10.** The BLE passkey is displayed on the OLED; without it, bonding needs a serial
   fallback that then has to be removed.
5. **P1 before F5 and A3.** Both sides parse the same 16-byte record; generate it once.
6. **V1 before F12.** Battery calibration depends on resolving the GPIO37 / divider-ratio question
   ([01 §1.3](01-hardware.md)).
7. **Batch `board: yes` tasks.** Especially V1 — do the whole bench checklist in one sitting.
8. **Never OTA the only board with an image that hasn't been flashed over USB first**
   ([11 §11.6](11-roadmap-and-risks.md)).

## 12.7 Anti-tasks

Do not create tasks for these. If one seems necessary, that is a signal to raise a question, not to
plan it.

| Not a task                                           | Why                                         | Ref                                            |
| ---------------------------------------------------- | ------------------------------------------- | ---------------------------------------------- |
| MQTT / Home Assistant publishing                     | D2                                          | [00](00-overview.md)                           |
| Billows tile, target UI, or fan alarm rules          | D11 — decode and store only                 | [00](00-overview.md)                           |
| Multi-bridge picker / switcher / aggregate view      | D12                                         | [00](00-overview.md)                           |
| Building the device-served web UI                    | D13 — partition reserved, decision deferred | [06 §6.4](06-device-api.md)                    |
| iOS build or iOS-specific platform code              | Deferred                                    | [11 §11.2](11-roadmap-and-risks.md)            |
| DIO1 interrupt-driven LoRa RX                        | v1.1; the polling driver works              | [01 §1.5](01-hardware.md)                      |
| Wi-Fi join QR on the OLED                            | v1.1 stretch                                | [05 §5.3](05-connectivity-and-provisioning.md) |
| Three-button hardware variant                        | v1.1; only abstract the input layer now     | [07 §7.4](07-display-and-controls.md)          |
| Cloud push / FCM / any server component              | Not planned                                 | [11 §11.2](11-roadmap-and-risks.md)            |
| Transmitting anything on LoRa beyond the sync ACK    | Hard invariant, enforced in code            | [02 §2.5](02-smoke-x-protocol.md)              |
| "Boot-time mode select by holding PRG through reset" | Physically impossible on this chip          | [03 §3.4.1](03-firmware-architecture.md)       |

## 12.8 Where estimates will be wrong

Flag these when planning; they are the epics most likely to blow through whatever budget is set.

| Epic                  | Uncertainty                                                                                         | Suggested handling                                                                                                                                                        |
| --------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **F3**                | Four header fields and one trailing field are unidentified, and no real X4 vector exists yet        | Write the parser against reference vectors; timebox X4-specific assertions until V2 delivers captures. Expect one rework pass                                             |
| **F10**               | Android BLE is Android BLE — bonding, MTU negotiation, and notification reliability all vary by OEM | Budget generously. `live_state` is already designed to fit the default 23-byte MTU so a negotiation failure degrades rather than breaks                                   |
| **F8 + A14**          | AP-mode routing on Android is the classic "works on my phone" trap                                  | Plan both mitigations (captive shim _and_ `bindProcessToNetwork`) as one unit of work; neither alone is sufficient                                                        |
| **F9 + F10 together** | RAM. The [01 §1.4](01-hardware.md) budget is estimates, on 512 KB with no PSRAM                     | Add an explicit measurement task at the end of each: log free heap and stack watermarks, compare against budget. If it's tight, that is a design conversation, not a task |
| **A10**               | `fl_chart` has no native zoom; pan/zoom is a custom transform over `minX`/`maxX`                    | Treat interaction as its own task, separate from rendering                                                                                                                |
| **F11**               | Pixel work — a 12×24 font table, a sparkline, inverted regions, an 8-row layout at 21 columns       | The framebuffer→PNG harness makes this iterable without the board; build that first                                                                                       |
| **F5**                | Torn-write recovery is easy to write and hard to get right                                          | The truncate-at-every-offset test in [10 §10.5](10-repo-tooling-and-testing.md) is not optional                                                                           |

Deliberately no time estimates here — velocity is unknown. These are _relative_ risk flags.

## 12.9 Questions that gate specific epics

| Question                                   | Gates                                       | Status                                                                               |
| ------------------------------------------ | ------------------------------------------- | ------------------------------------------------------------------------------------ |
| Real X4 packet captures                    | F3 completion, F13 alarm thresholds         | **Actionable now** — the reference build already prints decoded payloads over serial |
| GPIO37 usable as ADC_Ctrl? Divider ratio?  | F12                                         | V1 bench checklist                                                                   |
| Free heap with everything running          | Concurrency caps in F9, buffer sizes in F10 | Measure at F9/F10                                                                    |
| Does AP mode brown out on a depleted pack? | F8, F12 saver thresholds                    | V1                                                                                   |
| Public or private repo (Q-F)               | T5 (installer on GitHub Pages)              | Open, needed before M6                                                               |
| Billows semantics (Q3, Q5)                 | Nothing in v1 (D11)                         | Blocked, no unit — fine                                                              |

## 12.10 A worked task

For calibration of the intended grain:

> **F5.3 — `cook_store`: recover torn append on session open**
>
> - **Epic:** F5 · **Milestone:** M1 · **blocked-by:** F5.1 (record codec), F5.2 (session open/append)
> - **verify:** H · **board:** no
> - **design:** [04 §4.5](04-storage-and-history.md)
>
> Implement the seven-step recovery sequence when reopening a session whose `active_id` is set in
> NVS: validate the header magic/version/CRC, align the body to a whole number of records, then walk
> back up to three records validating CRC-16, truncating each time. Write an auto-mark
> `{kind: 7, text: "power restored"}` on successful resume. A header that fails validation renames
> the file to `.bad` and starts a fresh session rather than discarding data silently.
>
> **Done when:** host tests pass for a `.smk` truncated at _every_ byte offset within the final
> record, a header with bad CRC, a header with bad magic, and a header declaring a future `version`
> with a larger `rec_len` (which must be read, not rejected). Recovery must converge in all cases —
> no infinite loop, no unbounded truncation.

## 12.11 Checklist for the planning session

- [ ] Read §12.3 and confirm no task contradicts a decision
- [ ] Plan **M0 and M1 only**, in detail; leave M2+ as epic-level placeholders
- [ ] Every task has `blocked-by`, `verify`, `board`, `design`
- [ ] `board: no` tasks are the majority of firmware work — if not, tasks are mis-tiered (§12.5)
- [ ] T3 and F4 are scheduled early (§12.6 rules 1 and 2)
- [ ] Nothing from the §12.7 anti-task list appears
- [ ] §12.8 epics carry an explicit uncertainty note
- [ ] The V2 capture campaign appears as standing, recurring work — not a one-off task
      </content>
