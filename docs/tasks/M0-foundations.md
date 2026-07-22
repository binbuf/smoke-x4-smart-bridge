# M0 — Foundations

**Exit gate:** CI is green, and `dart run tools/sim --cook fixtures/brisket-18h.smk` serves a fake
18-hour cook over the real API. The Flutter app can be built and tested against it before any
firmware exists.

52 tasks — **44 `board: no`, 8 `board: yes`**. The board work is one sitting plus one cook and runs
concurrently with everything else; see the wave diagram in [README](README.md).

---

## Lane B — the board campaign (V1, V2)

Do the whole bench checklist **in one sitting** ([§12.6 rule 7](../design/12-task-planning-notes.md)).
Returning to it piecemeal wastes the scarcest resource in the project.

> ⚠ **Two ways to destroy the hardware, both before you write a line of code.** Reversed SH1.25-2
> polarity kills the board; powering up with the LoRa antenna disconnected can kill the SX1262 PA.
> V1.1 exists to be done first.

### V1.1 bench: verify battery connector polarity and first power-up

- **blocked-by:** — · **verify:** B · **board:** yes
- **design:** [01 §1.6](../design/01-hardware.md), [01 §1.5](../design/01-hardware.md)

Meter the supplied SH1.25-2 pack against the board's silkscreen before connecting it — Heltec's
polarity is not standardised across third-party packs and the bundled "battery set" has been reported
wrong. Confirm the LoRa antenna is fitted before applying power.

**Done when:** polarity is recorded in `docs/hardware-verified.md` and the board boots on battery.

### V1.2 bench: flash the unmodified reference firmware

- **blocked-by:** V1.1 · **verify:** B · **board:** yes
- **design:** [10 §10.4](../design/10-repo-tooling-and-testing.md)

Install ESP-IDF v5.4, build `docs/reference/smoke-x-receiver` for `heltec-v3`, and flash it. This is
a known-good baseline: OLED, LoRa RX, and Wi-Fi are all proven working *before* our code exists to
be blamed. It is also the instrument for V2.1 — its serial log already prints every decoded payload,
so the first real capture needs no new code.

**Done when:** the reference boots, the OLED draws its status page, and `idf.py monitor` shows LoRa
activity.

### V1.3 bench: resolve the GPIO37 gate and the battery divider ratio

- **blocked-by:** V1.2 · **verify:** B · **board:** yes
- **design:** [01 §1.2, §1.3](../design/01-hardware.md)

Toggle GPIO37 and confirm GPIO1's ADC reading tracks it — published pinouts claim GPIO33–38 are
unusable, but that guidance is for parts with octal PSRAM, which the FN8 does not have. Then measure
the divider ratio against a DMM at **≥ 2 pack voltages** to settle the ×4.9 (Heltec forum) vs ×2.0
(ESPHome) conflict.

**Retires R6 and gates F12.** If GPIO37 turns out unusable, battery reporting degrades to
unavailable and nothing else breaks — record that outcome rather than working around it.

**Done when:** both numbers are in `docs/hardware-verified.md`, or the failure is recorded explicitly.

### V1.4 bench: verify button, LED, Vext, and OLED I²C

- **blocked-by:** V1.2 · **verify:** B · **board:** yes
- **design:** [01 §1.2, §1.8](../design/01-hardware.md), [07 §7.1, §7.4](../design/07-display-and-controls.md)

Four checks: GPIO0 reads reliably as a user button after boot with a debounce window that survives
the boot strapping; GPIO35 LED is active-HIGH and dims under LEDC PWM; GPIO36 must be driven **LOW**
for the OLED rail to come up; OLED I²C at 400 kHz is stable while Wi-Fi is active.

**Done when:** all four are recorded. Note that the *BLE* half of the I²C stability check cannot be
done yet — the reference uses Improv over serial, not BLE — and is carried forward to V3 in M3.

### V1.5 bench: measure current draw and brownout behaviour

- **blocked-by:** V1.2 · **verify:** B · **board:** yes
- **design:** [01 §1.6](../design/01-hardware.md)

Measure each row of the §1.6 table that the reference can reach (AP with OLED on, STA with modem
sleep), plus real runtime on the 3000 mAh pack, plus: **does the board brown out when Wi-Fi AP starts
on a depleted pack?**

R4 is already arithmetic, not a risk — ~18.5 h in AP mode does not cover a 24-hour cook. The point of
measuring is to make the app's honest copy about AP-mode battery cost accurate rather than assumed.

