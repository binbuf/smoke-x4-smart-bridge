# 10 — Repo, Tooling, and Testing

## 10.1 Monorepo layout

```
smoke-x4-smart-bridge/
├── firmware/                     ESP-IDF v5.4 project  ── see 03
│   ├── main/
│   ├── components/
│   ├── vendor/esp-idf-sx126x/    submodule, pinned commit
│   ├── test/                     host unit tests (plain CMake, no ESP-IDF)
│   ├── partitions.csv
│   ├── sdkconfig.defaults[.heltec-v3]
│   └── Makefile
│
├── app/                          Flutter, Android first  ── see 08
│   ├── lib/
│   ├── test/  integration_test/  test/goldens/
│   └── android/
│
├── protocol/                     ★ single source of truth  ── §10.2
│   ├── records.yaml              binary record layouts (sample, header, mark, BLE payloads)
│   ├── openapi.yaml              HTTP + WebSocket contract
│   ├── ble-gatt.md               UUIDs, characteristics, payload tables
│   ├── fixtures/                 shared golden vectors — raw LoRa, .smk files, JSON bodies
│   └── gen/                      generated: record_gen.h · records.g.dart  (committed)
│
├── tools/
│   ├── sim/                      Dart: a fake bridge serving the real API  ── §10.3
│   ├── lora/                     capture + replay of real Smoke X traffic  ── §10.4
│   ├── cookgen/                  synthesize physically plausible cook data
│   ├── flash/                    esptool wrappers, merged-binary builder
│   └── installer/                esp-web-tools GitHub Pages page
│
├── docs/
│   ├── design/                   these documents
│   ├── hardware-verified.md      results of the 01 §1.8 bench checklist
│   └── reference/                upstream smoke-x-receiver, read-only, MIT © G-Two
│
├── .github/workflows/
└── README.md
```

`docs/reference/` stays untouched. It is provenance for [02](02-smoke-x-protocol.md) and a place to
diff against when upstream fixes something.

## 10.2 `protocol/` — one definition, two languages

The classic failure of a firmware + app monorepo is a C `struct` and a Dart class drifting apart
until someone spends an afternoon with a hex dump. Two mechanisms prevent it, applied where each
actually earns its cost:

**Binary layouts are generated.** `protocol/records.yaml` describes every packed structure — the
16-byte sample, the 256-byte session header, the 32-byte mark, and each BLE characteristic payload:

```yaml
sample_rec:
  size: 16
  fields:
    - { name: t,     type: u32 }
    - { name: temp,  type: i16, count: 4, sentinel: { -32768: detached, -32767: invalid } }
    - { name: flags, type: u8,  bits: [p1_alarm, p2_alarm, p3_alarm, p4_alarm,
                                       billows, new_alarm, source_celsius, _rsv] }
    - { name: rssi,  type: i8 }
    - { name: crc16, type: u16, crc: { poly: ccitt_false, over: 0..13 } }
```

`tools/protogen` emits `protocol/gen/record_gen.h` and `protocol/gen/records.g.dart`, both committed.
CI regenerates and fails on any diff. This is worth automating because byte layouts are exactly
where silent corruption lives, and a size or endianness mistake produces plausible-looking garbage
rather than an error.

**JSON models are hand-written but golden-tested.** `openapi.yaml` documents the HTTP contract and
feeds external tooling; the Dart models are hand-written `freezed` classes. Generated JSON models
are more trouble than they solve at this scale — but every request and response shape has a fixture
in `protocol/fixtures/`, and both the firmware's host tests and the app's tests parse the *same
bytes* and assert the same values. Drift shows up as a red test, not a field returning null in the
field.

## 10.3 `tools/sim` — the fake bridge

A Dart server implementing the complete HTTP + WebSocket API against recorded or synthesized data.
It is the single highest-leverage tool in the repo: the Flutter app becomes developable and
CI-testable before any firmware exists, and stays testable afterwards without a smoker running.

```bash
dart run tools/sim --port 8080 --speed 60 --cook fixtures/brisket-18h.smk
dart run tools/sim --scenario stall --probes 4
dart run tools/sim --scenario lid-open --drop 5%
dart run tools/sim --scenario base-lost --after 2h
dart run tools/sim --scenario unpaired
dart run tools/sim --advertise-mdns          # so app discovery is exercised too
```

Scenarios exist for every case that is painful to produce on real hardware:

