# T37 bench checklist — pair, stock receiver, power cut, detach, units, cadence, display

**Status:** prepared by T25 (steps 0–5) and T26 (steps 6–7) on 2026-10-26.
**Not executed.** The physical run is T37; this file claims no hardware result.

**Owner:** T37 (V0 end-to-end bench). **Companion files:**
[`docs/hardware-verified.md`](../../docs/hardware-verified.md) (the result rows),
[`README.md`](README.md) (the evidence manifest) and
[`CADENCE-REPORT-TEMPLATE.md`](CADENCE-REPORT-TEMPLATE.md) (filled by
`tools/bench/cadence_report.py`). Design matrix:
[10 §10.3 B0/B1](../../docs/design/10-test-and-release.md).

## Rules for the sitting

- One capture file per step. Never overwrite a capture; add a suffix instead.
- Every step produces a serial log **and**, where the OLED/receiver is the
  subject, a photo or screenshot. A verbal result is not evidence.
- Do not edit a `docs/hardware-verified.md` row to PASS without an artifact
  link. Rows stay `⏳` until the run finishes.
- The stock receiver is independent of the bridge. If it stops updating, that
  is a real T37 failure, not a side effect to waive.
- Record the board image, X4 channel/frequency, units, probe count, UTC time,
  and what changed in the manifest row *before* moving to the next step.

## Preflight

1. Build/flash the V0 image and record its identity:

   ```powershell
   $env:IDF_PYTHON_ENV_PATH='C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env'
   & D:\esp\esp-idf\export.ps1
   Set-Location firmware
   idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
   idf.py -p COM5 -B build flash
   Set-Location ..
   git rev-parse HEAD
   (Get-FileHash firmware\build\sx4_bridge.bin -Algorithm SHA256).Hash
   ```

2. Start the first capture from the repository root (the helper creates the
   parent directory; `--reset` pulses EN/RTS, it does not touch GPIO0/DTR):

   ```powershell
   python firmware/bench/t10_probe/tools/capture.py --port COM5 --reset `
     --out artifacts/bench/T37/00-preflight.log
   ```

3. Preflight pass: the log contains `boot: sequence complete`,
   `sx4.log.flash: recovered ... state OK`, `sx4.radio: configured ... freq=`,
   and `radio_rx started`. Record the image hash and boot time in the manifest.
   Stop the capture with `Ctrl+C`; the file ends with `# closed ...`.

## Step 1 — Real X4 pair

- **Capture:** `artifacts/bench/T37/01-pair.log`
  ```powershell
  python firmware/bench/t10_probe/tools/capture.py --port COM5 --reset `
    --out artifacts/bench/T37/01-pair.log
  ```
- **Action:** put the Smoke X4 into SYNC/pair mode (record the exact gesture and
  the X4's channel). Keep the stock receiver powered and reading the same X4.
- **Pass rule:**
  - exactly one `pair ACK sent on <freq> Hz` (the operating frequency, normally
    918 500 000 Hz), and `tuned to <freq> Hz` if the scan moved;
  - state frames follow: `rx len=...` plus `payload="LMXC[\,..."`;
  - `stored seq=0 ...` or the next expected sequence appears;
  - the OLED/app shows four probes;
  - reboot the bridge and confirm it still reports `configured ... freq=<same>`
    and receives state frames without another SYNC.
- **Artifacts:** `01-pair.log`, `01-pair-app.png` (or OLED photo
  `01-pair-oled.jpg`), and the reboot capture `01-pair-reboot.log`.
- **Record:** X4 channel/frequency, SYNC gesture, probe count, time.

## Step 2 — Stock receiver keeps updating

- **Capture:** `artifacts/bench/T37/02-stock-receiver.log` (run for at least
  90 s while the bridge records).
- **Action:** photograph the stock receiver twice, at least one sample apart,
  with the bridge log timestamps visible or noted.
- **Pass rule:** both photos show the stock receiver updating (different values
  or a fresh reading); it is not frozen, blank, or asking to re-pair. The bridge
  capture shows new `stored seq=` lines over the same interval.
- **Artifacts:** `02-stock-receiver.log`, `02-stock-receiver-t0.jpg`,
  `02-stock-receiver-t1.jpg`.
- **Failure:** any stock-receiver freeze is a T37 failure even if the bridge
  still records.

## Step 3 — USB power cut mid-recording

- **Setup:** make USB the only power source. Disconnect the pack, or use a
  switch that removes both USB and pack. **Pulling USB with the pack connected
  is not a power cut** — the bridge keeps running.
- **Capture:** `artifacts/bench/T37/03a-before-cut.log`
  ```powershell
  python firmware/bench/t10_probe/tools/capture.py --port COM5 `
    --out artifacts/bench/T37/03a-before-cut.log
  ```
