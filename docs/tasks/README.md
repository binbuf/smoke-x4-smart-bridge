# Smoke X4 Smart Bridge — Task Backlog

Execution plan derived from [`docs/design`](../design/README.md), following the conventions in
[12 — Task Planning Notes](../design/12-task-planning-notes.md).

| Doc | Contents |
| --- | --- |
| [M0 — Foundations](M0-foundations.md) | 52 tasks. Repo, protocol contract, simulator, firmware + app skeletons, the bench sitting |
| [M1 — Receive and Persist](M1-receive-and-persist.md) | 41 tasks. LoRa, parser, pairing, novelty log, `cook_store`, time, replay tooling, drift cache |
| [M2–M6 — Outline](M2-M6-outline.md) | Epic-level placeholders. **Deliberately not detailed** — see §12.1 |
| [Standing work](standing-work.md) | The V2 capture campaign and other recurring obligations |

## Why M2+ is not planned in detail

[§12.1](../design/12-task-planning-notes.md) is explicit: *"Do not try to write the whole backlog at
once. M0 and M1 are well understood and can be planned in detail today; M4–M6 depend on facts that
don't exist yet (real packet formats, measured RAM headroom, how Android behaves on the actual
phone). Planning them now produces fiction that later gets rewritten."*

Plan M2 when M1 exits — by then the parser is validated against real captures and the RAM picture is
no longer a guess.

## Task format

`<Epic>.<n> <component>: <imperative>` — every task carries four fields:

| Field | Values |
| --- | --- |
| `blocked-by` | task ids, or `—` |
| `verify` | **H** host test · **S** sim/integration · **B** bench, board required · **C** real cook required |
| `board` | yes / no — the board is a serialized resource ([11 §11.6](../design/11-roadmap-and-risks.md)) |
| `design` | doc + section, so the implementer doesn't re-derive decisions |

**Definition of done** by tier:

- **H** — host tests green in CI, including the named failure cases
- **S** — passes against `tools/sim` including the relevant adverse scenario, not just the happy path
- **B** — verified on the board, result written into `docs/hardware-verified.md`
- **C** — observed across a real cook, artifact committed to `protocol/fixtures/` or the PR

Counts: **M0 is 44 `board: no` / 8 `board: yes`. M1 is 39 / 2.** That ratio is the point — roughly
60 % of the interesting firmware logic lives in ESP-IDF-free components precisely so it closes
without the board ([03 §3.1](../design/03-firmware-architecture.md)).

## Execution order

Two lanes run concurrently. **Lane B** holds the board; **Lane S** is everything else. The waves below
are a scheduling aid — **each task's `blocked-by` field is authoritative**, and a few within-wave
orderings are finer-grained than the diagram can show.

```
        Lane B  (board)                     Lane S  (no board)
        ─────────────────                   ──────────────────────────────────────────
Wave 1  V1.1 polarity ⚠                     T1.1 repo skeleton
        V1.2 flash reference                T1.2 vendor snapshot
        V1.3 GPIO37 + divider  ← R6         T1.3 lint/format config
        V1.4 button/LED/Vext/OLED           A2.1 domain entities        ← rule 3, zero deps
        V1.5 current draw + brownout
        V1.6 write hardware-verified.md
                │
Wave 2  V2.1 first real X4 cook  ← R1       P1.1 records.yaml    F1.1 IDF skeleton
        V2.2 X4 sync handshake              A1.1 Flutter scaffold  A2.2–A2.7 analysis
                │                                   │
Wave 3          │                           P1.2 record_gen.h    F1.2 partitions + sdkconfig
                │                           P1.3 records.g.dart  F1.3 event bus
                │                           A1.2 riverpod/router A1.3 packages
                │                                   │
Wave 4          │                           P1.4 gen freshness CI   F1.4 tasks.h
                │                           P1.5 shared fixtures    F1.5 boot sequence
                │                           P2.1–P2.3 openapi       F1.6 host harness
                │                           P3.1 ble-gatt.md        T1.4 Makefile
                │                           A3.1–A3.3 transport     T1.5–T1.7 CI, docs
                │                                   │
Wave 5          │                           T2.1–T2.3 cookgen
                │                                   │
Wave 6          │                           T3.1–T3.6 tools/sim   ◄── M0 EXIT GATE
        ════════╪═══════════════════════════════════════════════════════════════════
Wave 7  (board free — batch                 F7.1–F7.3 app_config
         flashes, don't                     F2.1–F2.5 app_lora
         interrupt a cook)                  F5.1–F5.3 cook_store core
                │                           A4.1–A4.2 drift
Wave 8  F3.9 pair vs stock receiver         F3.1–F3.8 smoke_x
        F5.11 power-cut resume              F4.1–F4.3 novelty log  ← rule 2, land early
                │                           F5.4–F5.10 sessions, retention, reads
                │                           F6.1–F6.3 app_time
                │                           T4.1–T4.3 replay       A4.3–A4.4 delta sync
                                                                   ◄── M1 EXIT GATE
```

