# 12 — Copy & Label Review (Proposal)

**Status:** Proposal for review — not yet applied · **Date:** 2026-10-26  
**Scope:** every user-visible string in `app/lib`, the Experimental lab, the
OLED preview, the screenshot set, and the destructive/confirmation flows.  
**Baseline:** the current `app/` mockup and the approved UI direction in
[11 — UI/UX Refresh](11-ui-ux-refresh-proposal.md).

I reviewed the copy against Material 3 and Android platform conventions,
leading cooking and telemetry apps, accessibility guidance, and the product’s
own trust invariants. I did not run the app on hardware; hardware-dependent
wording is flagged where it needs confirmation.

---

## 12.1 Verdict

The structure is strong. The copy is not yet product-ready.

| Dimension | Score | Comment |
|---|---:|---|
| Information architecture | 8/10 | Three destinations with clear jobs. No redundant tabs. |
| Data honesty | 8/10 | Gaps, `—`, and “never 0 °F” are excellent. Stale Billows and empty-history metadata break the rule. |
| Copy clarity | 5.5/10 | Too much hardware vocabulary and several internal design rules leaked into the UI. |
| Consistency | 5/10 | “Device” means two different things; time/temperature/unit formatting varies by screen. |
| Accessibility | 6.5/10 | Good semantics on probes and chart summary; some small tap targets, wrapped buttons, and color/contrast risks. |
| Product readiness | 6/10 | “(simulated)”, “in this build”, and “Simulate hold PRG” remain on product surfaces. |
| Lab quality | 7.5/10 | Excellent state coverage. Name drift, factual counts, and paraphrased product copy reduce its value as a review tool. |

### What is already top-tier and should not change

- Three destinations: **Live**, **History**, **Settings**.
- Probe identity as **P1–P4 + colour**, never colour alone.
- A detached probe is `—` + “Not connected”, never `0 °F`.
- Gaps are rendered as gaps; history is never silently deleted.
- Destructive sheets name the object, the exact count, and the date range.
- “The Bridge keeps recording” is repeated where it matters.
- Settings apply immediately; there is no save-all bar.
- Billows is honest about being observation-only.
- The warm charcoal/ember identity is distinctive and worth protecting.
- The Experimental lab is a genuinely useful review surface.

---

## 12.2 The five changes that matter most

If only five things are changed before the next usability review:

1. **Make the Bluetooth permission rationale match the Android version.**
   The app supports Android 7+; Android 11 and below require location permission
   for BLE scanning. The current primer says location is never used and only
   mentions Nearby devices on Android 12+.
2. **End the “device” collision.** “Device log” currently means *the phone*,
   while “Device ID” and “Device display” mean *the Bridge*. A user can delete
   the wrong copy because the labels do not distinguish them.
3. **Fix the PRG instruction.** “If the screen is off, hold PRG” can power the
   Bridge off while the user is trying to wake it. Press wakes the screen; hold
   powers off/on.
4. **Never show stale Billows as live.** In the offline-cache state the Billows
   card stays bright and says “Detected”, with no timestamp. That directly
   violates the “app never presents stale data as live” invariant.
5. **Fix the empty-history contradiction.** The empty History screen says
   “No readings yet” and, directly above it, “Saved 2m ago · 4 probes.”

---

## 12.3 Stack-ranked proposal

`P0` = correctness/trust, fix before a public build or usability test.  
`P1` = next copy pass. `P2` = polish. Effort: S/M/L.

| # | Priority | Change | Why it matters | Effort |
|---:|---|---|---|---|
| 1 | P0 | Make the permission primer OS-version aware | Android 7–11 asks for location to scan BLE; the current copy denies it | M |
| 2 | P0 | Replace “device” with “phone” or “Bridge” everywhere | Two meanings, including in destructive storage actions | M |
| 3 | P0 | Correct PRG copy: press to wake, hold to power off/on | Current copy can turn the Bridge off during troubleshooting | S |
| 4 | P0 | Label stale Billows state with time/source, or hide it offline | Violates the core “never stale as live” rule | M |
| 5 | P0 | Fix the passkey illustration contradiction | Says “the app never shows it” while showing a code | S |
| 6 | P0 | Remove prototype/debug copy from product screens | “(simulated)”, “in this build”, “no OTA path” undermine trust | M |
| 7 | P0 | Make history metadata truthful when empty/partial | “No readings yet” + “Saved 2m ago · 4 probes” is a visible contradiction | S |
| 8 | P1 | Rename “Past cooks” and fix “Current”/“Hottest now” | An in-progress cook under “Past cooks”; “Current” is false in history | M |
| 9 | P1 | Standardize freshness language; remove repeated stale lines | “Last contact”, “Saved”, “Last data”, “No new 4m” mean different things | M |
| 10 | P1 | Clarify Live probe cards: timeframe, delta, empty history | Bare “1h” and “+3.8°” are unexplained; no “Probes” heading | S |
| 11 | P1 | Purge hardware jargon from product surfaces | OLED, BLE, CH 4, Database, dBm, heltec3 are not user language | M |
| 12 | P1 | Simplify the Billows card and Billows screen | “Read-only” appears three times; “Status: Detected” adds no information | M |
| 13 | P1 | Replace cryptic history range labels | `24H` vs `24 h` vs `Custom` vs `Entire memory` | S |
| 14 | P1 | Keep action labels stable when disabled; move reasons to helper text | “Connect to clear the Bridge log” is an instruction, not a label | M |
| 15 | P1 | Clean up destructive copy and shorten button labels | Duplicate bullets, “advertising as new”, wrapped “Factory reset Bridge” | M |
| 16 | P1 | Remove “never 0 °F” from user copy | It is a QA rule, not guidance for a cook | S |
| 17 | P1 | Un-duplicate the setup title/eyebrow and use sentence case | App bar, eyebrow, and title all repeat the same instruction | S |
| 18 | P1 | Remove overpromising and dead-end actions | “Start monitoring” implies alerts; “Close” strands users | S |
| 19 | P1 | Define temperature/time/count formatting | `165.2 °F` vs `166.0°`; `2 h` vs `2h`; `10 m` vs “10 minutes” | M |
| 20 | P1 | Fix chart labels, axes, gap reasons, and help copy | Repeated degree signs, duplicate multi-day dates, “Overwritten” | M |
| 21 | P2 | Fix Settings root grammar and labels | “128,430 device · 24,810 Bridge readings” is ungrammatical | S |
| 22 | P2 | Correct About/technical claims | “Model heltec3”, “OTA path”, duplicate app version | S |
| 23 | P2 | Unify Experimental lab naming and factual counts | “Experimental lab” vs “Scenario lab”; “four overlays” is seven | S |
| 24 | P2 | Make lab scenarios use product copy verbatim | Lab paraphrases create copy drift during review | M |
| 25 | P2 | Fix OLED labels and page copy | `LMXC[`, `Pit`, `Records`, `bonded`, missing units | M |
| 26 | P2 | Rewrite “Two separate copies” and storage copy | Negative phrasing, missing articles, duplicate “Database” row | S |
| 27 | P2 | Rewrite the custom-range flow | “Entire memory”, “Use range”, “inside the readings in memory” | S |
| 28 | P2 | Unify voice and contractions | Formal/technical and friendly copy alternate sentence by sentence | M |
| 29 | P2 | Define capitalization, punctuation, and all-caps policy | Buttons and titles currently mix Title Case and sentence case | M |
| 30 | P2 | Centralize strings for localization and add copy tests | Every string is hardcoded; this will drift again after the next pass | L |
| 31 | P3 | Improve probe-card discoverability of History | Whole card is tappable but has no visible affordance | S |
| 32 | P3 | Align accessibility semantics with the new labels | Summary says “current” when the UI says “Latest” | S |

---

## 12.4 Terminology standard

The single largest source of confusion is that **device** means both the phone
and the Bridge. Choose one term per concept and use it everywhere, including the
lab.

