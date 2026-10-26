# 11 — UI/UX Refresh Proposal

**Status:** Approved and implemented in the prototype · **Date:** 2026-10-25 ·
**Baseline:** `app/` prototype at `412cb48`

This proposal was approved in full. The prototype now implements the Live,
History and Settings direction; the decisions have been folded into
[00](00-product.md), [04](04-data-and-storage.md),
[05](05-ble-contract.md), [06](06-app.md), [07](07-display-and-controls.md),
[10](10-test-and-release.md), and the M0–M4 task plans.

> **Final implementation note (2026-10-26):** the prototype now uses a Bridge
> connection-chain card on Live (simple App → Bridge → Smoke X4 icons with status
> text underneath), no app-bar status chip, “probe” terminology everywhere, one
> unified Bridge settings section with no duplicate sync or repair actions,
> Billows that appears automatically, mirrors the read-only Smoke X4 channel 4
> set temp and logs detection/loss beside Bridge pairing events, a Summary with
> current / min / max and no deltas, and Past cooks
> that open a dedicated historical view instead of replacing the current History
> range. History ranges are `1H`, `6H`, `24H`, `2D` and `Custom` (exact dates and
> times, defaulting to everything in memory); range and probes are compact
> dropdowns. Settings shows Bridge first, then Preferences; there is no separate
> `Bridge details` button. Where the sketches below differ,
> [06-app.md](06-app.md) is authoritative.

The short version: the prototype already proves the hard truths — four probes,
honest gaps, no invented zeros, explicit destructive actions. What it does not
yet feel like is a finished product. It feels like a state catalogue with a demo
chart, a fake probe taxonomy, and a settings index. The proposal fixes the
information architecture and the two screens that matter most: **Live** and
**History**.

### At a glance

- **Live:** a connection-chain card for phone → Bridge → Smoke X4, then four
  P1–P4 tiles with relative 1 h sparklines. No aggregate preview graph.
- **History:** range/probe filter card, premium pan/zoom chart, current/min/max
  summary, detected past cooks that open a separate historical view, gaps and
  empty states. Past cooks never replace the current History tab state.
- **Settings:** one Bridge section first, then Preferences; the Bridge status
  header contains the status, sync action and every Bridge setting. Tapping the
  header opens Bridge details; there is no separate details button. °F/°C inline,
  no save-all bar, no duplicate rows, no `Actions` screen, no probe names.
- **Probe identity:** P1–P4 + colour only. Remove names, roles and tags from the
  UI, OLED and config. Use “probe” consistently.
- **Naming:** the ESP32 device is the **Bridge**.
- **Prototype chrome:** theme toggle, lab icon, simulation buttons and fake OS
  prompts move to the lab; product screens use production copy.
- **Visual system:** keep the warm charcoal/ember palette, raise chart label
  sizes, use one probe palette, reserve red for errors.

---

## 11.1 What I reviewed

- Every screen in `app/lib/features/` and the shared widgets.
- The current screenshot set in `app/screenshots/`.
- The design baseline (`00`, `04`, `05`, `06`, `07`) and task plans
  (`M0`–`M6`).
- The current prototype behaviour and tests (`flutter test` is green, 6 tests).
- How the leading products handle the same jobs: FireBoard, ThermoWorks,
  MEATER, Combustion, Weber Connect, plus Android/Material settings guidance
  and mobile time-series chart practice.

### What the best products get right

| Product / pattern | What they do | What we should take |
|---|---|---|
| **FireBoard — Summary view** | Each channel is a row with current temperature, min/max context, last-updated time, and a **sparkline**. Tapping the sparkline opens a single-channel zoomable chart with a date-range tool. | Per-probe sparklines on Live; tap a tile to open History focused on that probe. This is the strongest competitive validation of the requested tile history. |
| **FireBoard — Chart view** | Current temperatures across the top, chart below. Tap a series for time/temperature; double-tap or pinch to zoom; drag to pan. | A real History chart with crosshair, zoom/pan, reset, and a visible “Now” state. |
| **ThermoWorks app** | Graphs per probe and saved multi-probe graphs; unit change lives in device/sensor settings. Gaps are explicit when the link is interrupted. | Keep gaps explicit. Do **not** bury °F/°C the way ThermoWorks does; surface units at the top of Settings. |
| **MEATER** | One hero internal temperature, ambient temperature, target and estimate; the graph supports the number rather than competing with it. | Keep the temperature number dominant. Remove duplicate status text around it. Do not add cook sessions or prediction in this MVP. |
| **Combustion** | Real-time graph with scrubbing, target lines and prediction; advanced sensor detail is optional. | Adopt graph scrubbing and a pinned readout. Do not add prediction; it is outside the product. |
| **Weber Connect** | Colorful live graphing and multiple recipe/timer cards. | The live graph is expected, but our continuous archive means History should be its own destination, not a widget on the dashboard. |
| **Material / Android settings** | Settings show current values at a glance, grouped by object; toggles/choices apply immediately; destructive actions are separated and explained. | Rebuild Settings around objects (`Bridge`, `History & storage`, `Preferences`) and remove the save-all bar. |
| **Sparkline guidance (Tufte/CDC/Grafana)** | A sparkline is an inline, axis-free trend for glanceability; a stat panel pairs a big current value with a tiny trend line. | Use sparklines only where they help a glance. Do not put an aggregate chart on Live. |

---

## 11.2 Verdict

### Scorecard (current)

| Dimension | Score | Why |
|---|---:|---|
| Visual craft | 6/10 | Warm palette and restrained cards are good; the screens still read as a component demo. |
| Information architecture | 4/10 | Graph vs preview, Settings duplicate entry points, an `Actions` screen that exists only to hold three actions. |
| Data visualisation | 3/10 | Static chart, no crosshair/filter/zoom, awkward axis ticks, 10 px labels, diagnostic “plot points”. |
| Interaction | 3/10 | One pan gesture, no scrub, no filter state, save-all settings bar. |
| Trust and clarity | 8/10 | Best part of the current build: no fake zeros, honest gaps, good destructive copy. Keep this. |
| Accessibility | 4/10 | Custom-painted chart has no semantics; chart labels are too small; color carries too much meaning. |
| Production readiness | 3/10 | Theme toggle, scenario-lab icon, “simulated” copy, fake OS prompt and “Simulate…” buttons are on product screens. |

### Keep these

- Four tiles, always present, in probe order.
- `—` and “Not connected”, never `0 °F`.
- Gaps are rendered as gaps, and offline history is still usable.
- Destructive actions name the loss, the count and the date range.
- The warm charcoal/ember palette, not a generic blue dashboard.
- Three destinations. Do not add tabs.

### The eight big problems

1. **Probes have no durable identity.** Names and roles are fake in the prototype
   (`Brisket`, `Point`, `FOOD`, `GRATE`) and are explicitly out of MVP scope.
   The UI should be P1–P4 + color, consistently.
