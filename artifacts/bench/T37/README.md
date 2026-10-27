# T37 bench evidence - pair, stock receiver, power cut, detach, units, cadence, display

**Status:** **closed 2026-10-27** — the automatable residual run passed; the
physical-only checks are deferred with named owners (T55/T61/T62/T67) so V0 does
not block the harness. This file records only artifacts that exist.

Procedure: [`artifacts/bench/T37/CHECKLIST.md`](CHECKLIST.md) plus the residual
scope in [`docs/tasks/37-bench-v0-end-to-end.md`](../../../docs/tasks/37-bench-v0-end-to-end.md).
Cadence report template: [`CADENCE-REPORT-TEMPLATE.md`](CADENCE-REPORT-TEMPLATE.md).
Result rows: [`docs/hardware-verified.md`](../../../docs/hardware-verified.md).
Keep this manifest in sync with the files actually committed.

## Residual run — 2026-10-27

| Field | Value |
|---|---|
| Session window | 2026-10-27 11:09–11:29 PDT (18:09–18:29Z) |
| Phone | Pixel 11 Pro Fold, Android 17 / API 37 |
| ADB serial | `adb-67021FDDJ000CF-zWIo1k._adb-tls-connect._tcp` (wireless) |
| App | `com.binbuf.smoke_bridge` 0.1.0, package update 2026-10-27 10:29 |
| Board | Heltec WiFi LoRa 32 V3, MAC `ac:a7:04:38:82:76`, COM5 |
| Firmware | `010bbd3-dirty`, compile 2026-10-27 09:37:04 |
| `sx4_bridge.bin` SHA-256 | `B0A9943BE1CBEA88820BD2671C0CF689B7C27CF6024BA328323563A092AAFC36` |
| X4 | 918.5 MHz, four probes, already synced |
| MTU | 247 |
| Phone bonds | 1/4 |
| Cadence run | pending (physical 30 min) |
| OLED awake/asleep split | pending |

| Step | Artifact | Result |
|---|---|---|
| 0 Preflight | `00-preflight.log` | PASS — fresh X4 frames, `stored seq=243`, live sync |
| 1 Bridge reset | `01-bridge-reboot.log` | PASS — recovered `seq 0..243`, next 244, state OK; app reconnected in 31 s with no passkey prompt |
| 1 MTU / details | `01-technical-details-scrolled.xml` | PASS — MTU 247, 1 bond, firmware 0.1.0, protocol 1.0 |
| 2 Forced drop | `02-bt-off.xml` | PARTIAL — `Reconnecting` attempts 3/6, then `Can’t reach the Bridge`; bounded retry UI passed |
| 2 Adapter off/on finding | `02-bt-restored.xml`, `03-bt-on-recovered.xml`, `03-bridge-details-offline.xml` | **Finding** — after adapter off/on the app still showed stale `Bridge Connected` while the bridge had no central link; required a process restart, then Setup reconnect. Routed to T43 |
| 3 Quiet 30 s sync | `03-quiet-sync.log`, `03-quiet-sync-ui-connected.xml` | PASS — sync pairs 30.18 s apart, no sync card, Live current |
| 1 Wrong-code / re-pair | — | deferred to T55 |
| 4 Cadence | — | deferred to T61 |
| 5 Power cut | — | deferred to T61 |
| 6 Detach / units | — | deferred to T61 |
| 7 OLED / controls / battery | — | OLED walk deferred to T67; battery/PRG deferred to T62 |
| 8 History | `08-history.xml` | PASS — real 24 h shell, four probes, Summary |
| 8 Offline cache | `08-history-failed-cache.xml` | **Finding** — chart retained, but banner says `Can’t reach the Bridge`, not `Showing saved readings`; routed to T43/T45 |
| 9 Billows absent | `01-bridge-details.xml` | PASS — `Billows: Not detected`; no Live card |
| 9 Stock receiver | — | deferred to T61/T63 |
| — Cold launch (expected) | `03-cold-launch.xml` | Setup appears; auto-connect is T43/T46, not this gate |
| — New Live UI | `00-current-live.png`, `00-current-live.xml` | PASS — four probes, BLE/LoRa meters, Min/Max line, 5m change |

The old manifest rows below stay as the template for the remaining physical
steps; do not mark them `?`-free until the artifact exists.

## Common settings (fill once)

| Field | Value |
|---|---|
| Date/time (UTC) | |
| Board MAC | `ac:a7:04:38:82:74` |
| Firmware commit | |
| `sx4_bridge.bin` SHA-256 | |
| Flash command / port | |
| X4 channel / frequency | |
| X4 units at start | |
| Probe count / which probe detached | |
| Stock receiver model | |
| App version / phone | |
| Cadence run start/end (UTC) | |
| OLED awake / asleep times | |

## Manifest

| Step | Capture / artifact | Settings, time, what changed | Result |
|---|---|---|---|
| 0 Preflight | `00-preflight.log` | boot, image hash, recovery line | ⏳ |
| 1 Pair | `01-pair.log`, `01-pair-app.png`, `01-pair-reboot.log` | X4 SYNC gesture, channel, time | ⏳ |
| 2 Stock receiver | `02-stock-receiver.log`, `02-stock-receiver-t0.jpg`, `02-stock-receiver-t1.jpg` | receiver state at t0/t1, time between | ⏳ |
| 3 Power cut | `03a-before-cut.log`, `03b-after-reboot.log`, `03-post-cut-tail.txt` | pack disconnected, last pre-cut seq, recovered next_seq | ⏳ |
| 4 Detach/reattach | `04-detach.log`, `04-oled-detached.jpg`, `04-app-detached.png` | probe number, detach/reattach times | ⏳ |
| 5 °F/°C flip | `05-units.log`, `05-app-celsius-source.png` | X4 value/unit, stored Fahrenheit tenths, flag | ⏳ |
| 6 Cadence (30+ min) | `06-cadence.log`, `CADENCE-REPORT.md`, `06-run-*.jpg` | four probes, X4 frequency, OLED awake/asleep times, menu activity | ⏳ |
| 7 Display/controls | `07-display.log`, `07-pages-*.jpg`, `07-sleep.jpg`, `07-wake.jpg`, `07-battery.jpg`, `07-hold.jpg`, `07-cancel.jpg`, `07-off.jpg`, `07-wake-hold.jpg` | page walk, sleep/wake, battery vs DMM/known state, PRG off/on | ⏳ |

## Pass rule reminders

- Pair: `pair ACK sent` once; persisted pairing survives reboot.
- Stock receiver: updates in both photos while the bridge records; a freeze is
  a real failure.
- Power cut: recovered log keeps earlier records, next sequence continues, state
  `OK`, at most the in-flight record lost.
- Detach: OLED `---`, app `—`, stored sentinel `-32768`, attach bit clear.
- Units: X4 Celsius input, stored Fahrenheit tenths and `flags=0x40`
  (source-Celsius provenance); never store the raw Celsius number.
- Cadence: at least 30 min, four probes, OLED awake and asleep; packet count,
  expected count, interval min/mean/max, RSSI range and missed samples in
  `CADENCE-REPORT.md`; every gap > 90 s and every restart has a cause.
- Display: every page legible at arm's length; sleep/wake keeps the page;
  battery plausible or `—`; PRG countdown, early-release cancel, power off and
  hold-to-wake all observed.

Every row stays `⏳` until the artifact exists and the date/time is recorded.
