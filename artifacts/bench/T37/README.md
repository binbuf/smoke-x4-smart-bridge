# T37 bench evidence — pair, stock receiver, power cut, detach, units, cadence, display

**Status:** awaiting the T37 sitting (prepared by T25 and T26, 2026-10-26). No
result in this directory is hardware evidence yet.

Procedure: [`artifacts/bench/T37/CHECKLIST.md`](CHECKLIST.md).
Cadence report template: [`CADENCE-REPORT-TEMPLATE.md`](CADENCE-REPORT-TEMPLATE.md).
Result rows: [`docs/hardware-verified.md`](../../docs/hardware-verified.md).
Keep this manifest in sync with the files actually committed.

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
