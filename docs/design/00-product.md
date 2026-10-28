# 00 — Product & Scope

## 0.1 The product in one page

A ThermoWorks Smoke X4 transmits probe temperatures over LoRa every ~30 seconds.
The stock ThermoWorks receiver continues to work. The **Smoke X4 Smart Bridge**
is a second listener:

```
 4 probes ──► Smoke X4 ──LoRa 915 MHz──► stock receiver(s)
                  │
                  └──► Heltec WiFi LoRa 32 V3 ──► rolling flash log
                                                     │
                                                     ├──► 128×64 OLED
                                                     └──► BLE GATT ──► Android app
```

The bridge is **always recording** while it is on and synced with a Smoke X4.
The phone may be absent, asleep, or out of range; that changes nothing. When the
phone reconnects, it asks for everything after its last stored sequence number.

The app is a monitor and a remote control, not the recording authority:

- **Live** — four probe temperatures, per-probe last-hour sparklines,
  freshness, bridge/Billows status.
- **History** — all four probes over the whole locally stored history, with
  gaps rendered as gaps and tools for exploring the archive.
- **Settings** — one Bridge section, History & storage, preferences and About.
  Units and appearance apply immediately; Bridge name, screen timeout and the
  device actions live with the Bridge object. Billows detection/last-seen is
  read-only; there is no target setter.

## 0.2 Who it is for and where it is used

One user, one smoker, one bridge, one Android phone at a time. Up to four
phones may be bonded for replacement/handoff, but only one is connected and
multi-user access is not a feature. The phone is used in a yard, often at night,
often at arm's length or farther. The bridge sits near the
smoker, powered by USB or its 3000 mAh pack. The phone is not expected to stay
connected for the entire cook; it is expected to reconnect and catch up.

The product is successful when a user can:

1. Power the bridge on, see probe temperatures on the OLED, and walk away.
2. Open the app, find and pair the bridge once, and see live temperatures.
3. Close the app for six hours, reopen it, and see the entire six hours in
   History without doing anything else.
4. Change the temperature unit or the bridge display timeout from the phone.
5. Forget the phone or factory-reset the bridge from the phone when needed.
6. See whether a Billows is attached and, when the RF field is validated, the
   target set on the Smoke X4. Set the target on the Smoke X4.

## 0.3 The thin vertical slice (V0)

V0 is the first deployable end-to-end build. It is deliberately narrower than
the MVP but exercises every layer of the architecture:

| Layer | V0 behaviour |
|---|---|
| Radio | Real Smoke X4 paired; stock receiver still works; state packets decoded |
| Firmware | Samples appended to the flash ring; OLED shows four probes; PRG cycles pages and powers off |
| BLE | Advertises when idle; passkey pairing; live-state notify; reads the last 15 minutes of readings |
| App | Scans, pairs with the code on the OLED, shows four live temperatures, and shows the last 15 minutes in the full History shell |
| Failure paths | Disconnect/reconnect; Smoke X4 stops sending; power-cycle the bridge |

V0 is the end of milestone **M2** in the task plan. It is the point at which the
hardware, radio, storage, BLE, and app are proven together. History sync,
settings, and Billows come after it without re-architecting anything.

## 0.4 MVP definition

The MVP is V0 plus:

- Full history sync, resume after disconnect, and an interactive History view
  over all local data.
- The Settings tab and all app-controlled device actions.
- Automatic data rotation on the bridge and user-controlled deletion on the
  phone.
- Battery/deep-sleep behaviour and a 24-hour soak.
- Billows observation only: attached/not attached and a validated observed
  target. Setpoint control is out of scope; the Smoke X4 receiver itself cannot
  change set points, so the bridge cannot either. See [08](08-billows.md).

An MVP is not "feature-complete" until it has been used for one real overnight
cook with the phone left away from the bridge for several hours.

## 0.5 Feature acceptance

Each line from the brief maps to a concrete acceptance test and an owning
design/task.

