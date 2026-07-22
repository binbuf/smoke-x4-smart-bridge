# 11 — Roadmap, Risks, and Open Questions

## 11.1 Milestones

Each milestone ends in something demonstrable. The ordering is deliberate: **the data path is
proven before anything user-facing is built**, because a beautiful app in front of a firmware that
loses cooks is worse than nothing.

### Two tracks, not one queue

Firmware and app are developed **in parallel**, against `tools/sim` on the app side, converging at
the milestone boundaries. This matters more than usual here: there is one board, so serializing the
work would leave it idle for weeks at a time when it could be out collecting protocol evidence
(§11.6).

```
        M0        M1              M2            M3          M4         M5        M6
        │         │               │             │           │          │         │
  F ────┼── LoRa · pairing ───────┼─ Wi-Fi ─────┼─ BLE ─────┼──────────┼─ alarms ┼─ OTA
        │   cook_store            │  HTTP/WS    │  GATT     │          │  OLED   │  soak
        │   novelty log           │  mDNS       │           │          │  button │
        │         │               │             │           │          │         │
  A ────┼── transport · drift ────┼─ HTTP xport ┼─ BLE xport┼─ MVP UI ─┼─ FGS ───┼─ polish
        │   domain analysis       │  live sync  │  onboard. │  charts  │  notifs │
        │   MockTransport         │             │           │          │         │
        │         │               │             │           │          │         │
  ▲ sim ready     ▲ real X4       ▲ API frozen  ▲ handoff   ▲ MVP      ▲ v1 fn   ▲ v1.0
    app unblocked   captured        app switches  works      demoable    complete
                                    off sim
```

The **F track gates on real X4 captures at M1**; the **A track does not** — it runs against the
simulator until M2 and never blocks on hardware. `tools/sim` is therefore the highest-priority item
in M0, not a testing nicety.

### M0 — Foundations

Repo skeleton, `protocol/` with `records.yaml` and the generator, CI green on an empty build,
`tools/sim` serving synthesized data, `tools/cookgen`.

_Done when:_ CI is green, and `dart run tools/sim` serves a fake 18-hour cook over the real API.
The Flutter app can now be built against it before any firmware exists.

### M1 — Receive and persist ← the load-bearing milestone

Port `smoke_x_parser` (MIT, attributed), the `ra01s` SX1262 integration, and the pairing state
machine. Build `cook_store`: LittleFS, session lifecycle, 16-byte records, torn-write recovery,
retention. Host tests for all of it. Packet capture tooling.

_Done when:_

- A real Smoke X4 pairs with the bridge **and the stock ThermoWorks receiver keeps working**
- A cook is logged to flash and survives a mid-cook power cut, resuming into the same session
- Real X4 packets are captured and committed to `protocol/fixtures/` — closing as many of
  [02 §2.8](02-smoke-x-protocol.md)'s open questions as the hardware can answer
- Host tests pass against real captures, not just the synthetic X4 vectors

**Gate (F track only):** do not start M2 firmware work until real X4 traffic is decoded correctly.
Everything downstream assumes the parser is right. The A track keeps moving against `tools/sim`
regardless — it has no dependency on the board until M2.

### M2 — Network and API

Wi-Fi AP/STA state machine with backoff retry, mDNS, captive-portal shim + DNS responder, the
HTTP REST API, WebSocket push, streamed history endpoints. Partition table finalized.

_Done when:_ `curl` retrieves a 24-hour cook as CSV and as raw records; a WebSocket client receives
live samples; AP↔STA switching works from `curl`; free heap ≥ 150 KB with everything running.

### M3 — BLE and provisioning

NimBLE, the Bridge Control Service, LESC passkey on the OLED, bonding, live-state notify, the
handoff choreography.

_Done when:_ a phone provisions the bridge from factory-reset to a working STA connection entirely
over BLE, and can recover from a deliberately wrong Wi-Fi password without touching the hardware.

### M4 — Flutter MVP

Transport abstraction with all three implementations, connection manager, drift cache with delta
sync, onboarding wizard, dashboard, chart, session list and detail, settings, export.

_Done when:_ start-to-finish on real hardware — install the APK, onboard over BLE, choose a mode,
watch a live cook, scroll 15 hours of history, export a CSV.

**This is the MVP.** Everything above this line is the product working.

### M5 — Alarms, display, insights

