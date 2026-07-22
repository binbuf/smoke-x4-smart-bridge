# M2–M6 — Epic-level outline

**Deliberately not planned in detail.** [§12.1](../design/12-task-planning-notes.md): _"M4–M6 depend
on facts that don't exist yet (real packet formats, measured RAM headroom, how Android behaves on the
actual phone). Planning them now produces fiction that later gets rewritten."_

Plan each milestone as the previous one exits. What follows is scope, dependencies, exit gates, and
the handful of planning decisions worth recording now so they aren't rediscovered later.

---

## M2 — Network and API

| Epic      | Scope                                                                             | Design                                                               |
| --------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| **F8**    | `app_net` — AP/STA state machine, backoff retry, mDNS, DNS hijack, captive shim   | [05 §5.3–5.5, §5.8.1](../design/05-connectivity-and-provisioning.md) |
| **F9**    | `app_api` — httpd, REST, **streamed** history, WebSocket fan-out                  | [06](../design/06-device-api.md)                                     |
| **F4.4**  | `/api/v1/debug/packets` and `/debug/novelty` — the read half of M1's capture work | [02 §2.7](../design/02-smoke-x-protocol.md)                          |
| **T4.1b** | `tools/lora/pull.py` — fetch ring, novelty, and `.raw` over HTTP                  | [10 §10.4](../design/10-repo-tooling-and-testing.md)                 |
| **A5**    | `HttpTransport` — REST + WebSocket                                                | [08 §8.1](../design/08-flutter-app.md)                               |
| **A7**    | `ConnectionManager` — racing discovery, cache, manual entry, backoff              | [08 §8.4](../design/08-flutter-app.md)                               |
| **A14**   | `platform/network_binder` (Kotlin), permissions flow, manifest                    | [05 §5.8](../design/05-connectivity-and-provisioning.md)             |

**Exit gate:** `curl` retrieves a 24-hour cook as CSV and as raw records; a WebSocket client receives
live samples; AP↔STA switching works from `curl`; **free heap ≥ 150 KB with everything running.**

### Decisions to carry into planning

**A14 is planned with F8, as one unit of work.** AP-mode routing on Android is the classic "works on
my phone" trap ([§12.8](../design/12-task-planning-notes.md)): the phone probes
`connectivitycheck.gstatic.com`, our AP has no internet, Android marks the network unvalidated and
keeps the default route on cellular — so requests to `192.168.4.1` go out the mobile interface and
vanish. **Both** mitigations are required; neither alone is sufficient. A manual-IP escape hatch that
always works ships alongside them.

**Close the heap question here.** [§12.9](../design/12-task-planning-notes.md) defers "free heap with
everything running" to F9/F10. Add an explicit measurement task at the end of F9: log free heap and
per-task stack watermarks, compare against the [01 §1.4](../design/01-hardware.md) budget. If it is
tight, that is a design conversation, not a task. This also closes three boxes deferred from V1.6.

**F9 inherits a structural rule, not an optimisation.** No handler ever materialises a full response
in RAM; history streams from flash in ≤ 2 KB chunks. This is the direct lesson from the reference's
16 KB `json_str` ceiling — an X4 starts returning `500` at roughly 600 records (~5 h). F5.10 already
built the streaming read path so F9 has nothing to invent.

**The `www` partition stays declared and unformatted** (D13). `app_api` mounts it only if it formats
cleanly and contains an `index.html.gz`; otherwise unmatched `GET`s return a small built-in page
pointing at the app.

---

## M3 — BLE and provisioning

| Epic     | Scope                                                                                       | Design                                                      |
| -------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| **F11a** | `app_ui` **partial** — SSD1306 driver, framebuffer primitives, PNG harness, passkey overlay | [07 §7.1, §7.3, §7.6](../design/07-display-and-controls.md) |
| **F10**  | `app_ble` — NimBLE, Bridge Control Service, bonding, OLED passkey                           | [05 §5.6](../design/05-connectivity-and-provisioning.md)    |
| **A6**   | `BleTransport` — flutter_blue_plus + GATT                                                   | [05 §5.6](../design/05-connectivity-and-provisioning.md)    |
| **A8**   | Onboarding wizard — scan, bond, passkey, mode choice, handoff                               | [05 §5.7](../design/05-connectivity-and-provisioning.md)    |
| **V3a**  | Coexistence checks deferred from V1.6                                                       | [01 §1.8](../design/01-hardware.md)                         |

**Exit gate:** a phone provisions the bridge from factory-reset to a working STA connection entirely
over BLE, **and can recover from a deliberately wrong Wi-Fi password without touching the hardware.**

### Decisions to carry into planning

**F11 splits, and the first half lands here.** [§12.6 rule 4](../design/12-task-planning-notes.md)
requires F11 before F10 because the BLE passkey is displayed on the OLED — without it, bonding needs
a serial fallback that then has to be removed. But the paged UI and gesture machine belong in M5 with
the alarm engine. So M3 takes only what F10 needs: display init, the framebuffer, the 12×24 font, and
the passkey overlay. Everything else in [07](../design/07-display-and-controls.md) waits.

**Build the framebuffer→PNG harness first.** [§12.8](../design/12-task-planning-notes.md) flags F11 as
pixel work — a 12×24 font table, a sparkline, inverted regions, an 8-row layout at 21 columns. Page
renderers are pure functions of a snapshot struct, so the whole display layer is host-testable and
reviewable in CI without the board. The reference already ships
`scripts/render_oled_preview.py` to copy from.

**Budget F10 generously.** Android BLE is Android BLE — bonding, MTU negotiation, and notification
reliability all vary by OEM (R7). `live_state` is already designed at 16 B to fit the default 23-byte
ATT MTU, so a negotiation failure degrades rather than breaks. Everything else chunks from the
negotiated MTU. Test on the same three OEM builds as R3.