2. **Live has no per-probe memory.** A tile shows the current number and nothing
   else. The user cannot tell whether P1 is climbing or has been flat for an
   hour without leaving Live. Sparklines fix this.
3. **The aggregate graph on Live is a second, worse History tab.** It duplicates
   state, eats the most valuable screen space, and has its own `Open graph`
   navigation. Remove it.
4. **History is a demo, not a tool.** It has a chart, a separate legend card and a
   separate “Range summary” card with implementation details like “Plot points”.
   It needs crosshair, filters, zoom/pan, statistics, gaps, and empty states.
5. **Settings is an index of screens, not a set of settings.** `Bridge` and
   `Smoke X4` open the same screen; `Sync now` is a navigation row that performs
   an action; `Forget this phone` appears twice; `Data` rows all lead to the same
   screen; `Actions` is not a category.
6. **The settings save model is wrong for preferences.** Units, timeout and
   device name sit behind a bottom “Save changes” bar. A segmented control should
   apply immediately.
7. **Prototype chrome is leaking into the product.** Theme toggle and flask icon
   in every app bar, “Prototype · no device is contacted” on every setup page,
   “Simulate…” buttons on production flows, and a fake Android prompt on the
   pairing page. Review tools should live in the lab.
8. **The visual system is not yet a system.** 10 px chart labels, arbitrary
   y-axis ticks (`263°, 226°, 189°…`), P4 drawn in error-red, repeated green
   “Live” pills, and two copies of the probe palette in code
   (`ProbeColors` and `ProbeColorsAccessor`).

### Where the problems live

| Symptom | Evidence in the current tree |
|---|---|
| Aggregate preview on Live | `app/lib/features/live/live_screen.dart` → `_PreviewGraphCard`, `Open graph` |
| Names/roles everywhere | `prototype_controller.dart` → `probeNames`, `probeRoles`; `ProbeEditorScreen`; `probe_editor_dark.png` |
| Duplicate status | `ConnectionBanner`, `LiveScreen` header pill, `ProbeCard` footer, `Billows` card |
| Demo chart | `graph_screen.dart` → `_LegendCard`, `_RangeSummary`, hard-coded `1 visible gap`; `probe_chart.dart` → 10 px labels, fixed missing marker |
| Settings duplicates | `settings_screen.dart` → `Bridge`/`Smoke X4` both push `ConnectionSettingsScreen`; `Sync now`/`Forget` duplicated; `Data` rows all push `DataSettingsScreen` |
| Save-all bar | `settings_details.dart` → `DeviceSettingsScreen` bottom bar; `BillowsSettingsScreen` save button |
| Settings dead ends | `ActionsScreen`, `ProbeEditorScreen`, `DeviceSettingsScreen` as a catch-all |
| Prototype chrome | `prototype_app_bar.dart` theme toggle; `app_shell.dart` flask icon; `setup_screen.dart` prototype footer and simulation buttons |
| Palette duplication | `app_theme.dart` `ProbeColors`; `probe_chart.dart` `ProbeColorsAccessor` |
| Tests encode old IA | `app/test/widget_test.dart` expects `Graph`, `Probes`, `Brisket`; screenshot tool writes `graph_*` |

---

## 11.3 North star

> **Read the pit in one glance. Trust the history. Change a setting in two taps.
> Nothing on screen belongs to the prototype.**

Design principles:

1. **Temperature is the hero.** Big numerals, tabular figures, no decoration
   competing with them.
2. **One status surface.** Healthy connection is quiet. Problems get a banner.
3. **Probe identity is P1–P4 + color.** No names, roles or tags in the MVP.
4. **Live is now; History is the archive.** One chart destination, not two.
5. **Immediate preferences, explicit actions.** Choice controls apply now;
   device actions and deletions always confirm.
6. **Never invent data.** Keep gaps, no-data states and cache labels honest.
7. **Prototype stays in the lab.** Product screens use production copy only.

---

## 11.4 Proposed information architecture

```
┌──────────────────────────────────────────┐
│  Live          History          Settings  │  NavigationBar
├──────────────────────────────────────────┤
│  Live: connection-chain card, 2×2 probes  │
│        + sparklines, Billows if detected  │
│  History: range + probe filter card       │
│           chart + summary + past cooks    │
│  Settings: preferences, one Bridge card,  │
│            history & storage, about       │
└──────────────────────────────────────────┘
```

- `AppTab.graph` becomes `AppTab.history`; `GraphScreen` becomes
  `HistoryScreen`; lab group `Graph` becomes `History`.
- The app bar title is the screen name (`Live`, `History`, `Settings`). Do not
  repeat it inside the content (`Probes`, `Probe history`).
- No connection chip in the app bar. Live owns a two-LED connection-chain card;
  History shows a banner only for degraded states; Settings uses its Bridge
  section header.
- Remove the theme toggle and scenario-lab icon from product app bars.

---

## 11.5 Live

### Layout

```
┌────────────────────────────────────────────┐
│ Live                                       │
├────────────────────────────────────────────┤
│ Connection                    ⟳ Sync now   │
│ This phone ▸ Bridge ▸ Smoke X4             │
│ ● Bridge            Connected              │
│   Connected for 2h 14m · last contact 4s ago   > │
│ ● Smoke X4          Receiving              │
│   Last data 12s ago · 915 MHz              │
├────────────────────────────────────────────┤
│ ┌──────────────────┐ ┌──────────────────┐  │
│ │ ● P1             │ │ ● P2             │  │
│ │ 165.2 °F         │ │ 164.0 °F         │  │
│ │ ╭──────╮   +0.8° │ │ ╭──────╮   -0.3° │  │
│ │ ╰──────╯    1h   │ │ ╰──────╯    1h   │  │
│ └──────────────────┘ └──────────────────┘  │
│ ┌──────────────────┐ ┌──────────────────┐  │
│ │ ● P3             │ │ ● P4             │  │
│ │ —                │ │ 225.0 °F         │  │
│ │ Not connected    │ │ ╭──────╮   +2.1° │  │
│ │                  │ │ ╰──────╯    1h   │  │
│ └──────────────────┘ └──────────────────┘  │
├────────────────────────────────────────────┤
│ Billows                   Detected          │
│ CH 4 set temp 225 °F · Read-only           │
└────────────────────────────────────────────┘
```

### Rules

- **Connection chain first.** The top card shows the whole link as two LED rows:
  phone → Bridge and Bridge → Smoke X4. State the last Bridge contact, current
  session length, and the last Smoke X4 data age. No app-bar status chip.
- **No names, roles or tags.** The tile label is `Probe 1` / `P1`, plus the
  probe color. The same identity is used in History, Summary and the OLED.
- **Sparkline in every tile when that probe has history.** Use the last hour,
  `1h`, and scale it to that probe's own min/max. This is a relative shape, not
  a cross-probe comparison. History is where probes share one scale.