**Done when:** measured figures replace the estimates in `docs/hardware-verified.md`.

### V1.6 bench: write docs/hardware-verified.md

- **blocked-by:** V1.3, V1.4, V1.5 · **verify:** B · **board:** yes
- **design:** [01 §1.8](../design/01-hardware.md)

Every box in the §1.8 checklist gets a measured number or an explicit **unresolved**. Three boxes
*cannot* close at M0 and must be marked deferred with their target milestone:

| Deferred check | Why | Closes at |
| --- | --- | --- |
| Free heap ≥ 150 KB with AP + NimBLE + httpd + both LittleFS mounts | Our stack doesn't exist yet | F9 / F10 (M2–M3) |
| LoRa RX with BLE advertising **and** a WebSocket client streaming | Same | V3 (M3) |
| OLED I²C stable with BLE active | Reference has no BLE | M3 |

**Done when:** the file exists and no box is silently blank.

### V2.1 capture: record the first real X4 traffic

- **blocked-by:** V1.2 · **verify:** C · **board:** yes
- **design:** [02 §2.3, §2.8](../design/02-smoke-x-protocol.md), [10 §10.4](../design/10-repo-tooling-and-testing.md)

**The single highest-value hour in the project.** Every X4 test vector in the reference is
*synthetic*, extrapolated from the X2 format. Cook anything with all four probes attached, let it run
overnight if possible, and keep the serial log.

Closes **Q1** (does header field 1 ever leave `30`?), **Q6** (does an X4 emit the same values as an
X2?), plus interval statistics, real dropouts, and RSSI decay.

**Done when:** the payload lines are normalised into `protocol/fixtures/lora/` and the synthetic X4
vector in [02 §2.3](../design/02-smoke-x-protocol.md) is replaced by a real one. **This retires R1
and gates M1's exit.**

### V2.2 capture: record an X4 sync handshake

- **blocked-by:** V1.2 · **verify:** C · **board:** yes
- **design:** [02 §2.2.1, §2.8](../design/02-smoke-x-protocol.md)

Two minutes of work: put the base in sync mode with the bridge unpaired and capture the 6-comma
beacon. Closes **Q2** (what is sync field `020001`?) partially and **Q6** fully.

**Done when:** a real X4 sync vector is committed alongside V2.1's state vectors.

> The remaining capture opportunities — probe-state edge cases (Q4), the alarm edge (Q8), a mid-cook
> °C switch — are **deliberately not M0 tasks.** Once F4's novelty log exists in M1 they collect
> themselves while you cook dinner ([10 §10.4](../design/10-repo-tooling-and-testing.md)). They live
> in [standing work](standing-work.md).

---

## T1 — Repo skeleton and tooling

### T1.1 repo: initialise the monorepo skeleton and git history

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [10 §10.1](../design/10-repo-tooling-and-testing.md)

Create the §10.1 tree (`firmware/`, `app/`, `protocol/`, `tools/`, `docs/`, `.github/workflows/`)
with placeholder READMEs. `git init` — the working tree is currently not a repository at all. Ignore
`build/`, the generated root `sdkconfig` (per-board `sdkconfig.heltec-v3` **is** committed),
`.dart_tool/`, `node_modules/`, `*.bin`.

**Done when:** the tree matches §10.1, one commit exists, and `git status` is clean with no build
artifact tracked.

### T1.2 repo: snapshot docs/reference as a read-only vendor drop

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [10 §10.1](../design/10-repo-tooling-and-testing.md), [00 §Attribution](../design/00-overview.md)

`docs/reference/smoke-x-receiver` currently carries its own `.git` directory. Make it a **snapshot,
not a submodule** — the point is a frozen provenance copy to diff against, and a submodule adds a
clone step for every contributor to get files nobody compiles. Strip the nested `.git`, write
`docs/reference/PROVENANCE.md` naming the upstream URL, the pinned commit SHA, and the MIT © 2022
G-Two notice.

**Done when:** no nested `.git` remains, `PROVENANCE.md` exists, and `CONTRIBUTING.md` states that
`docs/reference/` is never edited.

### T1.3 repo: add formatting and lint configuration

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [10 §10.7](../design/10-repo-tooling-and-testing.md)