Device-tier alarm engine with latching and hysteresis, OLED pages and the button gesture machine,
LED patterns, the foreground service, notification channels, and the analysis layer (rate, ETA,
stall, lid-open, cook stats).

_Done when:_ an unattended overnight cook wakes the user for `target_reached`, the bridge alarms
correctly with the phone powered off, and a lid-open does not fire a false pit alarm.

### M6 — Hardening and release

OTA with the rollback health gate, the browser installer, the 24-hour soak, the bench verification
checklist from [01 §1.8](01-hardware.md), and the on-target release checklist from
[10 §10.5](10-repo-tooling-and-testing.md). The fallback web UI is **not** part of this milestone
(D13) — decide it here, on evidence from real use, and build it in v1.1 if the answer is yes.

_Done when:_ v1.0.0 is tagged with a merged binary, an APK, and a working web installer.

## 11.2 What is explicitly deferred

Named so they don't accumulate as ambient guilt, and so nobody builds them by accident:

| Feature                                                              | Why deferred                                                                                                                                                                                                | Where it lands              |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| Full history over BLE (chunked transfer)                             | Bandwidth makes it awkward; Wi-Fi covers the case                                                                                                                                                           | v1.1                        |
| MQTT / Home Assistant publishing                                     | Decision D2 — the event bus is shaped to accept it as one module                                                                                                                                            | v1.1                        |
| iOS build                                                            | Platform work is isolated behind two channels; the rest is portable                                                                                                                                         | v1.1                        |
| DIO1 interrupt-driven LoRa RX                                        | The vendored driver polls; works, but costs power and a core                                                                                                                                                | v1.1                        |
| Wi-Fi join QR on the OLED                                            | Needs a QR encoder (~3 KB); the SSID/password text works today                                                                                                                                              | v1.1                        |
| Three-button hardware variant                                        | Input layer already abstracted (D3); needs soldering + an enclosure                                                                                                                                         | v1.1                        |
| **Billows display** — tile, target readout, fan-specific alarm rules | **D11** — no unit to test against. The `billows_attached` flag and `billows_target` field are decoded and stored in every sample, so a later build reinterprets existing cooks rather than needing new ones | when a Billows is available |
| **Device-served fallback web UI**                                    | **D13** — 512 KB partition declared and left empty; reclaiming it is a one-line change, carving it out later would erase stored cooks                                                                       | post-MVP decision           |
| Multi-bridge / multi-smoker in one app                               | **D12** — schema and discovery support it (`bridges` table); the screens don't                                                                                                                              | v1.2                        |
| Cook comparison and "recipes" (saved probe/target/alarm presets)     | Pure app feature on top of existing data                                                                                                                                                                    | v1.2                        |
| Cloud push (FCM) for off-network alarms                              | Needs a relay service — real ongoing scope                                                                                                                                                                  | not planned                 |
| Controlling the Billows                                              | The Smoke X owns control; we observe. Would require transmitting                                                                                                                                            | not planned                 |

## 11.3 Risks

Ranked by probability × impact.

### R1 — The X4 packet format is only half-known · **medium probability, high impact**

_Downgraded from high probability: an X4 is in hand, so this is testable in week one rather than
hoped about._

Every X4 test vector in the reference is **synthetic**. The X2 format is confirmed against a real
capture; the X4 format is extrapolated. Four header fields and one trailing field are entirely
unidentified ([02 §2.8](02-smoke-x-protocol.md)).

_Mitigation:_ M1 is gated on real X4 captures, which are now a first-week task. The parser treats
unknown fields as opaque and the firmware keeps a raw-packet ring buffer at
`GET /api/v1/debug/packets`, so investigation never needs a second radio. The `.smk` format versions
independently, so a corrected interpretation does not invalidate stored cooks.

_Residual:_ Q3 and Q5 stay open — they need a Billows, which is not available. Per D11 those fields
are decoded and stored anyway, so the exposure is a wrong _interpretation_ of two recorded values,
not lost data, and no v1 feature depends on them.

### R2 — RAM exhaustion · **medium probability, high impact**

512 KB of SRAM, **no PSRAM**, hosting Wi-Fi + NimBLE + `esp_http_server` + two LittleFS mounts +
mDNS + our tasks. The budget in [01 §1.4](01-hardware.md) lands at 160–210 KB used, but those are
estimates, and heap fragmentation on a device that runs for 24 hours is its own problem.