| Concept | Use | Avoid | Notes |
|---|---|---|---|
| The ESP32 hardware | **Bridge** | bridge (lowercase), device, unit | Capitalise as a product name. |
| The Android phone | **this phone**, **your phone** | device, handset | “On this phone” is warmer than “local”. |
| Data stored on the phone | **history on this phone** | device log, local data, saved data | The short row label can be **Storage**. |
| Data stored on the Bridge | **history on the Bridge** | Bridge log, Bridge storage, ring, sectors | Use “log” only for the connection event log. |
| Individual values | **readings** | records, samples, points | “128,430 readings”. |
| The archive screen | **History** | Graph, Log, Data | Already correct. |
| The phone–Bridge link | **connected**, **offline** | linked, bonded | “Bonded” is Android-internal; use “paired”. |
| Smoke X4–Bridge pairing | **paired** | synced, bonded, learned | “Synced” means history transfer, not RF pairing. |
| Phone–Bridge pairing | **paired** / **forget** | bonded | “Forget this phone” matches Android. |
| History transfer | **synced** / **syncing** | caught up, backfilled | “Last synced 2 min ago.” |
| Live reading age | **updated** | last contact, last data, last seen | “Updated 4s ago.” |
| Billows state | **reporting**, **last seen** | detected (bare), connected | “Reporting” means data is arriving; it does not mean the fan is running. |
| Billows target | **set temp** | CH 4 set temp, target setpoint | Add “Set on the Smoke X4” once. |
| On-device display | **Bridge screen** | OLED, display | Use “OLED” only in lab/hardware details. |
| Firmware update method | **USB cable**, **computer** | OTA path, flash | “Firmware updates require a USB connection to a computer.” |
| Temperature unit | **°F / °C** | F / C, Fahrenheit (in buttons) | Spoken form: “degrees Fahrenheit”. |
| Probe identity | **P1–P4** in compact UI; **Probe 3** in prose | sensor 3, channel 3, FOOD/GRATE | The Smoke X4 channel is a hardware detail; the app exposes probes. |
| A detected cooking period | **cook** (section: **Cooks**) | session, Past cooks when it is active | Explain “Grouped automatically from your readings.” |

### Pairing and connection vocabulary

Use these consistently:

- **Connected** — the phone is talking to the Bridge.
- **Receiving** — the Bridge is hearing the Smoke X4.
- **Reporting** — the Smoke X4 is hearing Billows.
- **Paired** — an RF or Bluetooth pairing exists.
- **Synced** — history has been copied to the phone.
- **Updated** — a new reading arrived.

Do not use “synced” for the Smoke X4 link, and do not use “connected” for
Billows if the design wants to avoid implying the fan is running.

---

## 12.5 Formatting standard

### Temperature

Current inconsistency: `165.2 °F`, `166.0°`, `225.0 °F`, `+3.8°`, and
`CH 4 set temp 225 °F` all coexist.

Proposed:

- Hero values on Live and the OLED: whole degrees, no space: **165°F**,
  **225°F**.
- Detailed History values (Summary, tooltip, accessibility): one decimal, no
  space: **165.2°F**.
- Deltas: whole degrees with a direction, not a bare signed number:
  **↑3.8°F in 1h** or **+3.8°F · 1h**.
- Unit toggles: **°F** and **°C**.
- Spoken/accessibility: “165.2 degrees Fahrenheit.”
- If the team prefers one decimal everywhere, keep the decimal in every surface
  and remove the space. Do not mix precision levels without a reason.

Why: 0.1°F is false precision for a cooking probe and consumes width. Whole
degrees are faster to read at arm’s length; one decimal in analysis surfaces is
useful and honest.

### Time and recency

| Context | Proposed | Avoid |
|---|---|---|
| Live reading age | **Updated 4s ago**, **Updated 4 min ago** | last contact, last data, no new 4m |
| History transfer | **Synced 2 min ago** | saved 2m ago, last sync 2 h ago |
| Link duration | **Connected for 2h 14m** | connected 2h 14m · last contact… |
| Older than a day | **3 days ago** / **Oct 22 at 6:30 PM** | 72h ago |
| Billows | **Last seen 12s ago** | detected (bare) |
| Technical details | **Last synced 2 min ago** | last sync 2 minutes ago |
| Screen timeout | **30 sec**, **1 min**, **2 min**, **Never** | 30 s, 60 s, 120 s |

Use the system 12/24-hour setting, not a hardcoded format. The current Settings
storage rows use `08:14` while History uses `6:30 PM`; that must be consistent.

### Counts and pluralisation

- `1 reading` / `2 readings`
- `1 probe` / `2 probes`
- `1 scenario` / `82 scenarios`
- `1 phone` / `4 phones`
- `1 cook` / `2 cooks`
- Use commas for counts above 999: `128,430 readings`.

Fix every hardcoded plural. The lab currently says “82 scenarios” even when the
filter returns one, and the OLED preview says “four overlays” when there are
seven states.

### Dates and ranges

- `Oct 24, 6:30 PM – Oct 25, 6:30 PM` (comma between date and time).
- Include the year when the range is not in the current year.
- Use an en dash with spaces for ranges.
- In prose, use “from … to …”; in compact labels, an en dash is fine.
- Multi-day chart axes must show date **and** time, not four repeated dates.

### Distance

Use **10 meters (about 30 feet)**, not `10 m`. In a cooking app, `m` reads as
minutes.

### Capitalisation

- Sentence case for buttons, menu items, field labels, card metrics, and section
  headers: **Find bridge**, **Open app settings**, **Set temp**, **Quick picks**.
- Title case only for proper names: **Smoke X4**, **Bridge**, **Billows**,
  **Settings**, **History**, **Live**.
- No terminal period in titles, buttons, or labels.
- Full sentences in body copy get a period.
- Oxford comma in lists of three or more: “Bridge, Smoke X4, and Billows”.

---

## 12.6 Voice and tone

**Voice:** calm, plain, specific, and quietly confident. A knowledgeable friend
who has set up a smoker before.

Rules:

1. **State first, action second.** “Bluetooth is off. Turn it on to find your
   Bridge.”
2. **One idea per sentence.** Split the long Billows explanation.
3. **Use “you” and “your.”** “Your Bridge keeps recording.”
4. **Use contractions** in body copy: “can’t”, “doesn’t”, “isn’t”. Keep
   “cannot be undone” for destructive gravity.
5. **No implementation nouns** in product copy: segment, path, identity,
   advertising, reused, catch up, backfill, MTU, RSSI, GATT, OTA, ring, sector.
6. **No “simply”, “just”, or “never”** unless “never” is a true guarantee.
   “Never 0 °F” is a test rule, not user copy.
7. **Reassure only where true.** “The Bridge keeps recording.” “History on this
   phone is kept.” Do not promise monitoring or alerts.
8. **Do not blame the user.** Name the next step.
9. **Use the same label for the same object everywhere**, including the lab.

Tone examples:

| Instead of | Use |
|---|---|
| “The Bridge reused this time range before it synced.” | “The Bridge ran out of space before these readings reached your phone, so they can’t be recovered.” |
| “Detected means the Smoke X4 is receiving Billows data… It does not mean the fan is running.” | “Billows reports through the Smoke X4. This doesn’t mean the fan is running.” |
| “The app checks this before showing the Android prompt.” | Remove; it is implementation detail. |
| “This is the only copy of the device log.” | “This is the only copy of this history.” |
| “No data is deleted automatically.” | “Only the selected readings are deleted.” |

---

## 12.7 Screen-by-screen changes

### Global shell and navigation

