# 12 — Copy & Label Review (Final Baseline)

**Status:** Final copy baseline, implemented in the prototype · **Date:** 2026-10-26
· **Audited against:** the `app/` working tree after `e6aa7b5`

This is the source of truth for product copy, labels and state vocabulary. The
prototype implements this baseline; [13 — UI/UX Implementation Contract](13-ui-implementation-contract.md)
maps it to production states and tasks. Remaining gaps are listed in §12.3 and
are task-owned. If a new string conflicts with this document, update this
document first.

The review verifies against [02](02-smoke-x-protocol.md),
[04](04-data-and-storage.md), [05](05-ble-contract.md),
[07](07-display-and-controls.md) and the current `AndroidManifest.xml`.

---

## 12.1 State vocabulary

BLE link state, X4 telemetry freshness, Bridge sync and saved history are four
different things. Never collapse them into one “Connected/Offline” label.

| State | Use | Do not use |
|---|---|---|
| BLE link up | `Bridge connected · 2h 14m` | `Connected` alone |
| BLE link down | `Bridge disconnected · last connected 2h ago` | `Offline` alone |
| X4 fresh, ≤90 s | `Receiving readings · updated 12s ago` | `Connected` |
| X4 stale, 90 s–10 min | `No readings for 4 min` | `Receiving` |
| X4 lost, >10 min | `Smoke X4 signal lost · 10 min ago` | `Not connected` |
| Bridge syncing | `Syncing saved readings` | `Syncing` or `backfill` alone |
| Background backfill | `Loading saved readings` | `Loading older history` |
| Viewing saved data | `Showing saved readings · last reading 20 min ago` | `Live` |
| Bridge recording | `Recording` (only when connected and `storage_ok`) | `Recording` while disconnected or when storage failed |
| Bridge not recording | `Not recording` / “Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.” | `Live` |
| Billows attached | `Billows detected · last detected 12s ago` | `Reporting`, `Connected`, `Fan running` |
| Billows lost this session | `Billows not detected` | `Billows disconnected` |
| Billows target known | `Set temp` / `Set on the Smoke X4.` | `Target` with no source |
| Billows target unknown | `Set temp —` | A guessed 225°F |
| Phone paired | `Phone paired` | `Synced` |
| X4 paired | `Smoke X4 paired` | `Synced` |
| App command | `Forget this phone`, `Factory reset`, `Clear history`, `Power off` | `Read-only` for the whole app |

Only the Billows set temp is read-only. The app does control Bridge settings and
actions, so do not describe the whole app as read-only. The app sends
authenticated BLE control ops such as set time, forget phone, factory reset,
clear history, unpair Smoke X4 and power off. The Bridge’s only LoRa
transmission is the pairing ACK; the app does not control the Smoke X4 or the
Billows target.

**Priority note:** `P1` is a release-blocking quality fix; `P2` is release
polish that still needs a reviewed decision before shipping. Neither is silently
optional for a high-confidence MVP.

---

## 12.2 Copy baseline applied in the prototype

### Objects and navigation

- Product names: `Bridge`, `Smoke X4`, `Billows`, `Live`, `History`, `Settings`.
- Local archive: **`History on this phone`**. Never `Device log`, `Saved data`,
  `recorded data` or `local data`.
- Bridge copy: **`History on the Bridge`**. Never `Bridge log`, `bridge history`,
  `ring` or `sectors`.
- Counts: **`readings`**. Never `records`, `points` or `samples` in user copy.
- Detected archive sessions: **`Cooks`**, opened as a **`Cook`** view. No
  user-created cook sessions, names, marks or phases.
- Summary column: **`Latest`**. `Current` is gone.
- Settings: `Bridge name` (not Device name), `Bridge screen timeout` (not
  Display timeout), `Technical details`, `Connection log`, `Bridge actions`,
  `About this app`.
- The ESP32 device is always the **Bridge**, including in destructive copy.

### Live

