# T37 cadence and display report — 30-minute run

**Status:** generated skeleton. Fill the run conditions and every ⏳ row from the
real T37 sitting; the measured cadence columns are written by
`tools/bench/cadence_report.py` and must not be edited by hand. Do not claim a
result before the capture and photos exist in this directory.

**Capture:** `{{CAPTURE}}` · **Generated from:** `tools/bench/cadence_report.py`

## Run conditions (fill from the T37 manifest)

| Field | Value |
|---|---|
| Date/time (UTC) | |
| Firmware commit | |
| `sx4_bridge.bin` SHA-256 | |
| X4 frequency / channel | |
| Probe count | 4 |
| OLED state | awake for the first part, asleep for the second (record the times) |
| Phone/app connected | |
| Menu activity during the run | |
| Notes (weather, distance, obstacles) | |

## Cadence

| Field | Measured |
|---|---|
| Capture opened | {{OPENED}} |
| Capture closed | {{CLOSED}} |
| Capture wall duration | {{WALL_DURATION}} |
| Observed sample span (first to last) | {{OBSERVED_SPAN}} |
| Stored samples (packets) | {{SAMPLE_COUNT}} |
| Expected at 30 s nominal | {{EXPECTED_COUNT}} |
| Missed samples (expected − observed) | {{MISSED_COUNT}} |
| Radio RX packets seen (all classes) | {{RADIO_PACKET_COUNT}} |
| Interval min / mean / max | {{INTERVAL_MIN}} / {{INTERVAL_MEAN}} / {{INTERVAL_MAX}} |
| Gaps > {{GAP_THRESHOLD}} | {{GAP_COUNT}} |
| Bridge restarts in capture | {{RESTART_COUNT}} |
| RSSI min / mean / max | {{RSSI_MIN}} / {{RSSI_MEAN}} / {{RSSI_MAX}} |
| Sequence range | {{FIRST_SEQ}} … {{LAST_SEQ}} |
| Missing sequence numbers | {{MISSING_SEQ}} |
| Boots in capture | {{BOOT_COUNT}} |

Expected count is the capture wall duration divided by the nominal 30 s cadence
(rounded). With no `# opened`/`# closed` pair, the extractor uses the
first-to-last sample span and says so under Warnings.

## Gaps > 90 s and restarts

Every row needs a cause before this task is accepted. Use the T37 session notes:
radio dropout, menu activity, bridge restart, power cut, or a named test action.
If a gap cannot be explained, record that fact and open a follow-up; do not
invent a cause.

{{GAPS_TABLE}}

## Extractor warnings

{{WARNINGS}}

## Display and controls — T37 manual checks

These are physical observations. The host goldens only prove the renderer; they
do not prove the panel, the case window, the button or the battery.

| Check | Expected | Result | Evidence |
|---|---|---|---|
| Walk all visible pages | Probes, Connection, Billows (only when detected), Bridge all legible at arm's length; no clipped rows | ⏳ | `06-pages-*.jpg` |
| Display sleeps after the timeout | panel off; no redraw while asleep | ⏳ | `06-sleep.jpg` |
| Wake by PRG tap | panel on, page unchanged by the waking press | ⏳ | `06-wake.jpg` |
| Display sleep/wake with BLE connected | panel returns to the same page; link stays up | ⏳ | `06-sleep-ble.jpg` |
| Battery reading vs DMM / known state | plausible pack voltage and percent; unknown renders `—`, never `0%` | ⏳ | `06-battery.jpg` |
| PRG hold countdown | 2 → 1 → `release to confirm` | ⏳ | `07-hold.jpg` |
| Early release before 1.5 s | cancels, bridge stays on and keeps recording | ⏳ | `07-cancel.jpg` |
| Commit hold | `OFF` frame, then deep sleep | ⏳ | `07-off.jpg` |
| Hold to wake from deep sleep | boots to page 1; early release returns to sleep | ⏳ | `07-wake-hold.jpg` |
| Waking press consumption | the press that wakes does not also change the page or start a countdown | ⏳ | `07-wake-press.jpg` |

## Sign-off

| Field | Value |
|---|---|
| Run ≥ 30 minutes with four probes and OLED awake/asleep | ⏳ |
| Every gap has a cause | ⏳ |
| Cadence report committed beside the raw capture | ⏳ |
| Display/control rows filled and linked in `docs/hardware-verified.md` | ⏳ |
| T37 owner / date | |