`.clang-format` carried over from the reference (4-space, 80 col), `.editorconfig`,
`analysis_options.yaml` with `flutter_lints` plus `prefer_final_locals` and
`require_trailing_commas`, and `.pre-commit-config.yaml` extended from the reference's.

Two deltas from the reference's config: **drop its `eslint` hook** (it targets `web_ui/`, which we do
not have — D13) and **add** `dart format`, YAML/JSON validation, and a `protocol/gen` freshness check.

**Done when:** `pre-commit run --all-files` passes on the skeleton.

### T1.4 repo: write the root Makefile

- **blocked-by:** F1.1 · **verify:** H · **board:** no
- **design:** [03 §3.8](../design/03-firmware-architecture.md)

Targets: `setup build flash flash-monitor menuconfig test-host sim`. Keep the reference's `export.sh`
sourcing and Python-version detection; the v2/v3 board matrix collapses to a single `heltec-v3`
target, which removes most of its complexity.

Note for T5 (M6): the reference's `merge_bin` offsets are for **its** partition table. Ours differ —
see [03 §3.5](../design/03-firmware-architecture.md).

**Done when:** `make test-host` and `make build` both work from a clean checkout.

### T1.5 ci: firmware-build.yml and firmware-test.yml

- **blocked-by:** F1.1, F1.6 · **verify:** H · **board:** no
- **design:** [10 §10.6](../design/10-repo-tooling-and-testing.md)

Build in the `espressif/idf:release-v5.4` container; **report binary size and free-space delta on
every PR**. Run the CMake + CTest host suite with coverage. Warnings as errors.

Binary-size reporting is worth its two lines: with 2.5 MB app slots holding Wi-Fi + BLE + httpd +
LittleFS, the day someone adds a library that doesn't fit should be the day they find out.

**Done when:** both workflows are green on the skeleton and the size report appears in a PR comment.

### T1.6 ci: app.yml and protocol.yml

- **blocked-by:** A1.1, P1.4 · **verify:** H · **board:** no
- **design:** [10 §10.6](../design/10-repo-tooling-and-testing.md)

`flutter analyze`, `dart format --set-exit-if-changed`, `flutter test`, debug APK build. `protocol.yml`
regenerates `protocol/gen/**` and fails on any diff.

Add one project-specific check: **`app/lib/domain/` must not import anything from Flutter.** It is a
hard rule in [08 §8.3](../design/08-flutter-app.md) and a one-line grep enforces it forever.

**Done when:** both workflows are green, and a deliberate `import 'package:flutter/material.dart';`
in `domain/` fails CI.

### T1.7 repo: write README, LICENSE, CONTRIBUTING, and attribution

- **blocked-by:** T1.2 · **verify:** H · **board:** no
- **design:** [00 §Attribution](../design/00-overview.md), [11 §11.4](../design/11-roadmap-and-risks.md)

MIT for our code; retain G-Two's notice verbatim on every carried file; state plainly that the
project is not affiliated with or endorsed by ThermoWorks. Document the "listener, never a
transmitter" invariant and the fact that Smoke X LoRa traffic is unencrypted and unauthenticated —
that is a property of the product and users deserve to know it.

Record **Q-F (public or private repo)** as the one open decision, needed before M6.

**Done when:** the files exist and Q-F is tracked somewhere a human will see it before M6.

---

## P1 — The binary record contract

**P1 before F5 and A3** ([§12.6 rule 5](../design/12-task-planning-notes.md)): both sides parse the
same 16-byte record, so generate it once. Byte layouts are exactly where silent corruption lives — a
size or endianness mistake produces plausible-looking garbage rather than an error.

### P1.1 protocol: write protocol/records.yaml

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [04 §4.2](../design/04-storage-and-history.md), [05 §5.6](../design/05-connectivity-and-provisioning.md), [10 §10.2](../design/10-repo-tooling-and-testing.md)

Describe every packed structure: `sample_rec` (16 B), `session_header` (256 B), `mark_rec` (32 B),
and the BLE payloads `live_state`, `net_status`, `wifi_scan_result`, `wifi_config`, `device_control`,
`result`, `history_preview`.

**Done when:** every field in the [04 §4.2](../design/04-storage-and-history.md) tables and the
[05 §5.6](../design/05-connectivity-and-provisioning.md) payload blocks appears exactly once; sizes
are declared and self-consistent; the `temp` sentinels (`INT16_MIN` detached, `INT16_MIN+1` invalid)
and the `flags` bit names are named, not numbered.

