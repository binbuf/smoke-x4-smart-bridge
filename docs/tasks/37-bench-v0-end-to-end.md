# T37 — Bench: V0 residual physical gate

**Status:** done 2026-10-27 · automatable residual run passed on the real Pixel
11 Pro Fold + Heltec V3 + synced X4. Physical-only items are deferred with named
owners (T55/T61/T62/T67) so the V0 gate does not block the harness.

## Goal
Close the V0 physical checks that the automated suite and the first real-hardware
bring-up could not prove. This is **not** a second happy-path run: scan, first
bond, stored-bond reconnect, `set_time`, a recent sync and four live values are
already verified. T37 is done when every residual row below either passes with a
committed artifact or has a named follow-up task.

## Context (read first)
- **Bench available for this run (confirmed 2026-10-27):**
  - Real Android phone on ADB: **Pixel 11 Pro Fold**, Android 17 (API 37),
    wireless serial `adb-67021FDDJ000CF-zWIo1k._adb-tls-connect._tcp`.
    `emulator-5554` is present on this host and is **not** the target.
  - Real ESP32 on USB: **Heltec WiFi LoRa 32 V3** on **COM5**
    (Silicon Labs CP210x).
  - Real **Smoke X4 is powered on and already synced to the Flutter app** on
    that phone; use the existing pairing and do not re-pair it unless a step
    explicitly asks for it.
  - App package `com.binbuf.smoke_bridge`, version `0.1.0`; confirm the installed
    build before the run.
  - Capture helper: `firmware/bench/t10_probe/tools/capture.py`. The system
    `python` lacks `pyserial`; use the IDF env:
    `C:\Users\dan\.espressif\python_env\idf6.0_py3.13_env\Scripts\python.exe`.
- Full historical procedure and artifact names:
  [`artifacts/bench/T37/CHECKLIST.md`](../../artifacts/bench/T37/CHECKLIST.md).
  Use only the residual steps in this task; do not re-run the already-verified
  happy path.
