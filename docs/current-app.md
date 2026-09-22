# The current app — a complete feature inventory

> **Archived — describes the legacy app (`app.old/`), not the shipping app.**
> The app was rebuilt from the `newui/` prototype and now lives at [`app/`](../app/);
> see [`new-app.md`](new-app.md) for the rebuilt app. The file references below
> point at the legacy layout and no longer match the shipping tree. This page is
> kept as history.

**Purpose.** This document describes what the companion app *does today*, in enough detail that
someone who has never opened the repo can critique its UI/UX and the communication and business
logic underneath it. It is descriptive, not aspirational: everything below was read out of the
shipping code at `app/lib/`, and file references are given so any claim can be checked.

**A note on "the web app".** There is one Flutter codebase. It ships **Android-first for v1**
(`app/pubspec.yaml`, `app/README.md`: *"Android-only for v1"*, `minSdk 24`, `targetSdk 35`). A web
target exists (`app/web/`) and is used to run the hardware-free **UX Lab** in Chrome
(`app/lib/lab/main_lab.dart`). So "the web app" and "the Flutter app" are the same product; on web,
Bluetooth, notifications and the foreground service are unavailable, so only the Wi-Fi/HTTP path and
the Lab are meaningful there.

**Reference material that already exists**, if the advisor wants the intended design rather than the
built one:

| Doc | What it is |
|---|---|
| `docs/design/13-ux-architecture.md` | The UX spec: three-hop setup, IA, screen specs, failure matrix |
| `docs/design/14-design-system.md` | Tokens, type scale, colour, component table, chart spec, a11y |
| `docs/design/08-flutter-app.md` | App architecture, package choices, connection race, sync |
| `docs/design/09-alarms-and-insights.md` | The two alarm tiers, ETA/stall analysis, notification policy |
| `docs/ui/index.html` | The original HTML prototype the visual language came from |

---

## 1. The product in one page

Three pieces of hardware and one app:

```
ThermoWorks Smoke X (base station)   →  LoRa, one packet ≈ every 30 s
        ↓
Smoke Bridge (ESP32-S3, custom)      →  BLE GATT + Wi-Fi HTTP/WebSocket, OLED, LED, battery
        ↓
This Flutter app (phone)
```

The Smoke X is a four-probe barbecue thermometer with its own long-range receiver. The **bridge** is
a custom device that listens to the base station's LoRa broadcasts, records every reading to its own
flash, runs its own alarm rules, and re-publishes everything over Bluetooth and Wi-Fi (and
optionally MQTT / Home Assistant). The app is the bridge's front end.

Three facts drive nearly every design decision in the app, and any redesign has to keep them true:

1. **The bridge records with or without the phone.** Recording is not started or stopped by the app.
   A cook exists on the bridge whether or not the user ever "set up a cook" in the app.
2. **The bridge alarms with or without the phone.** Device-tier alarm rules run on the ESP32 and
   survive the phone being off, flat or out of range. Everything the *app* computes (ETA, stall, lid
   open) is explicitly advisory.
3. **The usage context is fourteen hours, outdoors, at 3 a.m.** The app is a monitor watched from
   across a room, not a task app. Dark-only, big numbers, and "the app must be able to wake you" are
   consequences of that, not style choices.

---

## 2. Stack and code shape

