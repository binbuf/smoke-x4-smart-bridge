# ADR 0033 — Cadence evidence is extracted from serial uptime, not estimated

**Status:** accepted (T26, 2026-10-26)

## Context

T37 must prove a 30-minute run at the nominal 30 s cadence: packet count versus
expected, observed intervals, RSSI, missed samples, and a cause for every gap
greater than 90 s (design 02 §2.8). The T10 probe's `to_loralog.py` already
parsed `t10cap: RX` lines, but the product image logs a different shape:
`sx4.radio: rx len=... rssi=... snr=...` followed by
`sx4.sample: stored seq=...`. The serial capture also has no per-line wall
clock, and a bridge restart resets the ESP-IDF uptime.

Estimating these numbers from the OLED or from sequence numbers alone would
invent evidence. The report needs a reproducible, auditable extraction.

## Decision

1. **Samples come from stored records first.** The extractor counts
   `sx4.sample: stored seq=` lines. Only when a capture has no product records
   does it fall back to T10 `state26` RX lines. Sync beacons and ACKs are never
   samples.
2. **Intervals use device uptime within one boot.** The ESP-IDF `I (ms)` prefix
   is the sample clock, so serial latency does not distort the interval. A boot
   banner or backwards clock starts a new epoch; no interval is computed across
   it.
3. **Restarts are gap rows, not intervals.** A restart resets the clock, so its
   duration is unknown. It gets its own row and a required cause rather than a
   fabricated delta.
4. **Expected count uses capture wall time.** The `# opened`/`# closed` markers
   from `capture.py` give the run duration; expected is the rounded duration
   divided by 30 s. Without both markers the extractor uses the first-to-last
   sample span and records a warning.
5. **RSSI comes from the RX line immediately before the stored record.** A
   stale packet from an earlier frame is not attached. Missing RSSI is reported
   as unknown, not zero.
6. **Causes stay human-owned.** The extractor writes `_unrecorded — fill at
   T37_` for every radio gap. Automation may not invent a cause for a dropout,
   menu wobble or restart.
7. **The host gate is the page/overlay matrix.** `ui-render` goldens must have a
   case for every `UI_PAGE_*` and every `UI_OVERLAY_MASK_*`; that gate is
   separate from the real-panel legibility walk at T37.

## Consequences

- `tools/bench/cadence_report.py` is the single producer of the cadence numbers;
  `CADENCE-REPORT-TEMPLATE.md` is the committed contract and its cause/display
  rows remain for T37.
- The extractor is tested on the real T10 capture and a product-format fixture
  (`tools/bench/test_cadence_report.py`, also run in CI's host-test job).
- A capture with no samples, or a report with an unexplained gap, fails T37
  rather than producing a plausible-looking summary.
- T37/T62 can change the report wording, but not the measurement semantics,
  without superseding this ADR.