- **Tap a tile → History**, with that probe selected and the 1 h range active.
  This is the FireBoard pattern and makes the tile useful without adding a
  separate chart screen.
- **Do not show “Live · updated 4s ago” on every tile.** Healthy tiles stay
  quiet. Show only the exception: `Not connected`, `No new reading for 4m`, or
  a dimmed value in the offline state.
- **Detached probe with history:** show the historical sparkline muted, ending
  at the last sample, and `Not connected` underneath. Never extend the line to
  now and never invent a value.
- **No history for a probe:** keep the tile height consistent and show a quiet
  `No history yet` in the sparkline area.
- **Tap target** is the whole tile. Minimum 48 dp. Add semantics:
  “Probe 1, 165.2 degrees Fahrenheit, up 0.8 degrees in the last hour.”
- **Remove the aggregate preview graph and the footer instruction text.** The
  History tab is one tap away; the sparklines provide the glance.
- **Billows** is one compact card and appears only when detected. Showing it
  implies a live connection, so do not add a “Connected” pill. Show:
  - `Detected`, not a control mode,
  - the Smoke X4 channel 4 set temp if validated, else `—`,
  - a read-only explanation that the value comes from the Smoke X4.
  There is no mode switch and no `Set target` button; the MVP is observation-only.
  If it was detected earlier in this session and is now missing, show one
  `Billows disconnected` notice. Detection history and last-seen belong in
  Settings > Bridge > Billows.
- **Sync/error notices** only appear when there is something to say. A healthy
  Live screen should start with temperatures, not chrome.
- **Offline with cache:** dim the values, show one banner
  `Showing last saved readings · 6:18 PM` with `Retry`. Do not repeat
  “No readings for 12m” four times.
- **Pull-to-refresh** stays. It is the one visible recovery action.

### Status language

| Internal state | User-facing |
|---|---|
| `live` | Bridge `Connected · last contact 4s ago`; Smoke X4 `Receiving · last data 12s ago` |
| `aging` | `Last contact 62s ago` (amber dot only) |
| `stale` | Smoke X4 `No recent data · last data 4m ago` (Bridge stays green) |
| `frozen` | `No new readings for 12 min` (dimmed values) |
| `offline` + cache | Bridge `Offline · last connected 2h ago`; values dimmed |
| `offline` no cache | `Can’t reach the Bridge · nothing saved yet` |
| `reconnecting` | `Reconnecting… attempt 2 of 6` |
| `failed` | `Can’t reach the Bridge` + `Reconnect` |

Drop `Aging`, `Stale` and `Frozen` from the UI. They are internal health names,
not user language.

---

## 11.6 History

### Rename and purpose

- Tab, app bar and all copy: **History**.
- Remove `Probe history`, `Open graph`, `Graph` and the `Graph` lab group.
- History is not just a chart. It is the archive: chart + per-probe summary +
  detected past cooks + data-quality states.

### Layout

```
┌────────────────────────────────────────────┐
│ History                                    │
├────────────────────────────────────────────┤
│ [ 24H ▾ ]  [ All probes ▾ ]          ↺     │
├────────────────────────────────────────────┤
│ Oct 24 6:30 PM – Oct 25 6:30 PM            │
│ Saved 2m ago · 4 probes                    │
│                                            │
│ 275 ┤          ╭─╮                         │
│ 225 ┤──╮   ╭───╯ ╰──╮      P4              │
│ 175 ┤  ╰───╯        ╰──╮   P1/P2           │
│ 125 ┤                   ╰──                │
│     └──────────────────────────────        │
│      6:30 PM   2:30 AM   10:30 AM   Now    │
│  ● P1 166.0° ● P2 171.9° ● P4 215.8°       │
│  Pan · pinch or scroll to zoom   − + ⛶ Now │
├────────────────────────────────────────────┤
│ Summary                         °F  Probe ▾│
│ PROBE   CURRENT        MIN       MAX       │
│ ● P1    166.0°         149.9°    181.5°  > │
│ ● P2    171.9°         148.4°    175.9°  > │
│ ● P3    159.6°         132.6°    168.2°  > │
│ ● P4    215.8°         202.7°    247.0°  > │
├────────────────────────────────────────────┤
│ Past cooks                     View all    │
│ [OCT 25] Today  9:10 AM – 6:30 PM · 4      │
│ [OCT 24] Yesterday  10:05 AM – 7:20 PM · 4 │
└────────────────────────────────────────────┘
```

### Feature set

**Must ship in the refresh**

- Range menu: `1H`, `6H`, `24H`, `2D`, `Custom`. Custom starts with the entire
  archive in memory and opens an exact date-and-time sheet.
- Custom range via a calendar icon (date/time range sheet).
- Probe filter chips: `All`, `P1`–`P4`. A probe with no data in the selected
  range is disabled with `No data in this range`.
- Range chips and probe chips persist across tab switches.
- One labelled filter card keeps range, probes, custom date and Past cooks
  visible together.
- Shared y-axis when all probes are visible; auto-scale to the selected probe
  when one is selected.
- Nice y-axis ticks (1/2/2.5/5 × 10ⁿ) and the unit shown once (`°F` / `°C`).
- Locale-aware time labels; date labels at midnight for multi-day ranges.
- Crosshair + tooltip: timestamp and every visible probe value. The tooltip is
  **pinned until the user taps elsewhere**; it does not disappear after a
  second. Haptic feedback on sample snap.
- Drag to pan; pinch or mouse-wheel/scroll to zoom; double-tap to fit. Zoom
  buttons and a `Now` action appear in the chart toolbar when useful.
- Live-follow badge when the chart is at Now; panning pauses follow, `Now`
  resumes.
- Latest-point dots at the end of each visible series.
- Gap bands with a reason (`No signal`, `Bridge off`, `Overwritten before
  sync`) and a tap explanation. Never connect across a gap.
- Estimated-time badge when any visible sample has `time_estimated`.
- Offline cache banner; the chart still renders.
- `Expand` opens a dedicated full-screen chart view for precise scrubbing. It
  never forces landscape; portrait and landscape both fill the screen. This also
  removes the gesture conflict with page scroll.
- Empty states: no readings at all, no readings in this range, offline with no
  cache.
- Accessibility: a chart summary for screen readers and a text summary table
  that does not depend on color.

**Recommended polish**

- Preload each range on selection and show a non-blocking `Loading 30 days…`
  state.
- A small overview brush for `2D` and `Custom`.
- A dashed Billows target reference line when the target is known and P4 is
  visible. This is a real reading, not an alarm.
- Sort menu on Summary:
  `Probe order`, `Hottest now`, `Highest peak`, `Most recent`,
  `Since cook started`.
- Past cooks list sorted newest first; tapping a cook filters the chart to its
  exact start/end time.