| Current | Proposed | Why |
|---|---|---|
| Tab labels `Live` / `History` / `Settings` | Keep | Clear, domain-specific, three jobs. |
| App bar `Live` / `History` / `Settings` | Keep, but unify title treatment between root and detail screens | Detail screens currently use a pill; root screens use plain text. Pick one. |
| Overflow menu with one item `Experimental lab` and tooltip `App menu` | Debug-only: remove the one-item overflow; expose the lab from About (debug builds) or a visible `Lab` row | A menu with one item is an anti-pattern. |
| `Experimental lab` (menu) vs `Scenario lab` (screen) | Use **Experimental lab** everywhere | The product has three names for one thing. |
| Footer `Smoke X4 Smart Bridge · Local only` | `Smoke X4 Smart Bridge · No account needed` or `Works offline` | “Local only” sounds limiting; privacy is a benefit. |
| Screen titles ending in a period (`Bluetooth is off.`) | Drop the period | Inconsistent with every other title. |

### Live — connection card

Current:

> App / This phone → Bridge / Connected → Smoke X4 / Receiving  
> Connected for 2h 14m · last contact 4s ago

Proposed:

> Phone / Connected → Bridge / Connected → Smoke X4 / Receiving  
> Updated 4s ago · connected for 2h 14m

Why: “App / This phone” says the same thing twice. Lead with freshness, which
is what the user checks. “Last contact” is telecom language.

- For offline with cache: **Last connected 2h ago** (keep) and dim all values.
- For reconnecting: **Reconnecting… attempt 2 of 6**; use one ellipsis style.
- For blocked: **Bluetooth is off**, **Bluetooth permission needed** (keep),
  but add the next step in the banner action.
- For `Not connected`: **Not paired with this phone** (keep).

### Live — notices

| Current | Proposed |
|---|---|
| `Smoke X4 not sending` / “The Bridge is connected but has no recent data. Put the Smoke X4 in SYNC and keep it in range.” / `Pairing instructions` | `No data from Smoke X4` / “The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.” / `Troubleshoot` |
| `Couldn’t catch up` / “The last sync did not finish. Live readings can continue; retry when the link is stable.” / `Retry sync` | `History sync failed` / “Live readings are still updating. Retry when the Bluetooth connection is stable.” / `Retry sync` |
| `Storage unavailable` / “The Bridge can show live readings, but this session is not being recorded.” | `Not recording` / “Live readings are still available, but the Bridge can’t save them. Check the Bridge’s storage.” Add `Bridge details` action. |
| `No probes connected` / “Plug a probe into the Smoke X4. Detached probes are shown as —, never 0 °F.” | `No probes connected` / “Plug a probe into the Smoke X4 to see a reading.” |
| `Billows disconnected` / “It was detected earlier this session. Check the fan’s power and its link to the Smoke X4. The connection log records the drop.” / `View connection log` | `Billows not detected` / “Billows was detected earlier this session. Make sure the fan is powered on and in range of the Smoke X4.” / `View connection log` |

Why: the current copy mixes internal rules (“never 0 °F”), implementation
details (“the connection log records the drop”), and vague antecedents (“It”).

### Live — sync card

| Current | Proposed |
|---|---|
| `Syncing` / `Loading older history` | `Syncing` / `Loading older readings` |
| `slow link` | `Slow connection` |
| “Recent history first, then a forward catch-up.” | “Newest readings load first.” |
| “Recent history is already available. Older readings continue in the background.” | “Your latest readings are ready. Older readings continue in the background.” |

### Live — probe cards

Current:

> P1  
> 165.2 °F  
> [sparkline]  
> 1h      +3.8°

Proposed:

> **Probes** (section heading)  
> P1  
> 165°F  
> [sparkline]  
> 1h · ↑3.8°F

Rules:

- Add a **Probes** section heading above the 2×2 grid. Without it, `P1` has no
  context for a first-time user.
- Combine the timeframe and delta: `1h · ↑3.8°F` or `+3.8°F in 1h`. A bare
  `+3.8°` does not say what period it covers.
- Use **Not connected** for a detached probe. Keep `—`.
- For a connected probe with no history: **No history yet** in the sparkline
  area and no `1h` label.
- For a stale probe: **Updated 4 min ago**, not `No new 4m`.
- For a frozen/offline probe: **Last updated 12 min ago** or `Offline` in the
  card, not repeated four times. Prefer one banner + dimmed values.
- Add a quiet affordance for History: a chevron in the card header or a
  `History ›` label in the footer. The whole card is tappable, but the current
  layout does not advertise it.
- Accessibility label: “Probe 1, 165 degrees Fahrenheit, up 3.8 degrees in the
  last hour. Tap for History.”

### Live — Billows card

Current:

> Billows  
> CH 4 SET TEMP        STATUS  
> 225.0 °F             Detected

Proposed:

> Billows  
> Set temp            Last update  
> 225°F               12s ago  
> Set on the Smoke X4.

Why: “Status: Detected” is redundant on a card that only appears when Billows
is detected. Replace it with information the user cannot get elsewhere: when it
was last seen. Move the read-only explanation to one small caption, not three
repetitions.

When offline with cache, either hide the card or show:

> Billows  
> Last seen 2h ago  
> Set temp (last known) 225°F

Do not leave a bright “Detected” card on a screen full of dimmed, cached values.

### History — filter card

| Current | Proposed |
|---|---|
| `1H` `6H` `24H` `2D` `CUSTOM` | `1 hour` `6 hours` `24 hours` `2 days` `Custom` |
| Menu items `1 h` `6 h` `24 h` `2 d` | `Last hour` `Last 6 hours` `Last 24 hours` `Last 2 days` |
| `Custom range…` | Keep |
| `Custom` on the button | `Custom` (button), `Custom range…` (menu) |
| Tooltip `History range` | Keep |
| Tooltip `Probes` | `Filter by probe` |
| `Reset filters` | Keep |

Why: `1H` can read as a channel, a port, or an hour; the menu and button use
different spacing. Words are clearer and fit at this width.

### History — chart header and metadata

| Current | Proposed |
|---|---|
| `Oct 24 6:30 PM – Oct 25 6:30 PM` | `Oct 24, 6:30 PM – Oct 25, 6:30 PM` |
| `Saved 2m ago · 4 probes` | `Synced 2 min ago · 4 of 4 probes` |
| No readings + `Saved 2m ago · 4 probes` | `No readings yet · 0 of 4 probes` (or hide the line) |
| `Recorded · 4 probes` (past cook) | `Recorded history · 4 probes` |
| `· estimated time` | `· Times estimated` plus an info affordance |
| `Showing last saved readings` | Keep |
| `Last sync 2 h ago` | `Last synced 2h ago` |

Why: “Saved” is ambiguous (saved where?), and the count is wrong when a probe
has no data. “Estimated time” is never explained anywhere else in the UI.

### History — chart, axes, and help

| Current | Proposed |
|---|---|
| Y ticks `275°`, `225°`, `175°` plus `°F` at top-left | Numeric ticks only: `275`, `225`, `175`; one `°F` unit label |
| Multi-day x labels repeat `Oct 24` | Date + time for multi-day ranges: `Oct 24, 6 PM` etc. |
| Gap band `No data` | `No signal` when that is the recorded reason |
| Gap band `Overwritten` | `Not synced` or `Lost before sync` |
| `Pan · pinch or scroll to zoom` | `Drag to pan · pinch to zoom` (Android); add “scroll” only on desktop lab |
| Chart help: “A gap means the Bridge has no reading for that time. The line never bridges a gap.” | “A gap means no reading was recorded. The chart doesn’t connect across it.” |
| Chart help: “All visible probes share one temperature scale. Filtering to one probe expands that scale.” | “All probes share one scale. Choose one probe to see more detail.” |
| `estimated time` unexplained | Add: “The Bridge’s clock wasn’t set when these readings were recorded, so the times are approximate.” |
| `Now` | Keep |
| `Fit` | `Fit range` |

Why: the chart is the core History tool. Degree signs on every tick add noise;
duplicate dates make a two-day chart unreadable; “Overwritten” and “reused” are
implementation language.

