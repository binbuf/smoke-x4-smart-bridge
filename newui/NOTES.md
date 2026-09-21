# NOTES — Smoke X4 Smart Bridge, new UI prototype → Flutter

This folder is a **static HTML prototype** of a proposed UI/UX for the Smoke X4
Smart Bridge app. It is deliberately *not* Flutter and deliberately *not* a copy
of the existing app. Its job is to let every screen, state and flow be argued
about in a browser before any Dart is written.

> **Read `components_research_notes.md` first.** It is the parts bin. This file
> is the translation plan for the prototype built on top of it.

---

## 1. What is in this folder

| File | What it is |
|---|---|
| `index.html` | The shell: phone frame, status bar, app bar, scroll view, bottom nav, overlay host, dev panel. Loads the other three files. |
| `styles.css` | The design system: tokens, phone chrome, and every component used. Ported from `docs/design/14-design-system.md` and `app/lib/design/`. |
| `mock-data.js` | **The data model.** The preset catalog, the expected-cook (timeline) database, four bridge scenarios, history, connection modes, alarm rules. This is the most important file to read. |
| `app.js` | Renderers + interactions. §1 state, §2 formatting, §3 SVG, §4 domain, §5 chrome, §6 views, §7 overlays, §8 actions, §9 boot. |
| `NOTES.md` | This file. |

**Open it:** double-click `index.html`. No build, no server. The panel on the
right switches scenarios, screens and overlays. Deep links also work:

```
index.html#screen=graph
index.html#overlay=setup
index.html#scenario=existing
index.html?screen=timeline&units=C
```

---

## 2. Information architecture

Five bottom-nav destinations, one overlay stack, plus a fullscreen graph.

```
Live        The "now" glance: sticky alert strip, summary strip (grate /
            hottest / to-target), compact probe rail, mini graph, quick actions.
Temps       Big per-probe widgets — large numerals, trend, sparkline, stats,
            target/pull/ETA. Tap a card for the probe sheet. This is where the
            timer-board detail moved so Live can breathe.
Timeline    Database-driven expectation. Gantt of every item on the grill,
            upcoming interventions (wrap/spritz/turn), event rail.
Graph       Multi-series chart with range chips, zoom + pan + fullscreen,
            band shading, tap-to-isolate legend, per-probe window stats.
Settings    Dual-link connection (Bluetooth + Wi-Fi, independently), Wi-Fi
            provisioning, appearance, alarms, and History. No 5th "Cooks" tab.
History     Inside Settings. Past cooks grouped by recency + cook detail with a
            planned-vs-actual recap. "Cook again" replays preset + style.
```

Overlays (sheets/modals), all reachable from the dev panel:

`onboarding` · `setup` (catalog + style packs + custom food + three start modes) ·
`connect` (dual-link) · `modes` · `modesRef` (the technical reference the `?`
opens) · `provisionSta` · `provisionAp` · `alarms` · `alarmDetail` · `mark` ·
`probe` · `adopt` · `editStart` · `confirm` (generic, used for the long-item
warning and the device cost sheets) · `customFood` · `firmware` ·
`firmwareUpdate` · `diagnostics` · `verb` (the restart / forget / factory / OTA
progress sheet).

**Why this shape.** The brief asks for timers front-and-centre *and* a graph
*and* a timeline *and* a catalog. Those are four different mental modes, so they
get four destinations. The fifth is Settings (which owns History). Alerts and
the transport chip are global chrome that persist across all of them.

### 2.1 Theme, profile and density (new)

Three independent axes, all applied as classes on `<body>`:

| Axis | Values | Default | Where |
|---|---|---|---|
| `themeMode` | `system` \| `light` \| `dark` | `system` | Settings → Appearance |
| `displayProfile` | `standard` \| `daylight` | `standard` | Settings → High-contrast |
| `density` | `compact` \| `comfortable` | `compact` | Settings → Density |

`theme-light` / `theme-dark` swap the whole token set; `profile-daylight` layers
a high-contrast boost on either. `density-compact` tightens padding. Status and
series tints are written `rgba(var(--x-rgb), a)` so they retint with the theme.
In Flutter these are `ThemeMode` + a `ThemeExtension` for the contrast profile.