- **Action:** note the last `stored seq=N` line; pull power mid-recording. The
  capture helper writes `# serial error: ...` and closes cleanly. Wait a few
  seconds.
- **Capture after reboot:** reconnect USB and start
  `artifacts/bench/T37/03b-after-reboot.log` (do **not** pass `--reset`; the
  reconnect is the power-on).
- **Pass rule:**
  - boot log shows `sx4.log.flash: recovered in ... ms: gen ..., seq 0..M,
    next M+1, ... records, ... state OK`;
  - `M >= N` and earlier sequences are still readable (no `READ_ONLY`, no new
    generation unless the whole log was unusable);
  - new `stored seq=M+1 ...` lines appear and the app syncs past `M`;
  - at most the in-flight record is lost.
- **Artifacts:** `03a-before-cut.log`, `03b-after-reboot.log`. Add
  `03-post-cut-tail.txt` with the last pre-cut lines and the recovery line.
- **Record:** last pre-cut sequence, recovered `next_seq`, records lost.

## Step 4 — Detach / reattach one probe

- **Capture:** `artifacts/bench/T37/04-detach.log`.
- **Action:** detach one probe from the X4; wait at least two state frames;
  photograph the OLED showing `---`; reattach; wait at least two more frames.
- **Pass rule:**
  - while detached, the OLED shows `---` (and the app shows `—`) for that
    probe, never `0.0`;
  - the serial `stored seq=... t=... flags=0x..` line shows `t=-32768` for that
    probe and its attach bit clear;
  - after reattach, a numeric value returns and the attach bit is set.
- **Artifacts:** `04-detach.log`, `04-oled-detached.jpg`,
  `04-app-detached.png`.
- **Host proof (already green):** `sample-log-rec` (`test_detached_never_numeric`),
  `sample-pipe` (detached record), `ui-render` (`---`, never `0.0`).

## Step 5 — X4 °F/°C flip

- **Capture:** `artifacts/bench/T37/05-units.log`.
- **Action:** start in °F, then flip the X4 to °C; wait for a state frame with
  the Celsius units field; photograph the app/OLED. Flip back to °F.
- **Pass rule:**
  - the raw payload in the capture shows the X4 in Celsius;
  - the next `stored seq=... t=... flags=0x..` line carries Fahrenheit tenths
    (e.g. `30.0 °C -> 860`), with the source-Celsius flag `0x40` set;
  - the app/OLED shows the Fahrenheit value, not the raw Celsius number;
  - after flipping back, the flag clears and the numeric values are unchanged
    within the X4's rounding.
- **Artifacts:** `05-units.log`, `05-app-celsius-source.png` (or OLED photo).
- **Host proof (already green):** `sx-protocol` (38.1 °C → 100.5 °F etc.),
  `sample-pipe` (Celsius capture → 824/820/824/820 °F tenths),
  `sample-log-rec` (Celsius provenance flag).

## Step 6 — 30-minute cadence run (four probes, OLED awake then asleep)

- **Setup:** four probes connected to the X4, X4 paired (step 1), phone/app
  optional. Record the X4 frequency, probe count and the wall-clock start.
  Keep the OLED awake for the first part (tap before the display timeout) and
  leave it alone for the second part so it sleeps; record both switch times.
- **Capture:** `artifacts/bench/T37/06-cadence.log` (run for at least 30
  minutes, do not stop early):
  ```powershell
  python firmware/bench/t10_probe/tools/capture.py --port COM5 --reset `
    --out artifacts/bench/T37/06-cadence.log
  ```
- **Action:** let the bridge record the whole time. Menu activity is allowed
  (normal wobble is 29–76 s), but note when it happened so every >90 s gap can
  be explained. Do not reboot the bridge during the run unless a restart is
  itself the observed event; a restart is reported separately and needs a
  cause.
- **Generate the report** from the repository root after stopping the capture:
  ```powershell
  python tools/bench/cadence_report.py artifacts/bench/T37/06-cadence.log `
    --out artifacts/bench/T37/CADENCE-REPORT.md
  ```
