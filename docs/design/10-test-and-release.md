# 10 — Test & Release

## 10.1 Test pyramid

| Layer | Runs on | What it proves |
|---|---|---|
| Pure C host tests | CI, no hardware | Parser, record codec, ring geometry/recovery, sync framing, config validation, UI framebuffer |
| Flutter unit tests | CI, no device | Models, freshness, gaps, decimation, sync cursor, time estimation, codecs, formatters |
| Flutter widget tests | CI, no device | Every UI state in [13 §13.4](13-ui-implementation-contract.md), both themes, 320 dp, semantics and every error copy |
| UI goldens / screenshots | CI, no device | The approved prototype visual set; intentional changes only |
| App integration with a BLE fake | CI | Scan → pair → subscribe → sync → live → reconnect, without a radio |
| Firmware target build | CI | The Heltec image builds with the pinned ESP-IDF |
| Bench tests | Real board | Radio pairing, OLED, button, deep sleep, BLE, power |
| Field cook | Real smoker | The product actually works when nobody is watching |

### Pull-request CI jobs

Every pull request runs the six jobs in `.github/workflows/ci.yml`; their names
are stable because they are the attribution boundary when a build goes red
(ADR 0019).

| # | Job | Command(s) | Fails on |
|---|---|---|---|
| 1 | protocol generate + drift check | `make protocol`, `git diff --exit-code -- protocol/gen`, `make protocol-check`, `make protocol-test` | stale or hand-edited generated output, bad codec vectors |
| 2 | C host tests | `cmake -S firmware/test -B firmware/test/build -G Ninja`, build, `ctest` | parser/log/geometry/task-budget regressions |
| 3 | firmware build | `idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build` | the Heltec image no longer builds or the image guard finds Wi-Fi/HTTP/OTA |
| 4 | Flutter analyze/test | `flutter analyze`, `flutter test test/view_state_test.dart test/ui_state_matrix_test.dart`, `flutter test` | app compile/analyze failure, UI state or layout regression, BLE-fake regression |
| 5 | UI screenshot/golden check | `flutter test tool/ui_screenshots_test.dart` | any pixel change against `app/screenshots/` |
| 6 | no-network/no-OTA dependency guard | `python -m unittest discover -s tools/ci`, `python tools/ci/check_forbidden_deps.py` | `http`, WebSocket, MQTT, OTA packages, release network permissions or ESP-IDF network components |

Job 1 regenerates before checking drift, so a YAML edit without regenerating
turns the build red rather than silently repairing it in CI. Job 5 runs on the
same host platform and Flutter version that produced the approved baseline.
`legacy/` is not built in any job.

The first five layers must be green before a bench sitting. Bench time is the
scarce resource; do not use it to discover typos.

## 10.2 Host test requirements

### Firmware

The suite lives in `firmware/test` and is a plain CMake project with `ctest` as
the entry point; it links pure-C sources only. Fixtures are committed under
`protocol/fixtures/lora/` with provenance, and `parser-vectors.tsv` is the
machine-readable vector corpus. Run it with:

```bash
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
```

- Parser: all vectors in [02 §2.9](02-smoke-x-protocol.md), malformed input,
  foreign device ID, detached probe, Celsius, Billows attached.
- Record: encode/decode round-trip, CRC failure, sentinel validation, flags.
- Ring geometry: fill, wrap, oldest-sector erase, tail torn record, dual header
  recovery, empty log, full log, generation change, capacity arithmetic.
- Sync: forward/backward, count limits, gap, generation change, disconnect
  mid-batch, MTU 23 and 247 frame reassembly.
- Config: all active fields, bad UTF-8, reserved Billows fields ignored, factory
  reset, pairing-store clear.
- Control: every op, malformed body, unknown op, `set_billows_target` always
  `unsupported`, op_id echo.
- UI: framebuffer goldens for the pages in [07 §7.6](07-display-and-controls.md).
- Invariant test: only the sync handler can reach the radio TX function; an
  out-of-band frequency never retunes or transmits. Assert there is no Billows
  transmit path.

### App

- Codec vectors shared with firmware (same bytes, same fields).
- Freshness boundaries (45/90/600 s), no zero for detached.
- Gap splitting at 90 s.
- LTTB/min-max preserves spikes and never invents points.
- Sync:
  - first sync recent-first,
  - backward backfill to `min_seq`,
  - forward catch-up,
  - generation change keeps old data,
  - device rollover records a permanent gap,
  - disconnect mid-batch resumes at the last stored seq,
  - duplicate records are idempotent.