_Mitigation:_ NimBLE not Bluedroid (D6); no response ever materialized in RAM (D7); hard caps on
concurrent connections stated in the API contract; per-task stack watermarks and a minimum-heap
check in the 24-hour soak, with an explicit CI failure below 80 KB free. Measured at M2 and M3, not
at the end.

### R3 — Android will not route to the AP · **medium probability, medium impact**

The canonical "it works on my phone but not theirs" bug. Covered in
[05 §5.8](05-connectivity-and-provisioning.md), but OEM behaviour genuinely varies.

_Mitigation:_ both halves of the fix (captive-portal shim + explicit `bindProcessToNetwork`), tested
on at least three OEM Android builds during M4, plus a manual-IP escape hatch that always works.

### R4 — Battery does not cover a 24-hour cook in AP mode · **already confirmed**

~18.5 h at ~145 mA in AP mode with the display on ([01 §1.6](01-hardware.md)). This is arithmetic,
not a risk — it is a fact to design around.

_Mitigation:_ display auto-sleep, a battery-saver profile that auto-engages below 20 %, honest copy
in the app when the user chooses AP mode, and clear guidance that the supported long-cook setup is
USB power with the pack as a UPS. STA mode comfortably exceeds 24 h.

### R5 — Wi-Fi / BLE / LoRa coexistence · **low-medium probability, medium impact**

Wi-Fi and BLE share the 2.4 GHz radio. The SX1262 is sub-GHz and should be independent, but the
polling RX loop holds a semaphore and runs at tick rate.

_Mitigation:_ software coexistence enabled; `lora_rx` pinned to core 1 away from the wireless stacks;
explicitly on the [01 §1.8](01-hardware.md) bench checklist. If packet loss appears under load, the
DIO1 interrupt migration moves up from v1.1.

### R6 — GPIO37 / battery divider uncertainty · **medium probability, low impact**

Sources conflict on both whether GPIO37 is usable and what the divider ratio is
([01 §1.3](01-hardware.md)).

_Mitigation:_ runtime-calibrated ratio in NVS with a one-point calibration endpoint; if GPIO37 turns
out to be unusable, battery reporting degrades to unavailable and nothing else breaks.

### R7 — Android BLE flakiness across OEMs · **medium probability, medium impact**

Android BLE has a long history of per-vendor quirks: bonding failures, MTU negotiation refusals,
notifications silently stopping.

_Mitigation:_ `live_state` is designed to fit the **default 23-byte MTU** so telemetry works even
when negotiation fails; every characteristic degrades by chunking; the app always has an HTTP path;
BLE reconnect is aggressive and logged. Tested on the same three OEM builds as R3.

### R8 — Scope · **high probability, medium impact**

This is firmware, a protocol, a storage engine, a BLE stack, an HTTP API, a Flutter app, and a
simulator. It is a lot for a small team.

_Mitigation:_ the M1–M4 ordering means each milestone is independently useful — M1 alone gives a
bridge that reliably records cooks to flash, which is already better than the reference. The
simulator decouples app work from firmware work so the two can proceed in parallel or in either
order. The deferred list in §11.2 is a commitment, not a wish list.

### R9 — Upstream and vendor goodwill · **low probability, low impact**

The bridge listens to an unencrypted broadcast, coexists with ThermoWorks' own receivers, and never
impersonates one. The reference project has operated this way publicly since 2022.

_Mitigation:_ keep the "listener, never a transmitter" invariant ([02 §2.5](02-smoke-x-protocol.md))
literally enforced in code; retain the MIT attribution; state clearly that the project is
unaffiliated with ThermoWorks.

## 11.4 Open questions

### Settled