### 2.2 The cook-style packs (new)

Selecting a cut is not enough — "Pork Shoulder" could be Texas pulled pork,
Kālua pork, Carolina, Cuban mojo, pernil or cochinita pibil. `MOCK.STYLES` keys
cook variants to a preset id; each sets pit band, wrap, spritz, target, rest and
timeline together, and carries a `region` badge so the app teaches the taxonomy.

This is deliberately a **large content table**, not a handful of presets. The
catalog now holds **139 foods across 10 categories** (a new `Desserts` category
joins the original nine), and **every one of them has at least two preparation
styles** — **318 named variants over 133 styled cuts** at last count. The same
braise/dry-rub/glaze machinery covers beef offal (cheeks, oxtail, tongue,
shank), whole-hog and hock, game birds and wild game, shellfish, 20+ vegetables,
sides and desserts. A `Custom food` form adds user cuts with their own target +
timeline (stored on the item as `timeline`, bypassing `MOCK.TIMELINES`).

**In Flutter** this is the same class of reviewer-owned data as `presets.dart`:
a preset+style record keyed by the preset id, with a named reviewer on the
table. The `region` field is identity metadata, never a status channel.

### 2.3 Catalog search

The setup sheet searches all 139 foods at once (name, category or blurb). Results
show a live count; each tile shows its variant count ("4 styles"). In Flutter
this is a debounced filter over the preset library, not a new repository.

### 2.4 The dual-link connection model (new)

`connection.bt` and `connection.wifi` are independent links with their own
health; `connection.primary` says which carries data; `connection.phase` is
`connected | connecting | offline | provisioning | rollback | error`. Wi-Fi has
`mode: off | ap | sta`. The appbar chip shows the primary plus two radio
indicators. The connection sheet, Settings and the provisioning flows all read
the same model. `MOCK.EVENTS` is the mock event bus — the dev panel fires
`ble-connected`, `wifi-connecting`, `wifi-wrong-password`,
`wifi-router-unreachable`, `wifi-connected`, `ap-broadcasting`, `ap-joined`,
`switch-rollback`, `resync-complete` and alarm events; each mutates the active
scenario. In Flutter these become live bridge state from `ConnectionSupervisor`.

---

## 3. The business logic that must survive the port

These are the rules the prototype encodes. They are carried from
`components_research_notes.md` §1 (the invariants). **A redesign may re-express
these; it may not violate them.**

### 3.1 Device is authoritative; the app mirrors (I2)

- The bridge records with or without the phone. The UI says so in three places:
  the cook header ("Recording on the bridge — safe even if this phone drops"),
  the Cooks empty notice, and the alarms sheet.
- **Pausing the stopwatch does NOT stop device recording.** Pause only freezes
  the *displayed* clock. In Dart this is a UI-only flag over `cook.startedAtMs`.
- App alarms are labelled **Advisory**; device alarms are labelled **Device**.
  The two tiers are never merged in a list without their tag.

### 3.2 Absent ≠ zero (I3)

A detached probe renders `—` + "Unplugged", never `0°`. See `timerTile()`:
`attached === false` short-circuits the whole tile.

### 3.3 Never present stale data as current (I4)

The freshness ladder is live / aging / stale / frozen. When a probe is not
`live`, **derived values (ETA, trend) are removed, not greyed**. See the
`canShowDerived` branches in `timerTile()`. The offline scenario demonstrates it.

### 3.4 Food safety is a hard gate (I12)

Every target in the catalog runs through the same floors as
`domain/plan/presets.dart`:
- Poultry carryover is **always zero** — the app never predicts a bird upward.
- Carryover (`carryoverFor`) is by cut thickness, not doneness.
- Pull temp (`pullTempFor`) is clamped at the safety floor.

The prototype approximates these in `app.js §4`. **In Flutter, call the real
`CookPreset.pullF10For` / `safePullF10` — do not port the approximation.**

### 3.5 One ember primary action per screen (I14)

Each screen/overlay has at most one `.btn.primary`. Grep for `btn primary` to
see the intended call to action on each surface.

### 3.6 Colour discipline (17 §17.2)