**Deliberately not included**

- User-created cook sessions, names, marks, phases, ETA, stall/lid detection.
  (Detected past cooks are archive navigation only.)
- Alarms, notifications, recipes, cloud, sharing, CSV export.
- Chart smoothing that would hide real noise.
- A second aggregate chart on Live.

### Chart behaviour details

- Default on first open: `24H`, `All probes`.
- If the user arrived by tapping P1's tile: `1H`, `P1` selected.
- If only one probe has data, keep the chips honest; do not silently hide the
  other probes.
- Y-axis: 4–5 nice ticks, shared across visible series. Do not auto-scale to a
  single point or produce `263°` ticks.
- X-axis: local timezone; `6:00 PM` style with locale support; date at
  midnight for multi-day ranges.
- Line: 2.5 px, round caps/joins, 8% area fill for a single selected series
  only. Do not fill four overlapping series.
- Gaps: muted hatched band + a short label when wide enough; dashed vertical
  edges when narrow. A gap is information, not an error.
- Missing-from-bridge: a distinct gap reason and copy:
  “The bridge overwrote this range before it synced.”
- No data: no line, no zero, and `No data in this range` in Summary.
- Units: one conversion path for tiles, axis, tooltip, summary and Billows.
- Data volume: SQL-bucket long ranges; LTTB plus min/max envelope; never pass
  more than a few thousand points to the painter.
- Performance: keep chart state out of the 30 s live rebuild unless the chart
  is visible; `RepaintBoundary`; `shouldRepaint` on a revision counter.
- Accessibility: expose a summary like “History, 24 hours, P1 last 165.2,
  minimum 151, maximum 182” and make Summary the accessible table view.

### Summary and sorting

The summary is where sorting belongs. A time series is inherently chronological;
sorting the chart itself would be meaningless.

| Field | Meaning |
|---|---|
| `Current` | Newest valid reading in range |
| `Min` | Lowest valid reading in range |
| `Max` | Highest valid reading in range |
| `No data` | No valid reading for that probe in range |

There are no temperature deltas. Default order is probe order. The sort menu
offers hottest now, highest peak, most recent and since cook started. The last
option detects the active cook from recorded sample timestamps (falling back to
the latest past cook) and shows that start age above the rows. Tapping a row
selects/focuses that probe.

### Past cooks

Show detected cook sessions derived from recorded readings and gaps. Each row
carries the date, exact start/end time, duration, probe count and gap state.
Tapping a row opens a **new Past cook view** with that historical graph and
summary. It does not change the current History tab, which stays on the current
cook (or its own range when there is no current cook). `Past cooks` in the filter
header opens the full list; the summary card shows the most recent three. This
gives the archive a browseable structure without inventing named or user-created
sessions.

---

## 11.7 Settings

### New root

```
Settings

BRIDGE
┌────────────────────────────────────────────┐
│ Backyard Bridge                          > │
│ Bridge A4F2 · Bluetooth                    │
│ ● Connected                    Battery 87%  │
│ Signal ▂▄▆▁ Fair                            │
│ Last contact 4s ago                         │
│ [ Sync now ]                               │
└────────────────────────────────────────────┘

HISTORY & STORAGE
  Device & Bridge logs  128,430 device · 24,810 Bridge >

PREFERENCES
  Temperature units                    [°F][°C]
  Appearance                           System >

ABOUT
  About                                App 0.1.0 >
```

- There is one Bridge section: the status header is the only row on the root.
  Smoke X4 pairing, Billows, Bridge name and Bridge screen timeout live inside
  Bridge details. Do not add a second `Bridge` group.
- Settings shows Bridge first, then History & storage, then Preferences. The
  Bridge status header is the status and primary sync action. Tapping the header
  opens Bridge details; there is no separate `Bridge details` button.
- The Bridge status header uses a cell-style signal meter with an
  `Excellent / Good / Fair / Weak` label on its own row, plus battery and
  `Last contact`. It does not repeat `Connected for 2h 14m`; the status LED and
  `Connected` label already say that.
- `History & storage` is one destination row. The sub-view shows the Device log
  and Bridge log together with their separate deletion rules.
- If offline, the header says `Offline · last connected 2h ago` and the button
  becomes `Reconnect`.
- The app bar on Settings does not need a second status chip; the Bridge section
  is the status surface.
- Destructive actions are not a top-level section. They live at the bottom of
  Bridge details, where the object they affect is unambiguous.
- No `Device settings` screen, no `Actions` screen, no `Probe names & roles`.

### Current → proposed mapping

| Current | Problem | Proposed |
|---|---|---|
| `Connection` group | Mixes status, pairing, action and destructive row | `Bridge` group + bridge status card |
| `Bridge` row | Opens the same screen as `Smoke X4` | Bridge status card → Bridge details |
| `Smoke X4` row | Duplicate destination | `Smoke X4` row → pairing detail |
| `Sync now` row with chevron | Looks like navigation, performs an action | `Sync now` button in bridge card |
| `Forget this phone` in Connection and Actions | Duplicated destructive path | One row in Bridge details → “This phone” |
| `Device` group | Ambiguous: phone or bridge? | `Preferences` (app) + `Bridge` (device) |
| `Units` row → full screen → Save | Two taps plus save for a two-choice preference | Inline `[°F][°C]` at top of Settings, immediate |
| `Display timeout` | What display? | `Bridge screen timeout`, inline choices |
| `Probe names & roles` | Out of MVP; fake names | Removed everywhere |
| `Billows` under Device | Billows is not a display setting | `Bridge > Billows` |
| `Device name` | Ambiguous | `Bridge name` (app-facing label) |
| `Data` group with four rows | Three rows open the same screen, one duplicates sync | `History & storage` with Device log / Bridge log rows |
| `Delete recorded data` | Technical; hides 30/90/all options | `Delete device log…` one action with options |
| `Clear bridge history` | “History” ambiguous | `Clear bridge log…` inside Bridge log |
| `Actions` group/screen | A container for three unrelated actions | Bridge details > Bridge actions |
| `Power off bridge` | Correct label, wrong location | Bridge details > Bridge actions |
| `Factory reset` | Ambiguous object | `Factory reset bridge` in Bridge actions |
| `About this build` | Fine destination, wrong prototype content | `About`, with a debug-only lab entry |
| App bar theme toggle | Prototype control | `Preferences > Appearance` |
| App bar flask icon | Prototype control | Debug-only, via About or lab build |

### Temperature units

- Top-level `Temperature units` segmented control: `°F` / `°C`.
- Applies immediately to Live, sparklines, History axis/tooltip/summary,
  the Billows target readout, destructive copy and the bridge OLED.
- No `Save changes` button.
- If the bridge is offline, change the phone display immediately and show
  `The bridge OLED will update when it reconnects.` Do not block the toggle.
- Add a widget test that flips units and checks Live, History and Billows in the
  same frame.