| Scenario | Reproduces |
| --- | --- |
| `stall` | A 3-hour plateau at 158 °F — for the stall detector and ETA suppression |
| `lid-open` | A 40 °F pit drop and recovery — for the grace-window logic |
| `base-lost` | Packets stop dead — for the watchdog and gap rendering |
| `flaky` | 5–20 % packet loss — for gap detection at every scale |
| `unpaired` | The pairing flow, without holding a base station in sync mode |
| `detached` | Probes unplugged mid-cook — for the null-not-zero rule |
| `celsius` | A mid-cook unit switch — for the canonical-°F conversion |
| `storage-full` | The retention path |
| `ota` | Upload, progress, reboot |
| `long` | 54 days of samples, for pagination and decimation at the limit |

`tools/cookgen` synthesizes new fixtures from a simple thermal model (Newton cooling toward a pit
temperature that itself wanders, plus evaporative-plateau and lid-open events), so scenarios can be
generated rather than recorded.

## 10.4 `tools/lora` — capture and replay

Real protocol work needs real packets, and [02 §2.8](02-smoke-x-protocol.md) lists eight open
questions that only a capture can close.

**There is one board.** It is simultaneously the development target and the only instrument
pointed at the Smoke X. That constraint shapes everything here: capture cannot be a special build
you flash for a session, because flashing it costs a cook and you only get so many briskets.

**Capture is always on, in three layers.**

| Layer | Where | Cost | Answers |
| --- | --- | --- | --- |
| `GET /api/v1/debug/packets` | RAM ring, last 64 payloads | free | "what did it just receive?" |
| `novelty.log` | flash, 64 KB ring, structurally-new packets only | 2.6 % of `cooks` | Q1, Q2, Q3, Q4, Q6, Q8 — over normal use ([02 §2.7](02-smoke-x-protocol.md)) |
| `<id>.raw` | flash, whole session, opt-in per cook | ~345 KB / 24 h, last 2 kept | full-fidelity replay corpus |

`tools/lora/pull.py` fetches all three over HTTP and normalizes them into `.loralog` files under
`protocol/fixtures/lora/`. No serial cable, no reflash, no interrupting a cook.

**Replay is the multiplier.** `tools/lora/replay.py` feeds a `.loralog` into (a) the host unit tests
as a corpus and (b) a firmware build where `app_lora` is swapped for a stub fed from a file — so the
whole decode → store → alarm → API path runs at 100× speed with no Smoke X, no smoker, and no fire.
**One captured cook becomes an unlimited test fixture.** With a single board this is not a
convenience, it is the thing that makes iteration possible at all.

**Capture opportunities**, ordered by what a normal cook yields for free:

| # | Do this | Get | Effort |
| --- | --- | --- | --- |
| 1 | Cook anything, all four probes attached | The first real X4 vectors — every X4 test in the reference is synthetic | none, just cook |
| 2 | Let it run overnight | Q1 (does field 1 ever leave `30`?), interval statistics, real dropouts and RSSI decay | none |
| 3 | Unplug and replug a probe mid-cook | Q4 — probe `state` values beyond `0`/`3` | 10 seconds |
| 4 | Set a tight alarm band so it trips, leave it tripped | Q8 — is `new_alarm` edge or level? | 1 minute |
| 5 | Flip the base between °F and °C mid-cook | The unit-change path, and whether anything else shifts | 1 minute |
| 6 | Re-sync the base while the bridge is unpaired | Q2, Q6 — real X4 sync vectors | 2 minutes |
| 7 | Short the probe jack, open it, exceed range | The rest of Q4 | bench, no cook needed |
| 8 | *Borrow an X2* | Q2 comparison across models | opportunistic |
| 9 | *Borrow a Billows* | Q3, Q5 — the only blocked questions | opportunistic |

Items 1–7 need no equipment beyond what's already in hand and mostly happen by cooking. Because the
novelty log runs unattended, **items 1, 2, 4, and 5 collect themselves** — the evidence is waiting at
`/api/v1/debug/novelty` the next time anyone looks.

## 10.5 Testing

```
                    ┌───────────────────────────────┐
        few         │  on-target smoke + 24 h soak  │  manual, pre-release
                    ├───────────────────────────────┤
                    │  app ↔ tools/sim integration  │  CI, emulator
                    ├───────────────────────────────┤
                    │  widget / golden snapshots    │  CI
                    ├───────────────────────────────┤
       many         │  host unit tests: C and Dart  │  CI, every push, seconds
                    └───────────────────────────────┘
```

**Host unit tests (C).** `firmware/test/`, plain CMake + CTest, no ESP-IDF, no hardware. Covers the
parser, record encode/decode and CRC, session lifecycle and torn-file recovery, retention policy,
alarm rules, and the display page renderers (framebuffer in, PNG out). This is the pattern the
reference established with `test_smoke_x_parser.c` and it is the reason ~60 % of the interesting
firmware logic lives in ESP-IDF-free components ([03 §3.1](03-firmware-architecture.md)).