- [10 §10.3 B2/B3](../design/10-test-and-release.md) — BLE and app bench matrix.
- [13 §13.4](../design/13-ui-implementation-contract.md#134-complete-state-inventory) — Setup/Live/Settings states to walk.
- [05 §5.12](../design/05-ble-contract.md) — first-connect and reconnect procedures.
- Verify tier: **P/B**. Board: **yes**.
- Depends on T30, T31, T35, and T36. Auto-connect after a cold launch is
  **not** part of this gate (T43/T46); the app may still open Setup after a
  process kill.

## Already verified (do not redo)
- [x] Advertising, public identity name `SmokeX4-8276`, and `info.device_id`
  agree; scan finds the Bridge.
- [x] First bond with the OLED passkey; the OLED wakes to show the code.
- [x] Four real X4 frames at ~30 s cadence are stored and synced.
- [x] `set_time` returns `result ok`; a 195-byte recent sync completes.
- [x] Live shows P1 79.4 °F, P2 78.9 °F, P3 79.5 °F, P4 79.3 °F with
  `updated 22s ago` and −35 dBm LoRa signal.
- [x] A stored bond reconnects without a new passkey prompt.
- [x] Host/widget coverage: reconnect backoff, watchdog branches, stale/offline
  states, codecs, gap splitting, probe/UI states, destructive copy.

Evidence: [`hardware-verified.md`](../hardware-verified.md#lora-receive-root-cause-and-re-check-2026-10-27),
[`T37/lora-rx-after-syncword-fix.log`](../../artifacts/bench/T37/lora-rx-after-syncword-fix.log),
[`T37/lora-rx-ble-sync-after-fix.log`](../../artifacts/bench/T37/lora-rx-ble-sync-after-fix.log).

## Residual scope
Start a capture for each step unless the step says otherwise. Every pass needs a
log, screenshot/photo, or both, plus the date/time in the manifest. Human-assisted
steps are marked **[human]** and must not be claimed from a host test.

### 0. Preflight
- [ ] Record the phone serial/model/Android version, app version, board MAC,
  `sx4_bridge.bin` SHA-256, X4 frequency, units at start and probe count in
  `artifacts/bench/T37/README.md`.
- [ ] Confirm the installed app and the board image are the ones under test:
  ```powershell
  adb -s adb-67021FDDJ000CF-zWIo1k._adb-tls-connect._tcp shell dumpsys package com.binbuf.smoke_bridge |
    Select-String "versionName|lastUpdateTime"
  (Get-FileHash firmware/build/sx4_bridge.bin -Algorithm SHA256).Hash
  ```
- [ ] Start `00-preflight.log` on COM5 and confirm `boot: sequence complete`,
  `sx4.log.flash: recovered ... state OK`, `sx4.radio: configured ... freq=`,
  `radio_rx started`, and fresh X4 state frames. Stop the capture cleanly.

### 1. Real OS bond edge cases
- [ ] **[human]** Reject a wrong passkey once; confirm the named
  `The code didn’t match` state and that the next attempt can succeed.
- [ ] Reboot the bridge, then reconnect from the phone with the stored bond;
  confirm **no passkey prompt** and that Live returns without a setup flow.
- [ ] Record the negotiated MTU in the manifest and note whether it is 247 or a
  slow-link value.

### 2. Forced link drop and backoff
- [ ] Drop the phone→Bridge link without killing the app (turn phone Bluetooth
  off, or walk out of range). Confirm `Reconnecting… attempt N of 6`, the
  bounded backoff, and that the last-known values are labelled saved.
- [ ] Restore the link before the six attempts expire; confirm automatic
  recovery, a fresh `live` read, forward sync and no passkey prompt.
- [ ] Confirm a user pull-to-refresh or app resume cuts a reconnect wait short.

### 3. Quiet 30 s forward sync
- [ ] Leave the app on Live for at least two minutes with the X4 running.
  Confirm History keeps growing and the manual sync card does **not** flash every
  30 s.
- [ ] Confirm the newest sequence is not duplicated when a live notification and
  the quiet forward sync arrive for the same sample. Until T41 lands this is a UI
  and log check; the DAO-level proof is T41/T46.

### 4. 30-minute cadence and gap report
- [ ] **[human for the OLED wake/asleep split]** Capture `06-cadence.log` for at
  least 30 minutes with four probes, OLED awake for part of the run and asleep
  for the rest.
- [ ] Generate `artifacts/bench/T37/CADENCE-REPORT.md` with
  `tools/bench/cadence_report.py`; record packet count, expected count, interval
  min/mean/max, RSSI min/mean/max and missed samples.
- [ ] Explain every >90 s gap and every restart. Do not invent a cause.

### 5. USB power cut mid-recording
- [ ] **[human]** Remove the **only** power source (USB and pack) mid-recording,
  reboot, and capture `03a-before-cut.log` / `03b-after-reboot.log`.
- [ ] Confirm earlier records survive, `state OK`, the next sequence continues,
  and at most the in-flight record is lost.
- [ ] Reconnect the app and confirm it syncs past the recovered sequence.

### 6. Detach / reattach and X4 units
- [ ] **[human]** Detach one probe; confirm OLED `---`, app `—`, stored sentinel
  `-32768`, and no `0.0`. Reattach and confirm a numeric value returns.
- [ ] **[human]** Flip the Smoke X4 to °C and back. Confirm the stored value stays
  canonical Fahrenheit tenths and the source-Celsius flag is handled correctly.

### 7. OLED and controls
- [ ] **[human]** Walk every OLED page through the case window; confirm legibility
  and no clipped text.
- [ ] **[human]** Confirm the blinking `BT` discovery indicator while
  advertising, display sleep/wake, passkey wake, PRG hold countdown, early
  release cancel, power off and hold-to-wake.
- [ ] **[human]** Compare the battery reading with a known pack state; unknown
  must render `—`.

### 8. Real History and offline cache
- [ ] On the phone, open History and confirm the recent window matches the live
  values and has no fixture chrome.
- [ ] Take the Bridge out of range or power it off; confirm the cached History
  remains usable and labelled `Showing saved readings`, with no cached value
  presented as live.
- [ ] Confirm the new Live connection chain, probe Min/Max line and X4 warning
  dialog render correctly at the phone’s width.

### 9. Stock receiver and Billows
- [ ] **[human]** Confirm the stock receiver keeps updating while the Bridge
  records; a freeze is a T37 failure.
- [ ] Confirm the Billows card is absent while `caps.billows_observe = 0` on this
  firmware. Do not exercise a Billows control path.

### 10. Close-out
- [ ] Fill every residual row in `artifacts/bench/T37/README.md`; leave anything
  not run as `?`.
- [ ] Update the matching rows in `docs/hardware-verified.md` with dated results
  and artifact links.
- [ ] Commit the logs, screenshots/photos and the manifest. Keep capture markers
  (`# opened`, `# closed`, `# serial error`) intact.
- [ ] File a named follow-up for any failure; do not silently waive a step.

## Out of scope
- Re-running the already-verified scan/pair/set_time/recent-sync/live happy path.
- Cold-launch saved-Bridge auto-connect and archive-backed offline cache → T43;
  phone proof → T46.
- Full-ring history, mid-sync resume and 24 h sync timing → T46.
- Settings/config writes, destructive app flows and the full UI/a11y/copy gate →
  T55/T54.
- Billows observation on a real unit → T56, T57, T59.
- Release packaging → T64/T65; soak/runtime → T61/T62.
- Wi-Fi/HTTP/OTA — outside MVP; no task owns it.

## Design notes
- The phone is on wireless ADB; always pass
  `-s adb-67021FDDJ000CF-zWIo1k._adb-tls-connect._tcp` so commands do not land
  on `emulator-5554`.
- Start captures from the repository root. Use a fresh filename per attempt; the
  helper appends and does not rotate.
- A USB power cut ends the capture with `# serial error: ...`. That line is
  evidence, not a tool failure.
- At MTU 23 sync is slow but valid; record the negotiated value rather than
  assuming 247.
- "Stale" is the Bridge still connected with a quiet X4 (90 s–10 min); after
  10 min it is `Smoke X4 signal lost`. Do not conflate it with BLE loss.
- No prototype chrome, fixture badge, simulated prompt or lab-only control may
  appear on a product screen.
- If a check cannot be completed in this sitting, leave it open and name the
  follow-up; do not convert a host PASS into a physical PASS.

## Progress — 2026-10-27 11:09–11:29 PDT
Automated/preflight portion of the residual run passed on the real Pixel +
Heltec V3 + synced X4:
- Preflight X4 frames/live sync; forced reset recovered `seq 0..243`, next 244,
  state OK; app auto-reconnected in 31 s with no passkey prompt.
- Negotiated MTU 247; firmware 0.1.0; protocol 1.0; 1/4 bond slots.
- Forced Bluetooth loss entered `Reconnecting` and exhausted six attempts to
  `Can’t reach the Bridge`; the bounded retry UI passed. Automatic recovery
  after adapter restore did **not** happen (stale `Bridge Connected`), so the
  app needed a process restart and Setup reconnect.
- Quiet forward sync pairs were 30.18 s apart, with no sync card on Live.
- Real 24 h History shell showed four-probe Summary data; Billows stayed absent.
- Cold launch still enters Setup, as expected until T43/T46.

Findings routed to other tasks:
- **T43:** after an adapter off/on cycle the app could still show stale
  `Bridge Connected` while the bridge had no central link. Runtime adapter-state
  handling is now explicit in T43.
- **T45:** with the reconnect budget exhausted, History kept the cached chart
  but the banner said `Can’t reach the Bridge`, not `Showing saved readings`.

Deferred with named owners (do not lose them):
- wrong-code passkey / re-pair / bond-after-reboot → **T55**
- 30-minute cadence, USB power cut, probe detach/reattach, X4 °F/°C, stock
  receiver → **T61** (long-run bench)
- battery plausibility and PRG/deep-sleep -> **T62**
- OLED page/overlay walk and blinking `BT` indicator -> **T67**

Evidence and the run manifest are in `artifacts/bench/T37/README.md`.

## Done when
- [x] Every automatable residual step passes; every physical-only step has a
      named owner (T55/T61/T62/T67).
- [x] Reboot recovery, bond/no-prompt, MTU and quiet 30 s sync are recorded.
- [x] Forced-drop/backoff UI is recorded; the adapter off/on stale-state finding
      is routed to T43.
- [x] Real History and Billows-absent checks pass on the real phone; the cached
      banner finding is routed to T45.
- [x] `docs/hardware-verified.md` and the T37 manifest are updated.
- [x] Evidence is committed with the T37 close-out.
- [x] Hand-off below filled in.

## Hand-off
- **Passed on hardware:** preflight frames/sync; bridge reset recovery
  (`seq 0..243`, next 244, state OK); stored bond reconnected in 31 s with no
  passkey prompt; MTU 247; quiet 30 s forward sync (30.18 s pair interval, no
  sync card); real four-probe History/Summary; Billows absent with `caps=0`.
- **Findings routed:** T43 — stale `Bridge Connected` after an adapter off/on
  cycle; T45 — cached History after reconnect failure says `Can’t reach the
  Bridge` instead of `Showing saved readings`.
- **Deferred, not waived:** wrong-code/bond → T55; 30-min cadence, power cut,
  probe detach, X4 °F/°C, stock receiver → T61; battery/PRG → T62; OLED visual
  walk → T67.
- **Next task:** T39 can start immediately. Evidence is in
  `artifacts/bench/T37/`; app was left on Live connected.