### Save model

| Control | Behaviour |
|---|---|
| Temperature units | Immediate; local change + queued bridge write if offline |
| Appearance | Immediate; local only |
| Bridge screen timeout | Immediate; requires connection, disabled with reason offline |
| Bridge name | Edit in a small dialog; apply on Done; inline `Saving…` / `Saved` / `Couldn’t save` |
| Billows | Read-only; detection/last-seen only. No mode or target write. |
| Destructive actions | Confirmation sheet with exact loss, count and range |

Remove bottom `Save changes` bars. A preference should not need a second tap to
take effect. Do not show a global success banner for a successful write; a small
inline state is enough.

### Bridge details

```
Bridge
┌────────────────────────────────────────────┐
│ Smoke X4 Bridge A4F2        ● Connected     │
│ Updated 4s ago · Battery 87% · Signal good  │
│ [ Sync now ]  [ Disconnect ]                │
└────────────────────────────────────────────┘
Smoke X4
  Paired · last packet 12s ago
  [ Re-pair Smoke X4 ]
  Re-pairing keeps the log and phone pairings.

Technical details (collapsed)
  Device ID, firmware, protocol, MTU, RSSI

Bridge actions
  Power off bridge
  Factory reset bridge

This phone
  Forget this phone
```

- Move `MTU`, `RSSI`, `protocol`, `GATT` and `characteristic` language into
  `Technical details` or `About > Diagnostics`.
- Keep `Firmware` visible if it helps support; keep the full technical block
  collapsed by default.
- `Power off`, `Factory reset` and `Forget this phone` are action rows, not
  navigation rows. No chevrons.
- Remove “The current cook is not ended or deleted” from power-off copy. There
  are no cook sessions in this product.

### History & storage

Two clearly labelled copies, not three duplicated deletion rows:

```
DEVICE LOG
  128,430 readings · Sep 1 – Oct 24 · 9.2 MB
  Stays on this device even if the bridge is reset.
  [ Delete device log… ]

BRIDGE LOG
  24,810 of 338,400 readings · 7.3% · ~117 days capacity
  Oldest Oct 17 · Newest Oct 25
  The bridge overwrites its oldest readings automatically.
  [ Clear bridge log… ]        (connected only)
```

- `Delete device log…` opens a sheet with `Older than 30 days`, `Older than
  90 days`, `Everything`, showing the exact count and date range before the
  final confirmation.
- `Clear bridge log…` is a separate bridge action and says the device log is
  kept.
- Use **readings**, not **records**, in user-facing copy.
- No auto-delete; no “sectors”, “ring” or “generation” in user copy.

### About

- App version/build, bridge firmware, protocol, bridge ID.
- USB-only firmware update note.
- Privacy: no cloud, no account, data stays on the phone and bridge.
- Attribution: Smoke X protocol decoding derives from G-Two/smoke-x-receiver
  (MIT © 2022 G-Two). Not affiliated with or endorsed by ThermoWorks. Smoke X is
  a trademark of its owner.
- No “Prototype mode” card in the product. Debug builds show an
  `Experimental lab` item in the app-bar menu; release builds hide it unless
  enabled with `--dart-define=ENABLE_EXPERIMENTAL_LAB=true`.

### Offline behaviour

| Control | Offline |
|---|---|
| Temperature units | Local change; bridge write queued |
| Appearance | Available |
| Bridge screen timeout | Disabled with `Connect to change this` |
| Smoke X4 pairing | Disabled with reason |
| Billows status | Last observed attached/target visible; no action |
| Bridge name | Disabled with reason |
| Sync now | Becomes `Reconnect` |
| Delete device log | Available |
| Clear bridge log | Disabled |
| Power off / factory reset | Disabled |
| Forget this phone | Available (local clear) |

Show one global offline banner, not a `Connect to edit` notice on every
subscreen. Each disabled control gets a short inline reason.

---

## 11.8 Setup

The setup flow is structurally fine. The problem is that it reads like a
technical demo and shows prototype controls.

### Changes

- `Set up bridge` → `Connect bridge`.
- `No bridge yet.` → `Connect your bridge`.
- Body: “Power it on. If the screen is off, hold PRG for 1.5 seconds.” Keep the
  full technical explanation out of the first screen.
- `Find bridge` stays. If saved device log exists, `View device log` is
  the secondary action.
- Move the permission explanation into a contextual pre-permission sheet after
  tapping `Find bridge`. Do not put an Android-version table on the first
  screen.
- Scan results: `Nearby bridges`, remembered first. Show signal as
  `Strong / Good / Weak` and keep dBm in a detail line.
- Pairing page: show the OLED instruction and the code illustration. The
  simulated Android prompt belongs in the lab, not the product flow.
- Bonding steps: `Connecting`, `Pairing with code`, `Syncing recent history`.
  Remove `Connect to GATT` and `Secure characteristics`.
- First sync: `Loading history`; `Recent readings are ready. Older history
  continues in the background.` Primary action `Start monitoring`.
- Error states: one primary action + one text link. Remove the extra
  `Back to scan` / footer option where the primary already covers it.
- Remove `Prototype · no device is contacted` from every page.
- Remove `Simulate scan results`, `Simulate successful bond` and
  `Simulate wrong code` from product pages; expose them in the lab only.
- Rename `Saved data` to `Device log` everywhere.
- Keep the `stale bond`, `bond store full`, `wrong code` and `no prompt` states;
  rewrite them in plain language:
  - `This bridge already has 4 phones paired.`
  - `This phone’s pairing is out of date.`
  - `The code didn’t match.`
  - `No prompt appeared. Check the notification shade.`

---

## 11.9 OLED

- Page 1 uses `P1`–`P4` only:
  ```
  P1        225.0
  P2        165.2
  P3          ---
  P4         80.0

  ● BLE   ● X4   87%
  ```
- Remove `FOOD`, `GRATE`, `AMBIENT`, `UNUSED` and the custom-name note from
  [07](07-display-and-controls.md).
- P4 is the fixed Billows/pit channel on Smoke X4. That is hardware behavior,
  not a user-editable role.
- Page 2: `Phones paired 2/4` is fine; use `paired`, not `bonded`, in user copy.
- Page 3: Billows detected, the Smoke X4 channel 4 set temp, P4 pit. Do not
  imply the fan is running or that the app can change the target.
- Page 4: diagnostics are appropriate on the OLED.
- Update the OLED preview in the lab and the `07` diagrams.

---

## 11.10 Prototype lab

The lab is a review tool, not a product screen.

- Remove the flask icon and theme toggle from product app bars.
- In debug builds, open the lab from `About` (long-press the version row or a
  `Prototype lab` row). The release build has no entry.
- Put the theme switch in the lab header.
- Rename `Graph` scenarios to `History`.
- Remove `Probe names & roles`, `Device settings` and `Actions` scenarios that
  no longer exist.
