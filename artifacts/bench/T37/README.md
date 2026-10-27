# T37 bench evidence — pair, stock receiver, power cut, detach, units

**Status:** awaiting the T37 sitting (prepared by T25, 2026-10-26). No result in
this directory is hardware evidence yet.

Procedure: [`artifacts/bench/T37/CHECKLIST.md`](CHECKLIST.md).
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

## Manifest

| Step | Capture / artifact | Settings, time, what changed | Result |
|---|---|---|---|
| 0 Preflight | `00-preflight.log` | boot, image hash, recovery line | ⏳ |
| 1 Pair | `01-pair.log`, `01-pair-app.png`, `01-pair-reboot.log` | X4 SYNC gesture, channel, time | ⏳ |
| 2 Stock receiver | `02-stock-receiver.log`, `02-stock-receiver-t0.jpg`, `02-stock-receiver-t1.jpg` | receiver state at t0/t1, time between | ⏳ |
| 3 Power cut | `03a-before-cut.log`, `03b-after-reboot.log`, `03-post-cut-tail.txt` | pack disconnected, last pre-cut seq, recovered next_seq | ⏳ |
| 4 Detach/reattach | `04-detach.log`, `04-oled-detached.jpg`, `04-app-detached.png` | probe number, detach/reattach times | ⏳ |
| 5 °F/°C flip | `05-units.log`, `05-app-celsius-source.png` | X4 value/unit, stored Fahrenheit tenths, flag | ⏳ |

## Pass rule reminders

- Pair: `pair ACK sent` once; persisted pairing survives reboot.
- Stock receiver: updates in both photos while the bridge records; a freeze is
  a real failure.
- Power cut: recovered log keeps earlier records, next sequence continues, state
  `OK`, at most the in-flight record lost.
- Detach: OLED `---`, app `—`, stored sentinel `-32768`, attach bit clear.
- Units: X4 Celsius input, stored Fahrenheit tenths and `flags=0x40`
  (source-Celsius provenance); never store the raw Celsius number.

Every row stays `⏳` until the artifact exists and the date/time is recorded.