| #   | Question               | Answer                                                                                | Decision              |
| --- | ---------------------- | ------------------------------------------------------------------------------------- | --------------------- |
| —   | BLE scope              | Custom GATT service                                                                   | [D1](00-overview.md)  |
| —   | MQTT / Home Assistant  | Dropped for v1                                                                        | [D2](00-overview.md)  |
| —   | Button strategy        | One button, gestures                                                                  | [D3](00-overview.md)  |
| —   | Alarm delivery         | Foreground service + local notifications                                              | [D4](00-overview.md)  |
| Q-A | Smoke X4 in hand?      | **Yes** — R1 downgraded, M1's capture gate is a week-one task                         | —                     |
| Q-B | Billows?               | **No unit.** Decode and store the fields; no UI in v1                                 | [D11](00-overview.md) |
| Q-C | One smoker or several? | **One.** Schema stays multi-capable, UI is single-device                              | [D12](00-overview.md) |
| Q-D | Default display unit   | **°F**, switchable                                                                    | [D14](00-overview.md) |
| Q-E | Fallback web UI?       | **Post-MVP decision.** Partition reserved and left empty                              | [D13](00-overview.md) |
| Q-G | Name                   | **SmokeBridge** confirmed — AP SSID, mDNS host, BLE name, package id all settle on it | —                     |

### Still open

One question, and it blocks nothing before M6.

| #   | Question                    | Why it matters                                                                                                                                                                                                                                                                        | When it's needed          |
| --- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Q-F | **Public repo or private?** | Affects licensing posture, whether the browser installer can live on GitHub Pages, and how carefully the reverse-engineering notes are worded. The docs are written as though public — MIT attribution retained, nothing that assumes privacy — which is the safe superset either way | before M6 / first release |

Q-H is settled: **one board**, with the consequences worked through in §11.6.

## 11.5 Suggested first steps

1. **Capture real X4 traffic and commit it to `protocol/fixtures/`.** With hardware in hand this is
   the single highest-value hour in the project — it closes Q1, Q4, Q6, and Q8 and retires the top
   risk before a line of firmware is committed. The reference build flashes today and its serial log
   already prints every decoded payload, so this needs no new code
2. Run the [01 §1.8](01-hardware.md) bench checklist on the real board and write up
   `docs/hardware-verified.md` — the GPIO37 / battery-divider conflict, the free-heap figure, and
   the AP-mode current draw all collapse from assumptions into facts, cheaply
3. Stand up M0: repo skeleton, `protocol/records.yaml`, the generator, CI, and `tools/sim`. A day or
   two, and it unblocks Flutter work immediately, in parallel with firmware
4. Read §11.6 before writing tasks — the single-board constraint changes sequencing, not just tooling
5. Settle Q-F before M6

## 11.6 Working with one board

There is exactly one Heltec V3. It is the development target, the test rig, and the only instrument
pointed at the Smoke X. Four consequences that shape the plan rather than merely inconveniencing it:

**1 — Capture is a background behaviour, never a session.** Flashing a special capture build costs a
cook, and cooks are the scarce resource. So the shipping firmware always keeps a RAM packet ring, a
persistent novelty log, and an opt-in per-session raw log
([02 §2.7](02-smoke-x-protocol.md), [10 §10.4](10-repo-tooling-and-testing.md)). The novelty log is
the load-bearing piece: six of the eight open protocol questions get answered by cooking dinner,
with the evidence waiting at `/api/v1/debug/novelty` whenever anyone looks. **Build it in M1, not
later** — every cook before it exists is evidence thrown away.

**2 — Replay is not optional tooling.** One captured cook has to serve as an unlimited test fixture,
because you cannot re-run reality. `tools/lora/replay.py` and `tools/sim` are M0 deliverables, ahead
of most firmware. This is also what lets the app track proceed without ever touching the board.

**3 — The board is a serialized resource; plan around contention.** Only one track can hold it at a
time. Concretely: do bench work (GPIO verification, current draw, OLED, button) in one sitting and
write up `docs/hardware-verified.md` rather than returning to it piecemeal; batch firmware flashes;
and when a cook is running, the board belongs to data collection, not to debugging. Tasks should be
tagged with whether they need the board, so a planner can pack the ones that don't.

**4 — Bricking it stops everything.** With no spare, an unbootable board is a total halt until it is
recovered over USB. This raises the value of things already in the design and lowers the tolerance
for shortcuts around them: OTA rollback behind a health gate ([03 §3.7](03-firmware-architecture.md)),
the post-boot AP recovery window and double-reset path ([03 §3.4.1](03-firmware-architecture.md)),
and the rule that a factory reset is always reachable from the button. Never ship an OTA to the only
board without having flashed the same image over USB first.

**What this does not change:** the milestone content. M0–M6 stand as written; the single board
affects _ordering and tooling priority_, and it makes `tools/sim` plus the novelty log the two
highest-leverage things to build early.
</content>