| Requirement | Acceptance | Design | Tasks |
|---|---|---|---|
| Hold PRG to turn off/on | From on, hold 1.5 s; countdown appears; release confirms; device sleeps. From sleep, hold 1.5 s; device boots to page 1. A short tap never powers off. | [07](07-display-and-controls.md) | T23, T26, T62 |
| Tap PRG to cycle information windows/dialogs | Each tap advances one page; a tap wakes a sleeping display without changing the page; the passkey overlay and power-off dialog have defined tap behaviour. | [07](07-display-and-controls.md) | T22, T23, T26 |
| Automatic BLE discovery whenever on and not connected | Advertising starts at boot and restarts on disconnect, failed connect, and advertising timeout. The app finds it without pressing a button. | [05](05-ble-contract.md), [06](06-app.md) | T27, T30, T32 |
| Pairing code on screen, entered on phone | First bond shows six digits on the OLED; the phone's OS prompt accepts them; a wrong code produces a named retry path; subsequent reconnects do not prompt. | [05](05-ble-contract.md) | T30, T33, T37 |
| App can forget device | App-initiated "Forget this phone" removes the current phone's bond on both sides (when connected) and clears the saved connection; local history is kept. Other phones are unaffected. | [05](05-ble-contract.md), [06](06-app.md) | T49, T52, T55 |
| App can factory reset | Authenticated control op wipes config, all bonds, and bridge history, then reboots. The app states what is lost before sending, treats the disconnect as success, and keeps local history until the user deletes it. | [05](05-ble-contract.md), [06](06-app.md) | T49, T52, T55 |
| Re-pair a re-synced Smoke X4 | Settings → Bridge → Smoke X4 pairing shows the current state and a `Re-pair Smoke X4` action; it clears the old radio pairing, keeps the log/bonds, and restarts the scan. | [02](02-smoke-x-protocol.md), [06](06-app.md) | T16, T48, T51, T55 |
| Record whenever on, synced, and Smoke X4 is sending | With no phone present, samples continue into flash; unplug/replug resumes into the same rolling log with only the last record at risk. | [03](03-firmware-architecture.md), [04](04-data-and-storage.md) | T15–T19, T25 |
| Collect all connected probe temps | Four probes in probe order, tenths °F internally; detached = null; partial connections are represented without inventing data. | [02](02-smoke-x-protocol.md), [04](04-data-and-storage.md) | T14, T17 |
| Billows: set target temp | **Out of scope.** The app has no target setter. It shows "Set on the Smoke X4." Public ThermoWorks docs say a Smoke X4 receiver cannot change set points or the Billows; only Signals with its app can. | [08](08-billows.md), [decision](../billows-decision.md) | none |
| Billows: connected/status | App and OLED show attached/not attached and the observed target when the field is validated; otherwise `—`. No fan speed or duty is invented. | [08](08-billows.md) | T56, T57, T59 |
| Periodic collection, efficient storage | 30 s samples; 18 B each; ~117 days in a 5.875 MB partition; ring rotates oldest first; app stores every synced sample. | [04](04-data-and-storage.md) | T17–T19, T61 |
| App handles discovery/connection/health | Auto-connect to remembered device, explicit states for scanning/connecting/bonding/syncing/live/stale/reconnecting/failed; reconnect with bounded backoff. | [06](06-app.md) | T32–T35, T43 |
| Settings the device cannot do | Units, bridge display timeout, bridge name, forget, factory reset, power off. Billows target is not a setting. | [06](06-app.md), [07](07-display-and-controls.md) | T47, T50–T53 |
| Show four probe temps | Live cards in probe order, large values, per-probe last-hour sparkline, detached state, freshness; no zero for absent data. No probe names, roles or tags in the MVP. | [06](06-app.md) | T34 |
| History all four probes; no data means no line | Four series, gaps at >90 s, LTTB/min-max decimation, range/probe/custom filters, crosshair, pan/zoom, Latest/Min/Max Summary, Cooks, gap reasons, cached data available offline. | [06](06-app.md), [04](04-data-and-storage.md) | T42 |
| Device records regardless of app; app catches up | Sync cursor is sequence-based; connect triggers catch-up; live notifications append; quiet periodic catch-up every 30 s while connected. | [04](04-data-and-storage.md) | T31, T39, T41 |
| Rotate old data out on ESP32; never auto-delete in app | Bridge ring wraps oldest sectors; app only deletes through an explicit user action, with a confirmation that says what is lost. | [04](04-data-and-storage.md), [06](06-app.md) | T18, T44 |
| Live is one honest status surface | BLE link state and X4 telemetry freshness are separate; healthy screens are quiet; detached probes show `—`, never zero; cached data is labelled saved; every failure has a next action. | [06](06-app.md), [13](13-ui-implementation-contract.md) | T34, T43, T45 |
| History is an archive, not a demo chart | Range/probe filters persist; crosshair, pan/zoom, Summary, gap reasons, Cooks and a dedicated Cook view work on offline cache; no data never draws a line. | [06](06-app.md), [13](13-ui-implementation-contract.md) | T36, T42, T54 |
| Settings applies immediately | Units and appearance apply in the same frame; Bridge controls save per field or explain why they are disabled; there is no save-all bar and no duplicate action. | [06](06-app.md), [13](13-ui-implementation-contract.md) | T50–T53 |
| Prototype chrome never ships | No theme toggle, lab icon, simulation button, fake OS prompt or “simulated” copy is reachable in a release build; the Experimental lab is debug-only. | [06](06-app.md), [13](13-ui-implementation-contract.md) | T06, T64 |