### History — “Some history was overwritten”

Current:

> Some history was overwritten  
> The Bridge reused this time range before it synced. The gap is permanent; the
> chart does not draw a straight line across it.

Proposed:

> Some readings were lost before they reached your phone  
> The Bridge ran out of space and overwrote this part of its history before it
> synced. The readings can’t be recovered, so the chart leaves this period
> blank.

Why: “Reused this time range” is incomprehensible. State the cause, the loss,
and what the chart shows.

### History — Summary and sorting

| Current | Proposed |
|---|---|
| Column `CURRENT` | `LATEST` |
| Sort `Probe order` | `Probe order` (keep), but prefix with `Sort:` or use a sort icon |
| `Hottest now` | `Hottest` |
| `Highest peak` | `Highest` |
| `Most recent` | `Latest reading` |
| `Since cook started` | `Since cook start`; disable with helper “No cook detected yet” when none |
| `No cook detected in the recorded readings.` | `No cook detected in this history.` |
| Row semantics “current … minimum … maximum” | “latest … lowest … highest” |
| `No data` | Keep |

Why: “Current” is wrong for a 24-hour or historical range; the row shows the
latest sample in range, which may be hours old. “Hottest now” is false when
looking at last Tuesday.

### History — Cooks / Past cooks

Current:

> Past cooks  
> Detected from recorded readings  
> Today · 9:10 AM – 6:30 PM · 9h 20m · 4 probes · gap · In progress

Proposed:

> Cooks  
> Grouped automatically from your readings  
> Today · 9:10 AM – 6:30 PM · 9h 20m · 4 probes · missing readings · In progress

Or, if the product wants to keep the “Past cooks” label:

- Move the in-progress cook into a separate **In progress** card above the
  past list.
- Never show a cook labelled “In progress” under a heading that says “Past”.

Why: the current section contradicts itself. “Cook” is fine as a domain term,
but “gap” and “detected from recorded readings” are lab language. “Missing
readings” is clearer than “gap”.

Cook sheet:

| Current | Proposed |
|---|---|
| “The app groups recorded readings into cooks. Choose one to open its historical graph.” | “Cooks are grouped automatically from your readings. Choose one to open its history.” |
| `View all` | `View all cooks` (if space allows) |
| `In progress` | Keep |

### History — empty and partial states

| Current | Proposed |
|---|---|
| `No readings yet` / “The Bridge records whenever it is on and synced with the Smoke X4.” / `Go to Live` | `No readings yet` / “The Bridge records whenever it’s on and paired with the Smoke X4.” / `View Live` |
| `No data in this range` / “P3 has no readings in this range. Try another range or show all probes.” / `Show all probes` | `No readings from Probe 3 in this range` / “Try another range or show all probes.” / `Show all probes` |
| `Some history was overwritten` | See above. |

Why: “synced” is the wrong term for the LoRa link; “P3” in prose is terse;
“Go to Live” is less standard than “View Live”.

### History — custom range sheet

| Current | Proposed |
|---|---|
| `Custom range` / “Pick exact dates and times. It starts with everything the phone has in memory.” | `Custom range` / “Choose a start and end time. It starts with all the history saved on your phone.” |
| `54d 18h of history` | `54 days, 18 hours of history` |
| `QUICK PICKS` | `Quick picks` |
| `Entire memory` | `All saved history` |
| `Use range` | `Apply` |
| `Choose a range inside the readings in memory.` | `Choose a range within your saved history.` |
| `The end must be after the start.` | `End time must be after start time.` |
| `START` / `END` | `Start` / `End` |
| `53d 18h` | `54 days, 18 hours` (in prose) |

Why: “Memory” is implementation vocabulary; “Use range” is not a standard
confirmation label; all-caps field labels slow reading.

### Settings root

Current:

> Bridge  
> Backyard Bridge  
> Bridge A4F2 · Bluetooth  
> ● Connected                    Battery 87%  
> Signal ▂▄▆▁ Fair  
> Last contact 4s ago

Proposed:

> Bridge  
> Backyard Bridge  
> Bridge A4F2  
> ● Connected                    Battery 87%  
> Signal ▂▄▆▁ Fair  
> Updated 4s ago

Current:

> History & storage  
> Device & Bridge logs  
> 128,430 device · 24,810 Bridge readings

Proposed:

> History & storage  
> Storage  
> 128,430 readings on this phone · 24,810 on the Bridge

Current:

> Temperature units  
> Every reading, target and the Bridge OLED

Proposed:

> Temperature units  
> All temperatures, including the Bridge screen.  
> Offline: “The Bridge screen will update when you reconnect.”

Why: the current subtitle is ungrammatical, redundant (“Bridge” twice), and
“OLED” is hardware jargon.

Appearance:

| Current | Proposed |
|---|---|
| `System` / `Match the phone setting` | `System` / `Match your phone` |
| `Light` / `Warm daylight palette` | `Light` / `Always use light` |
| `Dark` / `Low-light palette for night cooks` | `Dark` / `Always use dark` |

About row/footer:

| Current | Proposed |
|---|---|
| `About` / `App 0.1.0 · firmware 0.1.0` | `About` / `App 0.1.0 · Firmware 0.1.0` |
| `Smoke X4 Smart Bridge · Local only` | `Smoke X4 Smart Bridge · No account needed` |

### Bridge details

Header:

| Current | Proposed |
|---|---|
| `Bridge` / `Backyard Bridge` / `Bridge A4F2 · Bluetooth` | `Bridge` / `Backyard Bridge` / `Bridge A4F2` |
| `Connected` / `Battery 87%` / `Signal ▂▄▆▁ Fair` | Keep |
| `Last contact 4s ago` | `Updated 4s ago` |
| `Recording continues on the Bridge.` | Keep |
| `Sync now` / `Reconnect` | Keep |
| `Disconnect` / `Connect` | Keep |

Smoke X4 pairing:

| Current | Proposed |
|---|---|
| `Smoke X4 pairing` / `Paired · receiving` | Keep title; pill `Receiving` |
| `Last data 12s ago · 915 MHz` | `Updated 12s ago` (move frequency to Technical details) |
| `Re-pair Smoke X4` | Keep when connected; disabled label stays `Re-pair Smoke X4` with helper “Connect to the Bridge to re-pair.” |

Bridge settings:

| Current | Proposed |
|---|---|
| `Bridge name` / `Backyard Bridge · connect to change` | `Bridge name` / value only; helper “Connect to change.” |
| `Bridge screen timeout` / `60 s · OLED sleep` | `Bridge screen timeout` / `1 min · screen turns off` |
| `60 s` / `120 s` options | `1 min` / `2 min` |
| `OLED stays on` | `Screen stays on` |
| `Billows` / `Read-only · Detected` | `Billows` / `Status only · Detected` or `Set on the Smoke X4 · Detected` |

Technical details:

| Current | Proposed |
|---|---|
| `Firmware, signal, MTU and identifiers` | `Firmware, signal, and connection details` |
| `Device ID` | `Bridge ID` |
| `Signal -71 dBm` | Keep in technical details |
| `MTU 247` | Keep in technical details |
| `Last connected Just now` | `Connected for 2h 14m` |
| `Last sync 2 minutes ago` | `Last synced 2 min ago` |

Connection log:

| Current | Proposed |
|---|---|
| `Connection & pairing log` | `Connection log` |
| `Bridge, Smoke X4 and Billows events together` | `Bridge, Smoke X4, and Billows events` |
| `Bridge connected` / `Bridge connection lost` | `Bridge connected` / `Bridge disconnected` |
| `Smoke X4 paired` / `915 MHz · pairing confirmed by the Bridge` | `Smoke X4 paired` / `The Bridge confirmed the pairing` |
| `Billows connection lost` | `Billows lost` |
| `History synced` / `Recent readings are on this phone` | Keep |

Bridge actions:

| Current | Proposed |
|---|---|
| `BRIDGE ACTIONS` | `Bridge actions` (sentence case) |
| `Power off Bridge` / `Stop recording until you wake it` | `Power off Bridge` / `Stop recording until you turn it back on` |
| `Factory reset Bridge` / `Wipes pairing, settings and the Bridge log` | `Factory reset Bridge` / `Erases pairings, settings, and saved readings` |
| `Forget this phone` / `Removes this phone’s pairing; keeps device log` | `Forget this phone` / `Removes this phone’s pairing; keeps history on this phone` |
| Footer “Power off and factory reset need a live connection. Forget this phone can still clear this phone locally.” | “Power off and factory reset require a connection to the Bridge. You can forget this phone while offline.” |

### Billows screen

Current:

> Read-only fan status  
> Billows is detected automatically through the Smoke X4. Its set temperature
> is the channel 4 set temp on the Smoke X4; the app never changes it.

Proposed:

> Billows status  
> Billows reports through the Smoke X4. Its set temperature is set on the
> Smoke X4; this app shows it for reference.

Current status card:

> Current state  
> Detected  
> Last seen 12s ago  
> CH 4 set temp 225.0 °F  
> Source Read-only · Smoke X4 channel 4

Proposed:

> Status  
> Reporting  
> Last seen 12s ago  
> Set temp 225°F  
> Set on: Smoke X4 (channel 4)

Explanation:

> Detected means the Smoke X4 is receiving Billows data. The target is simply
> the Smoke X4 channel 4 set temp, so it can be changed only on the Smoke X4. It
> does not mean the fan is running.

Proposed:

> Billows reports through the Smoke X4. The set temp comes from channel 4 on the
> Smoke X4 and can only be changed there. Reporting doesn’t mean the fan is
> running.

When offline:

- Title: `Last observed state`
- Pill: `Last seen 2h ago` or `Not reporting`
- Value: `Set temp (last known) 225°F`
- Never show a bare `Detected` on an offline screen.

Connection log subtitle:

| Current | Proposed |
|---|---|
| “Billows is paired through the Smoke X4, so detection and drops sit in the same timeline as the Bridge.” | “Billows events appear here with the Bridge’s connection events.” |
| “No Billows events this session. It will appear automatically when the Smoke X4 detects the fan.” | “No Billows events yet. Billows will appear here when the Smoke X4 detects it.” |

### History & storage

| Current | Proposed |
|---|---|
| `Device log` | `History on this phone` |
| `Bridge log` | `History on the Bridge` |
| `Stays on this device even if the Bridge is reset.` | `Stays on this phone even if the Bridge is reset.` |
| `Database` / `9.2 MB` | Remove the duplicate row, or use `Storage used` once |
| `Readings` / `24,810 of 338,400` | Keep |
| `Capacity` / `~117 days at 30 s` | `Capacity` / `About 117 days at 30-second intervals` |
| `Oldest` / `Oct 17, 2026 · 08:14` | `Oldest reading` / `Oct 17, 2026 at 8:14 AM` (locale time) |
| `Newest` / `Oct 25, 2026 · 18:30` | `Newest reading` / `Oct 25, 2026 at 6:30 PM` |
| `Delete device log…` | `Delete history from this phone…` |
| `Clear Bridge log…` | `Clear history on the Bridge…` |
| `Connect to clear the Bridge log` (disabled label) | Keep `Clear history on the Bridge…`; helper “Connect to the Bridge to clear it.” |
| `Two separate copies` / “Deleting device log does not clear the Bridge log. Clearing the Bridge log does not delete device log.” | `Two separate copies` / “Deleting history from your phone doesn’t clear the Bridge. Clearing the Bridge doesn’t delete history from your phone.” |

Delete sheet:

| Current | Proposed |
|---|---|
| `Everything` | `All history on this phone` |
| `No data is deleted automatically` | `Only the selected readings are deleted` |
| `Delete device log older than 30 days?` | `Delete history older than 30 days?` |
| `Delete all device log readings?` | `Delete all history from this phone?` |
| `Delete 128,430 readings` | Keep — the explicit count is excellent |

Why: “device” and “log” are the two biggest sources of ambiguity in the
destructive flows. “History on this phone” / “history on the Bridge” makes the
loss unambiguous.

### About

| Current | Proposed |
|---|---|
| `Smoke X4 Smart Bridge` / `App 0.1.0` | Keep |
| `App version 0.1.0` row | Keep one version display, not both header and row |
| `Bridge firmware 0.1.0` | `Firmware 0.1.0` |
| `Protocol 1.0` | `Bridge protocol 1.0` |
| `Bridge ID A4F2` | Keep |
| `Bluetooth name SmokeX4-A4F2` | Keep if support needs it; otherwise move to Technical details |
| `Model heltec3` | `Hardware Heltec WiFi LoRa 32 V3` (or remove) |
| “Firmware updates are USB only in this build. There is no OTA path.” | “Firmware updates require a USB connection to a computer. This app can’t update the Bridge over Bluetooth.” |
| “No cloud, no account. Data stays on this phone and the Bridge.” | Keep, or “No account, no cloud. Readings stay on your phone and the Bridge.” |
| “Smoke X protocol decoding derives from G-Two/smoke-x-receiver…” | “Smoke X protocol decoding is based on G-Two/smoke-x-receiver…” |
| “Smoke X is a trademark of its owner.” | Name the owner if legally accurate: “Smoke X is a trademark of ThermoWorks.” |

### Setup — first run

Current:

> App bar: Connect Bridge  
> Eyebrow: SETUP  
> Title: Connect your Bridge  
> “Power it on. If the screen is off, hold PRG for 1.5 seconds.”  
> Primary: Find Bridge

Proposed:

> App bar: Set up  
> (No eyebrow on the first screen)  
> Title: Connect your Bridge  
> “Power it on. Press PRG to wake the screen. If the Bridge is off, hold PRG for
> 1.5 seconds to turn it on.”  
> Primary: Find bridge  
> Secondary (if saved history): View history on this phone

Why: three labels currently say the same thing; the PRG instruction is
dangerous; title case is inconsistent.

### Setup — permission primer

Current:

> `PERMISSION`  
> `Allow Bluetooth to find your Bridge`  
> “The app uses Bluetooth only to find and connect to your Bridge. It does not
> use location, and there is no cloud account.”  
> Bullets: “Nearby devices permission on Android 12+”, “No location is read or
> stored”, “The Bridge keeps recording while you set up”  
> Primary: `Allow Bluetooth`  
> Secondary: `Not now`

Proposed, Android 12+:

> `Permission`  
> `Allow Bluetooth to find your Bridge`  
> “Android will ask for Nearby devices permission so the app can find your
> Bridge. Your location is never used or stored. There is no cloud account.”  
> Primary: `Continue`  
> Secondary: `Not now`

Proposed, Android 7–11:

> `Permission`  
> `Allow location to find your Bridge`  
> “On this version of Android, Bluetooth scanning requires location permission.
> The app uses it only to find your Bridge and never reads or stores your
> location.”  
> Primary: `Continue`  
> Secondary: `Not now`

Why: minSdk is 24. On Android 11 and below the OS prompt will say “Location”
even though the app only scans for BLE. The current copy says the opposite and
will cause denials. If the team does not want to explain location permission,
raise minSdk to 31 instead.

### Setup — other states