### The two things that unlock everything else

**`tools/sim` (T3)** is the highest-leverage item in M0. It decouples the entire app track from the
board — the Flutter app becomes developable and CI-testable before any firmware exists, and stays
testable afterwards without a smoker running ([§12.6 rule 1](../design/12-task-planning-notes.md)).

**The novelty log (F4)** lands early in M1, not late. Every cook before it exists is evidence thrown
away, and six of the eight open protocol questions close by themselves once it is running
([§12.6 rule 2](../design/12-task-planning-notes.md)).

### Sequencing rules honoured here

| Rule | Where it shows up |
| --- | --- |
| 1 — T3 before A-track UI | No A9–A12 task exists before M4; A3/A4 target `MockTransport` and the sim |
| 2 — F4 early in M1 | F4.1–F4.3 sit in Wave 8 alongside F3, not after F5 |
| 3 — A2 can start day one | A2.1 is in Wave 1 with no `blocked-by` |
| 4 — F11 before F10 | F11 **splits**: framebuffer + passkey overlay in M3, pages and gestures in M5 (see [M2–M6](M2-M6-outline.md)) |
| 5 — P1 before F5 and A3 | P1.2/P1.3 gate F5.1 and A3.2 |
| 6 — V1 before F12 | V1.3 resolves the divider ratio; F12 is M5 |
| 7 — Batch `board: yes` | All of V1 is one sitting; V2.1 is one cook |
| 8 — Never OTA the only board un-USB-flashed | Stated in [M2–M6](M2-M6-outline.md) under F14, and in the release checklist |

## Milestone exit gates

| | Gate |
| --- | --- |
| **M0** | CI green, and `dart run tools/sim --cook fixtures/brisket-18h.smk` serves a fake 18-hour cook over the real API. The Flutter app can now be built against it before any firmware exists |
| **M1** | A real Smoke X4 pairs **and the stock ThermoWorks receiver keeps working**; a cook survives a mid-cook power cut and resumes into the same session; real X4 packets are committed to `protocol/fixtures/`; host tests pass against real captures, not just synthetic vectors |

**M1 is the load-bearing milestone and the F track gates on it.** Do not start M2 firmware work until
real X4 traffic decodes correctly — everything downstream assumes the parser is right. The A track
has no such gate; it runs against `tools/sim` until M2.

## Open decisions

| # | Question | Blocks | Needed by |
| --- | --- | --- | --- |
| **Q-F** | Public repo or private? | T5 — whether the browser installer can live on GitHub Pages | before M6 |

Everything else in the decision log is settled. **Do not relitigate D1–D14**
([§12.3](../design/12-task-planning-notes.md)) — if a decision looks wrong, raise it as a question,
don't quietly plan around it.

## Anti-tasks

Nothing in this backlog builds: MQTT/Home Assistant (D2), a Billows tile or fan alarm rules (D11), a
multi-bridge picker (D12), the device-served web UI (D13), iOS, DIO1 interrupt-driven LoRa RX, an
OLED Wi-Fi QR, a three-button hardware variant, cloud push, any LoRa transmission beyond the sync
ACK, or boot-time mode select by holding PRG through reset (physically impossible on this chip).

Full list with reasons: [§12.7](../design/12-task-planning-notes.md).
