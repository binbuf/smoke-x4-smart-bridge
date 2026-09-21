# N13 — Settings & device

**Goal:** the settings tree, firmware/OTA, diagnostics, and the destructive device
verbs — each behind a stated cost and a named progress sheet.

**Design:** [`newui/app.js`](../app.js) §6 `viewSettings`, §7 `overlayFirmware`,
`overlayFirmwareUpdate`, `overlayDiagnostics`, `overlayConfirm`, `overlayVerb`,
`openVerb`, `applyVerb` · `newui/NOTES.md` §2.1, §3.8, §6 · `mock-data.js`
DEVICE/FIRMWARE.

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| I5 | No dead controls — disabled controls state their reason | device rows |
| I7 | Verify by behaviour: device verbs are confirmed by read-back / watching the link, not by a return value | verb sheet |
| I8 | State the cost before a destructive action, split into keeps / loses | cost sheet |
| — | OTA is **Wi-Fi only**; a recording session returns 409 `session_active` unless explicitly forced; a failed health gate within 120 s auto-rolls back | OTA copy + guard |
| I11 | A bridge with no clock stores no timestamp — never a made-up one | diagnostics/empty copy |

## 13.1 Settings tree

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N13.1 | Bridge card (reuse N10.12) + "Set up Wi-Fi" rows (join home / use hotspot / forget) | N10.12 | W | `app.js` viewSettings |
| N13.2 | Cooks card → History | N12.1 | W | `app.js` viewSettings |
| N13.3 | Preferences — display: Units (°F/°C), Appearance (Auto/Light/Dark), High-contrast profile, Density, Reduce motion | N3.5, N3.8 | W | `app.js` viewSettings |
| N13.4 | Preferences — behaviour: alarms & monitoring, prefer my own alarms, quiet hours, keep Bluetooth warm, wrap/spritz reminders | N11.6 | W | `app.js` viewSettings |
| N13.5 | Persist every setting via `PrefsRepository`; applied immediately | N2.29, N13.3 | W | NOTES §2.1 |
| N13.6 | "Bridge" card: Firmware row, Update firmware row, About & diagnostics row | N13.1 | W | `app.js` viewSettings |
| N13.7 | "Device actions" card: Restart, Forget this bridge, Factory reset (danger) | N13.6 | W | `app.js` viewSettings |
| N13.8 | Honesty footer: no-clock = no timestamp; detached = absent, never 0 | N13.7 | W | I11, I3 |

## 13.2 Firmware & OTA

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N13.9 | Firmware sheet: installed version/date/channel, hardware, bootloader, auto-rollback, channel Stable/Beta | N13.6 | W | `app.js` overlayFirmware |
| N13.10 | Update sheet: installed vs available, release notes, size/date, channel | N13.9 | W | `app.js` overlayFirmwareUpdate |
| N13.11 | **Transport rule first**: image is Wi-Fi-only; if not on Wi-Fi the primary action becomes *Join Wi-Fi*, not *Install* | N13.10 | W | NOTES §3.8, I5 |
| N13.12 | **Session guard**: if recording, warn about 409 `session_active`; require an explicit **force** toggle before enabling Install | N13.11 | W | NOTES §3.8 |
| N13.13 | OTA progress verb sheet (verify → stream → write → reboot → health check); apply on success | N13.12, N2.28 | S | `app.js` VERBS.ota |
| N13.14 | Auto-rollback promise stated verbatim ("failed health check within 120 s auto-rolls back; nothing is lost") | N13.13 | W | `mock-data.js` FIRMWARE.rollback |

## 13.3 Diagnostics & verbs

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N13.15 | Diagnostics sheet: identity, firmware, hardware, bootloader, uptime, heap, battery, recording, last crash | N13.6 | W | `app.js` overlayDiagnostics |
| N13.16 | Signal card (BLE + Wi-Fi, two hops), storage card (sessions, flash used, retention, bar) | N13.15 | W | `app.js` overlayDiagnostics |
| N13.17 | Recent logs list (level-coloured) + Copy diagnostics + Field report | N13.16 | W | `app.js` overlayDiagnostics |
| N13.18 | Five-tap diagnostics gate (Settings → About) | N13.15 | W | research notes §11.4 |
| N13.19 | Cost sheet (`confirm`): Restart / Forget / Factory — keeps vs loses, named confirm button | N13.7, N3.30 | W | research notes I8, `app.js` openConfirm |
| N13.20 | Verb-progress sheet: named steps complete one by one; apply the scenario mutation on the last step | N13.19 | W | `app.js` openVerb/applyVerb |
| N13.21 | Restart copy: "recording pauses ~30s"; Forget: "removed from this app only"; Factory: "erase all settings, Wi-Fi and sessions" | N13.20 | W | `app.js` VERBS |
| N13.22 | Generic confirm used for device cost sheets and the long-item warning (shared component) | N13.19, N9.14 | W | `app.js` overlayConfirm |

## Exit gate

Every settings row does something real against the mock; OTA Install is
impossible without Wi-Fi and is gated on the session guard; each device verb
shows its cost, then its progress, then the resulting state.

## Must-not-regress

I5, I7, I8, I11 and the three OTA rules (Wi-Fi-only, 409 guard, 120 s rollback).