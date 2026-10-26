# 10 — Test & Release

## 10.1 Test pyramid

| Layer | Runs on | What it proves |
|---|---|---|
| Pure C host tests | CI, no hardware | Parser, record codec, ring geometry/recovery, sync framing, config validation, UI framebuffer |
| Flutter unit tests | CI, no device | Models, freshness, gaps, decimation, sync cursor, time estimation, codecs |
| Flutter widget tests | CI, no device | Live states, History states, settings enabled/disabled, every error copy |
| App integration with a BLE fake | CI | Scan → pair → subscribe → sync → live → reconnect, without a radio |
| Firmware target build | CI | The Heltec image builds with the pinned ESP-IDF |
| Bench tests | Real board | Radio pairing, OLED, button, deep sleep, BLE, power |
| Field cook | Real smoker | The product actually works when nobody is watching |

The first four layers must be green before a bench sitting. Bench time is the
scarce resource; do not use it to discover typos.

## 10.2 Host test requirements

### Firmware

- Parser: all vectors in [02 §2.9](02-smoke-x-protocol.md), malformed input,
  foreign device ID, detached probe, Celsius, Billows attached.
- Record: encode/decode round-trip, CRC failure, sentinel validation, flags.
- Ring geometry: fill, wrap, oldest-sector erase, tail torn record, dual header
  recovery, empty log, full log, generation change, capacity arithmetic.
- Sync: forward/backward, count limits, gap, generation change, disconnect
  mid-batch, MTU 23 and 247 frame reassembly.
- Config: all fields, bad UTF-8, bad target, factory reset, pairing-store
  clear.
- Control: every op, malformed body, unknown op, unsupported Billows, op_id echo.
- UI: framebuffer goldens for the pages/overlays in [07 §7.6](07-display-and-controls.md).
- Invariant test: only the sync handler — plus the B5.0-A Billows handler when
  that build option is compiled — can reach the radio TX function; an out-of-band
  frequency never retunes or transmits, and the Billows frame is allow-listed.

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
- Widgets: Live four probes/sparkline/detached/stale/offline; History empty/
  one probe/gap/filters/ranges/summary; Settings connected/offline/read-only/
  units; every error state.
- No test may require a real phone or board.

## 10.3 Bench matrix

Run in this order; each row is evidence, not a checkbox.

### B0 — Board bring-up

- [ ] Board identity, flash size, antenna fitted.
- [ ] OLED Vext/order, button, battery divider.
- [ ] Deep-sleep wake 20/20, USB attached and detached.
- [ ] On/connected/sleep current; 24 h runtime on the pack.

### B1 — Radio and storage

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
- [ ] History ranges, filters, gaps, pan/zoom, no data, summary sort.
- [ ] Settings units/display timeout/bridge name/Billows.
- [ ] Re-pair the Smoke X4 from the app; stock receiver unaffected.
- [ ] Delete 30/90/all; confirm counts and dates.
- [ ] Factory reset from app; app returns to setup.
- [ ] Phone reboot; app relaunch; data intact.

### B4 — Billows

Per [08 §8.8](08-billows.md). Observation must pass without a control path;
control only after the B5.0 decision.

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
- [ ] Only TX path is the sync ACK, plus the B5.0-A Billows frame if
      `caps.billows_control` is set; invariant test green for the actual build.
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

### Product

- [ ] One overnight cook completed.
- [ ] Stock receiver unaffected.
- [ ] Billows decision recorded and signed; option C has explicit owner
      acceptance; release notes do not overclaim.
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
| Billows control | op tests | only if B5.0/B5.2 | supervised |
| Efficient storage | capacity/recovery | ring rotation | 24 h |
| BLE health/reconnect | fake + state tests | range walk | phone away |
| Settings | widget tests | real writes | — |
| Four temps | widget tests | legibility | — |
| History | unit/widget | full sync | overnight |
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
- Billows: observe only / control (choose one and be specific)
- BLE range and phone-background behavior
- recovery if all bonded phones are lost
```

The release note must match the capability bits. If
`caps.billows_control = 0`, the note says observe only.