- Add:
  - Live: sparkline present / one probe no history / detached with history /
    all tiles stale / offline cache.
  - History: 1h/6h/24h/7d/all, probe filter, no data in range, custom range,
    crosshair, full-screen, summary sort, past cooks, gap reasons.
  - Settings: units °C, immediate-save states, offline, device log delete
    options, bridge log clear, bridge actions.
- Keep the lab’s search, reset and “start first-run flow”.
- Rename the `Saved data (orphaned)` scenario to `Device log (orphaned)`.

---

## 11.11 Design system

### Colour

Keep the warm charcoal/ember direction. Reserve red for errors and destructive
actions. P4 is currently error-red; move it to violet.

| Token | Dark | Light | Use |
|---|---|---|---|
| Background | `#0F0D0B` | `#F8F4EF` | Scaffold |
| Surface | `#191512` | `#FFFFFF` | Cards |
| Surface raised | `#221D18` | `#FFFFFF` | Sheets/dialogs |
| Text | `#F7F1E8` | `#211A15` | Primary |
| Text secondary | `#B8ADA2` | `#6B6157` | Supporting |
| Outline | `#3D352D` | `#E3D9CE` | Borders/dividers |
| Ember | `#F07A4F` | `#C6532F` | Primary action/selection |
| Live | `#4CC38A` | `#2E7D52` | Connected/current |
| Attention | `#E9A83E` | `#8A5A12` | Delayed/no new reading |
| Error | `#F06A6A` | `#B3261E` | Failure/destructive |

Probe palette:

| Probe | Dark | Light |
|---|---|---|
| P1 | `#F2B35E` amber | `#9B5B0C` |
| P2 | `#64C7A2` teal | `#267354` |
| P3 | `#7EA6F8` blue | `#3F62A8` |
| P4 | `#C08AF0` violet | `#7B4AA8` |

- Every series also carries a `P` label; colour is never the only identity.
- Chart lines need 3:1 contrast against the chart surface; labels 4.5:1.
- Remove the duplicate `ProbeColorsAccessor`; use one theme extension/palette.

### Typography

- Tabular figures for every temperature and axis label.
- Live temperature: 40–46 px on phone, weight 700, `°F`/`°C` in a smaller
  suffix.
- Screen title: 22–26. Section title: 18–20. Body: 14–15. Labels: 11–12.
- Chart axis labels: 11–12, not 10. At arm’s length, 10 px is decoration.
- Section headers can stay small caps but use sentence case in body copy.
- Use locale-aware time formatting, not hard-coded `5:30p`.

### Spacing, shape, motion

- 4/8 px spacing grid; 16 px screen gutter; 12 px grid gap.
- Cards: 16 px padding, 16–18 px radius. Controls: 12 px radius. Chips: full
  pill.
- Borders and tonal surfaces, not heavy shadows.
- Motion 150–220 ms ease-out. Chart range changes crossfade; no bouncy
  transitions.
- Haptics: light impact on range/filter change; selection tick when scrubbing to
  a sample; success haptic only for a confirmed device action.

### Accessibility

- 48 dp minimum targets; probe tiles and chart controls included.
- Dynamic type: do not lock temperature text; allow wrapping or scale the
  container, not the font below readability.
- Semantics for tiles, chart summary, connection card, range chips and
  destructive rows.
- Reduce-motion support.
- Chart information duplicated in the Summary table.
- No colour-only state: use text and icons as well.

---

## 11.12 Naming and copy

### Dictionary

| Use | Do not use |
|---|---|
| **Live** | Dashboard, Now, Monitor (as a tab) |
| **History** | Graph, Probe history, Chart (as a tab) |
| **Device log** | Saved data, recorded data, local data |
| **Bridge log** | Bridge storage, bridge history, ring, sectors |
| **Readings** | Records, points, samples (in user copy) |
| **Pairing / paired** | Bond / bonded (in user copy) |
| **Bridge name** | Device name |
| **Bridge screen timeout** | Display timeout |
| **Detected** (Billows) | Connected, attached, monitor only |
| **No new readings for 4m** | Stale, aging, frozen |
| **Can’t reach the Bridge** | Lost the Bridge (unless it is a hard failure) |
| **Technical details** | MTU/RSSI/protocol on the main screen |

### Key copy changes

| Current | Proposed |
|---|---|
| `Graph` | `History` |
| `Probe history` | Removed; app bar is `History` |
| `Legend` | `Probes` filter/legend |
| `Range summary` | `Summary` |
| `Plot points` | Removed; use `readings` if needed |
| `Live · updated 4s ago` on every tile | Connection card with last contact/data; exceptions only |
| `Aging · 62 s since last reading` | `Updated 62s ago` |
| `Last reading 4m ago` | `No new reading for 4m` |
| `No readings for 12m` ×4 | One banner + dimmed values |
| `Data` | `History & storage` |
| `Actions` | `Bridge actions` (inside Bridge details) |
| `Device settings` | Removed; split into Preferences and Bridge |
| `Probe names & roles` | Removed |
| `Delete recorded data` | `Delete device log…` |
| `Clear bridge history` | `Clear bridge log…` |
| `Factory reset` | `Factory reset bridge` |
| `Saved data` | `Device log` |
| `Records` | `Readings` |
| `Attached` (Billows) | `Detected` |
| `Observe` / `Monitor only` | Removed; there is no control mode |
| `Bonding…` | `Pairing…` |
| `Connect to GATT` | `Connecting` |
| `Bond with passkey` | `Pairing with code` |
| `Secure characteristics` | `Securing connection` |
| `Protocol mismatch` | `App update needed` |
| `Stale bond` | `Pairing is out of date` |
| `Bond store full` | `4 phones already paired` |
| `MTU 23 (slow link)` | `Slow Bluetooth link` (Technical details) |
| `RSSI -71 dBm` | `Signal: good` (Technical details) |
| `The current cook is not ended or deleted` | Removed; there are no cook sessions |
| `The bridge rotates oldest sectors…` | `The bridge overwrites its oldest readings automatically.` |
| `The recent graph is useful immediately` | `Recent history is ready first` |
| `Enable Billows in Settings > Device > Billows` | Remove circular copy; Billows status is read-only in `Bridge > Billows` |

### Tone

- State first, action second.
- One sentence per idea.
- No raw implementation nouns in product copy.
- Use exact counts and date ranges for loss.
- Reassure that the bridge keeps recording and device log is kept where
  true.
- Do not blame the user; name the next step.

---

## 11.13 Model and implementation notes

### Remove probe identity from the model

- `Probe` becomes `{ number, tempF, health }`.
- Remove `name`, `role`, `probeNames`, `probeRoles`, `setProbeName`,
  `setProbeRole`, `ProbeEditorScreen` and all settings/lab references.