### P1.2 tools/protogen: emit protocol/gen/record_gen.h

- **blocked-by:** P1.1 · **verify:** H · **board:** no
- **design:** [10 §10.2](../design/10-repo-tooling-and-testing.md)

Packed structs, a `_Static_assert` on every declared size, CRC helpers (CRC-16/CCITT-FALSE over bytes
0..13 of a sample; CRC-32 over bytes 0..251 of a header), sentinel constants, and bitfield accessors.

**Done when:** it compiles under `-Wall -Wextra -Werror`, the static asserts pass, and a hand-written
hex vector round-trips.

### P1.3 tools/protogen: emit protocol/gen/records.g.dart

- **blocked-by:** P1.1 · **verify:** H · **board:** no
- **design:** [10 §10.2](../design/10-repo-tooling-and-testing.md)

`ByteData` readers and writers with endianness stated explicitly at every call. **Sentinels map to
`null`, not to a number** — a detached probe must be structurally incapable of surfacing as `0`, which
is the specific bug the reference has and the one that ruins a graph.

**Done when:** the same hex vector from P1.2 round-trips in Dart and yields `null` for `INT16_MIN`.

### P1.4 ci: fail the build when protocol/gen is stale

- **blocked-by:** P1.2, P1.3 · **verify:** H · **board:** no
- **design:** [10 §10.2, §10.6](../design/10-repo-tooling-and-testing.md)

Both generated files are committed. CI regenerates and fails on any diff.

**Done when:** editing `records.yaml` without regenerating turns CI red.

### P1.5 protocol: commit shared record fixtures

- **blocked-by:** P1.2, P1.3 · **verify:** H · **board:** no
- **design:** [10 §10.2, §10.5](../design/10-repo-tooling-and-testing.md)

`protocol/fixtures/records/` — hex vectors for: four probes attached; one detached; all detached; a
°C-sourced sample; alarm flags set; a header with `clock_valid` clear; **a header at a future
`version` with a larger `rec_len`**; a mark carrying multibyte UTF-8.

The C host tests and the Dart tests read the *same files*. This is the drift guard — a C struct and a
Dart class diverging shows up as a red test, not as a field returning null in the field.

**Done when:** both test suites parse every fixture and assert identical values.

---

## P2 — The HTTP contract

### P2.1 protocol: write openapi.yaml

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [06 §6.1–6.3](../design/06-device-api.md)

Every path in the [§6.2](../design/06-device-api.md) table, with the `GET /status` and `GET /live`
bodies specified in full and `GET /sessions/{id}/samples` carrying all its query parameters
(`from`, `to`, `stride`, `bucket`, `agg`, `format`, `probes`).

**Done when:** the spec validates, and the documented `/live` schema makes a detached probe's temp
`null` rather than optional-with-default.

### P2.2 protocol: specify the error model and concurrency limits

- **blocked-by:** P2.1 · **verify:** H · **board:** no
- **design:** [06 §6.1, §6.3](../design/06-device-api.md)

The `{ "error": { "code", "message", "detail" } }` envelope and the status → code mapping. **Every
response, success or failure, is JSON** — the reference replies to POSTs with plain text, forcing
clients to special-case content types.

State the hard caps in the contract rather than letting clients discover them as flakiness:
`max_open_sockets = 7`, at most **2** concurrent WebSocket upgrades, a third gets `503 busy`.

**Done when:** every code in the §6.1 table is in the spec and `busy` is documented on the upgrade.

### P2.3 protocol: commit request/response fixtures

- **blocked-by:** P2.2 · **verify:** H · **board:** no
- **design:** [10 §10.2](../design/10-repo-tooling-and-testing.md)

A fixture per shape: full `status`; `live` with two probes detached; a bucketed `samples` response
carrying a non-empty `gaps` array; both `config/wifi` accept shapes (AP returns the generated PSK,
STA does not return the password); one body per error code.

**Done when:** `tools/sim` and the app's tests both read these files, so a contract change breaks
both at once.

---

## P3 — The BLE contract

### P3.1 protocol: write protocol/ble-gatt.md

- **blocked-by:** T1.1, P1.1 · **verify:** H · **board:** no
- **design:** [05 §5.6](../design/05-connectivity-and-provisioning.md)