---

## M4 — Flutter MVP

| Epic    | Scope                                                     | Design                                 |
| ------- | --------------------------------------------------------- | -------------------------------------- |
| **A9**  | Dashboard, probe tiles, session controls                  | [08 §8.6](../design/08-flutter-app.md) |
| **A10** | Chart — LTTB, gaps, min/max envelope, overlays, pan/zoom  | [08 §8.7](../design/08-flutter-app.md) |
| **A11** | Sessions list, detail, stats, export                      | [08 §8.6](../design/08-flutter-app.md) |
| **A12** | Settings — probes, alarms, network, device, advanced, OTA | [08 §8.6](../design/08-flutter-app.md) |
| **A15** | Golden tests + `integration_test` against `tools/sim`     | [08 §8.9](../design/08-flutter-app.md) |

**Exit gate — this is the MVP.** Start to finish on real hardware: install the APK, onboard over BLE,
choose a mode, watch a live cook, scroll 15 hours of history, export a CSV.

### Decisions to carry into planning

**Chart interaction is its own task, separate from rendering.** `fl_chart` has no native zoom;
pan/zoom is a custom transform over `minX`/`maxX` ([§12.8](../design/12-task-planning-notes.md)).

**Golden tests cover the shapes that break things**, not just the happy one: no probes, all detached,
mid-gap, alarm active, 15 h of data, 54 days of data, both themes.

**Probe colour is chosen at implementation time against the project's data-visualisation guidance**
([08 §8.7](../design/08-flutter-app.md)) — but the constraints are requirements, not preferences:
colourblind-safe, legible in direct sunlight and in a dark theme, consistent across app, exports, and
the OLED's single bit of ink, with roles carrying semantic weight.

---

## M5 — Alarms, display, insights

| Epic     | Scope                                                                       | Design                                             |
| -------- | --------------------------------------------------------------------------- | -------------------------------------------------- |
| **F13**  | `app_alarm` — rules, latching, hysteresis, lid-open grace                   | [09 §9.2](../design/09-alarms-and-insights.md)     |
| **F11b** | `app_ui` **remainder** — five pages, button gesture machine, sparkline, LED | [07](../design/07-display-and-controls.md)         |
| **F12**  | `app_power` — battery ADC, calibration, SoC curve, saver profile            | [01 §1.3, §1.6](../design/01-hardware.md)          |
| **A13**  | Foreground service, notification channels, quiet hours                      | [09 §9.5–9.6](../design/09-alarms-and-insights.md) |

**Exit gate:** an unattended overnight cook wakes the user for `target_reached`; the bridge alarms
correctly **with the phone powered off**; a lid-open does not fire a false pit alarm.

### Decisions to carry into planning

**F12 gates on V1.3.** Battery calibration cannot be written until the GPIO37 / divider-ratio question
is resolved ([§12.6 rule 6](../design/12-task-planning-notes.md)). If GPIO37 turned out unusable,
battery reporting degrades to unavailable and F12 shrinks accordingly.

**Hysteresis is the feature, not a detail.** A probe oscillating ±1 °F across its target must fire
**once** ([10 §10.5](../design/10-repo-tooling-and-testing.md)). Without it, a probe hovering at
threshold generates an alarm every 30 seconds all night — and an alarm that cries wolf gets muted
permanently, which is the real failure.

**Two tiers stay separate.** The device tier is authoritative for alarm state and runs with no phone
in existence; the app tier is advisory. An alarm that fired at 03:40 while the phone was face-down is
still latched and unacknowledged at 07:00, and the app says so.

**Rules live in `components/app_alarm/rules.c` — pure C, no ESP-IDF, host-tested.** The same rules are
mirrored in `domain/analysis/`, already built in A2.

---

## M6 — Hardening and release

| Epic    | Scope                                                       | Design                                                                                  |
| ------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **F14** | OTA + rollback health gate                                  | [03 §3.7](../design/03-firmware-architecture.md), [06 §6.2](../design/06-device-api.md) |
| **T5**  | `tools/flash`, merged-binary build, esp-web-tools installer | [10 §10.8](../design/10-repo-tooling-and-testing.md)                                    |
| **V3**  | 24-hour soak: heap, stacks, counters, reconnects            | [10 §10.5](../design/10-repo-tooling-and-testing.md)                                    |
| **V4**  | On-target release checklist                                 | [10 §10.5](../design/10-repo-tooling-and-testing.md)                                    |

**Exit gate:** v1.0.0 tagged with a merged binary, an APK, and a working web installer.

### Decisions to carry into planning

**Never OTA the only board with an image that hasn't been flashed over USB first**
([§12.6 rule 8](../design/12-task-planning-notes.md)). With no spare, an unbootable board is a total
halt until it is recovered over USB. That is also why the health gate exists: LittleFS mounted, Wi-Fi
reached its configured state, httpd listening, 120 s of uptime with no panic — fail any and the next
reset rolls back.

**OTA is refused with `409` while a session is active** unless `?force=1`. Nobody should discover a
bad flash 14 hours into a brisket.

**Q-F must be settled before T5.** Public vs private repo determines whether the browser installer can
live on GitHub Pages. The docs are written as though public — MIT attribution retained, nothing
assuming privacy — which is the safe superset either way.

**The fallback web UI is decided here, not built here** (D13). Decide on evidence from real use; if
the answer is yes it ships in v1.1. The 512 KB partition has been reserved since F1.2 precisely so
this decision stays cheap — reclaiming it is a one-line change, carving it out later would erase
every stored cook.

**T5 cannot copy the reference's `merge_bin` offsets.** Its partition table differs from ours
([03 §3.5](../design/03-firmware-architecture.md)); the installer page itself is worth copying
outright.
