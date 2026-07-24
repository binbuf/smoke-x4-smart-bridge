# Hardware verification results — Heltec WiFi LoRa 32 V3

Results of the [01 §1.8](design/01-hardware.md) bench checklist (tasks V1.1–V1.6).
**Template status: every box below is ⏳ until a measured number or an explicit
outcome replaces it.** No box may be silently blank (V1.6).

How to measure: flash the bench diagnostic (`make bench-flash`, or
`idf.py -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.heltec-v3;sdkconfig.bench" build flash monitor`
from `firmware/`) and transcribe its `BENCH`-prefixed log lines. The capture
runbook lives at [`tools/lora/README.md`](../tools/lora/README.md).

## V1.1 — battery connector and first power-up

| Check | Result |
| --- | --- |
| SH1.25-2 pack polarity vs board silkscreen (meter BEFORE connecting) | ⚠ 2026-07-22 — **visually verified only** (red wire aligned with the `+` silkscreen; owner decision to skip metering, no DMM used). The pack works, but this row is downgraded, not green: meter any *replacement* pack before its first connection. |
| LoRa antenna fitted before first power | ✅ fitted before the first power-up and never removed |
| Board boots on battery | ✅ 2026-07-22 — USB pulled with the pack connected; OLED and LED stayed alive; recovered cleanly on replug |

## V1.3 — GPIO37 gate and battery divider (retires R6, gates F12)

| Check | Result |
| --- | --- |
| GPIO37 LOW gates the VBAT divider (ADC divider_ON vs divider_OFF differ) | ✅ 2026-07-22 — the gate works, **but the sense is inverted vs the bench's assumption: GPIO37 HIGH enables the divider**, LOW disconnects (reads 0 mV). F12 must drive it HIGH to sample. |
| Divider ratio at pack voltage #1 (DMM ÷ `adc_divider_ON`) | ✅ adc=788 mV with the pack connected → pack ≈ 3.86 V at ×4.9. No DMM used: the verdict comes from Li-ion range arithmetic (×2.0 would put the pack at 1.58 V, impossible; ×4.9 lands mid-charge). |
| Divider ratio at pack voltage #2 | ⏳ unresolved — no second charge state measured. F12 self-calibrates against the 4.2 V full-charge plateau instead; a DMM point can refine later. |
| Verdict: ×4.9 (Heltec forum) or ×2.0 (ESPHome) or other | ✅ **×4.9** |

R6 is retired: GPIO37 is usable (with the HIGH-enable sense above) and
battery reporting is possible.

## V1.4 — button, LED, Vext, OLED I²C

| Check | Result |
| --- | --- |
| GPIO0 PRG reads reliably after boot; debounce survives boot strapping | ✅ 2026-07-22 — three presses logged cleanly (held 319/210/180 ms), no bounce artifacts, no phantom events |
| GPIO35 LED is active-HIGH and dims under LEDC PWM | ✅ visually confirmed fading both directions on the 5 s bench cycle |
| GPIO36 LOW required for the OLED rail (`vext-gate` line: off=NO_ACK, on=ACK) | ✅ off=NO_ACK, on=ACK + full SSD1306 init. **Gotcha for F11:** the I²C pull-ups hang off the switched rail — probing with the rail off wedges the `i2c_master` controller; recreate the bus after powering Vext (fixed in bench.c, applies to app_ui). |
| OLED I²C @ 400 kHz stable with Wi-Fi AP active (`i2c` line: err count after ≥10 min) | ✅ 1,160 transfers / **0 errors** over >10 min with the soft-AP up |
| OLED I²C stable with **BLE** active | **deferred → M3** (no BLE stack yet) |

## V1.5 — current draw and brownout