- Chain: `App` → `Bridge` → `Smoke X4`. The node row is visual; the status block
  carries the words. No second label under every node.
- Healthy: `Bridge connected · 2h 14m`; `Receiving readings · updated 12s ago`.
- Tile exceptions only: `Updated 62s ago`, `No readings for 4 min`,
  `No readings for 12 min`, `Not connected`, `No history yet`.
- Tile footer: `1h · +3.8°F` or `1h · -1.4°F`. One hour and the signed change;
  not an unrelated `1h` and delta at opposite edges.
- Detached: `—` + `Not connected`; never `0°F`.
- Cached: `Showing saved readings · last reading 20 min ago`; values dimmed; one
  Bridge status surface, not four repeated no-reading lines.
- Sync: `Syncing saved readings` / `Newest readings load first.`;
  `Loading saved readings` / “Your latest readings are ready. Older readings
  continue in the background.”; `Slow connection` when the MTU is low.
- Sync failure: `History sync failed`; “Live readings are still updating. Retry
  when the Bluetooth connection is stable.”; `Retry sync`.
- Storage failure: `Not recording`; “Live readings are available, but the Bridge
  can’t save them. Check the Bridge’s storage.”
- No X4 data: `No data from Smoke X4`; SYNC-mode instruction; `Troubleshoot`.
- No probes: `No probes connected`; “Plug a probe into the Smoke X4 to see a
  reading.”
- Billows: `Billows`; `Set temp`; `Last detected`; age (`12s ago`); caption
  `Set on the Smoke X4.`; no `Connected` pill, no `Read-only`, no fan-running or
  duty claim. Offline uses `Last observed state`, `Set temp (last known)` and a
  last-detected age.
- Dirty tile `Billows not detected`, with `View connection log`.

### History

- Range trigger: `1 hour`, `6 hours`, `24 hours`, `2 days`, `Custom`.
- Range menu: `Last hour`, `Last 6 hours`, `Last 24 hours`, `Last 2 days`,
  `Custom range…` (`Any date and time`).
- Probe menu: `All probes`, `P1`–`P4`; unavailable options disabled with
  `No data`.
- Custom range: `Custom range`; “Choose a start and end time. It starts with all
  the history saved on your phone.”; quick picks `All saved history`, `Today`,
  `Yesterday`, `Last 6 hours`; `Apply` / `Cancel`; errors `Choose a range within
  your saved history.` and `End time must be after start time.`
- Chart metadata: `Synced 2 min ago`; `Recorded history` in a Cook view;
  `· 4 probes` or `· 3 of 4 probes`; `times estimated`.
- Chart help: `Reading the chart`; tap to inspect, drag/pinch, Cooks/custom range,
  gaps, shared scale, estimated times.
- Empty: `No readings yet`; “The Bridge records whenever it’s on and paired with
  the Smoke X4.”; `View Live`. In-range: `No readings in this range`; “Probe 3
  has no readings in this range. Try another range or show all probes.”;
  `Show all probes`.
- Summary: `Summary`; `Probe`, `Latest`, `Min`, `Max`; `No data`; sort labels
  `Probe order`, `Hottest`, `Highest`, `Latest reading`, `Since cook start`.
- Cooks: `Cooks`; “Grouped automatically from your readings”; `In progress`;
  `View all`; cook metadata `9h 20m · 4 probes · missing readings`.
- Gaps: `No signal`, `Bridge off`, `Not synced`; “The Bridge overwrote this part
  of its history before it reached your phone. The readings can’t be recovered,
  so the chart leaves this period blank.”
- Chart controls: `Drag to pan · pinch to zoom`; `Now`; `Fit range`.
- Full screen: `Full-screen chart` / `Close full-screen chart`.

### Settings, setup and confirmations

- Root sections: `Bridge`, `History & storage`, `Preferences`, `About`.
- Units: `Temperature units`; `°F` / `°C`; “All temperatures, including the
  Bridge screen.” Offline: “The Bridge screen will update when you reconnect.”