Three channels, and the prototype honours all three:

| Channel | Where | Rule |
|---|---|---|
| **Series** | probe hues P1–P4 | marks only; legend swatches show the stroke pattern too, because hue is never the only identity channel |
| **Status** | critical/warning/info/positive | chrome only; icon **and** word; green = transport health only |
| **Identity** | food avatars | may fill and carry a word; never encodes state |

The hero temperature is always ink. "Target reached" closes the ring and says
"DONE"; it is never green.

### 3.7 The colour rule scales with live state (17 §17.5)

Onboarding, the catalog and the empty reader may be warm and saturated (no cook
exists, so nothing can lie). A running cook cools to ink-and-chrome. The
prototype follows this: the setup sheet is vivid, the live probe board is
disciplined.

### 3.8 Firmware, diagnostics and device verbs (new)

Settings → **Bridge** now has three live rows and a **Device actions** group.
No row is a dead control (I5).

- **Firmware** (`overlayFirmware`) — installed version, channel (stable/beta),
  hardware, bootloader and the auto-rollback promise.
- **Update firmware** (`overlayFirmwareUpdate`) — states the transport rule
  first: an image is **Wi-Fi-only**. If the bridge is not on Wi-Fi the primary
  action becomes *Join Wi-Fi*, not *Install*. If a cook is recording it warns
  about the firmware's **409 `session_active`** guard and offers an explicit
  **force** toggle before the button is enabled. Maps to `app_ota`.
- **About & diagnostics** (`overlayDiagnostics`) — device id, hardware, uptime,
  heap, battery, both radios, storage/retention, recent logs, copy-diagnostics
  and field report. Maps to `device_facts.dart` + the field-report flow.
- **Device actions** — *Restart*, *Forget this bridge*, *Factory reset*. Each
  opens a **cost sheet** (`confirm`) that states the consequence, then a
  **verb-progress sheet** (`verb`) that names every step as it completes:
  `applyVerb()` mutates the scenario when the last step lands. This is the
  restart/forget/factory-reset contract from the research notes, finally
  reachable from Settings.

`MOCK.DEVICE` and `MOCK.FIRMWARE` hold the identity + release data. The OTA
rules (Wi-Fi-only, session guard, 120 s health-gate rollback) are real and must
survive the port.

---

## 4. The Timeline database — the one genuinely new system

`MOCK.TIMELINES` in `mock-data.js` is a **per-cut expected-cook database**. The
existing app has nothing like it. It is what makes the Timeline tab possible.

```js
beef_brisket: {
  totalMin: [600, 840],                              // expected cook, pre-rest
  stall: { minF: 150, maxF: 170, durationMin: [120, 240] },
  wrap:  { tempF: 165, label: 'Wrap in butcher paper', note: '…' },
  spritzEveryMin: 45,
  turn:  { elapsedMin: 5, note: '…' } | null,
  restMin: 60,
  phases: [ { id, label, note }, … ],                // the honest arc
}
```

**To seed it properly**, every cut in the catalog needs an entry. The prototype
covers all ~35 items (some with an empty timeline, which the Timeline view
tolerates). When this moves to Dart:

1. Make it a table (Drift table or a const map). The existing `Presets.all`
   already keys by `id`; key the timeline by the same `presetId`.
2. Add a **named reviewer** for the whole table. `presets.dart` already flags
   that the preset table needs one; this table is the same class of data.
3. The Timeline view derives everything from it:
   - Gantt bar length = `totalMin` midpoint.
   - Stall band = 38–72 % of the bar (placeholder fraction; replace with a
     temperature-triggered estimate once analysis is wired).
   - Wrap milestone = 55 % of the bar (placeholder; replace with the temp
     crossing from the rate engine).
   - Upcoming interventions = `wrap`, `spritzEveryMin`, `turn`.
   - Event rail = actual marks ∪ predicted `phases`.
4. **Every intervention is optional and editable.** The `autoWrapReminder`
   setting gates whether the app nudges. A cut with `wrap: null` simply has no
   wrap reminder.

The expected times are **estimates and must say so** (the same honesty rule as
the ETA and rest timer in `cook_phase.dart`).

---