| Check | Result |
| --- | --- |
| AP mode, OLED on (est. ~145 mA) | **unresolved** — no current meter available; estimates stand |
| STA mode, modem sleep (est. ~70 mA) | **unresolved** — same |
| Real runtime on the 3000 mAh pack | ⏳ deferred — pack verified working; a full runtime soak is a future unattended run (pairs naturally with M6's V3 24 h soak) |
| Brownout when Wi-Fi AP starts on a depleted pack? | **unresolved** — needs a deliberately depleted pack; retest at M6 hardening |

## Deferred to later milestones (V1.6 table — do not close here)

| Deferred check | Why | Closes at |
| --- | --- | --- |
| Free heap ≥ 150 KB with AP + NimBLE + httpd + both LittleFS mounts | Our stack doesn't exist yet | F9 / F10 (M2–M3) — **F9.13 provisional; V3a.1 below re-measures** |
| LoRa RX with BLE advertising **and** a WebSocket client streaming | Same | V3a.1 (M3) — see the M3 section below |
| OLED I²C stable with BLE active | Reference has no BLE | V3a.1 (M3) — see the M3 section below |

## M1 exit gate (F3.9, F5.11) — verified on the board 2026-07-22

| Check | Result |
| --- | --- |
| F3.9 pair → unpair → re-pair, stock receiver unaffected | ✅ Full cycle under our firmware: (1) flash-over-reference **adopted the existing pairing via the F7.2 v0→v1 migration** (booted CONFIRMED on 918.5 MHz, no re-sync); (2) erase = unpair; (3) fresh sync → single 15 B ACK **sent only after retuning** → CONFIRMED on first state message. Stock ThermoWorks receiver confirmed updating before, between, and after. |
| F5.11 session resumes across a real power cut | ✅ USB pulled mid-cook; on replug the §4.5 ladder reopened **the same session** (`store event RESUMED, session 00000001`, 416 ms into boot), wrote the `power restored` auto-mark, and continued appending. Evidence dumped off the flash via esptool+littlefs: [`protocol/fixtures/board/f511-power-cut.smk`](../protocol/fixtures/board/f511-power-cut.smk) — t monotonic `0..61 → 91..241` across the cut, marks at the seam, zero >45 s gaps. |
| Board-found bug (the reason F5.11 exists) | The first power-cut run exposed a uint32 underflow: post-resume `t` was computed as `uptime − started_uptime`, but uptime restarts with the boot → `t ≈ 4.29e9`. Fixed with an anchored resume base (`cook_session_resume_base_t`), host-tested, re-verified on the board in the committed evidence above. |

## M2 exit gate (F8.8, F9.12, F9.13, A14.4) — bench sitting 2026-07-22

| Check | Result |
| --- | --- |
| F8.8 AP mode on the board | ✅ `SmokeBridge-8274` (MAC-derived), channel auto-picked (6), generated PSK, DHCP served; this PC joined and held the AP through the whole sitting |
| F8.8 STA + supervision on the board | ✅ mechanically, via the credential-free drill: `POST /config/wifi` (bogus SSID) answered `accepted/applying_in_ms:500` and the reply survived its own teardown; STA attempt failed fast; **fallback AP back on air in ~5 s** (never unreachable); retry ladder observed at the 1/2-minute marks; restore `POST {"mode":"ap"}` echoed the PSK and returned to AP. **Real-credential STA join deferred to M3's BLE onboarding by owner decision** — credentials belong to the provisioning flow, not a bench file. mDNS-from-LAN verification rides on that same deferral. |
| F9.12 exit-gate curls | ✅ over the AP from this PC: `/status` (full contract JSON), `/sessions`, 766 samples as CSV (767 lines) **and** raw records (12,256 B = 766×16), WebSocket delivering `hello` + current sample + a live 30 s push (`OK: live push verified`, twice) |
| F9.13 heap with everything running | ✅ `free_heap 190,468 / min_free_heap 180,716` at first measure; 189,064/183,852 on a later boot — comfortably above the 150 KB gate. **Provisional per the plan caveat**: NimBLE does not exist until M3; V3a re-measures with BLE live. |
| A14.4 Android AP-routing proof | ⏳ **partial by design**: the binder-alone/shim-alone matrix needs app UI that arrives in M4 (recorded in the plan); the shim-half phone-browser check was pending user observation at sitting close. |
| Board-found defects (all fixed + committed, `5864bb8` + follow-ups) | sys_evt stack 2304→4096; httpd stack 4 KB→8 KB (TLS-trample LoadProhibited); WS fan-out moved off the event loop onto the ws_push task (3072→4096 — the lwip send path runs there); **IDF v6 never calls the ws URI handler on the handshake GET** — open path moved to `ws_post_handshake_cb`; ghost WS clients purged via the httpd `close_fn`. |

## M3 exit gate (F10.10, A6.7, A8.4, V3a.1) — ⏳ the sitting is owed

All 24 board-free M3 tasks are done (host 21/21, app 225/225, both images build
with NimBLE). These four rows are the whole remainder, and they are **one
sitting** ([§12.6 rule 7](design/12-task-planning-notes.md)) in this order —
V3a.1 last, because it needs everything else running.

Flash: `idf.py -B build/heltec-v3 '-DSDKCONFIG=sdkconfig.heltec-v3' -p COMx flash monitor`
(ESP-IDF PowerShell; quote args containing `=` or `.`).

| Check | Result |
| --- | --- |
| **F10.10** advertises with the §2 scan-response blob (verify against the byte tables with a BLE scanner app) | ⏳ |
| **F10.10** a phone bonds via the passkey **shown on the real OLED** — F11a's whole output proving itself in one glance | ⏳ |
| **F10.10** an unauthenticated `wifi_config` write from an unbonded central is rejected | ⏳ |
| **F10.10** bonds survive a reboot; forget-all (`device_control` op 8) clears them | ⏳ |
| **F10.10** record the negotiated ATT MTU and any OEM oddity, with the phone's OEM + Android version | ⏳ |
| **A6.7** the scan list shows the blob-decorated entry (`pit … °F · … h … m`) before connecting | ⏳ |
| **A6.7** `live_state` notifications arrive at the sample cadence; `control(set_units)` round-trips `ok` | ⏳ |
| **A6.7** kill Wi-Fi on the phone → the ConnectionManager race falls through to the BLE lane, degraded-capability notice surfaces | ⏳ |
| **A8.4** the wizard provisions a **working STA connection entirely over BLE** | ✅ 2026-07-22 — `net_status up ip=10.50.50.38 ssid=Home_WiFi` over BLE, then a real `GET /api/v1/status` → **200** from the phone, 4.9 s from config write to verified. The exit gate's first clause. (The full A8.4 row still needs the factory-reset start and the wrong-password branch.) |
| **A8.4** factory-reset (10 s PRG), run the wizard, **enter a wrong Wi-Fi password first**, recover over the still-connected BLE link, correct it, finish on the **real home network** | ⏳ |
| **A8.4** closes F8.8's deferred real-credential STA join — the row M2 deferred to exactly this flow | ⏳ |
| **A8.4** with STA genuinely up: `smokebridge.local` and `dns-sd -B _smokebridge._tcp` from a LAN machine (the mDNS-from-LAN rider) | ⏳ |
| **A8.4** the hardware is never touched between factory reset and STA-up except to hold PRG at the start | ⏳ |
| **V3a.1** OLED I²C error count with BLE active, ≥ 10 min (the V1.4 method) | ⏳ **not measurable in the product image** — M3's panel is dark except while a passkey is showing (F11a scope), so there is no sustained I²C traffic to count errors against, and `app_ui` has no error counter. Either re-run the V1.4 bench image with BLE enabled, or defer to M5/F11b when the display is always on. Recorded rather than silently ticked. |
| **V3a.1** LoRa RX cadence unaffected with BLE advertising **and** a WebSocket client streaming | ✅ 2026-07-22 — 165 s soak with a phone bonded+connected over BLE, a WebSocket client streaming, and STA up: **5 packets, one per ~33 s**, `last_packet_s_ago` cycling 7→23 s. Sub-GHz is independent of the 2.4 GHz contention, confirmed rather than assumed. A separate 111 s run saw samples at 0/20/50/80/111 s — steady 30 s cadence through an interleaved HTTP request. |
| **V3a.1** free heap with AP + NimBLE + httpd + both LittleFS mounts — closes F9.13's provisional | ❌ **FAILS THE 150 KB TARGET.** Measured with STA up + NimBLE bonded/connected + httpd + a live WebSocket + LoRa RX: `free_heap` steady **≈ 90.5 KB**, `min_free_heap` **80,116 B = 78.2 KB**. Stable over the window (no leak — free_heap moved < 0.6 KB across 165 s), so this is a **level** problem, not a growth one. F9.13's provisional 180.7 KB is superseded: NimBLE's real cost here is ≈ 90–100 KB against the [01 §1.4](design/01-hardware.md) allowance of 35–45 KB. **This is the design conversation the plan requires before M4**, not a bench tuning exercise — see the open question below. |

### Open design question — the heap target (raised by V3a.1, 2026-07-22)

The 150 KB target is missed by roughly half. The plan
([M3](tasks/M3-ble-and-provisioning.md), [M2–M6](tasks/M2-M6-outline.md)) is explicit that this is a
design conversation held **before M4**, and that shrinking things ad hoc at the bench is not the
task. Stating the options rather than picking one:

1. **The target is wrong.** 150 KB was set in [01 §1.4](design/01-hardware.md) against an estimated
   NimBLE cost of 35–45 KB. The measured cost is roughly double. 78 KB of headroom on a device that
   is stable, leak-free, and doing everything it will ever do may simply be *fine* — the number to
   defend is "does it survive a 24 h cook", which is M6's V3 soak.
2. **Buffer counts.** `CONFIG_BT_NIMBLE_MSYS1_BLOCK_COUNT`, the Wi-Fi RX/TX buffers already trimmed
   in `sdkconfig.defaults`, and LittleFS cache sizes are all levers.
3. **Concurrency caps.** 2 WebSocket clients and 4 httpd sockets each cost real RAM.

**Nothing in M4 depends on this** — M4 is Flutter-side and consumes no device heap. M5 (F12/F13)
and M6's soak do. The decision is owed before M5, and the 24 h soak (V3) is what should settle it.

**Bring-up already done 2026-07-22** (firmware flashed to COM5, debug APK
installed on the test phone), with one board-found defect fixed before the
sitting proper:

| Check | Result |
| --- | --- |
| Firmware boots with NimBLE | ✅ `boot complete: 16/16 steps`; `app_ble: NimBLE up: SmokeBridge-8274, 0 bond(s) stored` |
| F11a.5 panel bring-up on the real OLED | ✅ `app_ui: display up: SSD1306 @400 kHz, passkey overlay only (M3)` — the V1.4 rail-before-bus order works in the product |
| §2 advertising interval policy | ✅ `adv_itvl_min/max=400` = 250 ms — the fast window for 60 s after boot, as specified |
| Task stacks | ✅ `32256 B declared across 9 tasks` — the renegotiated 32 KB budget |
| **F10.10** bond via the passkey on the real OLED | ✅ Android reports `le_authenticated: T`, `ble_enc_key_size: 16` — an **MITM-authenticated** LTK, not Just Works. The §3 security profile and F11a's passkey overlay both prove out in one observation |
| **A6.4** reconnect to a bonded bridge skips pairing | ✅ Cold app start → tap the bridge → straight through to the mode choice, **no passkey prompt** |
| **A6.6** no location prompt | ✅ `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` granted `USER_SET`; `ACCESS_FINE_LOCATION` never requested — `neverForLocation` holds on Android 16 |
| **A6.7** blob-decorated scan entry | ✅ `SmokeBridge-8274 · pit 88 °F · 6 h 40 m` rendered **before connecting**, from live LoRa data |
| **A6.7** negotiated MTU | ✅ `negotiated ATT MTU 247 (chunk 244)` — the full ask; `history_preview` fits a single PDU |
| **F10.7** Wi-Fi scan over BLE | ✅ 18 APs streamed as 15 correctly-indexed `wifi_scan_result` notifications, rendered in the picker |

**Two board-found defects, both fixed and re-verified:**

| Defect | Detail |
| --- | --- |
| **Event-bus subscribers silently overwrote each other** (firmware) | `bridge_event_handler_register` routed every subscriber through the same `guarded_trampoline` function pointer, and `esp_event_handler_register` de-duplicates by (base, id, function) — so **the second component to subscribe to an event replaced the first**, logging only `handler already registered, overwriting`. Latent since M0; M3 made it bite, because `app_ble` subscribes to SAMPLE/ALARM/NET and would have displaced `app_api`'s WebSocket fan-out (the live push F9.12 verified). Fixed with `esp_event_handler_instance_register`, which permits the same function with different args. Re-flashed: **0 warnings**. |
| **`RadioGroup` painted nothing** (app) | The network picker rendered a **completely blank screen — AppBar included** — with **no exception logged** and every build method completing normally (instrumentation confirmed `NET build n=16 scanning=false` on a black screen). Bisected on hardware to Flutter's `RadioGroup`/`RadioListTile` (new in 3.32); replacing it with plain `ListTile`s renders correctly. **No unit test could have caught this** — `RadioGroup` renders fine under `flutter test`; only the device showed it. Recorded in the code at the call site so it is not reintroduced. |
| **The handoff address was discarded** (app) | `net_status` carries the bridge's IP (§5.2) and the wizard threw it away, then probed `smokebridge.local` (Dart's HttpClient resolves through the platform resolver, which does not answer `.local`) and `192.168.4.1` (the AP just left). A healthy bridge read as unreachable. The settled `net_status` address is now the known-address lane, as §5.7's own diagram specifies. |
| **Re-provisioning did nothing, silently** (firmware) | Two stacked no-ops. `app_net_core_set_mode` returned early when the mode was unchanged — so re-provisioning an STA bridge never re-associated, and pointing it at a *different* SSID persisted the new credentials while keeping the old association. Fixing that exposed the second: `esp_wifi_connect()` on an already-connected station does nothing at all, so the core sat in `STA_CONNECTING` emitting **no event**, and the phone waited out its full 20 s handoff budget in silence. Now a provisioning write forces re-association, tearing the old association down first, with a one-shot flag so the self-inflicted disconnect does not trip the fallback ladder. |
| **Success looked exactly like failure** (app) | On completion the route navigated home immediately, so "Your bridge is ready" existed for one frame and the user landed on the M2 placeholder reading *"Not connected"*. A successful provision was indistinguishable from a failed one — reported as "doesn't look like it connected" about a run that had just returned HTTP 200. Onboarding no longer navigates itself; the final screen names the address it reached and waits to be dismissed. |