Specific cases worth naming because they are the ones that bite:

- Every fixture in `protocol/fixtures/lora/`, including malformed and truncated payloads
- A `.smk` truncated at every byte offset within the last record — recovery must converge
- A header with a bad CRC, a bad magic, and a future `version` with a larger `rec_len`
- Retention with a pinned oldest session, and with only the active session present
- Alarm hysteresis: a probe oscillating ±1 °F across its target must fire **once**
- Clock back-patching: a session that starts with no clock and acquires one at t = 40 min

**Dart unit tests.** `domain/` in full: ETA under both models and at their boundary, stall enter/exit
around the thresholds, lid-open detect-then-confirm and detect-then-escalate, LTTB against a
reference implementation, unit conversion round-trips, gap detection.

**Golden tests.** Dashboard, probe tiles, and chart rendered at: no probes, all detached, mid-gap,
alarm active, 15 h of data, 54 days of data, and both themes.

**Integration.** `integration_test` drives a real app build against `tools/sim` replaying an 18-hour
cook at 100×, asserting that the chart renders, alarms fire, sync resumes after a simulated
disconnect, and the cache survives a restart. Runs headless on an emulator in CI.

**On-target, before each release.** A checklist, run manually, recorded in the release notes:

- Pair with a real Smoke X4; confirm the stock ThermoWorks receiver still works throughout
- Unpair and re-pair; confirm neither affects the stock receiver
- Full AP and STA provisioning from the app, including a deliberately wrong password and recovery
  over BLE
- Power-cut mid-cook; confirm the session resumes and the file recovers
- OTA update with a session active; confirm rollback on a deliberately broken image
- **24-hour soak**: heap watermark, task stack watermarks, packet counters, no reconnect storms
- Battery runtime measurement against the [01 §1.6](01-hardware.md) table

## 10.6 CI

| Workflow | Runs | Does |
| --- | --- | --- |
| `firmware-build.yml` | push, PR | `espressif/idf:release-v5.4` container → build, report binary size and free-space delta, upload artifacts |
| `firmware-test.yml` | push, PR | CMake + CTest host tests, with coverage |
| `app.yml` | push, PR | `flutter analyze`, `dart format --set-exit-if-changed`, `flutter test`, build a debug APK |
| `integration.yml` | PR, nightly | Emulator + `tools/sim`, `integration_test` |
| `protocol.yml` | push, PR | Regenerate `protocol/gen/**` and fail on any diff |
| `release.yml` | tag `v*` | Merged `.bin`, release APK, changelog, GitHub Release, publish the web installer |

Binary-size reporting on every PR is worth the two lines it costs: with 2.5 MB app slots and a
BLE + Wi-Fi + filesystem image, the day someone adds a library that doesn't fit should be the day
they find out.

## 10.7 Style and hygiene

- **C**: `.clang-format` carried over from the reference (4-space, 80 col); `clang-tidy` on the
  components; warnings as errors in CI
- **Dart**: `flutter_lints` plus `prefer_final`, `require_trailing_commas`; `dart format` enforced
- **Pre-commit**: the reference ships a `.pre-commit-config.yaml` — extend it with `dart format`,
  `clang-format`, YAML/JSON validation, and a check that `protocol/gen` is current
- **Commits**: Conventional Commits, so the changelog is generated
- **Branches**: trunk-based with short-lived feature branches; `main` always builds and flashes

## 10.8 Releases and flashing

Semantic versioning across the whole repo — firmware and app share a version, because the API
contract binds them and the app enforces a minimum firmware version
([06 §6.5](06-device-api.md)).

`release.yml` publishes:

- `smoke-bridge-heltec-v3-<version>.bin` — merged image, flashable at offset `0x0`
- `smoke-bridge-<version>.apk`
- `smoke-bridge-<version>-ota.bin` — the app-only image for OTA
- Updated `tools/installer/` on GitHub Pages

The browser installer is worth copying from the reference outright: it uses
[`esp-web-tools`](https://esphome.github.io/esp-web-tools/) so a user with Chrome or Edge plugs the
board in, clicks Install, and is done — no Python, no esptool, no toolchain. Ours adds a first-boot
step: after flashing, the page shows *"open the Smoke Bridge app and look for `SmokeBridge-XXXX`"*,
which hands off to the BLE onboarding in [05 §5.7](05-connectivity-and-provisioning.md).

Manual flashing stays documented for people who prefer it:

```bash
python -m esptool --chip esp32s3 -p <PORT> -b 460800 write_flash 0x0 smoke-bridge-heltec-v3-1.0.0.bin
```
</content>