The UUID table under base `7f9aXXXX-4c5b-4b0f-9a3d-1c2e3f405162`, a byte-offset table per
characteristic, the security profile (which characteristics need encryption, and which two
additionally need authentication because they can change network config or wipe the device), the
advertising and scan-response layout, and the MTU strategy.

**Done when:** every characteristic in §5.6 has a byte table, and the doc shows by arithmetic that
`live_state` is **16 B ≤ 20 B** — so live telemetry survives a failed MTU negotiation, which is the
single most likely Android BLE failure (R7).

---

## F1 — Firmware skeleton

### F1.1 firmware: create the ESP-IDF v5.4 skeleton for esp32s3

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [03 §3.1](../design/03-firmware-architecture.md)

`firmware/` with `main/`, the `components/` directories from the §3.1 map (empty but declared), and a
`main.c` that boots and logs. This is what makes "CI green on an empty build" mean something.

**Done when:** `idf.py build` succeeds for `esp32s3`.

### F1.2 firmware: write partitions.csv and sdkconfig defaults

- **blocked-by:** F1.1 · **verify:** H · **board:** no
- **design:** [03 §3.5, §3.8](../design/03-firmware-architecture.md)

The §3.5 table exactly — including **`www` declared and left unformatted** (D13). Repartitioning
after ship means a full erase and history loss, so both OTA slots and the reserved `www` partition
exist from day one even though nothing uses them yet.

sdkconfig deltas from §3.8: NimBLE not Bluedroid, SW coexistence, `HTTPD_WS_SUPPORT`, OTA rollback,
task WDT, tickless idle, and the trimmed Wi-Fi buffers.

**Done when:** `idf.py partition-table` prints the layout, `0x5A0000 + 0x260000 == 0x800000` exactly
(nothing stranded), and the app image builds inside a 2560 KB slot with headroom reported.

### F1.3 firmware: define the bridge_event bus

- **blocked-by:** F1.1 · **verify:** H · **board:** no
- **design:** [03 §3.2](../design/03-firmware-architecture.md)

`BRIDGE_EVENT` base, the twelve event IDs, and POD payload structs copied by `esp_event` — no
pointers into caller stacks.

Add the enforcement: **a debug-build assertion that measures handler duration and fires above ~5 ms.**
At one packet per 30 s there is no throughput concern; the discipline exists so a slow LittleFS
garbage-collection pass or an OTA write can never stall the decoder.

**Done when:** a deliberately slow test handler trips the assertion in a debug build.

### F1.4 firmware: write main/tasks.h

- **blocked-by:** F1.3 · **verify:** H · **board:** no
- **design:** [03 §3.3](../design/03-firmware-architecture.md), [01 §1.4](../design/01-hardware.md)

One table of stack, priority, and core for every task in §3.3 — the single source of truth so the
§1.4 RAM budget stays auditable. `lora_rx` pinned to **core 1**, everything else to core 0, keeping
the polling radio loop off the core running Wi-Fi and BLE.

**Done when:** every task is declared through the table, and a compile-time sum of the stacks is
emitted so the budget is checkable without running anything.

### F1.5 firmware: implement the boot sequence skeleton

- **blocked-by:** F1.4 · **verify:** H · **board:** no
- **design:** [03 §3.4, §3.4.1](../design/03-firmware-architecture.md)

The sixteen steps of §3.4 with stubs for subsystems that don't exist yet. Two properties must be real
from the start:

1. **LoRa comes up before Wi-Fi and BLE.** Data capture is the product; if a later subsystem fails to
   init, the bridge still records the cook. Everything after step 8 is individually failure-tolerant
   and logged; only NVS and the event loop are fatal.
2. **The double-reset token** in RTC SRAM (step 2). It is the recovery path that works with a dead
   OLED, and with one board, an unreachable bridge is a total halt.

Step 7's 3-second PRG recovery window is stubbed until F11; step 16's OTA health gate until F14.

**Done when:** a stub that returns an error at step 12 still leaves a booted device with steps 1–11
complete, and the double-reset token round-trips across a reset but not a power cycle.

### F1.6 firmware: set up the host test harness

- **blocked-by:** F1.1 · **verify:** H · **board:** no
- **design:** [10 §10.5](../design/10-repo-tooling-and-testing.md)

`firmware/test/` — plain CMake + CTest, no ESP-IDF, `-Wall -Wextra -Werror`, following the pattern
the reference established in its `test/CMakeLists.txt`. Wired to `make test-host` and to CI.

