# T26 — Bench prep: cadence and display

## Goal
Prepare the cadence and display report, the serial counter extraction, and the
host page-golden review for the T37 bench run. This task does **not** walk the
OLED or press PRG; those physical checks are executed at **T37** (and the
USB-detached wake/current at **T62**).

## Context (read first)
- [10 §10.3 B1/B2](../design/10-test-and-release.md) — radio/storage and BLE bench rows.
- [02 §2.8](../design/02-smoke-x-protocol.md) — nominal 30 s cadence and the >90 s gap rule.
- [07 §7.7](../design/07-display-and-controls.md) — the display/button bench checklist.
- [07 §7.2](../design/07-display-and-controls.md) — page content and legibility expectations.
- `docs/hardware-verified.md` — results file.
- **Verification:** H (host/CI). **Board:** no. Physical proof is **T37/T62**.
- Depends on T22, T23, and T24.

## Scope
- [ ] Write a cadence-report template that records wall time, packet count,
      expected count, min/mean/max interval, gaps >90 s, RSSI range, and a cause
      for every gap.
- [ ] Add or reuse a host-side parser that extracts those numbers from the
      product serial log (the T10 probe's `to_loralog.py` is the starting point).
- [ ] Confirm the host framebuffer goldens cover every page and overlay; the
      page-walk itself is visual and belongs to T37.
- [ ] Record the T37/T62 evidence rows as ⏳ with the correct owner; do not
      claim a real run.
- [ ] Commit the template and tooling.

## Out of scope
- The 30-minute real run, page walk, display sleep/wake, PRG power off/on, and
  OLED legibility — **T37**.
- The USB-detached 20/20 wake count, currents, and 24 h runtime — **T62**.
- Pairing, stock-receiver independence, power-cut recovery, detached sentinel,
  and °F/°C storage — prepared by T25, executed at T37.
- BLE sync/catch-up and app history → T39–T46.
- Billows observation and target validation → T56–T60.
- Charging/USB-state reporting: outside MVP; no task owns it.
- Any Wi-Fi/HTTP/OTA testing: outside MVP; no task owns it.

## Design notes
- Nominal cadence is 30 s; normal menu-use wobble is 29–76 s. A delta greater
  than 90 s is a visible History gap.
- The report is generated from real T37 serial data, not from estimates.
- The host page goldens are the automated gate now; a human still judges the
  real OLED at arm's length in T37.
- Do not record a physical result you did not observe.

## Done when
- [ ] The cadence-report template is committed.
- [ ] The serial-to-report extractor is committed and tested on the T10 capture.
- [ ] Host page goldens cover every page/overlay and pass.
- [ ] `docs/hardware-verified.md` has ⏳ rows owned by T37/T62 and no false PASS.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