- DB: bulk insert, range query, deletion by date, DB survives relaunch.
- BLE fake: permission denied, Bluetooth off, bond failure, wrong passkey,
  stale bond, MTU 23, MTU 247, notification loss, disconnect.
- Widgets: every state in [13 §13.4](13-ui-implementation-contract.md). At
  minimum: Live healthy/aging/stale/frozen/detached/no-probes/offline-cache/
  no-cache/sync/error/Billows; History default/ranges/custom/filters/probe-empty/
  all-empty/gap/estimated/overwritten/Cooks/Cook view/full-screen; Settings
  connected/offline/read-only/units/appearance/storage/Bridge details/
  confirmations; setup and pairing failures.
- Layout: 320 dp and 390 dp, dark and light, no overflow; chart summary and
  Summary table are the accessible equivalents.
- Copy: no banned terms from [12](12-copy-and-label-review.md), no raw exception
  text, no prototype/simulation copy on product screens.
- No test may require a real phone or board.

## 10.3 Bench matrix

Run in this order; each row is evidence, not a checkbox.

### B0 — Board bring-up

- [ ] Board identity, flash size, antenna fitted.
- [ ] OLED Vext/order, button, battery divider.
- [ ] Deep-sleep wake 20/20, USB attached and detached.
- [ ] On/connected/sleep current; 24 h runtime on the pack.

### B1 — Radio and storage

Execute B1 at T37 with
[`artifacts/bench/T37/CHECKLIST.md`](../../artifacts/bench/T37/CHECKLIST.md):
every step names its serial capture, committed artifact and pass/fail rule. The
rows in `docs/hardware-verified.md` stay `⏳` until that sitting records
evidence.

- [ ] Pair with a real X4; the stock receiver keeps updating.
- [ ] Four probes, detached probe, °C/°F flip.
- [ ] Pull power mid-cook; reboot; earlier records survive; only the last
      record is at risk.
- [ ] Fill the ring (or simulate) and confirm oldest-sector rotation.
- [ ] Confirm `min_seq`/`max_seq`/`generation` through BLE.

### B2 — BLE

- [ ] Advertising starts at boot and after disconnect.
- [ ] Passkey shown on OLED; phone bonds; wrong code rejected.
- [ ] Bond survives reboot; reconnect has no passkey prompt.
- [ ] MTU negotiated value recorded.
- [ ] `live` notifications at sample cadence; one missed notification is caught
      by sync.
- [ ] Full sync 24 h and full ring (or the seeded 338,400-record fixture); resume
      after disconnect.
- [ ] `config` read/write; `control` set_time; `result` matching.
- [ ] Forget this phone (current bond only); factory reset (all bonds); power off.
- [ ] 4-phone pairing limit.

### B3 — App

- [ ] Fresh install → permission primer → scan → pair → live.
- [ ] Close/reopen app; auto-reconnect; history preserved.
- [ ] Walk out of range; stale/offline; walk back; reconnect.
- [ ] History ranges/filters/custom range, gaps, pan/zoom, Chart help, Summary
      sort, Cooks and the Cook view, full-screen chart, estimated and overwritten
      states.
- [ ] Settings units/appearance/display timeout/bridge name; Billows is
      status-only.
- [ ] Re-pair the Smoke X4 from the app; stock receiver unaffected.
- [ ] Delete 30/90/all; confirm counts and dates.
- [ ] Factory reset from app; app returns to setup; saved-history escape works.
- [ ] Phone reboot; app relaunch; data, tab, filters and theme intact.
- [ ] Walk the UI state matrix in [13 §13.4](13-ui-implementation-contract.md)
      on a real phone; no fixture or prototype chrome is reachable.
- [ ] 320 dp layout, dark/light, and screen-reader summary pass on the target
      phone.

### B4 — Billows

Per [08 §8.8](08-billows.md). Observation only. Confirm attached/detach, target
when validated (else `—`), units conversion, and no fan-running/duty claim.
There is no control path to test. A post-MVP receive-only RF survey is separate
and does not gate the release.

### B5 — Field

- [ ] One supervised cook with the phone present.
- [ ] One overnight cook with the phone away for ≥ 6 h; reconnect and view the
      whole gap-free (or explicitly gapped) History.
- [ ] One power cut during a cook.
- [ ] One “phone left at home” day; bridge records; sync later.
- [ ] Stock receiver works throughout.

## 10.4 24-hour soak

Run on the release image, on USB power first, then on the pack.

**Conditions:**