- History legend, Summary, tooltip and OLED use `P1`–`P4`.
- Keep the per-probe color mapping in one `ProbePalette`.

### Remove probe names/roles from the contract

The config currently spends 52 of its 80 bytes on `probe_name[4][12]` and
`probe_role[4]`. Since M0 has not started, remove the fields and their
validation from the design now. Keep the 80-byte characteristic with those
bytes reserved so packet size does not churn; or compact it later at the M0
contract freeze.

- `pit_temp_f10` becomes the fixed P4/pit reading, not “P1 or role grate”.
- `device_name` stays as the optional **Bridge name**.
- `probe_name` / `probe_role` stay out of the app, OLED and config validation.
- If probe names return after MVP, add them with a protocol version bump, not a
  dead UI path now.

### Sparkline model

```dart
class ProbeHistory {
  final int probe;              // 1..4
  final List<ChartPoint> points; // valueF == null at a gap
  final double? last;
  final double? min;
  final double? max;
  final DateTime? lastSampleAt;
  bool get hasData => last != null;
}
```

- Query the last hour for all four probes in one pass where possible.
- Decimate to roughly one point per horizontal pixel (a sparkline needs far
  fewer).
- Scale each sparkline to its own min/max with 10% padding.
- Draw no axis, no grid, no labels. One line, optional subtle area fill, end dot.
- A gap ends the line; never join across it.
- Empty: quiet `No history yet`, not a zero line.
- Tap target is the tile, not the sparkline; one route to History.

### History model

```dart
class HistoryQuery {
  final HistoryRange range;
  final int? probe;       // null = all
  final DateTimeRange? customRange;
}

class GapInfo {
  final DateTime start;
  final DateTime end;
  final GapReason reason; // noSignal, bridgeOff, bridgeRotated, unknown
}

class ProbeStats {
  final int probe;
  final double? last;
  final double? first;
  final double? min;
  final double? max;
  final double? average;
  final int readingCount;
}
```

- `sample` already has `p1..p4`; no schema change for per-probe sparklines or
  filters.
- `gap` already has `reason`; use it instead of the fixed `missing` marker.
- `HistoryRange` is the renamed `GraphRange`; add `custom`.
- Persist range/filter/sort in the controller or a small view-model so tab
  switches do not reset them.
- Compute Summary from raw/bucketed data; never show the decimated point count.

### Chart implementation

- Keep the custom painter. It already gives exact control over gaps, bands and
  end dots; adding `fl_chart` now would duplicate chart concepts and make gap
  rendering harder.
- Split into:
  - `HistoryChartPainter` (paint only),
  - `HistoryChartController` (viewport, selected index, hit testing),
  - `HistoryChart` (gestures, tooltip overlay, semantics),
  - `Sparkline` (axis-free, relative).
- Add a pure-Dart `niceTicks(min, max)` and table-test it.
- Use locale-aware time labels.
- Gesture arena: horizontal pan/pinch must win over vertical page scroll only
  after horizontal intent. Full-screen chart removes the conflict for precise
  work.
- Tooltip as a Flutter widget in a `Stack`, not painted text, so it is
  accessible and can be pinned.
- `RepaintBoundary` + revision counter; do not rebuild the chart on unrelated
  controller notifications.

### Settings implementation

- Move Bridge details and History & storage into
  `bridge_details.dart` / `settings_views.dart`; keep Billows, RePair,
  Device log, power-off and shared confirmation sheets in
  `settings_details.dart` for the prototype. `ProbeEditorScreen` and
  `ActionsScreen` are removed.
- One source of truth for destructive copy; the product paths and the lab
  confirmation preview should share the same helpers.
- In production, `Units`, `Appearance` and `Bridge screen timeout` should write
  through a small `SettingsWriter` that exposes `idle/saving/saved/error` per
  field, not one global save state.
- The prototype applies choices immediately to controller state and uses
  `simulateSave` only where a device acknowledgement is being demonstrated.

### Test keys / harness hooks

Add stable keys now so the harness does not depend on changing labels:

- `live.probe.1` … `live.probe.4`
- `live.sparkline.1` … `live.sparkline.4`
- `live.billows`
- `status.connection`
- `history.chart`, `history.range.1h`, `history.filter.all`,
  `history.filter.p1`, `history.summary`, `history.sort`, `history.cooks.open`
- `pastCook.history`
- `settings.units`, `settings.appearance`, `settings.bridge.status`,
  `settings.bridge.sync`, `settings.bridge.smoke`, `settings.bridge.billows`,
  `settings.bridge.name`, `settings.bridge.timeout`
- `settings.history.phone`, `settings.history.bridge`

### Files likely touched

| File | Change |
|---|---|
| `app/lib/features/shell/app_shell.dart` | `History` tab, no app-bar status chip, no duplicate title |
| `app/lib/features/live/live_screen.dart` | Remove preview graph; sparklines; compact states; Billows |
| `app/lib/features/history/history_screen.dart` | History screen; filters, chart, summary, days |
| `app/lib/widgets/probe_chart.dart` | Split sparkline/history chart; palette; tooltip; ticks |
| `app/lib/widgets/prototype_widgets.dart` | Probe tile, status strip, conditional banner, chips |
| `app/lib/features/settings/settings_screen.dart` | New root; units; bridge card |
| `app/lib/features/settings/settings_details.dart` | Split; remove probe editor/actions; new flows |
| `app/lib/features/setup/setup_screen.dart` | Copy, permission flow, remove simulation controls |
| `app/lib/features/device/device_preview_screen.dart` | P1–P4 only |
| `app/lib/prototype/prototype_controller.dart` | Remove probe names/roles; history state; units |
| `app/lib/prototype/fixtures.dart` | Per-probe series, gap reasons, no-data states |
| `app/lib/prototype/scenario_lab.dart` | History group; new states; lab-only chrome |
| `app/lib/theme/app_theme.dart` | Palette, type, one probe palette |
| `app/lib/widgets/prototype_app_bar.dart` | Remove theme toggle/lab icon |
| `app/test/widget_test.dart` | New IA, units, sparkline, no names |
| `app/tool/ui_screenshots_test.dart` | New screenshot set |
| `app/screenshots/README.md` | New names and states |

---

## 11.14 Docs and tasks to change after approval