- Appearance: `System`, `Light`, `Dark`; “Match your phone”, “Always use light”,
  “Always use dark”.
- Storage: `History on this phone`; `History on the Bridge`; `Readings`, `Date
  range`, `Storage used`, `Capacity`, `Oldest reading`, `Newest reading`;
  “About 117 days at 30-second intervals”; “The Bridge overwrites its oldest
  readings automatically.”; “Two separate copies” notice.
- Delete: `Delete history from this phone…`; `Older than 30 days`, `Older than
  90 days`, `All history on this phone`; `Clear history on the Bridge…`.
- Bridge details: `Bridge`, `Smoke X4 pairing`, `Re-pair Smoke X4`, `Bridge
  name`, `Bridge screen timeout`, `Billows`, `Technical details`, `Connection
  log`, `Bridge actions`, `Power off the Bridge`, `Factory reset Bridge`,
  `Forget this phone`.
- Smoke X4 re-pair: “Put the Smoke X4 into SYNC mode.”; “Hold its button until it
  beeps.”; “The Bridge confirms the pairing.”; “This clears the old radio pairing
  only. History on the Bridge, phone pairings, and settings are kept.”
- Power off: “Power off the Bridge?”; “The Bridge stops recording until you turn
  it back on.”; “Recording stops while the Bridge is off”; “History on this
  phone is kept”; “Hold PRG for 1.5 seconds to turn the Bridge back on.”
- Factory reset: `Factory reset this Bridge?`; “The Bridge erases its pairings,
  settings, and saved readings, then restarts.”; bullets: all paired phones,
  settings/screen preferences, saved readings/clock, becomes available to pair as
  a new device; “History on this phone is kept.”; button `Factory reset`.
- Forget: `Forget this phone?`; “This removes the Bluetooth pairing for this
  phone. The Bridge keeps recording.”; phone history kept; other phones not
  affected.
- About: `App 0.1.0`; `Firmware`; `Bridge protocol`; `Bridge ID`; `Bluetooth
  name`; `Hardware Heltec WiFi LoRa 32 V3`; “Firmware updates require a USB
  connection to a computer.”; “No cloud, no account. Data stays on this phone and
  the Bridge.”; attribution.

### Setup

- App bar `Set up`; headline `Connect your Bridge`; body “Power it on. Press PRG
  to wake the screen. If the Bridge is off, hold PRG for 1.5 seconds to turn it
  on.”; `Find bridge`.
- Permission: `Allow Bluetooth to find your Bridge`; Android 12+ Nearby devices
  vs Android 7–11 location; “The permission is only needed to find your Bridge.”;
  `Continue` / `Not now`.