## 5. The three ways to start a cook (the flexibility requirement)

`overlaySetup` in `app.js` offers a segmented switch. These map to three
distinct code paths:

### 5.1 `new` — set up before you light the fire
Pick category → cut → doneness (red meat defaults to **medium rare**) → assign a
probe → optional wrap/spritz reminders. Start.
Maps to `CookRepository.startFromPlan`.

### 5.2 `existing` — hook into data already collected
This is the brief's "grill already fired up, bridge already recording" case.

- On connect, if the bridge has a session the app has not adopted, the Live
  screen shows an **adopt banner** and the `adopt` modal (`overlayAdopt`).
- The user picks what is on the grill and confirms the start time; the app
  **backdates the cook** to the bridge session start and **pulls the samples
  already collected**.
- The prototype shows the sample count (`pendingSession.samples`) and the start
  time, so the cost is stated before the action (I8).

Maps to `CookRepository.backdate` / `candidateAnchors` + the SyncEngine's
high-water-mark protocol (`components_research_notes.md` §5.3). The bridge is
the source of truth for what was already recorded; the app only annotates a
window over it (I10).

### 5.3 `watch` — no targets, just live numbers
Instrument mode. No cook, no timers, no alarms. The Live screen renders the
instrument card instead of the cook header. A cook can be turned on later
without losing anything.

---

## 6. Feature-by-feature translation map

| Prototype feature | Existing Flutter piece to reuse |
|---|---|
| Transport chip + connection sheet | `ConnectionSupervisor`, `TransportChip`, capability flags (§4 matrix) |
| Mode switcher (BLE / AP / STA) | `app_net` modes; `applyNetwork`; the rollback timer + BLE escape hatch (§5 of research notes) |
| Live probe board | `buildDashboard()` projection; `ProbeHeroCard`, `ProbeStripRow`, `ProbeCompactCard` |
| Timer tiles | **new** — a glanceable wrapper over the projection. Consider `ProbeCompactCard` as the base. |
| Stopwatch / start-time edit | Cook `startedAtMs`; `CookAnnotation.backdatedTo` |
| Graph | `features/chart` (fl_chart); keep run-splitting, LTTB, labelled target lines, ≤16 % area fill |
| Legend tap-to-isolate | `SeriesLegend` (exists, currently unwired — wire it) |
| Timeline / Gantt | **new** — built on the timeline DB above |
| Catalog | `Presets.all` + a **new** timeline table + `FoodGlyph`/`FoodAvatar` |
| Marks (wrap/spritz/turn) | `CookRepository` marks; `MarkKind` enum |
| Alarm strip + sheet | `AlarmBar`, `planNotifications()`, `AlarmRuleSpec`, two-tier model (§6.4) |
| Prefer-my-own-alarms | **new setting** — device alarms are authoritative; this only changes which *notification* wins |
| Background monitoring | `CookMonitor` + `ForegroundServiceHost` |
| Cooks history | `CookRepository.list/watch`, `CookDetailView`; now reached from **Settings → History** |
| Onboarding | `SetupMachine` (§12), `BridgeIllustration`, `PasskeyDisplay` |
| Theme mode (system/light/dark) | **new** — `ThemeMode` + a light token set; `SmokeTokens.daylight` becomes the high-contrast profile |
| Cook-style packs | **new** — preset + style record; sets pit band/wrap/spritz/target/timeline, plus a `region` badge |
| Custom foods | **new** — user presets with their own timeline, stored with the preset library |
| Catalog search | **new** — debounced filter over the preset library; no new repository |
| Firmware / OTA | `app_ota`, `firmware_picker.dart`; Wi-Fi-only upload, session guard, health-gate rollback |
| About & diagnostics | `device_facts.dart`, field-report flow, five-tap diagnostics gate |
| Restart / Forget / Factory reset | `POST /restart`, `/pairing/unpair`, `/factory-reset`; cost sheet + verb-progress sheet |
| Dual-link connection UI | `ConnectionSupervisor` capability/health for BLE **and** Wi-Fi, exposed as two independent links |
| Wi-Fi provisioning (AP/STA) | `app_net` modes; the passphrase/SSID/QR flow + rollback timer |
| Mock event bus | **new** — dev-only; maps to live bridge state in the real app |
| Units toggle | `domain/analysis/units.dart`; storage stays tenths-°F |
| Daylight profile | `SmokeTokens.daylight` |
| Empty / problem states | `EmptyState`, `ProblemState`, `CapabilityNotice` |