- **Pass rule:**
  - capture wall duration is at least 30 minutes and four probes were present;
  - `CADENCE-REPORT.md` has packet count, expected count, min/mean/max interval,
    RSSI min/mean/max and missed samples;
  - every gap > 90 s (and every restart) has a real cause in the report —
    radio dropout, menu activity, bridge restart, power cut, or a named action;
  - no unexplained gap. If one cannot be explained, record that and open a
    follow-up; do not invent a cause.
- **Artifacts:** `06-cadence.log`, `CADENCE-REPORT.md`, and at least one
  `06-run-*.jpg` showing the four probes on the OLED while the capture runs.
- **Host proof (already green):** `python -m unittest discover -s tools/bench -p
  "test_*.py"` parses the real T10 capture and the product-format fixture.

## Step 7 — Display walk, sleep/wake, battery, PRG

- **Capture:** `artifacts/bench/T37/07-display.log` (optional; keep it running
  while walking the pages so tap timing and any reboot are visible).
- **Action and pass rule:**
  1. Walk every visible page: Probes, Connection, Billows (only when detected),
     Bridge. All rows legible at arm's length through the case window, no
     clipped text; the page changes on a tap with no perceptible lag.
  2. Let the display time out. Confirm the panel is off and the bridge still
     records. Wake with a PRG tap: the panel returns to the same page and the
     waking press does not also advance it. Repeat with BLE connected.
  3. Compare the Bridge/Probes battery reading with a DMM or a known pack
     state. The reading must be plausible; unknown must render `—`, never
     `0%`. The ±2 % DMM tolerance and calibrated ratio are T62.
  4. Hold PRG: `POWER OFF` + countdown 2 → 1 → `release to confirm`. Release
     early (before 1.5 s): cancels and the bridge keeps recording. Hold to
     commit: `OFF` frame, then deep sleep. Hold to wake: boots to page 1; an
     early release returns to sleep. A waking press is consumed.
- **Artifacts:** `07-display.log`, `07-pages-*.jpg`, `07-sleep.jpg`,
  `07-wake.jpg`, `07-battery.jpg`, `07-hold.jpg`, `07-cancel.jpg`,
  `07-off.jpg`, `07-wake-hold.jpg`.
- **Host proof (already green):** `ui-render` goldens cover every page and
  overlay (including a coverage assertion) and the sleep/wake path keeps the
  page; `ui-button` covers the 399/400 ms and 1499/1500 ms boundaries and
  waking-press consumption. These do not prove the real panel or button.
- **Do not** copy a host PASS into the OLED/button rows; the physical evidence
  is the photos and the capture.

## Step 8 — Close out

- Fill every row in `artifacts/bench/T37/README.md` (settings, time, change,
  artifact, result), including steps 6 and 7.
- Fill the run conditions, gap causes and display rows in
  `CADENCE-REPORT.md`, then commit it beside `06-cadence.log`.
- Update the radio/storage and display/control rows in
  `docs/hardware-verified.md` with the dated result and links. Leave anything
  not run as `⏳`.
- Commit the checklist, manifest, logs, screenshots and photos. Keep the
  capture files as-is (the `# opened`/`# closed`/`# serial error` markers are
  part of the evidence).
- If a step fails, add a named follow-up task; do not silently waive it.

## Capture helper notes

- `capture.py` opens the port with `dtr=False, rts=False`, so it does not pull
  the GPIO0/PRG net. `--reset` pulses RTS (EN) only.
- A USB power cut is expected to end the capture with `# serial error: ...`;
  that line is evidence of the cut, not a tool failure.
- The helper appends to an existing `--out` file. Use a fresh filename per
  attempt; do not rely on rotation.
- Host checks (no board) before/after the sitting:
  ```powershell
  $env:PATH='C:\msys64\ucrt64\bin;'+$env:PATH
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build --output-on-failure
  ```