**Done when:** a trivial test compiles and runs in seconds with no toolchain beyond `gcc` and `cmake`.

---

## A1 — Flutter skeleton

### A1.1 app: scaffold the Flutter project with the §8.3 layout

- **blocked-by:** T1.1 · **verify:** H · **board:** no
- **design:** [08 §8.3](../design/08-flutter-app.md)

Target `android`, `minSdk 24`, `targetSdk 35`. Create the full directory structure — `app/`, `core/`,
`domain/`, `data/`, `features/`, `platform/` — so nothing lands in the wrong layer by default.

**Done when:** `flutter build apk --debug` succeeds and `flutter analyze` is clean.

### A1.2 app: wire riverpod, go_router, theme, and the error boundary

- **blocked-by:** A1.1 · **verify:** H · **board:** no
- **design:** [08 §8.2, §8.7](../design/08-flutter-app.md)

**Dark-first theme**, large type, high contrast, generous touch targets. This is an app read from
four feet away in a dark yard at 3 a.m., possibly through a screen door — that constraint belongs in
the theme from the first commit, not retrofitted at M4.

**Done when:** a placeholder route renders under both themes and an uncaught exception surfaces in
the error boundary rather than a grey screen.

### A1.3 app: add and pin the §8.2 package set

- **blocked-by:** A1.1 · **verify:** H · **board:** no
- **design:** [08 §8.2](../design/08-flutter-app.md)

`riverpod`, `freezed`, `flutter_blue_plus`, **`nsd`** (not `multicast_dns` — it has a long-standing
Android discovery bug), `dio`, `web_socket_channel`, `drift`, `fl_chart`,
`flutter_local_notifications`, `flutter_foreground_task`, `shared_preferences`, `logger`.

Deliberately **not** added: any ESP provisioning package. We speak our own GATT protocol (D1) and
those packages assume Espressif's protobuf scheme.

**Done when:** `pubspec.lock` is committed and CI builds from it.

---

## A2 — Domain analysis (pure Dart, zero dependencies)

**Start these on day one** ([§12.6 rule 3](../design/12-task-planning-notes.md)). No dependencies at
all, and they front-load the analysis work that is easiest to get subtly wrong. Every one is a pure
function with table-driven tests, so each closes in milliseconds in CI.

### A2.1 domain: define the entities

- **blocked-by:** — · **verify:** H · **board:** no
- **design:** [08 §8.3](../design/08-flutter-app.md)

`Probe`, `Sample`, `CookSession`, `Mark`, `Alarm`, `BridgeStatus` as `freezed` classes. `domain/`
imports nothing from Flutter — a hard rule, enforced in CI by T1.6.

**Done when:** the entities exist and the CI import check is live.

### A2.2 domain: implement rateOfChange

- **blocked-by:** A2.1 · **verify:** H · **board:** no
- **design:** [09 §9.4](../design/09-alarms-and-insights.md)

Ordinary least-squares slope over a rolling 10-minute window (20 samples at 30 s). Returns **`null`,
not a number**, when fewer than 12 valid samples are present or the window spans a gap > 2 min. Below
±0.6 °F/hr the result is at the edge of meaningful and renders as `~0`.

**Done when:** table tests cover the null cases explicitly — they are the ones that matter.

### A2.3 domain: implement ETA under both models

- **blocked-by:** A2.2 · **verify:** H · **board:** no
- **design:** [09 §9.4](../design/09-alarms-and-insights.md)

Linear early; Newton cooling once the food is within ~60 °F of pit, with `k` fitted by regressing
`ln(T_pit − T)` against `t` over the last 60 minutes. Naive `(target − current) / slope` is wrong in
the back half of every cook because meat approaches pit temperature asymptotically.

All five guard rails: ≥ 30 min of history; `|slope| ≥ 1 °F/hr`; suppressed entirely during a stall;
refused when `target ≥ T_pit` (*"not at this pit temperature"* is the correct answer); and presented
as a **range** from the slope's standard error, rounded to 15 minutes.

Never `6h 23m`. The physics does not support that precision, and the false confidence is what makes
people trust it and then get burned.

**Done when:** tests cover both models, the boundary between them, and each guard rail firing.

### A2.4 domain: implement the stall detector

- **blocked-by:** A2.2 · **verify:** H · **board:** no
- **design:** [09 §9.4](../design/09-alarms-and-insights.md)