| Current | Proposed |
|---|---|
| `Bluetooth is off.` | `Bluetooth is off` |
| `Open Bluetooth settings` | Keep |
| `Check again` | Keep |
| `Bluetooth permission needed.` | `Bluetooth permission needed` |
| `Open settings` | `Open app settings` (when it opens the app’s settings) |
| `Bluetooth permission is blocked.` | `Bluetooth permission is blocked` |
| `This phone can’t scan for Bluetooth LE.` / `Close` | `This phone doesn’t support Bluetooth LE` / add `View saved history` and `Learn more`; keep `Close` as a last resort |
| `Looking for your Bridge…` | Keep |
| “Scanning stops after 10 seconds. Your remembered Bridge is preferred.” | “Scanning stops after 10 seconds. We’ll check your last Bridge first.” |
| `No Bridge found.` | `No Bridge found` |
| “Make sure it is on, then hold PRG for 1.5 s if it is asleep. Bluetooth range is usually about 10 m indoors.” | “Make sure it’s on and within about 10 meters (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.” |
| `Nearby Bridges` | `Nearby bridges` |
| “Remembered Bridges are shown first.” | “Your last Bridge is shown first.” |
| Pill `Remembered` | `Last used` |
| `P4 225 °F · 87% · -71 dBm` | `225°F · 87% · Strong signal` (keep dBm only in technical details) |
| `Protocol 2.x · needs a newer app` | `Requires a newer app` |
| `The scan stops after 10 seconds. If nothing appears, retry or open Bluetooth settings.` | “Scanning stops after 10 seconds. If your Bridge doesn’t appear, try again or open Bluetooth settings.” |
| `APP UPDATE NEEDED` / `This Bridge needs a newer app.` / `Update the app before pairing. The Bridge is not changed.` / `Close` | `App update required` / `Update the app to use this Bridge` / “Install the latest version, then try again. The Bridge hasn’t been changed.” / `Update app` (and a secondary `Close`) |

### Setup — pairing

Passkey page current:

> `Pair with the Bridge`  
> “The Bridge’s screen shows a 6-digit code. Enter it in the phone’s prompt.”  
> `LOOK AT THE BRIDGE OLED`  
> [illustration: `418 302`]  
> “Android will ask for this code. The app never shows it; it is only on the
> Bridge OLED.”

Proposed:

> `Pair with the Bridge`  
> “Enter the 6-digit code shown on the Bridge screen in the Android prompt.”  
> `Look at the Bridge screen`  
> [illustration labelled `Example: the code appears on the Bridge screen`]  
> “Only the Bridge screen shows the real code.”

Why: the current page shows a code and then says the app never shows it. Label
the illustration as an example or show a schematic without digits. Replace
“OLED” with “Bridge screen”.

Bonding page:

| Current | Proposed |
|---|---|
| `Pairing…` | Keep |
| `Enter the code shown on the Bridge when Android asks for it.` | Keep |
| `Connecting to the Bridge` / `Pairing with the code` / `Syncing recent history` | `Connecting to the Bridge` / `Checking the code` / `Syncing recent history` |

Pairing failures:

| Current | Proposed |
|---|---|
| `The code didn’t match.` / “Try again. After two failures, remove the old pairing in Android settings and pair again.” / `Open Bluetooth settings` | Keep title; “Try again. If it fails twice, forget the old pairing in Android settings and pair again.” / `Open Android settings` |
| `No prompt appeared.` / “Check the notification shade for the Android pairing prompt, then try again.” | `No prompt appeared` / “Open your notifications and look for the Android pairing request, then try again.” |
| `This phone’s pairing is out of date.` / “The Bridge was reset, so the old pairing no longer works. Remove it and pair again. The Bridge’s new identity is safe to trust.” / `Forget pairing and re-pair` | Keep title; “The Bridge was reset, so the old pairing no longer works. Forget the old pairing, then pair again.” / `Forget and re-pair` |
| `This Bridge already has 4 phones paired.` / “Forget one phone from a paired phone, then try again. The app checks this before showing the Android prompt.” / `I’ve freed a slot` | Keep title; “Remove this phone from another paired phone, then try again.” / `Try again` |

Why: “identity is safe to trust” is vague; “the app checks this” is
implementation detail; “I’ve freed a slot” is cute but not a standard action.

### Setup — first sync and device log

First sync:

| Current | Proposed |
|---|---|
| `Loading history` | Keep |
| “Recent history is ready first. Older readings continue in the background.” | “Your latest readings are ready. Older readings will load in the background.” |
| `64% · recent 24 hours` | `64% · last 24 hours` |
| `Phone clock set` | `Time set` |
| `Reading the last 24 hours` | `Loading the last 24 hours` |
| `Loading older history` | `Loading older readings` |
| `Live readings` | `Live view ready` |
| `Start monitoring` | `View live readings` |

Why: “Start monitoring” implies background monitoring and alerts that the app
does not provide. The steps currently expose implementation details.

Device log step:

| Current | Proposed |
|---|---|
| `Device log` | `History on this phone` |
| “History on this phone is separate from the Bridge. It is never deleted automatically.” | Keep |
| `No device log` | `No history on this phone` |
| “There is no history on this phone yet. The Bridge records whenever it is on and synced.” | “…whenever it’s on and paired with the Smoke X4.” |
| `Delete device log` | `Delete history from this phone…` |
| `Back to setup` | `Back` or `Done` |

### Destructive confirmations

Forget this phone:

| Current | Proposed |
|---|---|
| `Forget this phone?` | Keep |
| “This removes the Bluetooth pairing for this phone. The Bridge keeps recording.” | Keep |
| “This phone is removed from the Bridge’s paired phones.” | “The Bridge forgets this phone.” |
| “The Bridge is removed from this app.” | “This app forgets the Bridge.” |
| “Device log stays on this phone until you delete it.” | “History on this phone stays until you delete it.” |
| `Forget phone` | Keep |

Clear Bridge log:

| Current | Proposed |
|---|---|
| `Clear Bridge log?` | `Clear history on the Bridge?` |
| “The Bridge erases its rolling log. This cannot be undone on the Bridge.” | “The Bridge erases its saved readings. This can’t be undone.” |
| “The Bridge keeps its pairings and settings” | Keep |
| “Device log is kept” | “History on this phone is kept” |
| “The Bridge starts a new log segment.” | “The Bridge starts recording a new log.” |
| `Clear Bridge log` | `Clear history` |

Delete history:

| Current | Proposed |
|---|---|
| `Delete device log older than 30 days?` | `Delete history older than 30 days?` |
| `Delete all device log readings?` | `Delete all history from this phone?` |
| “This deletes 12,430 readings from this phone. It cannot be undone.” | Keep |
| “Date range: …” | Keep |
| “This does not change the Bridge” | “This doesn’t change the Bridge” |
| “No data is deleted automatically” | “Only the selected readings are deleted” |
| `Delete 12,430 readings` | Keep — excellent specificity |

Factory reset:

| Current | Proposed |
|---|---|
| `Factory reset Bridge?` | `Factory reset this Bridge?` |
| “The Bridge wipes its pairings, settings, and log, then reboots.” | “The Bridge erases its pairings, settings, and saved readings, then restarts.” |
| “All paired phones, including this one” | Keep |
| “Bridge settings and display preferences” | “Bridge settings and screen preferences” |
| “The Bridge log and its clock” | “Saved readings and the clock” |
| “The Bridge starts advertising as new” | “The Bridge becomes available to pair as a new device” |
| “Device log is kept. Delete it from Device log on the setup screen.” | “History on this phone is kept. You can delete it later.” |
| Button `Factory reset Bridge` | `Factory reset` (short enough not to wrap) |

Power off:

| Current | Proposed |
|---|---|
| `Power off Bridge?` | `Power off the Bridge?` |
| “The Bridge stops recording until you hold PRG for 1.5 s to wake it.” | “The Bridge stops recording until you turn it back on.” |
| “Recording stops while the Bridge sleeps” | “Recording stops while the Bridge is off” |
| “The Bridge stops recording while it is off” | Remove — duplicate |
| “This phone keeps its history” | “History on this phone is kept” |
| “Hold PRG for 1.5 s to turn the Bridge back on.” | Keep, but spell “1.5 seconds” |
| Button `Power off Bridge` | `Power off` |

Why: high-stakes screens should have the shortest possible button labels and the
clearest possible loss list. The current factory-reset button wraps on a 390 px
screen.

### Power-off screen

| Current | Proposed |
|---|---|
| `Bridge is off` | Keep |
| “Recording stops while the Bridge sleeps. Hold PRG for 1.5 s to turn it back on.” | “The Bridge isn’t recording. Hold PRG for 1.5 seconds to turn it back on.” |
| `Simulate hold PRG to wake` | Remove from product; in the lab use `Simulate holding PRG` |

### Experimental lab

Naming:

- Use **Experimental lab** in the app-bar menu, screen title, tests, and docs.
- Remove **Scenario lab** and **Prototype UI** as alternate names.
- The lab can still call its contents “scenarios”.

Header and search:

| Current | Proposed |
|---|---|
| `No devices required` | Keep |
| “Every screen and state is simulated. Pick a flow to open it directly.” | Keep |
| `Theme` | Keep |
| `Reset prototype` | `Reset lab state` |
| `Start first-run flow` | Keep |
| `Search screens and states` | Keep |
| `82 scenarios` | `${count} scenario` / `${count} scenarios` |
| No empty search state | `No scenarios match “…”` + `Clear search` |

Group titles/descriptions:

| Current | Proposed |
|---|---|
| `Setup & permissions` / “First run, scanning, pairing, and named failures” | `Setup & permissions` / “First run, scanning, pairing, and error states” |
| `Live & connection` / “Every freshness, probe, Billows, sync, and link state” | `Live & connection` / “Freshness, probe, Billows, sync, and link states” |
| `History` / “Ranges, gaps, empty states, offline cache, and time estimation” | Keep |
| `Settings` / “Bridge, preferences, Billows, history and about” | `Bridge, preferences, Billows, history, and About` |
| `Confirmations & results` / “Destructive sheets and the expected disconnect outcomes” | `Confirmations & results` / “Destructive confirmations and their outcomes” |
| `Device OLED` | `Bridge screen (OLED)` |

Scenario titles should mirror the product:

| Current lab title | Proposed |
|---|---|
| `Lost the Bridge` | `Can’t reach the Bridge` |
| `Sync failed` | `History sync failed` |
| `Bridge connected · no Smoke X4` | `Smoke X4 not sending` |
| `History · data missing from Bridge` | `History overwritten before sync` |
| `History · offline cache` subtitle “Showing saved readings” | “Showing last saved readings” |
| `Device log (orphaned)` | `History on this phone (after forgetting the Bridge)` |
| `Clear history progress` subtitle “keeps pairing and config” | “…keeps pairing and settings” |
| `Passkey` overlay | `Pairing code` |
| `Tap PRG` / `Hold PRG` | `Tap PRG button` / `Hold PRG button` |
| Footer “Prototype UI · BLE, database, sync, and permissions are not implemented” | “Prototype only. Bluetooth, storage, sync, and permissions are simulated.” |

Why: the lab is the review source of truth. If it paraphrases the product, the
copy reviewed is not the copy shipped.

### OLED preview

| Current | Proposed |
|---|---|
| `OLED preview` / `Device display` | `Bridge screen` / `Bridge screen preview` (lab) |
| “128×64 SSD1306 · simulated at 3×. One button, four pages, four overlays.” | “…One button, four pages, seven states.” (count is wrong) |
| Page chips `Page 1`…`Page 4` | `Probes`, `Connection`, `Billows`, `Device` (keep page numbers as secondary) |
| `Overlays` / `Passkey` | `States & overlays` / `Pairing code` |
| `Tap PRG` / `Hold PRG` | `Tap PRG button` / `Hold PRG button` |
| “Tap wakes a sleeping display without changing the page…” | Keep |

OLED page 1:

- Add the unit once: **P1 165°F**, **P2 164°F**, etc. (or `°F` in the status
  strip). Use whole degrees on the 128 px screen.
- Status strip: `• BLE • X4 87%` → `App • X4 87%` or `BT • X4 87%`; define the
  abbreviations in the lab.

OLED page 2:

| Current | Proposed |
|---|---|
| `BLE connected` / `advertising` | `App connected` / `ready to pair` |
| `Phones bonded 2/4` | `Phones paired 2/4` |
| `LMXC[` | Remove, or label `Radio 915` if it is diagnostic data |
| `RSSI -71` | `Signal -71` (technical page) |

OLED page 3:

| Current | Proposed |
|---|---|
| `BILLOWS detected` | `BILLOWS reporting` |
| `CH 4 SET 225.0 °F` | `SET 225°F` |
| `Pit 225.0` | `P4 225°F` |
| `Set on the Smoke X4` | Keep |

OLED page 4:

| Current | Proposed |
|---|---|
| `DEVICE v0.1.0` | `BRIDGE v0.1.0` |
| `Storage 12.4 days` | `Log 12.4 days left` |
| `Records 24,810` | `Readings 24,810` |
| `Heap 142k (min 128k)` | `Memory 142k (low 128k)` (technical page, acceptable) |

Boot overlay:

| Current | Proposed |
|---|---|
| `fit antenna before power` | `Attach antenna before power` |

Overlays:

- Pairing: keep `PAIR WITH PHONE` and `enter this code on your phone`.
- Power off: keep `POWER OFF`, `keep holding`, `release to cancel`.
- Storage: keep the warning, but consider `saving is off` instead of `storage
  unavailable` if space is tight.
- Resetting/clearing: keep `do not power off`.
- Off: keep.

---

## 12.8 Accessibility and platform conventions

1. **Do not change a button’s label to explain why it is disabled.** Keep
   `Clear history on the Bridge…` and put “Connect to the Bridge to clear it” in
   helper text. Same for `Re-pair Smoke X4` and the Bridge settings rows.
2. **48 dp minimum touch targets.** Several chart controls are 32×32 and the
   filter reset is 38×38 with `shrinkWrap`. Increase the hit area without
   increasing the icon.
3. **No wrapping destructive buttons.** `Factory reset Bridge` wraps on a
   390 px sheet. Use `Factory reset` and keep the object in the title.
4. **Contrast.** Check the selected segmented-control label (white on peach in
   light mode) and the destructive confirmation button (peach fill reads as a
   primary action, not a destructive one) against WCAG AA. Do not rely on color
   alone for destructive intent; label it clearly.
5. **Semantics stay in sync with visible labels.** If the column becomes
   `Latest`, the screen-reader label should say “latest”, not “current”. If
   `Past cooks` becomes `Cooks`, the semantic group should match.
6. **Chart summary includes uncertainty.** The screen-reader summary should
   mention gaps and estimated times, not only min/max/latest.
7. **Dynamic type.** Test the destructive sheets and filter card at 200% text
   size. Current `SettingsTile` subtitles are limited to two lines with ellipsis;
   important reasons such as “Connect to change” could disappear.
8. **Plain-language error states.** Every failure should have one primary action
   and one way out. `Close` on unsupported phone and protocol mismatch is a dead
   end. Add `View saved history` and `Update app` respectively.

---

## 12.9 Implementation guardrails

### 1. Move strings out of widgets

Every string is hardcoded today and there is no `l10n` setup. Before the next
copy pass, add `flutter_localizations`, `intl`, and an `app_en.arb`. Even if the
app ships English-only, this gives you:

- one place to review copy;
- pluralisation (`1 reading` / `2 readings`);
- locale-aware dates and times;
- a path to translation later without touching widgets.

### 2. Add a copy lint

Add a Dart test or script that scans product surfaces for banned terms. Allow
them only in `prototype/scenario_lab.dart`, `features/device/`, and the
`Technical details` section.

Suggested banned terms in `features/` and `widgets/`:

`OLED`, `BLE`, `MTU`, `RSSI`, `dBm`, `915`, `CH 4`, `Database`, `OTA path`,
`heltec3`, `simulated`, `(simulated)`, `device log`, `No new`, `bonded`,
`advertising`, `reused`, `Use range`, `Entire memory`, `Remembered`,
`Nearby Bridges`, `Start monitoring`.

### 3. Make the lab use product strings

Where possible, the lab should import the same string constants or render the
actual screens with a fixture, not paraphrase them. At minimum, keep a one-to-one
mapping between each lab scenario title and the product state it opens.

### 4. Add narrow-width golden tests

Add golden/widget tests at 320 px and 390 px for:

- factory reset / delete confirmation sheets;
- Bridge details action rows;
- custom range sheet;
- History filter card;
- Live probe card with a long delta;
- OLED page 1.

The current factory-reset button already wraps at 390 px.

### 5. Update the existing tests

These tests assert the old copy and will need to change with the proposal:

- `CURRENT` → `LATEST`;
- `Start monitoring` → `View live readings`;
- `Nearby Bridges` → `Nearby bridges`;
- `CH 4 SET TEMP` → `Set temp`;
- `Read-only fan status` → `Billows status`;
- `Connect to clear the Bridge log` → stable action label;
- `Experimental lab` / `Scenario lab` naming;
- `82 scenarios` pluralisation;
- OLED preview “four overlays” count.

### 6. Define a review checklist

For every new string, ask:

- Does it say **phone**, **Bridge**, or **Smoke X4** unambiguously?
- Is it a user outcome or an implementation detail?
- Does the action label stay the same when disabled?
- Does it use one term from the dictionary?
- Does it avoid hardware jargon outside Technical details/lab?
- Is the plural/date/time/temperature formatted by the shared formatter?
- Does it make sense at 320 px and 200% text size?

---

## 12.10 Open questions

1. **Android 7–11 support.** Keep minSdk 24 and add the location rationale, or
   raise minSdk to 31 and remove the location permutation? Recommendation: keep
   24 for a DIY/bench product, but make the primer version-aware.
2. **Billows status word.** Is “Reporting” accurate for what the Bridge sees? If
   not, use “Detected 12s ago” rather than a bare “Detected”.
3. **Cook sessions.** The UI has derived “Past cooks” but the product scope says
   there is no cook-session model. If keeping the feature, rename the section
   **Cooks** and explain it is grouped automatically. If not, remove the card
   and sort option instead of polishing the copy.
4. **Temperature precision.** Whole degrees on Live/OLED and one decimal in
   History is my recommendation. If the team wants one decimal everywhere,
   keep it everywhere and remove the space.
5. **“Bridge” as a proper noun.** The current app treats it as a name. Keep
   that; do not switch to lowercase “bridge” in UI.
6. **About attribution.** Confirm whether “Smoke X is a trademark of
   ThermoWorks” is the legally preferred wording, or keep “its owner”.
7. **“Local only” vs “No account needed.”** The latter is benefit-led and
   matches the privacy story; the former sounds like a limitation.
8. **Start monitoring.** Confirm there is no background monitoring/notification
   plan; if there is, the label becomes accurate and the product scope changes.

---

## 12.11 Suggested sequencing

### Pass 1 — trust and correctness (P0)

- Permission primer by Android version.
- Phone/Bridge terminology in storage, setup, and About.
- PRG press/hold corrections.
- Stale Billows state.
- Passkey illustration and “OLED” removal.
- Empty-history metadata.
- Remove prototype copy from product surfaces.

Ship this pass with updated tests and screenshots. It addresses the issues most
likely to cause a denied permission, a wrong deletion, or a loss of trust.

### Pass 2 — Live and History clarity (P1)

- Freshness dictionary and removal of repeated stale lines.
- Probe-card labels and delta/timeframe.
- Billows card/screen simplification.
- Range labels and custom-range flow.
- Summary “Latest” and sort labels.
- Cooks section.
- Disabled action labels and helper text.
- Destructive copy and short buttons.
- Chart axes, gap reasons, and help.
- Jargon purge.

### Pass 3 — consistency and craft (P2)

- Settings root grammar.
- About/technical truth.
- Lab naming, counts, and product-copy mirroring.
- OLED labels.
- Voice, capitalization, punctuation, and all-caps policy.
- Localization and copy lint.

### Pass 4 — polish (P3)

- Probe-card History affordance.
- Accessibility semantics.
- Contrast and tap targets.
- App-bar consistency.
- Final golden and 320 px review.

---

## Appendix A — Quick copy swaps

The highest-value one-line changes, in order:

1. `If the screen is off, hold PRG for 1.5 seconds.` → **Press PRG to wake the
   screen. If the Bridge is off, hold PRG for 1.5 seconds.**
2. `Device log` → **History on this phone**
3. `Bridge log` → **History on the Bridge**
4. `128,430 device · 24,810 Bridge readings` → **128,430 readings on this phone
   · 24,810 on the Bridge**
5. `LOOK AT THE BRIDGE OLED` → **Look at the Bridge screen**
6. `The app never shows it; it is only on the Bridge OLED.` → **Only the Bridge
   screen shows the real code.**
7. `CH 4 SET TEMP` → **Set temp**
8. `STATUS / Detected` → **Last update / 12s ago** (or **Reporting**)
9. `No new 4m` → **Updated 4 min ago**
10. `No new 12m` → **Updated 12 min ago**
11. `Saved 2m ago · 4 probes` → **Synced 2 min ago · 4 of 4 probes**
12. `CURRENT` → **LATEST**
13. `Past cooks` → **Cooks** (or exclude the in-progress cook)
14. `Hottest now` → **Hottest**
15. `24H` → **24 hours**
16. `Use range` → **Apply**
17. `Entire memory` → **All saved history**
18. `Remembered` → **Last used**
19. `Nearby Bridges` → **Nearby bridges**
20. `Start monitoring` → **View live readings**
21. `Go to Live` → **View Live**
22. `OLED sleep` → **screen turns off**
23. `60 s` / `120 s` → **1 min** / **2 min**
24. `Model heltec3` → **Heltec WiFi LoRa 32 V3**
25. `Firmware updates are USB only in this build. There is no OTA path.` →
    **Firmware updates require a USB connection to a computer.**
26. `The Bridge reused this time range before it synced.` → **The Bridge ran out
    of space and overwrote this part of its history before it synced.**
27. `No data is deleted automatically.` → **Only the selected readings are
    deleted.**
28. `The Bridge starts advertising as new.` → **The Bridge becomes available to
    pair as a new device.**
29. `I’ve freed a slot` → **Try again**
30. `four overlays` → **seven states**
31. `Records` → **Readings**
32. `Phones bonded` → **Phones paired**
33. `Pit` → **P4**
34. `fit antenna before power` → **Attach antenna before power**
35. `Local only` → **No account needed**
36. `Connect to clear the Bridge log` → **Clear history on the Bridge…** +
    helper
37. `Connect to re-pair` → **Re-pair Smoke X4** + helper
38. `· connect to change` → value + helper “Connect to change.”
39. `No data` gap → **No signal** (when that is the reason)
40. `Overwritten` → **Not synced**

---

## Appendix B — Screen inventory reviewed

- Shell / navigation
- Live: connection card, notices, sync card, probe cards, Billows card
- History: filters, chart, chart help, summary, cooks, empty states, custom
  range, full-screen chart
- Settings: root, units, appearance, About
- Bridge details: status, Smoke X4 pairing, Bridge name, screen timeout,
  Billows, technical details, connection log, actions
- Billows: status, source, connection log
- History & storage: phone copy, Bridge copy, delete options
- Setup: no Bridge, permission primer, Bluetooth off, permission denied/blocked,
  unsupported phone, scanning, no results, scan results, protocol mismatch,
  passkey, bonding, pairing failures, first sync, device log
- Confirmation sheets: forget, clear Bridge history, delete history, factory
  reset, power off
- Power-off state
- OLED preview: pages 1–4 and all overlays
- Experimental lab: all groups, entries, search, counts, theme controls, footer

No user-visible string in these surfaces was intentionally left unreviewed.