Test phone for the sitting: **Samsung SM-A166U (Galaxy A16 5G), Android 16**,
over wireless adb. `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` are `granted=false` —
`flutter_blue_plus` requests them at first scan, so **the first tap of "Set up a
bridge" should raise the system permission prompt**. That prompt appearing (and
*not* a location prompt) is itself an A6.6 observation worth recording.

**Go in with eyes open on V3a.1.** M2 measured `min_free_heap` ≈ 180.7 KB without
NimBLE; subtracting the [01 §1.4](design/01-hardware.md) allowance of 35–45 KB
lands at **136–146 KB, potentially under the 150 KB target** — and M3 also added
~5.5 KB of task stacks (`ble_push`, and M2's `ws_push`). If the margin is gone,
that is a **design conversation before M4** (buffer counts, concurrency caps, or
the target itself), opened as its own recorded question. Shrinking things ad hoc
at the bench is explicitly not this task.

## M4 exit gate (A15.5, A14.4b) — ⏳ the sitting is owed

All 26 board-free M4 tasks are done (app suite 448/448, firmware untouched
at 21/21). These two rows are the whole remainder and are **one sitting**
([§12.6 rule 7](design/12-task-planning-notes.md)), A15.5 first because
A14.4b observes the screens it installs.

Nothing in M4 was verifiable on hardware from this session: **the test
phone was unplugged and `adb` unavailable**, so no APK was built,
installed, or run. Everything below is therefore genuinely open, and the
app-side claims it will check are the ones `flutter test` cannot make —
that a real phone renders these screens, that a real BLE handoff lands on
the dashboard, and that an exported CSV survives the trip to a real file
system.

| Check | Result |
| --- | --- |
| **A15.5** install the APK on the real phone and reach the dashboard | ⏳ |
| **A15.5** onboard from a factory reset over BLE, choose a mode, and land on a live dashboard (not the wizard's own success screen) | ⏳ |
| **A15.5** watch a live cook update at the sample cadence, with the pit and food tiles readable at arm's length | ⏳ |
| **A15.5** scroll 15 hours of **real** history — chips, pan, pinch, double-tap, and the jump-to-now pill | ⏳ |
| **A15.5** export a CSV and open it off the phone; it must match the device's `format=csv` for the same range | ⏳ **note:** the export writes a real file to the app's documents directory and the UI names the path. **There is no share sheet** — handing the file to another app needs a platform intent, and a platform intent needs a device to test it on, so it is this row's first job rather than an untested guess committed now |
| **A15.5** record the phone's OEM, Android version, and time to first render | ⏳ |
| **A14.4b** binder-on / shim-on in AP mode: does the dashboard route? | ⏳ |
| **A14.4b** binder-off / shim-on | ⏳ |
| **A14.4b** binder-on / shim-off | ⏳ |
| **A14.4b** closes A14.4's *partial by design* row above (§5.8.1 predicts neither mitigation alone is sufficient — confirm or correct it) | ⏳ |

## V2 — capture campaign results

| Capture | Status |
| --- | --- |
| V2.2 sync beacon (6-comma) + our ACK | ✅ 2026-07-21 → [`x4-events-10min.loralog`](../protocol/fixtures/lora/x4-events-10min.loralog): sync field0=`000000` (not the X2's `020001`), freq 918.5 MHz decoded, our `SUCCESS` ACK captured |
| V2.1 X4 state traffic (26-comma), overnight | ⏳ overnight pending. 10-min event choreography done 2026-07-21: 37 state packets, hot-water curve, 2 real dropouts, cadence wobble during menu use |
| Stock ThermoWorks receiver still works after our pairing | ✅ 2026-07-22 — confirmed updating after the reference ACK (V2.2) and re-confirmed three times through our firmware's adopt/erase/re-pair cycle (F3.9 above) |
| Q1 / Q4 / Q8 / units manipulations performed | ✅ 2026-07-21 — Q1 never left `30`; Q4 detach `state=3` **freezes last temp, does not zero** (reattach jumps straight 3→0; shorted-jack state still uncaptured); Q8 trailing `new_alarm` is **edge-triggered**, one packet per alarm event; units flip confirms field 2 (1=°F, 0=°C), temps in tenths of active unit, alarm bands in whole degrees of active unit |
