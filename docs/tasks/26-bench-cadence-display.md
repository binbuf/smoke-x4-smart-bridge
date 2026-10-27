# T26 — Bench: 30-minute cadence and display

## Goal
A real 30+ minute run with all four probes and the OLED awake/asleep proves the observed packet cadence, RSSI, and display/button/power path. The report explains every gap and confirms the pages are legible and the power cycle works.

## Context (read first)
- [10 §10.3 B1/B2](../design/10-test-and-release.md) — radio/storage and BLE bench rows; this task takes the cadence and display subset.
- [02 §2.8](../design/02-smoke-x-protocol.md) — nominal 30 s cadence, observed 29–76 s wobble, and the >90 s gap rule.
- [07 §7.7](../design/07-display-and-controls.md) — the display/button bench checklist.
- [07 §7.2](../design/07-display-and-controls.md) — page content and legibility expectations.
- `docs/hardware-verified.md` — results file.
- **Verification:** B (bench/board). **Board:** yes.
- Depends on T22, T23, and T24.

## Scope
- [ ] Run for at least **30 minutes** with all four probes connected and the OLED both awake and asleep.
- [ ] Record packet counts versus expected, RSSI, observed intervals, and any missed samples.
- [ ] Walk all visible pages.
- [ ] Test display sleep/wake.
- [ ] Test the battery reading against the DMM/known state.
- [ ] Test PRG power off/on, including the hold countdown and wake confirmation.
- [ ] Record any gap with its cause (radio dropout, menu activity, bridge restart, etc.).
- [ ] Commit the cadence report.

## Out of scope
- Pairing, stock-receiver independence, power-cut recovery, detached sentinel, and °F/°C storage → T25.
- 24 h soak, field cook, and release acceptance → M6 field hardening.
- BLE sync/catch-up and app history → Phase 3 BLE tasks (T27–T38) and M3 (T39–T46).
- Billows observation and target validation → M5 (T56–T60); no Billows TX/control path exists.
- Charging/USB-state reporting: outside MVP; no task owns it.
- Any Wi-Fi/HTTP/OTA testing: outside MVP; no task owns it.

## Design notes
- Nominal cadence is 30 s; normal menu-use wobble is 29–76 s. A delta greater than 90 s is a visible History gap, so 60 s would draw false gaps ([02 §2.8](../design/02-smoke-x-protocol.md)).
- Count valid state packets, parse/CRC failures, foreign IDs, sync beacons, ACK attempts, last packet age, and RSSI/SNR; use these to explain gaps rather than guessing.
- Page walk: `Probes`, `Connection`, `Billows` (only after detection), `Bridge`. A waking press only wakes the display.
- Display sleep happens after the configured timeout (default 60 s) and must not change the page. Wake via a button press or a BLE connect (BLE connect is wired later; use the button here).
- Power off: hold ≥ 1.5 s, countdown, release commits; early release cancels. Hold from sleep boots to page 1; early release returns to sleep.
- Battery unknown is `—`; do not treat it as 0% or infer charging.
- Use the real OLED through the case window and judge legibility at arm's length in daylight and at night.
- Record results in `docs/hardware-verified.md` and commit the cadence report with the raw counts.

## Done when
- [ ] A 30+ minute run with four probes and the OLED awake/asleep is complete.
- [ ] Packet counts vs expected, RSSI, observed intervals, and missed samples are recorded.
- [ ] The cadence report is committed; any gap has a cause.
- [ ] All visible pages have been walked and are legible.
- [ ] Display sleep/wake works and does not change the page.
- [ ] The battery reading is checked and unknown renders as `—`.
- [ ] PRG power off/on works, including early-release cancel and hold-to-wake.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