---

## 7. Specific decisions the prototype makes (review these)

1. **Timer board over a probe list.** The four timer tiles are the primary
   surface on Live. Tapping one opens the probe detail sheet. This is the
   "timers front and centre" requirement.
2. **Jack 4 is the grate by default**, but every jack can be re-roled in the
   probe sheet (`probe-role`). The tile gets a "Grate" tag when it is the pit.
3. **The stopwatch is always visible** while a cook is active, with pause and an
   "adjust start" modal that only moves the cook window — never the samples.
4. **Alarms live in a sheet**, not a tab. The strip is global; the sheet holds
   active alarms, delivery verdict, the nine device rules, the three app
   advisories and the preferences. (Open question: see §9.)
5. **The catalog is the setup flow.** There is no separate "presets" screen.
6. **Food imagery is a placeholder** (coloured disc + emoji). Replace with the
   vector `FoodGlyph` set (`design/food_glyph.dart`) or real photography later.
   The avatar circle is an *identity* fill, exempt from the series rule.
7. **The timeline DB is editable per cook.** The setup sheet's wrap/spritz
   toggle is the seed of that.

---

## 8. Design tokens

Dark surfaces `#07090E / #0F131D / #161C2A / #121824 / #1E2638 / #04060A`; ink
`#F8FAFC / #CBD5E1 / #94A3B8 / #64748B`. Series `#D95926 / #9085E9 / #008300 /
#3987E5`. Status `#F04444 / #FAB219 / #10B981 / #94A3B8`. Radii 20 / 14 / 8 /
999. Spacing is a 4 dp scale. Fonts Archivo (display), Inter (text),
JetBrains Mono (keys/ids).

**Added:** a real **light** palette (`body.theme-light`) with weightier series
hues (`#C2410C / #6D5BD0 / #0F7A0F / #2563EB`) so they stay legible on white,
a high-contrast profile on top of either theme, motion tokens
(`--ease-standard`, `--ease-emphasis`, `--dur-*`), a focus ring, and
`--*-rgb` companions so every status/series tint is written
`rgba(var(--x-rgb), a)` and retints with the theme. All of this should live in
`app/lib/design/` in Flutter.

---

## 9. Open questions for the Flutter build

1. **Is "Alarms" a destination or a sheet?** The prototype uses a sheet. If the
   product wants a permanent alert history, it becomes a tab or a Cooks sub-page.
2. **How much of the timeline DB is shipped vs user-tunable?** Every cut has an
   expectation; should the user be able to edit the stall window per cook?
3. **Do we adopt automatically?** The prototype requires a tap. An auto-adopt
   with an undo could be better for the "already started" case.
4. **Pause semantics.** Does pause also suppress alarms/notifications, or only
   the displayed clock? The prototype assumes the latter (device is authoritative).
5. **Spritz cadence** is a single number per cut; real cooks vary it. Consider a
   per-cook override.
6. **Catalog size.** 35 items is a starting set. Decide whether categories are
   fixed or data-driven before building the picker.
7. **Food imagery** — vector glyphs vs photography. `17-identity-and-warmth.md`
   argues for vector (licensing, bundle size, daylight theming).

---

## 10. How to iterate on the prototype

- Switch **scenario** in the dev panel to see the same screen handle
  offline / idle / running / existing-session and every connection state.
- Fire **mock events** in the dev panel to move the link through
  connecting / wrong-password / unreachable / hotspot / rollback, and to raise
  alarms, without a bridge.
- Switch **screen** and open any **overlay** directly.
- Toggle **units**, **theme** (system/light/dark) and **profile** (daylight is a
  contrast profile, not a light theme).
- The prototype never talks to a bridge. Every value is in `mock-data.js`.
- `app.js` is commented with `[BIZ]` (rules that must survive) and `[FLUTTER]`
  (which engine to reuse). Search for those markers when porting.