- real Smoke X4 sending (or a fixture transmitter),
- BLE advertising for most of the run, with a phone connected for at least 4 h,
- OLED asleep,
- Billows observation if available,
- app syncing periodically.

**Criteria (fixed before the run):**

| Metric | Pass |
|---|---|
| Reboots/panics | 0 |
| `heap_free` floor | ≥ 80 KB |
| `heap_free` slope | ≥ −256 B/h |
| `heap_min` | ≥ 64 KB |
| Missed samples | 0 unexplained; any gap has a radio cause |
| Log recovery | clean after the run |
| BLE reconnects | bounded; no storm |
| App sync | catches up without duplication |
| Battery | ≥ 24 h on the pack with OLED sleep (separate run if needed) |

Commit the raw stats trace and a short report. If a criterion fails, that is a
finding, not a reason to lower the bar after the fact.

## 10.5 Release checklist

### Firmware

- [ ] Version string set and shown in `info`/OLED.
- [ ] `idf.py build` clean; host tests green.
- [ ] Partition table matches [01 §1.8](01-hardware.md); no OTA slots.
- [ ] Factory reset clears config, log, and bonds.
- [ ] Only TX path is the sync ACK. `caps.billows_control = 0`; invariant test
      green for the actual build.
- [ ] 24 h soak report committed.
- [ ] Merged image + flash command documented.
- [ ] `docs/hardware-verified.md` updated with dated results.

### App

- [ ] `flutter analyze` clean; `flutter test` green.
- [ ] Release APK signed (or a documented debug-only bench build).
- [ ] Android permissions verified on Android 12+ and one older device if
      supported.
- [ ] No HTTP/notification/foreground-service permissions or dependencies.
- [ ] Fresh install, upgrade, and “clear data” paths tested.
- [ ] App version and bridge firmware version visible in About.
- [ ] Privacy statement: no cloud, no account.
- [ ] UI parity with [13](13-ui-implementation-contract.md) verified; screenshots
      regenerated; 320 dp, dark/light and screen-reader checks pass.
- [ ] No Experimental lab entry, simulation control, fixture value or
      prototype-only copy in the release build.
- [ ] Strings centralized and locale time/date/number formatting used; banned
      copy terms test green.

### Product

- [ ] One overnight cook completed.
- [ ] Stock receiver unaffected.
- [ ] Billows decision recorded as observation only; owner acceptance is in
      `docs/billows-decision.md`; release notes say "Set the target on the
      Smoke X4."
- [ ] Known limitations written down (no OTA, no alarms, no iOS, BLE range,
      battery runtime, lost-phone recovery).
- [ ] A new user can follow the README from a blank phone/board to live data
      without external prose.

## 10.6 Acceptance matrix

| Feature | Host | Bench | Field |
|---|---|---|---|
| PRG on/off | gesture unit + golden | 20/20 wake, current | — |
| PRG pages | renderer goldens | legibility | — |
| Auto advertising | state test | scanner sees it | — |
| Passkey pairing | codec/state tests | bond/wrong code/reboot | — |
| Forget/factory reset | op tests | all paths | — |
| Record without phone | ring tests | power cut | overnight |
| Four probes/detached | parser/codec | real probes | real cook |
| Billows observe | parser/codec | real Billows | cook |
| Billows control | — | not implemented | — |
| Efficient storage | capacity/recovery | ring rotation | 24 h |
| BLE health/reconnect | fake + state tests | range walk | phone away |
| Settings | widget tests | real writes | — |
| Four temps | widget tests | legibility | — |
| History | unit/widget | full sync | overnight |
| Cooks / Cook view | unit/widget | real archive | overnight |
| UI state matrix | widget/golden | phone walk | field use |
| Accessibility / 320 dp | widget/semantics | phone walk | — |
| Copy baseline | banned-term test | review | — |
| App retention/delete | DB tests | — | user test |
| Device rotation | seeded full-ring test | reduced/accelerated partition | long cook (if it wraps) |

## 10.7 Release notes template

```
Smoke X4 Bridge vX.Y.Z

Firmware:
- ...
App:
- ...

Verified:
- board, phone model, Android version
- 24 h soak result
- overnight cook result

Known limitations:
- USB firmware update only
- no alarms/notifications (use the Smoke X4's alarm)
- Billows: observed only; set the target on the Smoke X4
- BLE range and phone-background behavior
- recovery if all bonded phones are lost
```

The release note must match the capability bits. The MVP always has
`caps.billows_control = 0`, so the note says observed only.