| Doc/task | Change |
|---|---|
| [00](00-product.md) | `Live / History / Settings`; remove probe names/roles from MVP acceptance; update success criteria and screen descriptions. |
| [05](05-ble-contract.md) | Remove `probe_name`/`probe_role`; P4 fixed pit; update config validation/size; remove role language from `pit_temp_f10`. |
| [06](06-app.md) | Rewrite §6.1, §6.5, §6.6, §6.7, §6.8. Add units, sparklines, History filters/summary/days, settings IA, prototype-chrome rule. |
| [07](07-display-and-controls.md) | Page 1 P1–P4 only; remove role/name copy; P4 as Billows channel. |
| [README](README.md) | Add decisions D16–D20 (see below). |
| `M0` T0.5 | Shell placeholder tabs: Live / History / Settings. |
| `M3` A3.3 | Rename to History; range/filter/crosshair/zoom/summary/days; sparkline query; gap reasons. |
| `M3` A3.6 | Add emptiness per range/probe; no aggregate preview. |
| `M4` A4.1 | New settings root (Preferences/Bridge/History & storage/About). |
| `M4` A4.2 | Units inline; remove probe names/roles; split bridge settings; immediate save. |
| `M4` A4.4 | Remove probe labels from Live/History/OLED; units only. |
| `M2` V0 | Add the live sparkline requirement (last 15 min) or explicitly defer the full History chart to M3. |
| `M6` V6.4 | Remove debug-only UI; verify no lab entry in release. |
| `app/screenshots/README.md` | Rename `graph_*` to `history_*`; remove `device`, `probe_editor`, `actions` screenshots; add new states. |

Proposed decisions for the design README:

- **D16 — Probe identity is P1–P4 + color.** No names, roles or tags in the MVP
  UI, OLED or config.
- **D17 — Live shows per-probe sparklines; no aggregate graph.** History is the
  only multi-probe chart.
- **D18 — History is a first-class archive**, with filters, crosshair,
  zoom/pan, summary and past cooks. It is not a demo chart.
- **D19 — Settings is object-based.** Units are top-level and immediate;
  destructive actions live with the object they affect; no `Actions` screen.
- **D20 — Prototype chrome is lab-only.** Product screens use production copy,
  no simulation controls, no theme/lab icons in the app bar.

---

## 11.15 Rollout and acceptance

### Sequence

1. **P0 — Align the docs and contract** (before M0 codegen)
   - Rename Graph → History in docs/tasks.
   - Remove probe names/roles from UI, OLED, config validation and tasks.
   - Add units/settings/IA decisions.
2. **P1 — Design system and shell**
   - Palette, typography, probe palette, status strip, nav rename.
   - Remove prototype chrome from product app bars.
3. **P2 — Live**
   - Probe tiles, sparklines, exception-only status, Billows, remove preview.
   - Review checkpoint: screenshots of Live dark/light/offline/billows.
4. **P3 — History**
   - Chart, filters, crosshair, zoom/pan, summary, days, states.
   - Review checkpoint: screenshots of all ranges, filters, no-data, offline.
5. **P4 — Settings**
   - New root, units, bridge details, history & storage, about, destructive
     actions.
6. **P5 — Setup, OLED, lab, tests, screenshots, docs**
   - Production copy, lab-only simulation, new golden set, widget tests.

### Acceptance criteria

- No probe names, roles, tags or `GRATE`/`FOOD` labels anywhere in the product
  UI, OLED preview or history legend.
- No `Graph` label in the product UI; tab and screen are `History`.
- Live has four tiles; each shows a relative 1 h sparkline when that probe has
  data; no aggregate preview graph.
- History has range presets, custom range, probe filters, crosshair, pinch/pan,
  reset/Now, gap reasons, summary and sorting.
- Settings has a top-level °F/°C control that applies immediately; no save-all
  bar for units/timeout.
- No `Actions` screen, no `Probe names & roles`, no duplicate `Sync now` /
  `Forget this phone` / storage rows.
- No `Prototype · no device is contacted`, `Simulate…`, theme toggle or lab icon
  on product screens.
- Chart labels are at least 11 px; P4 is not error-red; tabular figures on
  temperatures.
- Dark/light both pass contrast; touch targets at least 48 dp; chart has a
  screen-reader summary.
- `flutter analyze` and `flutter test` are clean; new widget tests cover units,
  sparklines, no-data and history filters.
- Screenshot set regenerated and README updated.

---

## 11.16 Decisions I need from you

I recommend all four; they are the ones that change implementation rather than
just visuals.

1. **Remove probe names/roles from the contract now, not just the UI.**
   *Recommendation: yes.* It removes dead config bytes, dead edit flows and
   dead OLED copy before M0. Keep the 80-byte characteristic with reserved bytes
   for now.
2. **Sparkline window on Live = fixed last 1 hour, relative scale.**
   *Recommendation: yes.* It is predictable, cheap to query, and tapping the
   tile opens History with the same 1 h / P# filter.
3. **History scope = the full recommended set**, including custom range,
   full-screen, summary sorting and past cooks.
   *Recommendation: yes.* These are front-end-only features and are what make
   History feel like a tool rather than a mock. If schedule pressure appears,
   ship presets/filters/crosshair/summary first and defer custom range/day
   groups to the polish pass.
4. **Keep an optional bridge name**, renamed from “Device name”, in Bridge
   details. *Recommendation: yes.* It is the bridge’s label, not a probe tag,
   and it helps multi-phone households later. If you want the absolute minimum,
   remove it from MVP too.

If you approve, I would start with P0 and P1, then bring you Live and Settings
screenshots for a checkpoint before doing the full History pass.

---

## 11.17 Research notes

What informed the proposal:

- **FireBoard** — Summary/Chart views, per-channel sparklines, single-channel
  zoomable view with date range, tap-for-time/temperature, pinch/double-tap
  zoom, drag pan, latest-value indicator, sessions by date.
  [Dashboard docs](https://docs.fireboard.io/app/app-dashboard) ·
  [App basics](https://www.fireboard.com/blog/the-fireboard-app-basics-part-1/)
- **ThermoWorks** — per-probe graphs, saved graphs, units in device/sensor
  settings, explicit graph interruption when the link is lost.
  [ThermoWorks BBQ app help](https://help.thermoworks.com/knowledge-base/thermoworks-bbq-app/)
- **MEATER** — hero internal/ambient temperatures, target, estimate; the graph
  supports the number. [App features](https://www.meater.com/app-features)
- **Combustion** — real-time graphing with scrubbing and target/prediction.
  [App and release notes](https://combustion.inc/pages/product-release-notes)
- **Weber Connect** — live temperature graphing and a dashboard of multiple
  recipes/timers. [Weber Connect](https://www.weber.com/us/en/weber-smart-products.html)
- **Material / Android settings** — current values at a glance, grouped
  settings, appropriate selection controls, destructive actions separated.
  [Android settings pattern](https://developer.android.com/design/ui/mobile/guides/patterns/settings) ·
  [Android settings guidelines](https://source.android.com/docs/core/settings/settings-guidelines)
- **Sparkline / stat panel guidance** — inline, axis-free trend for glanceable
  current values. [CDC sparkline](https://www.cdc.gov/cove/data-visualization-types/sparkline.html) ·
  [Grafana stat](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/stat/)
- **Chart interaction** — crosshair/trackball, tooltip, zoom/pan, range
  selection. [Syncfusion chart interaction](https://www.syncfusion.com/charts/interactivity)