Enter: `role == food` ∧ `|slope| < 2 °F/hr` sustained ≥ 30 min ∧ `140 ≤ temp ≤ 180 °F`.
Exit: `slope > 4 °F/hr` sustained ≥ 15 min.

**Done when:** table tests cover enter, exit, and hovering at each threshold without oscillating.

### A2.5 domain: implement the lid-open detector

- **blocked-by:** A2.2 · **verify:** H · **board:** no
- **design:** [09 §9.4](../design/09-alarms-and-insights.md)

Detect: pit drops ≥ 25 °F within any 3-minute window. Confirm: recovers ≥ 50 % of the drop within
20 min → it was a lid open; does not recover → escalate to `pit_crash`.

Firing on *detection* is what starts the alarm grace window immediately; confirming afterwards is
what lets a genuine fire failure still escalate 20 minutes later. **Both branches must be tested** —
suppressing a real `pit_crash` is the expensive failure.

**Done when:** detect-then-confirm and detect-then-escalate are both covered.

### A2.6 domain: implement LTTB decimation

- **blocked-by:** A2.1 · **verify:** H · **board:** no
- **design:** [08 §8.7](../design/08-flutter-app.md)

Largest-Triangle-Three-Buckets at a target of ~2 points per pixel. Naive stride decimation steps
straight over a lid-open spike; LTTB preserves the visual envelope.

**Done when:** output matches a reference implementation on a shared input, and a synthetic spike
survives decimation from 2,880 points to 400.

### A2.7 domain: implement unit conversion and gap detection

- **blocked-by:** A2.1 · **verify:** H · **board:** no
- **design:** [04 §4.2](../design/04-storage-and-history.md), [08 §8.7](../design/08-flutter-app.md)

`F10 = C10 × 9 / 5 + 320`, with round-trip tests. Gap detection: a `t` delta > 45 s means packets
were missed, and the chart must draw a break rather than a straight line across the hole.

A 30-minute dropout must look like a 30-minute dropout. This is the clearest single improvement over
the reference, whose samples carry no time at all.

**Done when:** conversion round-trips without drift and gap boundaries are exact at 45 s.

---

## A3 — Transport abstraction

### A3.1 data: define BridgeTransport, BridgeCapabilities, and BridgeEvent

- **blocked-by:** A2.1 · **verify:** H · **board:** no
- **design:** [08 §8.1](../design/08-flutter-app.md)

The interface from §8.1. **The UI never knows how it is talking to the bridge** — the dashboard, the
chart, and the session list are written once, and a capability flag drives the two places where the
difference is visible (the chart says *"connected over Bluetooth — full history needs Wi-Fi"*, and
the session list reads from cache).

`BridgeEvent` as a `freezed` union so `switch` over variants is exhaustive.

**Done when:** the interface compiles and adding a variant without handling it fails analysis.

### A3.2 data: implement binary record parsing

- **blocked-by:** A3.1, P1.3, P1.5 · **verify:** H · **board:** no
- **design:** [08 §8.1](../design/08-flutter-app.md), [04 §4.2](../design/04-storage-and-history.md)

Parse the 16-byte records on top of `records.g.dart`, honouring `rec_len` from the session header
rather than `sizeof` — that alone makes additive field growth backward-compatible, so a future v2
record is readable by a v1 client.

**Done when:** it parses every fixture in `protocol/fixtures/records/` to identical values as the C
host tests, detached probes come back `null`, and the future-`version` header fixture is **read, not
rejected**.

### A3.3 data: implement MockTransport

- **blocked-by:** A3.2 · **verify:** H · **board:** no
- **design:** [08 §8.1](../design/08-flutter-app.md)

Deterministic, backed by a `.smk` fixture file. Also able to point at a live `tools/sim` so the same
tests run against both.

**Done when:** a repository test drives a full 18-hour cook through `MockTransport` with no network.

---

## T2 — cookgen

### T2.1 tools/cookgen: implement the thermal model

- **blocked-by:** P1.3 · **verify:** H · **board:** no
- **design:** [10 §10.3](../design/10-repo-tooling-and-testing.md)

Newton cooling toward a pit temperature that itself wanders, per probe. Scenarios can then be
*generated* rather than recorded — which matters enormously when reality costs a brisket.

**Done when:** a generated pit trace has plausible variance and food probes converge asymptotically.

### T2.2 tools/cookgen: add the event repertoire