| Concern | Choice |
|---|---|
| Framework | Flutter (Dart SDK ^3.12.2), Material 3 with a custom `ThemeExtension` token set |
| Routing | `go_router` 17, `StatefulShellRoute.indexedStack` (one Navigator per tab) |
| State | Plain `ChangeNotifier` for the live session; `flutter_riverpod` is a dependency and `ProviderScope` wraps the app, but the shell session is the de-facto state container |
| Transport | `dio` (REST) + `web_socket_channel` (push) + `flutter_blue_plus` (BLE GATT) |
| Discovery | `nsd` (mDNS/DNS-SD); deliberately not `multicast_dns` |
| Local cache | `drift` (SQLite), schema v1, 5 tables |
| Prefs | `shared_preferences`, loaded once at boot so reads are synchronous |
| Charts | `fl_chart` with a hand-rolled viewport (pan/pinch/crosshair are ours; fl_chart has no zoom) |
| Notifications | `flutter_local_notifications` + `flutter_foreground_task` |
| Fonts | Archivo / Inter / JetBrains Mono, **bundled as assets**, never fetched (the phone may be on the bridge's own AP with no internet) |
| Tests | ~75 Dart test files: unit, widget, golden, integration, plus two interactive "lab" harnesses |

Layering (enforced by convention and by tests): `domain/` is pure Dart with **zero Flutter imports**;
`ui/` is stateless widgets over plain values with no providers or async; `features/` composes them;
`data/` owns transports, the cache and repositories.

---

## 3. Information architecture

### 3.1 Route tree

```
/setup                      guided three-hop setup       ← above the shell, root navigator
/onboarding                 legacy wizard (superseded, still registered)
/cook-preview               a preview route (registered, not linked)

└─ shell (four branches, four independent Navigators)
   /cook                    branch 0 — the live screen
   /history                 branch 1 — the cook list
     /history/:id             pushed inside the branch
   /alerts                  branch 2 — will this phone wake you
   /bridge                  branch 3 — the device
     /bridge/:section         settings pages, pushed inside the branch

legacy redirects: /  → /cook   ·   /sessions[/:id] → /history[/:id]   ·   /settings* → /bridge
```

Initial location is `/cook`. The setup flow is a **gate above the shell**, not a tab, so the tab bar
and transport chip can never render over an unprovisioned device. `app/lib/app/router.dart`

### 3.2 The four tabs, and the rule behind them

| Tab | Icon | Answers |
|---|---|---|
| **Cook** | flame | What is happening right now? |
| **History** | clock | What happened before? |
| **Alerts** | bell | Will this phone actually wake me? |
| **Bridge** | router | Which device is this, is it reachable, what can I do to it? |

"Alerts" is deliberately not called "Alarms": the bridge's alarm *rules* are a different thing from
whether this phone will deliver them.

### 3.3 Navigation rules the code enforces

- **`context.go` is banned** outside the top-level redirect and the setup gate. Every in-tab
  navigation is `context.push` *inside the branch*, so opening a cook from History keeps the tab bar,
  keeps the shell mounted, and keeps the live connection alive. System back returns to the list with
  its scroll position intact.
- **All four branches stay mounted.** History keeps its scroll and any pushed detail; the Cook chart
  keeps its viewport; you can flick between tabs without losing anything.
- **Re-tapping the active tab** pops that branch to its root (`goBranch(initialLocation: true)`).
- **One connection for the whole shell.** `ShellSession` boots the connection race once and is
  published through an InheritedWidget (`ShellScope`); no tab dials the bridge itself.

### 3.4 Adaptive behaviour (`app/lib/design/breakpoints.dart`)

Material 3's width classes, but with a product-specific rule: **extra width buys a bigger chart, never
a stretched temperature.** Readout columns are capped at 480 dp (`readableMax`) and every remaining
pixel goes to the chart.

| Width | Navigation | Cook | History / Bridge |
|---|---|---|---|
| < 600 dp | bottom `NavigationBar` | readouts scroll, chart pinned below at 28 % of window height (clamped 200–300 dp) | push a detail route |
| 600–839 dp | `NavigationRail` (icons + labels) | supporting pane: readouts 38 % / chart 62 % | list-detail split, list at 38 % |
| ≥ 840 dp | rail; extended (labels beside icons) from 1240 dp | same, chart fills the pane | list-detail split, list at 32 % |

**Foldables are handled explicitly.** `MediaQuery.displayFeatures` is read for hinge posture:

- **Tabletop** (half-open, horizontal hinge — the device standing on a counter) puts the **chart on
  the upper screen and readouts on the lower**, turning the phone into a purpose-built pit monitor
  with no stand. This is treated as the product's best physical posture.
- **Book** (half-open, vertical hinge) snaps panes to the hinge so nothing lands in the crease.
- On non-foldables `displayFeatures` is empty and every path is the `flat` one — no branching cost.

---

## 4. Screen-by-screen inventory

### 4.1 `/setup` — guided setup (the largest single feature)

A state machine of **~34 named states** across three hops plus a preflight gate, driven by
`app/lib/features/setup/setup_machine.dart` (1,900 lines) and rendered by dispatchers in
`features/setup/screens/`. The whole machine is pure over injected seams, so the entire flow runs in
tests and in the Lab with no radio.

**Hop 0 — preflight** (rendered as "Before we start", not as a fourth step)

| State | Why it exists |
|---|---|
| `SetupPermissionPrimer` | A rationale screen **before** the OS prompt — Android stops showing the dialog after two refusals, forever |
| `SetupPermissionDenied(permanent)` | Distinguishes "ask again" from "only app settings can fix this" |
| `SetupBluetoothOff(resumeAt)` | Watched for the whole setup lifetime, so Bluetooth toggled off at hop 3 resumes at hop 3 |
| `SetupLocationServicesOff` | Android SDK ≤ 32 only (currently a conservative stub) |
| `SetupBluetoothUnsupported` | Terminal, with no fake retry button — copy directs the user to read credentials off the OLED |

**Hop 1 — phone ↔ bridge over BLE**

Scan (sorted by RSSI, rows decorated from the advertising blob *before* connecting) → passkey → bond.
Four bond outcomes are four distinct states, not one error: `SetupPasskeyWrong`,
`SetupRebondNeeded` (bridge was factory-reset; the app auto-heals by dropping the stale OS bond and
re-pairing, and only falls back to "go to Bluetooth settings" if the platform refuses),
`SetupBondSlotsFull` (detected from the advertising blob *before* connecting), `SetupNotABridge`
(terminal — no retry offered on an unretryable failure).

Two more paths: `SetupPasskeyNotSeen` after 30 s with no OS prompt ("some phones put it in the
notification shade"), and `SetupAddThisPhone` — a fast ~15 s path for adding a second phone to a
bridge that is already provisioned.

**The passkey screen is the highest-value screen in the flow, and it deliberately shows no code.**
The six digits are generated on the bridge and appear only on its OLED; `PasskeyDisplay` takes no
`code` parameter at all, so rendering a real code is a compile error rather than a review note.

**Hop 2 — bridge ↔ Smoke X over LoRa**

Illustrated "hold SYNC on the base station" instruction → a **non-destructive** listen window (a
button labelled Pair must never unpair: the existing binding is preserved) → `heard` →
`confirmed`, whose payoff screen shows **real probe temperatures**. Failures are named by cause
(`timeoutNoBeacon`, `timeoutNoState`, `garbled`, `ackFailed` — the last auto-retries twice).
Skippable and resumable.

Implementation note: the dedicated `pair_status` BLE characteristic does not exist in firmware, so
this hop polls `status()` + `live()` every 2.5 s and watches `paired` flip. It works today; the
richer notify drops in behind the same interface later.

**Hop 3 — bridge ↔ Wi-Fi**

Network picker (pre-warmed in the background during hop 2, so the screen is instant), password screen
as its own page, hidden-SSID manual entry with an auth dropdown (so a hidden *open* network is
joinable and a keystroke can't silently downgrade WPA3), enterprise (`auth == 5`) disabled rather
than allowed-then-failed.

Applying is **four narrated phases** (`sent` → `joining` → `gettingAddress` → `checking`) with a
cancel, never one spinner. Five distinct failure reasons (`wrongPassword`, `notFound`,
`assocRefused`, `noIp`, `weakSignal`); after two failures the hosted-AP option is promoted to
primary. Retrying **prefills and reveals** the password field — a typo must not cost a rescan and a
full retype.

`SetupUnreachable` is its own state and a genuinely important one: `net_status: up` means the *radio*
associated, not that this phone can reach the bridge. Verification is a real `GET /status` 200
through the connection race, with the BLE lane excluded on purpose.

Hosted-AP mode shows the generated SSID **and PSK** on screen (OEM join behaviour varies), offers
"join it for me" (Android network-suggestion + `bindProcessToNetwork` — the binding is essential or
the OS leaves the default route on cellular and every request to 192.168.4.1 vanishes) and "I'll join
it myself".

**Finish** — name + units asked once, then a three-row summary where a skipped hop reads
"— not set up". Finishing records the verified base URL *and* the bonded BLE device id, which is what
stops a Bluetooth-only setup from bouncing back into onboarding on the next launch.

**Three invariants the machine holds:**

- *No state without a next step.* Every state has at least one method that advances it. A spinner
  that never resolves is the one outcome the machine may not produce.
- *No raw exception escapes.* Every public async method funnels through a wrapper that turns any
  unmodelled throw into `SetupFault` rather than a crash page.
- *A superseded flow cannot drag the user backwards.* A monotonic generation counter is bumped on
  restart/cancel/dispose and checked after every await.

Also reachable here: **factory-reset the bridge over Bluetooth** — the recovery path when the only
tool is the phone.

### 4.2 `/cook` — the live screen

**One scaffold, two modes, switched by a single nullable — the cook plan.**

**Instrument mode** (no plan): four equal probe rows in jack order, each with a colour swatch, name,
sparkline, large temperature, trend chip and chevron. A detached probe **renders in place at 45 %
opacity showing `—` and the word "unplugged"** — the user needs to see that jack 3 is empty, not have
it vanish. Header reads "Live readings · Nothing is being cooked yet — the bridge is logging anyway"
with a **[ Set up a cook ]** button. Instrument mode is never called "raw" in the UI.

**Guided mode** (a plan exists): the header turns ember and carries the cook name and an elapsed
clock; the pit and primary food probe become **hero cards** (96 pt temperature, never scaled to fit,
plus an 84 dp radial gauge); remaining probes drop to compact cards. Switching modes is an animated
transition, not a rebuild — confirming a cook visibly *installs* its targets as the gauges sweep in
over 800 ms.

The **TargetGauge** has two modes and one payoff: *sweep* (a food probe filling toward its target,
with a radial pull tick at the pull-early temperature) and *band* (the pit, with a tinted band sector
and a current-value dot that goes warning/critical when the reading leaves the band). Target reached
closes the ring and flips the pill to "Reached" — **it is deliberately not a colour change**, because
green is reserved for transport health.

**Cook setup sheet** — a modal: category chips (Beef / Pork / Poultry / Fish) → preset card → doneness
card → **[ Start the cook ]**. Ten presets with blurbs, doneness levels, rest offsets ("pull at X") and
recommended pit bands. Jack 1 is assumed to be the pit and jack 2 the primary food; the probe-mapping
page that would make this configurable is not built.

**Ending a cook** goes through a **cost sheet** rather than a confirm dialog. It states what survives
and what does not: *keeps* "Every reading, and this cook in your history"; *loses* "Your targets, the
doneness gauges and the cook's name." This is load-bearing copy — users end a cook expecting recording
to stop, and it does not.

**The plan is persisted** (JSON in prefs, read synchronously in the constructor so the first frame
picks the right mode). An OS kill at hour nine of an eighteen-hour brisket comes back to the same
gauges.

**The chart** sits under (or beside) the readouts: multi-series line chart, one colour per jack.
Reception gaps are drawn as **separate line segments** — a 30-minute dropout must look like a
30-minute dropout, not a straight line pretending everything was fine. Decimated data draws a min/max
envelope behind the mean line. Overlays: dashed target lines, a shaded pit alarm band, dashed vertical
mark lines. Gestures: pinch to zoom about the focal point, drag to pan, double-tap to reset,
long-press for a crosshair. Live mode auto-scrolls until the user pans, then stops.

**Freshness ladder** (`ProbeFreshness`) — the single most important safety behaviour on this screen:

| Age of last packet | Rendering |
|---|---|
| ≤ 45 s | `live` — full ink, pulse dot animating |
| ≤ 90 s | `aging` — still live-ish, pulse continues |
| ≤ 600 s | `stale` — **StaleVeil**: desaturated, dimmed, with "Readings are 4 minutes old" pinned over them; derived values (ETA, gauges) are **removed, not greyed** |
| > 600 s, or base station lost | `frozen` — "No readings for 4 hours" |

A stale number that still looks live is the exact failure this app is built to prevent.

**Other states on this screen:** not paired to a base station ("This bridge hasn't met your Smoke X
yet" — *not* "plug a probe"); paired but nothing plugged in; offline with an empty cache
("Can't reach your bridge · Saved cooks are still here. Pull down to try again"); on Bluetooth, a
capability notice reading "On Bluetooth — live readings only."

Pull-to-refresh works even on the non-scrolling empty states.

### 4.3 `/history` — cooks

**Cache-only. No transport is touched.** Scrolling an 18-hour cook on the sofa with the bridge
unplugged is literally the acceptance test.

**List:** name (or "Cook #27"), a "Recording" badge on open sessions (deliberately not "Cooking" —
an open session only means the bridge is recording), a metadata line (date · duration · peak · probe
count) and a sparkline. The list **watches** the database, so a cook that starts while the app is open
appears without a relaunch.

**Detail:** title and date, chart **window chips (15 m / 1 h / 6 h / 15 h / All) plus a "Now" pill**,
crosshair readout, a statistics table, and a mark timeline where tapping a mark centres the chart on
it.

**Statistics** — the thing that makes cooks comparable rather than just recorded:

| Row | Notes |
|---|---|
| Total time | first to last sample, gaps included |
| Readings | sample count |
| Gaps in recording | count + total missing time (jargon-free: not "dropouts") |
| Pit mean | null if no probe carried the pit role |
| Pit steadiness | ±σ, but the label avoids the Greek letter |
| Pit min / max | |
| Time in band | **gap time excluded** — a dropout is not evidence the pit behaved |
| Stall | duration, or "none detected" |
| Lid events | counted from marks, not re-detected |
| Per probe | start · end · peak, only for probes ever attached |

Every value that cannot honestly be computed is null and says so.

**CSV export** writes a streamed file (`cook-0027-brisket.csv`) that is **byte-compatible with the
device's own `format=csv`** — same header, same column order, same ISO-8601 spelling. A detached probe
is an **empty field**, never 0, never null, never NaN. The export is generated from the cache, so it
works with the bridge unplugged, and it is emitted line by line so a 54-day export cannot allocate
itself into an OOM.

### 4.4 `/alerts` — will this phone wake you

This tab leads with **delivery, not configuration**, and delivery leads with a **verdict**, not a
checklist: one card that says *"You'll be woken"* or *"You won't be woken"*, the specific reason, and
a one-tap fix.

Blockers, worst first:

| Blocker | Verdict impact | Fix button |
|---|---|---|
| Notifications denied | **won't be woken** | Allow notifications (real permission request) |
| Background monitoring off | **won't be woken** | Turn on monitoring (writes the pref) |
| Battery optimisation on | still "will be woken", but caveated | Allow background use (OS exemption request) |

Battery optimisation deliberately does *not* flip the verdict: it is the difference between "woken at
3 a.m." and "told at 7 a.m.", which is a caveat, not a failure.

Under it: **[ Send a test alarm ]**, which posts a real notification on the real critical channel —
the only way anyone verifies delivery before committing fourteen hours to it. Then a "RULES" card
that states honestly that the bridge's own alarm rules and this phone's stall/ETA/lid rules are **not
editable yet**, that the bridge's defaults are all on, and where to silence a ringing alarm.

### 4.5 `/bridge` — the device

**State-first.** The screen leads with a connection card naming the truth of right now, and everything
below declares which state it belongs to:

| State | Card title | What it says |
|---|---|---|
| Wi-Fi, joined | "Wi-Fi — your network" | address; full history, settings and updates available |
| Wi-Fi, hosted | "Wi-Fi — the bridge's own network" | same, plus the hosted framing |
| Bluetooth | "Bluetooth" | live readings only; "connecting to Wi-Fi in the background" while upgrading |
| Not connected | "Not connected" | keeps trying, Bluetooth first then Wi-Fi |
| Never provisioned | "No bridge set up" | a single card and one **[ Set up a bridge ]** button — not a page of dashes |

**Signal** is shown as **two hops that are never conflated**, because only one is measurable on each
lane:

- *Phone → bridge*: bars + dBm + a word + advice, but **only on Bluetooth** (the GATT RSSI). On joined
  Wi-Fi it says in words that Android only reports the phone's Wi-Fi strength to apps holding the
  location permission, which this app deliberately does not request. On the bridge's hosted network it
  says neither end can measure it, and shows the connected-client count instead of inventing bars.
- *Bridge → router*: from the device's `net.rssi`. This works **even over Bluetooth**, which is how you
  discover the bridge has drifted out of Wi-Fi range while you are standing next to it.

A missing measurement renders "Measuring…" or "Couldn't measure it just now" — never four grey bars.
A transport swap discards the previous reading rather than relabelling it. The poll (20 s) runs
**only while this tab is visible**.

**Identity card:** device id, address, firmware, last reading, Smoke X base paired/not. When
disconnected it is explicitly framed *"Not connected — these are the last known details"* (the
board-found bug this fixed: a factory-reset bridge whose old id and IP still read as current).
**Five taps on the firmware row** opens the diagnostics console — the Android "Build number"
convention.

**Actions:** links into the six device settings sections, plus "Run setup again · Change Wi-Fi or
re-pair. Keeps your cooks and this phone's Bluetooth bond."

**Reset and power** (not "DANGER ZONE" — the sheets carry the weight, calmly). Four verbs, each behind
a cost sheet that states keeps/loses:

| Verb | Enabled when | Cost sheet says |
|---|---|---|
| Restart the bridge | connected | keeps: everything |
| Forget this bridge | always | only this phone forgets it; loses the cooks cached on this phone |
| Factory reset | connected | loses pairing, Wi-Fi, every cook on the bridge, and this phone's saved connection |
| Power off | connected | loses remote access until someone walks over and holds PRG for ~5 s |

Disruptive verbs then run inside a **verb-progress sheet** that verifies by behaviour: send → poll
`status()` until the bridge stops answering (*the drop is the confirmation*) → an explicit done state
with what happens next. It distinguishes "done", "still answering — the command may not have taken",
and "the bridge was already unreachable, nothing changed". A confirmed factory reset forgets the
bridge on this phone at the same moment and offers **[ Set it up again ]**.

### 4.6 Settings sections (`/bridge/:section`)

| Section | Reachable from Bridge tab | What actually works today |
|---|---|---|
| **Probes** | yes | Name, role (Not used / Pit / Food / Ambient) and target per jack, with the target validated in the form (32–572 °F) rather than on the wire. Writes are HTTP-only; on BLE the page says so |
| **Network** | yes | Current mode/SSID/IP/PSK, switch to hosted AP, join a network, and the **manual-address escape hatch** that jumps the connection queue |
| **Device** | yes | Units (°F/°C — travels to the bridge's OLED so the two screens agree) and battery saver (off/on/auto). Display timeout, status LED and "cooks kept on the bridge" are shown but inert |
| **Home Assistant** | yes | MQTT broker host/port/user/password/prefix + HA auto-discovery toggle. Password is write-only (blank = keep). Wi-Fi only; on BLE the page explains why |
| **Firmware** | yes | Installed version; OTA streaming with device-reported progress; the `409 session_active` refusal is surfaced as copy plus a deliberate "Update anyway, ending this cook" — never an automatic retry. No file picker is wired, so today it explains the web installer / USB route instead |
| **About** | yes | App version, firmware, bridge id, and the MIT attribution for the reference packet parser (a legal obligation, so it is a committed string) |
| **Alarms** | **no entry point** | Two visibly different tiers ("On the bridge — these keep working with your phone switched off"; "On this phone — advisory only"), quiet hours, background monitoring, battery exemption, and an alarm log with acknowledge |
| **Diagnostics** | via the five-tap gate | LoRa/radio rows, base-station re-scan and unpair, raw packet ring, unrecognised-packet log, in-app log, export logs |
| **Power** | no (Bridge tab owns these verbs) | Restart / power off / factory reset with dialogs — a second, older implementation of the same verbs |

### 4.7 Global chrome (rides above every tab)

| Element | Behaviour |
|---|---|
| **Refresh banner** | A failed pull-to-refresh must *say so*. One message, one "Try again", dismissible. Distinguishes "Not connected" (loud) from "The bridge refused / didn't answer" (advisory). Auto-retires the moment a link comes back |
| **System status bar** | Transport chip (Bluetooth / Wi-Fi / Wi-Fi (hosted) / Offline) with a **pulse dot whose stopping is the staleness signal** — no colour flip; a retry counter while reconnecting; the bridge battery **only when it is knowable** (a `0 %` on a bridge that cannot measure one would be a bug report against the hardware). Tapping opens the connection sheet |
| **Alarm bar** | The highest-severity unacked alarm, **including device-scope alarms**, on every tab, with an inline **[ Acknowledge ]** — a 3 a.m. silence must never require a tab change. One haptic per alarm id, not per rebuild |
| **Connection sheet** | Current transport + address, the fallback story in plain words, a preferred-transport segmented control (Auto / Wi-Fi / Bluetooth) with a per-option explanation, a "Keep Bluetooth as backup" switch that admits it costs the bridge a little battery, and a link to network settings. It rebuilds live, so a chosen switch is *seen completing* |
| **Cost sheet** | The confirm pattern for anything that costs something: title, body, **what it keeps**, **what it loses**, and named buttons ("End cook" / "Keep cooking"), never "OK / Cancel" |
| **Verb progress sheet** | Described in §4.5 |

---

## 5. The design system

`app/lib/design/` + `app/lib/ui/`. Specified in `docs/design/14-design-system.md`.

**Surfaces and ink.** Six surfaces (`bg`, `surface`, `card`, `cardSubtle`, `cardRaised`, `well`), four
inks (`textHi`, `textBody`, `textMuted`, `chromeDim`), two hairlines, one shadow. Carried as a
`ThemeExtension` so a **daylight profile** can lift the whole ink ramp and switch every glow off —
because a bloom in direct sun is a smear — without a single call site knowing.

**Dark-only ships.** There is no light theme, deliberately: a white screen outdoors at night is worse
than a high-contrast dark one.

**Geometry.** Four radii (card 20 / control 14 / chip 8 / pill 999) and a 4 dp spacing scale. "A 6 or
a 10 is a bug."

**Type.** Fourteen named styles across three bundled variable fonts. Temperatures use a width axis for
optical size at ten feet, tabular figures, and — critically — **a temperature is never scaled to fit**:
a glyph that changes height as a probe crosses 99 → 100 °F reads as the layout breaking, not as a
temperature rising. The hero number is fixed at 96 pt; the gauge is the flexible child.

**Two colour palettes with a hard separation rule:**

- A **series hue** (per-probe) may only be drawn as a *mark*: a chart stroke, a gauge arc, a ≤ 12 dp
  dot, a card's left rule. It never fills a large shape and **never carries a word**.
- A **status hue** (critical / warning / positive / info / pit) may only be drawn as *chrome*: a
  12–16 % fill with a 22–35 % border, always containing an icon **and** a word.

Consequence: a lit chart line and a "target reached" banner can never be confused. And **banner text
is always `textHi`, never the status hue** — measured, `critical` on its own fill reads 3.2:1 while
`textHi` reads ~13:1. The hue is carried by the icon and border; the words are carried by contrast.

"Positive" green is reserved for transport health. **Target reached is not a colour** — the gauge ring
closes.

**Motion.** Five tokens, and no widget in `ui/` may write a `Duration` literal (a layering test greps
for it). This is the one seam where `MediaQuery.disableAnimations` is honoured. Notably the liveness
pulse is **not** zeroed under reduced motion — the dot ceasing to animate *is* the staleness signal, so
removing it would remove information; what reduced motion drops is the scale, leaving the fade.

**Component library** (`app/lib/ui/`, all stateless over plain values): `AlarmBar`, `PulseDot`,
`SignalBars`, `TransportChip`, `ActionRow`, `MonoWell`, `PrimaryAction`, `SegmentedChips`,
`InsightBanner`, `AnimatedTemp`, `ProbeCompactCard`, `ProbeHeroCard`, `ProbePills`, `ProbeStripRow`,
`Sparkline`, `TargetGauge`, `PasskeyDisplay`, `SetupRail`, `SetupScaffold`, `StaleVeil`, `EmptyState`
/ `ProblemState` / `CapabilityNotice`, `CostSheet`, `SmokeCard`.

**Copy discipline** is treated as part of the design system, and it is unusually consistent:

- Every empty state is glyph + title + one sentence + **exactly one action**; a dead-end with no next
  step is the thing the app is built not to do.
- No jargon: "Gaps in recording" not "dropouts"; "Pit steadiness" not "σ"; "Reset and power" not
  "DANGER ZONE".
- Failures name their cause. Six Wi-Fi causes get six sentences, not one "wrong password".
- A control that cannot work is either **absent**, or **present-and-disabled with its reason on
  screen** — never a switch that silently does nothing. The distinction is deliberate: disabled-with-a-
  reason is right for a control the user came looking for (battery calibration); absent is right for
  one they never knew existed (device "identify").

---

## 6. The communication layer

### 6.1 One interface, three implementations

Every screen talks to `BridgeTransport` and **never knows how it is connected**. Capability flags
drive the handful of places the difference is visible.

| Capability | HTTP (Wi-Fi) | BLE | Mock |
|---|:--:|:--:|:--:|
| Live state | ✔ | ✔ | ✔ |
| 2-hour history preview | ✔ | ✔ | ✔ |
| Full history | ✔ | ✘ | ✔ |
| Config (network) | ✔ | ✔ | ✔ |
| Probe names / roles / targets | ✔ | ✘ | ✔ |
| OTA | ✔ | ✘ | ✘ |
| MQTT / Home Assistant | ✔ | ✘ | ✔ |

Degradation is always surfaced as **copy, not an error**: "Connected over Bluetooth — full history
needs Wi-Fi. Showing the last 2 hours."

### 6.2 The launch race

Six lanes, in priority order (`ConnectionManager`):

1. **manual** — a user-typed address; pre-empts any race in flight and is probed alone
2. **cachedIp** — the last known address (the ~50 ms happy path)
3. **mdns** — `_smokebridge._tcp` browse
4. **mdnsName** — `smokebridge.local`
5. **apDefault** — `192.168.4.1` (the bridge's own AP)
6. **ble** — tried after every HTTP lane fails

A lane "wins" only on a real `GET /status` 200. Reconnect backoff is 1, 2, 4, 8, 15, 30 s, capped, and
is cut short by a connectivity change or by the user pulling to refresh.

### 6.3 The connection supervisor — the premium part of the story

`app/lib/app/connection_supervisor.dart`:

- **Lead with Bluetooth** so data appears the instant the app opens (a bonded BLE reconnect beats a
  Wi-Fi handshake), then
- **upgrade to Wi-Fi in the background** for full history / config / OTA,
- **hold the BLE link as a warm standby** beside the active Wi-Fi one, and
- **fail over to it silently** when Wi-Fi drops mid-cook, then climb back when it returns.

Exactly one transport is ever *active*, so its capability flags stay honest — a composite transport
merging two links would have to lie about what it can do.

Three user preferences steer it (persisted, applied live where safe): **Auto** (whichever connects
first), **Wi-Fi** (lead with Wi-Fi, no BLE→Wi-Fi flash at launch), **Bluetooth** (switch down now and
stay there — the "weak or changing Wi-Fi" case), plus **hold BLE as backup** on/off.

Link loss is **verified, not assumed**: a failed push stream triggers one `status()` read, because a
hit WebSocket cap leaves REST working and an unexpected close is often a hiccup the 10 s poll rides
out. Only a read that also fails triggers failover.

### 6.4 Reads, pushes and polls

| Mechanism | Cadence | Purpose |
|---|---|---|
| WebSocket / BLE notify | push | samples, alarms, session events, net mode, power, pairing, OTA phase |
| Backstop poll | 10 s | catches a missed push; the base station only transmits every ~30 s, so this is not an attempt to read faster than reality |
| Bridge-tab signal poll | 20 s, visible tab only | signal strength |
| Ongoing notification | 30 s | the live readout in the shade |
| Pull-to-refresh | user | **reconnect both radios if offline, then read live now**, and report failure honestly |

`refreshNow()` is the only read that **throws** — precisely because a gesture that silently does
nothing is indistinguishable from one that worked and found nothing new, and that is how an app
teaches people it is broken.

### 6.5 Also on the wire

Home Assistant / MQTT publishing is configured from the app but performed **by the bridge**, so it
keeps working with the phone gone. The bridge appears in Home Assistant as a device with probe,
battery and cook-status entities via auto-discovery.

---

## 7. Data, persistence and offline

**Cache-first is the architecture, not a feature.** `drift`/SQLite, schema v1: `Bridges`, `Sessions`,
`Samples`, `Marks`, `AlarmLog`. Every screen renders from the cache; the transport refreshes it.

**Delta sync** (`SyncEngine`): on connect, read status → reconcile the session list → for each session
whose cache is behind, fetch only from `cachedMaxT + 1`. Inserts are keyed on (bridge, session, t) and
idempotent, so a restart mid-sync resumes without duplicating rows. Reconnecting mid-cook transfers
only what was missed. Reconcile is **upsert-only**, so a cook the *device* has since purged still
exists on the phone: the app owns a full copy of every cook it has ever *seen*.

**Prefs** (`shared_preferences`, deliberately tiny — anything with structure belongs in the database,
anything secret belongs nowhere): last base URL, last bridge id, last BLE device id, last seen,
display units, quiet hours, background monitoring, preferred transport, hold-BLE, and the running cook
plan as JSON. No Wi-Fi password is ever stored by the app.

"Forget this bridge" clears the bridge identity **and the running cook plan** (a plan for a device
this phone no longer talks to would render targets against readings that can never arrive) but
deliberately leaves the transport preference, which is a device-agnostic user choice.

---

## 8. Business logic and domain analysis

All of `app/lib/domain/` is pure Dart with zero Flutter imports, so every rule below is unit-tested
without a widget tree.

### 8.1 The dashboard snapshot — one pure projection

Four sources of truth meet on the Cook screen: the cache, the live push stream, `GET /status`, and
the app's own analysis. Rather than reconciling them in `build()`, `buildDashboard(...)` is a **pure
function into one immutable snapshot** — same inputs, same screen, tested with no widgets. Every
widget renders the snapshot and nothing else. This is what makes "sometimes it shows the old
temperature" structurally impossible.

Sentinel discipline is carried all the way to the pixels: **null means detached, never 0**; null
battery means "cannot report", never "empty"; probes are always four entries in jack order, because a
probe that vanishes from the grid reads as an app bug rather than an empty jack.

### 8.2 Analysis

| Function | Behaviour |
|---|---|
| **Rate of change** | OLS over a 10-minute window; returns null when the window is too short or spans a gap |
| **Stall detection** | Rolling detector over a food probe; drives both the insight banner and a notification |
| **ETA to target** | Two models: linear early, **Newton cooling** once the food is within 60 °F of pit temperature, because meat approaches pit temperature asymptotically and naive `(target − current) / slope` is wrong in the back half of every cook |
| **Lid open** | A detector exists in `domain/analysis/lid_open.dart` but **has no caller in the app**; the lid marks the chart draws and the statistics count come from the bridge |
| **LTTB decimation** | Largest-triangle-three-buckets, plus a min/max envelope so decimation cannot hide a spike |
| **Gap detection** | Threshold derived from the cook's own cadence, so a session retained at 5-minute buckets is not read as one continuous dropout |

**The ETA's guard rails are the feature.** It refuses to answer, with a stated reason, when there is
under 30 minutes of history, when the slope is under 1 °F/hr (projecting noise), during a stall, when
the target is at or above pit temperature ("not at this pit temperature" is the correct answer), or
when the probe is moving away from the target. When it does answer it is **a range rounded to 15
minutes**, never `6h 23m` — the physics does not support that precision, and false confidence is what
makes people trust it and then get burned.

### 8.3 Cook plans, presets and food safety

A plan is app-tier only: it never reaches the Smoke X base (the bridge transmits exactly one packet
per pairing), so app targets drive the app's gauges and advisory alarms, not the base's beeper.

**`CookPlan`'s constructor is a food-safety gate.** Targets are hazard-classed, and a food target
below its protein's floor throws — so an unsafe plan is a build-time failure for the preset table and
an impossible state at runtime. Whole-muscle red meat has no floor (a 125 °F ribeye is a preference),
while poultry, pork and fish do (a 150 °F chicken breast is not a preference). Stored plans are
re-validated on load, so a plan that would now be refused is dropped rather than restored.

The preset table (10 cuts across 4 categories, with doneness levels, rest offsets and pit bands) is
food-safety data and is flagged in-code as **needing a named reviewer before it ships**.

### 8.4 Alarms — two tiers, visibly different

| Tier | Owner | Promise |
|---|---|---|
| **Device** | the bridge | Runs on the ESP32. Keeps working with the phone switched off, out of range, or flat. Nine rules: base-station alarm, target reached, pit out of band, pit crashing, probe unplugged, base station lost, battery low, storage nearly full, unexpected restart |
| **App** | this phone | **Advisory only.** Needs the app running, and never replaces the bridge's alarms: ETA-soon, stall started/ended, lid open, bridge unreachable, phone offline |

Listing them as one list of switches would imply the phone tier can be switched off and the device
tier cannot — so they are two sections with two stated promises. **The app mirrors device alarm state;
it never re-decides it.** Acknowledging silences, it does not resolve.

### 8.5 Notification policy — one pure function

`planNotifications(...)` takes the device's alarms, the set of keys already on screen, the wall clock,
the app-tier findings, quiet hours and the monitoring flag, and returns what to post and what to
withdraw.

- Four Android channels created up front (importance cannot be changed after creation): **critical**
  (sound + heads-up + full-screen intent), **warning**, **info**, **ongoing** (silent,
  non-dismissible).
- **Quiet hours (22:00–06:00) silence warnings and info but never critical** — overcooking a brisket
  at 3 a.m. is precisely what is worth waking up for. Evaluated in the *phone's* local time, because
  the bridge's clock may be stale or absent and quiet hours exist to protect a sleeping human next to
  the phone.
- An alarm the bridge reports as raised-and-unacknowledged at 07:00 **must** notify even though it
  fired at 03:40 while the phone was face-down — and must **not** re-notify on every poll.
- Turning monitoring off withdraws everything, because leaving notifications behind would imply it is
  still running.

### 8.6 Background monitoring

`CookMonitor` runs the same reconciliation loop with no UI: subscribe, persist every sample straight
to the database (history must survive the app being swiped away), reconcile alarms, post/withdraw
notifications, and maintain an **ongoing notification that is a live readout**, built from the *same*
projection the dashboard renders so the shade can never disagree with the screen behind it:

```
🔥 Smoke Bridge · Brisket · 04:12
Pit 243.0°F ▼   Brisket 163.0°F ▲
ETA 5h45m – 7h00m · 78%
```

Lifecycle: the foreground service starts when monitoring is on and a session is active, stops 10
minutes after the last successful connection when no session is active, and warns once (not per
retry) after 3 minutes with no data. The battery-optimisation exemption is **offered after the first
cook starts** — not at launch, because a permission prompt before the user has seen anything work is
the classic way to get it denied permanently — and a decline is accepted gracefully, because delta
sync means the app catches up when reopened.

---

## 9. Cross-cutting rules the code actually enforces

These read as house rules and show up everywhere. They are worth knowing before proposing changes,
because most of them exist to prevent a specific failure that already happened once:

1. **No dead controls.** A control that cannot work is absent, or disabled with its reason visible.
2. **No state without a next step.** Every screen and every setup state has at least one way forward.
3. **No raw exception reaches the user.** Failures become named states with specific copy.
4. **Absent ≠ zero.** A missing temperature, battery or signal renders as absent with a reason, never
   as `0`.
5. **Never present stale data as current.** Freshness veil, transport-swap discards, "last known"
   framing, the pulse dot.
6. **State the cost before a destructive action**, split into keeps and loses.
7. **Verify by behaviour, not by return value**, for anything the device answers before it does.
8. **Prefer copy over errors** when a capability is genuinely missing.
9. **The device is authoritative** for alarms, sessions and recording; the app mirrors.
10. **Extra screen width buys chart, not stretched numbers.**

---

## 10. What is *not* built, and where the seams show

Verified against the current code. This is the most useful section for a redesign conversation.

**Not built / not wired:**

| Gap | Evidence |
|---|---|
| **Alarm rules cannot be edited** — neither the bridge's nine rules nor the app's advisory ones | The Alerts tab says so in a "RULES" card; `AlarmSettingsView` exists but its rule map is a hardcoded const and its toggle callback is null |
| **The alarms settings page has no entry point** — quiet hours, background-monitoring toggle and the alarm log are only reachable by typing `/bridge/alarms` | `SettingsSection.deviceSections` excludes `alarms`; the Alerts tab does not link to it |
| **No share sheet for CSV export.** The snackbar shows a file path; `share_plus` is a dependency but unused | `features/sessions/sessions_route.dart` comments admit this deliberately |
| **No file picker for OTA**, so in-app firmware update is explained rather than offered | `AppEnv.firmwareImage` is never set in `bootstrap()` |
| **Cook renaming is not reachable.** `SessionDetailView` has a rename dialog; no route passes `onRename` | `sessions_route.dart` passes `onExport` only |
| **The Cook tab's action row is always empty.** "Mark", "Test alarm" and "Export" exist in the widget but no callback is wired | `cook_tab.dart` passes none of `onAddMark` / `onTestAlarm` / `onExport` |
| **Probe rows on Cook look tappable but do nothing.** `onProbeTap` is unwired, yet the rows keep their ripple and chevron | same file; the chevron is drawn unconditionally in `ProbeStripRow` |
| **No chart window chips, "Now" pill or crosshair on the Cook tab** — they exist and are used only in History | `ChartControls` / `CrosshairReadout` are referenced only from `sessions_screen.dart` and the unrouted `dashboard_screen.dart` |
| **No probe-mapping page in cook setup.** Jack 1 = pit, jack 2 = food by convention | `cook_setup_sheet.dart`; deferred, not faked |
| **No custom cook** — presets only; no editing a running cook's targets or name | `cook_setup_sheet.dart` |
| **No device "Identify"** verb (no firmware op), so the row was removed rather than left disabled | `bridge_tab.dart` |
| **Battery never displays** — the firmware does not yet report `soc_pct`, so the status bar omits it and battery calibration is disabled with its reason | `dashboard_snapshot.dart`, `settings_screen.dart` |
| **English only, no localisation.** Strings are partly extracted to `features/setup/copy/` but most are inline | |
| **iOS is out of scope for v1** and is a redesign, not a port (Android-only bond flow, `turnOn()`, settings intents, hotspot API, foreground service) | `docs/design/13 §13.9.1` U6 |

**Seams worth a second look during a redesign:**

- **The settings tree does not use the shared connection.** `SettingsRoute` builds its *own*
  `HttpTransport` from the remembered base URL, while the Bridge tab correctly reuses the shell
  session's open link. Consequences: on a Bluetooth-only setup the settings pages get no transport at
  all, and because `configure()` is called through a null-aware operator, **saving probe settings can
  appear to succeed while writing nothing.** (`settings_route.dart` `_load()` / `ProbeSettingsView.onSave`)
- **Device settings shows defaults as facts.** Display timeout (60 s), status LED (on) and "cooks kept
  on the bridge" (64) are constructor defaults rendered as if read from the device, and the write
  callback is null, so two of the three rows are inert.
- **Diagnostics is mostly a stub.** The radio map is `{firmware, packets_seen: numProbes}` — the second
  is mislabelled — and packets, novelty log, app log and "Export logs" are all empty or disabled.
- **Two implementations of the same destructive verbs** (`PowerSettingsView` dialogs vs the Bridge
  tab's cost sheets + verify sheet). The Bridge tab's is the good one; the older page is still routable.
- **Dead-ish code from the pre-shell era** still compiles and is partly imported for helpers:
  `features/dashboard/dashboard_route.dart`, `dashboard_screen.dart`, `header_strip.dart`,
  `session_controls.dart`, `features/onboarding/*` (the superseded wizard, still routed at
  `/onboarding`), and `/cook-preview`.
- **Session start/stop is not exposed at all.** `ControlCommand.sessionStart/sessionStop` exist on the
  transport; no screen sends them. This is arguably correct (the bridge always records) but it means
  the app has no answer to a user who wants to *split* cooks.
- **Marks can be read but not created.** The chart draws them and History lists them; the only code
  that sends `ControlCommand.mark` is the unrouted `session_controls.dart`.
- **The app's lid-open detector is unused.** `AppFinding.lidOpen` has copy written for it and is never
  produced; the pit-alarm pause it describes happens on the bridge.
- **`ProbeRole.ambient` exists** in the model and the probe editor but nothing downstream treats it
  differently from unused.

---

## 11. Testing and tooling (relevant because it constrains how fast a redesign can move)

- **~75 test files** across `app/test/`: unit (domain, data, transports), widget, **golden**, and
  integration. There is a golden suite for the app and a separate framebuffer golden suite for the
  device's OLED.
- **`tools/sim`** — a fake bridge (`dart run sim`) implementing the real HTTP/WebSocket API, so the
  whole app runs with no hardware.
- **UX Lab** (`flutter run -d chrome -t lib/lab/main_lab.dart`) — two hardware-free harnesses: the live
  Cook tab driven by a fake bridge with scripted scenarios, and the **real** setup machine driven over
  fakes. This is the fastest way for an advisor to *see* the flows without a bridge on the bench.
- The transport behavioural suite runs against `HttpTransport` and `MockTransport` from one harness,
  which is the claim the layered architecture rests on.

---

## 12. Questions worth putting to the advisor

Framed from what the code shows, not from a wish list:

1. **Is the four-tab IA right?** Alerts is a whole primary destination for what is essentially a
   permissions verdict plus a test button. Bridge is device management. Neither is where a user spends
   the fourteen hours.
2. **Instrument mode vs guided mode is a single nullable.** Is a modal "cook" the right mental model at
   all, given the bridge records regardless — or should the app treat cooks as *annotations over a
   continuous recording* (name it, target it, split it, after the fact)?
3. **The Cook tab is read-only in practice.** With marks, export, test-alarm and probe drill-down
   unwired, the only actions are "set up a cook" and "end cook". What belongs there?
4. **Chart affordances are split** — the live chart has gestures but no controls; the history chart has
   controls. Should they converge?
5. **Alarm configuration has no home.** Delivery lives in Alerts, rules live in an unreachable settings
   page, and the ringing alarm lives in the global bar. Where should rules go, and should the device
   tier and app tier stay visibly separate?
6. **How much transport detail should a user see?** The app currently exposes preferred transport,
   hold-BLE, two-hop signal strength and capability notices. That is unusually honest — and unusually
   technical.
7. **The settings tree is Material-default while everything else uses the custom design system.** It is
   the largest visual inconsistency in the app.
8. **Is the copy discipline worth preserving verbatim?** It is the app's strongest asset and the
   easiest thing to lose in a visual redesign.