- No results: `No Bridge found`; “Make sure it’s on and within about 10 meters
  (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.”; `Try again` /
  `Open Bluetooth settings`.
- Results: `Nearby bridges`; “Your last Bridge is shown first.”; `Last used`;
  `Good signal`; `P4 225°F · 87%`; `Rescan`.
- Passkey: `Pair with the Bridge`; “Enter the 6-digit code shown on the Bridge
  screen in the Android prompt.”; `Look at the Bridge screen`; “Example: the code
  appears on the Bridge screen. Only the Bridge screen shows the real code.”;
  `Pair` / `Cancel`.
- Pairing: `Pairing…`; `Connecting to the Bridge`, `Checking the code`,
  `Syncing recent history`.
- Wrong code: `The code didn’t match`; after two failures, remove the old pairing
  in Android settings.
- Timeout: `No prompt appeared`; “Open your notifications and look for the
  Android pairing request, then try again.”
- Stale bond: `This phone’s pairing is out of date`; explain the Bridge was reset;
  `Forget and re-pair`.
- Phone list full: `This Bridge already has 4 phones paired`; send the user to a
  paired phone or USB recovery; `Try again`.
- First sync: `Loading history`; “Your latest readings are ready. Older readings
  will load in the background.”; `Time set`, `Loading the last 24 hours`,
  `Loading older readings`, `Live view ready`; `View live readings`. The V0
  build reads only 15 minutes, so it says `Loading recent readings` /
  `last 15 minutes` until M3 full sync lands; never claim 24 hours early.
- Orphaned history: `History on this phone`; readings/range/storage; “This
  history is stored on your phone, not on the Bridge. It stays until you delete
  it.”; `Delete history from this phone…`.

---

## 12.3 Remaining copy/UX gaps before release

These are not prototype blockers; they are production close-out items. Task IDs
point at the owner.

| # | P | Where | Current in prototype | Required for production | Task |
|---:|---|---|---|---|---|
| C1 | P1 | Setup > unsupported phone / protocol mismatch | Only `Close` | `Update app`, `View history on this phone`, `Learn more` where applicable; explain the Bridge is unchanged | A2.2 |
| C2 | P1 | Bridge details > Smoke X4 pairing | Compact pill `Receiving` | `Receiving readings` only when a valid X4 packet is ≤90 s old; otherwise `No readings for 4 min` or `Signal lost`; keep `Updated 12s ago` | A4.2 |
| C3 | P1 | History > Summary sort | Disabled label `Since cook start (no cook detected)` | Keep the option `Since cook start`; show `No cook detected yet` as helper text when disabled | A3.3 |
| C4 | P1 | Live > offline without cache | Prototype still renders fixture probe values | No probe values presented as current; show the one `Bridge disconnected · nothing saved yet` state and one next action | A2.3, A3.4 |
| C5 | P1 | About > lab entry | App-bar and About entries now share a debug gate; no release-build test yet | Verify the release build has no lab entry unless `ENABLE_EXPERIMENTAL_LAB=true`; no simulation UI in release | V6.4 |
| C6 | P1 | All screens > strings and locale | Strings hard-coded; some time helpers are fixture-oriented | Centralize product strings, use locale time/date/number formatting, add a banned-term copy test | A4.5, V6.4 |
| C7 | P1 | All screens > accessibility | Mostly 48 dp; contrast, semantics and chart controls need a final phone audit | WCAG AA contrast, 48 dp targets, semantics for connection/tiles/chart/summary/filters, reduce-motion | A4.5, V6.4 |
| C8 | P2 | History > Chart help | Prototype sheet is product-ready | Keep the six help rows; no developer wording | A3.3 |
| C9 | P2 | Live > probe tile | Signed delta uses `+`/`-` | Keep the sign; it is clearer than an arrow and is screen-reader friendly | Accepted |

---

## 12.4 Accepted deviations (do not reopen)

These are deliberate, not oversights:

- `1h · +3.8°F` uses a sign rather than `↑3.8°F`. The sign is clearer, survives
  font fallback and reads correctly to a screen reader.
- Live has a small section heading `Probes`; the app-bar title is still only
  `Live`. The heading is a content label, not a duplicate screen title.
- The range trigger uses words (`24 hours`) while the internal enum/test key uses
  `24h`. Keys are not user copy.
- The chart can show no gap-reason label when the band is too narrow. The gap is
  still shown and the help sheet explains it; do not force unreadable text into a
  narrow band.
- `History` metadata says `Synced 2 min ago` rather than a full sentence. It is a
  timestamp label, not a sync status claim.
- `Billows` shows `Last detected` and an age, not a bare `Detected`. This is the
  honest form.
- The Experimental lab is a review tool. It may show fixture states that the
  product cannot produce; it must be unreachable in release.

---

## 12.5 Formatting, capitalization and tone

### Formatting

| Use | Not |
|---|---|
| `165.2°F` | `165.2 °F`, `165.2 F` |
| `2h 14m` | `2 h 14 m`, `2hr 14min` |
| `1 min` | `60 s`, `60s` |
| `12s ago` | `12 s ago` |
| `10 meters (about 30 feet)` | `10 m` alone |
| `6:30 PM` / locale time | `${hour}:${minute}p` |
| `Sep 1, 2026` / locale date | `09/01/26` hard-coded |
| `128,430` | `128430` in user copy |
| `readings` | `records`, `points`, `samples` |
| `paired` | `bonded` in user copy |
| `Can’t` (curly) | `Can't` mixed within one string set |

Keep 0.1°F precision. Do not round Live or OLED values for copy reasons unless a
compact display explicitly says it is rounded.

### Capitalization

- Sentence case for buttons, labels, field headers and menu items.
- Product names keep their casing: `Bridge`, `Smoke X4`, `Billows`, `Live`,
  `History`, `Settings`, `Cooks`, `Cook`.
- Section headers may use small caps or title case as designed; body copy is
  sentence case.
- Do not use all caps for ordinary actions (`FIND BRIDGE`), except intentional
  OLED labels and short status chips where the display requires it.

### Tone

- State first, action second.
- One sentence per idea.
- No raw implementation nouns in product copy (`GATT`, `MTU`, `RSSI`, `ring`,
  `sector`, `generation`, `backfill`).
- Use exact counts and date ranges for loss.
- Reassure that the Bridge keeps recording and phone history is kept where true.
- Do not blame the user; name the next step.

---

## 12.6 Banned terms and copy lint

Add a test that fails on these in product strings (case-insensitive, with
allow-listed context for technical docs and the lab):

```
Graph, Probe history, Dashboard, Monitor (as a tab), Now (as a tab)
Saved data, Device log, Bridge log, Bridge storage (as a copy of history)
Records, Plot points, Samples (user copy), Sessions
Aging, Stale, Frozen (user-facing)
Last contact, No new 4m, No new 12m
Attached, Reporting, Fan running, Fan speed
Read-only (for the whole app), Monitor only, Observe mode
Bonding, Bonded (user copy), Connect to GATT, Secure characteristics
Current cook, Cook started (as a user concept), Set target
Simulated, Simulation, Prototype, in this build, there is no OTA path
MTU, RSSI, GATT, characteristic, backfill, ring, sector, generation
```

`Cooks` is allowed; `cook sessions` is not. `Technical details` may contain
`MTU`/`RSSI`; the main status card may not.

---

## 12.7 Verified facts kept from the technical review

- **Privacy:** no location is read or stored. Do not promise “never used or
  stored” until the manifest and BLE client are audited; the current product copy
  only says the permission is needed to find the Bridge.
- **PRG:** tap wakes the screen; hold ≥1.5 s powers off; hold from sleep ≥1.5 s
  powers on. “Wake” is reserved for the screen; the Bridge is turned on/off.
- **Billows:** `billows_attached` is a real state-packet field, but the target
  field is still unvalidated. Use “Detected / last detected”, never “Reporting”
  or “fan running.” Show `Set temp` only after validation; otherwise `—`.
- **Smoke X4 telemetry:** `smoke_live` means a valid state packet within 90 s;
  the link is marked lost after 10 min. “Receiving readings” is reserved for the
  fresh window.
- **Factory reset:** wipes config, bonds and history. The copy may name all three.
- **Bond slots:** `forget_phone` removes only the current phone’s bond. There is
  no remote management of other phones’ slots. A full bond list must send the
  user to an already-paired phone, or to USB recovery if none is available.
- **Overwrite:** a `gap` returned by ring rotation is a verified overwrite event.
  Say the Bridge overwrote that part of its history before it reached the phone;
  do not speculate beyond that.
- **Precision:** keep 0.1°F. Do not round Live or OLED values for copy reasons.

---

## 12.8 Review evidence

- `flutter analyze` clean; `flutter test` green (26 widget tests at the baseline).
- Screenshot set generated from the real widget tree at 390 × 844 (3×), dark and
  light; see [`app/screenshots/README.md`](../../app/screenshots/README.md).
- Prototype-only simulation remains in the lab; product screens use the copy
  above.
- Remaining gaps are in §12.3 and must be closed before the release gate in
  [10 §10.5](10-test-and-release.md).