- **blocked-by:** T2.1 · **verify:** H · **board:** no
- **design:** [10 §10.3](../design/10-repo-tooling-and-testing.md)

Evaporative stall plateau, lid-open drop and recovery, probe detach/reattach, packet dropout at a
configurable rate, and a mid-cook °F↔°C switch.

**Done when:** each event is individually reproducible from a seed.

### T2.3 tools/cookgen: emit .smk and .mrk files

- **blocked-by:** T2.2, P1.2 · **verify:** H · **board:** no
- **design:** [04 §4.2, §4.3](../design/04-storage-and-history.md)

Write real files in the P1 layout, header CRC and per-record CRC included.

**Done when:** a generated 18-hour brisket validates against `record_gen.h`'s static asserts and CRC
checks, **and its stall is detected by A2.4** — a cheap cross-check that the generator and the
detector agree about what a stall looks like.

---

## T3 — tools/sim, the fake bridge

**The highest-leverage item in M0.** It is what decouples the app track from the board: the Flutter
app becomes developable and CI-testable before any firmware exists, and stays testable afterwards
without a smoker running.

### T3.1 tools/sim: serve /status, /live, and /sessions from a fixture

- **blocked-by:** T2.3, P2.3 · **verify:** S · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [10 §10.3](../design/10-repo-tooling-and-testing.md)

**Done when:** responses match the P2.3 fixtures byte-for-byte in shape, and `/live` emits `null` —
never `0` — for a detached probe.

### T3.2 tools/sim: implement streamed /sessions/{id}/samples

- **blocked-by:** T3.1 · **verify:** S · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [04 §4.8](../design/04-storage-and-history.md)

All four formats (`bin`, `json`, `ndjson`, `csv`) with `from`, `to`, `stride`, `bucket`, `agg`, and
`probes`. `agg=minmax` emits per-bucket min/mean/max so a lid-open excursion survives decimation.
The `gaps` array is computed from `t` deltas > 45 s.

CSV emits detached probes as **empty fields, not `0`**.

**Done when:** a 24-hour fixture returns 960 buckets at `bucket=90&agg=minmax`, and the `bin` form is
byte-identical to the stored records.

### T3.3 tools/sim: implement the WebSocket stream

- **blocked-by:** T3.1 · **verify:** S · **board:** no
- **design:** [06 §6.3](../design/06-device-api.md)

`hello` immediately on connect, then the current `sample`, so a client has state without a separate
`GET`. The full §6.3 frame set, 30 s server ping, drop after two missed.

**Enforce the 2-client cap** and return `503 busy` to a third. The app must handle it, so the
simulator must produce it.

**Done when:** a third concurrent client is refused with the documented error body.

### T3.4 tools/sim: implement config, pairing, time, control, and OTA

- **blocked-by:** T3.1 · **verify:** S · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md)

Including the deferred-reconfiguration semantics: `POST /config/wifi` answers **first**
(`applying_in_ms: 500`) and only then "applies". `GET` never returns a stored STA password; it does
return the AP PSK, which the user needs to read back.

**Done when:** both `config/wifi` accept shapes match their P2.3 fixtures.

### T3.5 tools/sim: implement the scenario matrix

- **blocked-by:** T3.2, T3.3, T3.4 · **verify:** S · **board:** no
- **design:** [10 §10.3](../design/10-repo-tooling-and-testing.md)

All ten: `stall`, `lid-open`, `base-lost`, `flaky`, `unpaired`, `detached`, `celsius`,
`storage-full`, `ota`, `long`. Each exists because it is painful or impossible to produce on real
hardware — `long` is 54 days of samples, which no one is going to cook.

**Done when:** every scenario runs, and `flaky` produces gaps that A2.7 detects.

### T3.6 tools/sim: add --speed replay and --advertise-mdns

- **blocked-by:** T3.5 · **verify:** S · **board:** no
- **design:** [10 §10.3](../design/10-repo-tooling-and-testing.md), [05 §5.5](../design/05-connectivity-and-provisioning.md)

Replay clock, plus `_smokebridge._tcp` on port 80 with the §5.5 TXT records so app discovery is
exercised too — the `nsd` path is a known Android trap and deserves to be tested from day one.

**Done when:** `dart run tools/sim --port 8080 --speed 60 --cook fixtures/brisket-18h.smk` replays 18
hours in 18 minutes, and `dns-sd -B _smokebridge._tcp` sees it.

**This closes M0.**