## 0.6 Out of scope (and intentionally absent)

- Wi-Fi, AP/STA provisioning, HTTP, WebSocket, mDNS, MQTT/Home Assistant.
- OTA or any firmware update path other than USB.
- Alarm rules, buzzer/LED alarms, phone notifications, foreground service.
- User-created cook sessions, names, marks, phases, presets, ETA, stall/lid
  detection. Detected Cooks are read-only archive navigation derived from the
  recorded readings; they are not editable sessions.
- CSV/JSON export, share sheets, cloud sync, accounts.
- Multi-bridge selection, multi-user access, remote access outside BLE range.
- iOS, web, desktop.
- X2-specific UI or acceptance.
- Battery saver profiles, battery calibration UI, charger status.
- A local web UI or debug HTTP server.
- Billows setpoint control, Billows mode, and any Billows/fan transmit path. The
  MVP is observation-only; post-MVP RF work is receive-only.

These are not "future roadmap" promises. They are removed so the kept path can
be made trustworthy. If a need appears after field use, it gets its own design
decision.

## 0.7 Product-level success criteria

| Criterion | Target |
|---|---|
| Cold scan → live temperature | < 60 s for a phone that has never seen the bridge; < 15 s for a bonded phone |
| Reconnect → live | < 10 s after the phone is in range |
| 24 h history catch-up | < 20 s at MTU ≥247 (51.8 KB of sample data); at MTU 23 expect ~1 min |
| Full ring catch-up | < 10 min at MTU ≥247 for ~5.9 MB, resumable if interrupted; at MTU 23 treat it as a background job |
| Record loss on power cut | At most the last record; no loss of earlier records |
| Continuous recording capacity | ≥ 110 days at 30 s cadence |
| 24 h soak | No reboot, no panic, no heap trend, no missed sample storm |
| Battery runtime | ≥ 24 h with OLED sleeping and BLE advertising, measured on the 3000 mAh pack |
| App history after relaunch | 100% of synced samples remain, regardless of bridge availability |

## 0.8 Assumptions and unknowns

- The board is the **Heltec WiFi LoRa 32 V3** (ESP32-S3FN8, 8 MB flash, SX1262,
  SSD1306). If it is not, [01](01-hardware.md) must be revised before M0 exits.
- A real Smoke X4 and probes are available for bench work. A Billows may not be;
  [08](08-billows.md) is written so attached/status can land without one. Target
  display waits for a real Billows capture; it is never guessed.
- The phone is Android 12+ with BLE and a working OS passkey dialog. Android 7–11
  need the legacy location-permission path; that is a task detail, not a product
  change.
- The bridge is powered by USB for long cooks; the battery is a UPS/portable
  option. Runtime is measured, not assumed.
