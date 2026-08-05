# Redesign Specification: Flutter BBQ Thermometer Companion App ("SmokeBridge")

## 0. How to read this document
This is an implementation-ready spec for an LLM editing the existing codebase. Sections are numbered so you can be pointed at one (e.g. "implement §D.4"). Where a choice depends on facts only the codebase owner has, it is flagged **OPEN DECISION** with options and trade-offs. Competitor evidence is cited inline as justification.

Guiding product sentence (north star, from the user): *the app is first and foremost a quick temperature reader for probes plus the synced history; everything else is controllable in-app because the ESP32 has one button (power-off only); an advanced cook system exists but you can start a cook now and set the timer/target/start-time later; settings control everything; AAA experience.*

---

## A. Competitive teardown & differentiators

### A.1 Feature matrix

| Capability | MEATER | FireBoard | TempPro BBQ | This app (target) |
|---|---|---|---|---|
| Local-only, no account required | ❌ account required to log in; users resent it | ⚠️ cloud-centric, account required | ✅ no account | ✅✅ **local-first, no account ever** |
| Device keeps recording/alarming with phone off | ⚠️ probe has memory but app-centric | ⚠️ cloud failsafe monitor | ⚠️ device alarm continues, app must stay open | ✅✅ **ESP32 records + runs 9 alarm rules autonomously** |
| Bluetooth quick-connect | ✅ | ✅ | ✅ (BLE only) | ✅ |
| Wi-Fi (own network) | ⚠️ only Block/Pro XL have built-in Wi-Fi; others need 2nd phone as bridge | ✅ Wi-Fi to cloud | ⚠️ some models | ✅ station mode |
| Wi-Fi SoftAP (device hosts network) | ❌ | ❌ | ❌ | ✅✅ **192.168.4.1 host mode** |
| Range extension w/o cloud | ❌ needs 2nd phone (MEATER Link) or Cloud | ❌ needs cloud | ❌ | ✅ SoftAP + station |
| Predictive done-time | ✅ Advanced Estimator (predicts remove-from-heat & rest) | ✅ FireBoard Analyze predictive | ⚠️ estimator, weak on stall | ✅ ETA w/ guardrails (already built) |
| Guided cook progression | ✅ approaching→remove→rest→ready | ❌ | ❌ | ✅ (to build honestly) |
| Editable alarm rules | ✅ Add Alert taxonomy | ✅ per-channel high/low + failsafe | ✅ hi/low + pre-alarm | ❌ today → ✅✅ (to build) |
| Sessions as editable annotations | ⚠️ cook-centric | ✅ auto date-named, editable start/end, notes | ❌ | ✅✅ (to build) |
| Retroactive start / backdate | ❌ | ✅ can edit start/end time | ❌ | ✅✅ (to build, core differentiator) |
| "Repeat this cook" | ✅ Previous Cooks reuse target+alerts | ⚠️ Analyze overlay | ✅ compare stats | ✅ (to build) |
| CSV export | ⚠️ | ✅ web portal, 3 resolutions (5 s / 1 min / 5 min) | ✅ save/share | ✅ (byte-compatible w/ device) |
| Full control of a 1-button device | n/a | n/a | n/a | ✅✅ **unique requirement** |

### A.2 The three differentiators this app should own
Pick these and market/engineer around them:

1. **Local-first, no cloud, no account — and it still wakes you at 3 a.m.** The single loudest recurring complaint about MEATER is the mandatory account. A top Play Store review reads: *"This is a meat thermometer, yet they insist on logging you in. Imagine if your Bluetooth headphones required their own account."* FireBoard and ThermoWorks are explicitly cloud-centric (FireBoard's own store listing calls it a *"Cloud Connected Smart Thermometer"* that *"pushes realtime temperature updates via the cloud"*; ThermoWorks stores *"all session data … in ThermoWorks Cloud"*). Owning "your data never leaves your phone and the device, and it still works with no internet" is a genuine, defensible wedge. The SoftAP mode is the proof: the phone joins the *bridge's own* network, so there is provably no internet path.

2. **The device is authoritative and autonomous.** The ESP32 records to flash and runs its nine alarm rules with the phone off or out of range. This directly answers the second-loudest complaint cluster across every competitor: disconnect-driven data gaps and missed alarms. MEATER's own Play listing acknowledges *"disconnect alerts can occur once the probe moves outside Bluetooth range"*, and a reviewer notes it *"will start pinging you like crazy that the thermometer is disconnected."* A competing Bluetooth fan controller was thrown out because *"there is NO alarm when the unit disconnect so you have to pray that it stays connected through an unsupervised cook … twice during the cook the meat probe just up and LOST the setting I had programmed with ZERO warning."* The TempPro app similarly requires you to *"not close the … app, simply minimize"* or the alarm won't fire. Frame the phone as an *archive and remote control*, not the source of truth.

3. **Cooks are editable annotations over a continuous recording — start now, backdate and target later.** No competitor lets you truly start a cook after the fact and re-anchor its start time; FireBoard is closest (a session auto-starts *"once temperature data is being pushed"* and you can *"adjust the start and/or end time"* later). This is exactly the user's stated requirement and it falls out naturally from "the bridge always records."

Honest-freshness discipline (the freshness ladder, absent≠zero) is a fourth, quieter differentiator worth keeping verbatim (see §H). It directly counters FireBoard's known weak spot, where a stalled feed only surfaces as a vague *"Waiting on temperature data"* message.

---

## B. Proposed information architecture

### B.1 The core problem with today's IA
Four tabs (`/cook`, `/history`, `/alerts`, `/bridge`) where two of them (Alerts = a permissions verdict + test button; Bridge = device management) are not where a user spends fourteen hours. The user wants a *reader first*. Collapse the two "meta" destinations into a single Device/Settings home and promote the reader.

### B.2 Proposed route tree

```
/  (redirect → /live if a bridge is known, else /onboard)

/onboard                     ← guided setup (slimmed from the 34-state machine; see §I)
  /onboard/connect
  /onboard/mode              ← choose BLE / SoftAP / station

Shell (StatefulShellRoute.indexedStack — KEEP this pattern; all branches stay mounted, one connection via InheritedWidget)
  Tab 1  /live               ← THE READER. Default landing. Always shows probes.
           /live/probe/:jack ← per-probe detail (chart chips, crosshair, targets, alarms)
  Tab 2  /cooks              ← session list (annotations over the recording)
           /cooks/:id        ← cook detail (chart + stats + marks + notes)
           /cooks/:id/edit   ← rename, backdate start, retarget, split/merge
  Tab 3  /device             ← device home: status, connection mode, battery, OLED/LED, power
           /device/settings/:section  ← the full settings tree (§F)
           /device/alarms    ← rule editor for BOTH tiers (§G)
```

Rationale for each change:
- **`/alerts` is deleted as a primary destination.** A permissions verdict is not a place you live. Fold the "will this phone wake you?" verdict into (a) a one-time onboarding gate and (b) a persistent, dismissible-until-fixed banner on `/live` and `/device` when a required permission is missing. The "test alarm" button moves into `/device/alarms`.
- **`/bridge` becomes `/device`** and absorbs settings, alarms, network mode, power. This is the "control everything" home.
- **`/cook` (singular, live) splits from `/cooks` (plural, the session system).** The live reader is not a cook — the cook is an *annotation* you can attach. This is the key mental-model shift (see §D).
- Keep `context.go` banned outside the top-level redirect; keep `context.push` for in-tab nav; keep re-tap-to-pop-to-root; keep the single shared connection via InheritedWidget. These rules are good and are load-bearing for keeping the live connection alive.

### B.3 First 400 ms of cold start & always-on-screen contract
The user demanded "first and foremost a quick temp reader." Concrete contract:
- On cold start, **before any transport connects**, `/live` renders immediately from the drift cache: the last-known probe values with their freshness state already computed from stored timestamps (so a 6-minute-old reading shows as *stale*, never as fresh, never as a spinner). This is possible because `buildDashboard()` is a pure projection over stored samples + wall clock — call it synchronously on boot with cached data.
- **Always on screen on `/live`:** every plugged probe's current temperature (the hero data), its freshness state, and the transport-health chip. Nothing else is allowed to push the temperatures below the fold at any breakpoint.
- The connection race (six lanes, BLE-leads) runs in the background and upgrades the reading in place; the number never flickers to a spinner once shown.

---

## C. Screen-by-screen specification

Legend for states every screen must handle: **Empty / Loading / Partial / Stale / Offline / Error / Permission-blocked.**

### C.1 `/live` — The Reader
- **Purpose / one question:** "What temperature is everything right now, and can I trust it?"
- **Layout (compact width):** vertical list of up to four probe rows in jack order. Each row: colour swatch (series hue, ≤12 dp), name, sparkline (series hue stroke), large tabular temperature (never scaled), trend chip, chevron → `/live/probe/:jack`. Transport-health chip pinned top; freshness applies globally.
- **Layout (expanded width / tablet):** extra width buys a **bigger shared chart** above the rows (multi-series), never wider numbers (readout column capped 480 dp). Foldable tabletop: chart upper screen, readouts lower (keep the existing `displayFeatures` logic).
- **Guided overlay:** when a cook plan with targets exists, the pit and primary-food probes become hero cards with the 96 pt temperature + 84 dp radial `TargetGauge`; other probes drop to compact cards (keep the existing 800 ms transition).
- **States:**
  - *Empty (no probes plugged):* glyph + "No probes connected" + one sentence + one action ("Check probe jacks"). Detached probes render in place at 45% opacity showing "—" and "unplugged" — **never 0**.
  - *Loading:* render cached values immediately (see §B.3); no full-screen spinner.
  - *Stale (>90 s / >600 s):* apply StaleVeil; **remove** derived values (ETA, gauges), don't grey them; pin "Readings are N minutes old."
  - *Offline / base-station lost:* frozen state; banner names the cause ("Base station lost — last reading 3 minutes ago").
  - *Permission-blocked:* top banner "Notifications are off — this phone can't wake you" + one action → system settings.
- **Controls & where they write:** action row (currently always empty — **wire it**): **Mark** (writes a Mark to device + cache via transport; §D), **Attach/Start cook** (opens cook sheet, §D), **Export** (share_plus sheet — currently unused dependency), **Test alarm** (moves to `/device/alarms` but a shortcut can live here). Probe rows currently look tappable but do nothing — **wire the chevron** to `/live/probe/:jack`.

### C.2 `/live/probe/:jack` — Per-probe detail
- **Purpose:** "What is this one probe doing over time, and what should it alarm on?"
- **Content:** big current temp + trend; chart with window chips (15 m / 1 h / 6 h / 15 h / All) + "Now" pill + crosshair readout — **converge the live and history chart affordances** (today these exist only in History; this is an OPEN question the team raised — recommendation: **converge them**, one chart widget used in both places). Below: this probe's role (pit / food / ambient / unused), target, and its alarm rules (§G) with inline edit.
- **States:** same ladder; if BLE-only and full history unavailable, show the honest copy from §E.5 rather than an error.

### C.3 `/cooks` — Session list
- **Purpose:** "Show me my cooks (past and running) as annotations over the recording."
- Model on FireBoard's auto-named sessions ("Tue May 17 Session", duration subtitle) but keep this app's nicer metadata line (date · duration · peak · probe count) + sparkline. "Recording" badge on the open session. List watches the DB (cache-only, no transport). "+" in app bar → **create a cook now** (which may backdate; §D). Note that FireBoard sessions *"automatically close after 30 minutes of inactivity"* and *"roll over into a new session after 24 hours"* — this app should NOT auto-close aggressively; because the bridge records continuously, let a cook run as long as the user wants and only bound it on explicit edit.
- **States:** *Empty:* "No cooks yet — your bridge is still recording. Start one anytime." (Reinforces the annotate-over-continuous model.)

### C.4 `/cooks/:id` and `/cooks/:id/edit` — Cook detail & editor
- **Detail:** chart (same widget as live), statistics table (keep the existing rich set: total time, readings, gaps in recording, pit mean/steadiness/min/max, time in band with gap time excluded, stall, lid events, per-probe start/end/peak), mark timeline (tap centres chart), notes field (steal from FireBoard/TempPro — a 0/200 notes field with placeholder like "flip burgers"), photo attach (OPEN — nice-to-have), CSV export via share sheet.
- **Editor:** rename (currently a dialog with no route wiring — **fix**); **backdate start time** (§D.3); retarget probes; **split** at a chosen mark/time; **merge** with adjacent cook; delete (cost sheet: recording does NOT stop, only the annotation is removed).

### C.5 `/device` — Device home
- **Purpose:** "Is my bridge healthy, how is it connected, and how do I control it?"
- Content: device name, connection mode (BLE / SoftAP / station) with a plain-language explainer and a **switch-mode** control (§E), battery (once firmware reports it — see gap), storage used, firmware version + update entry point (file picker — currently missing), OLED/LED quick toggles, **Power off** (mirrors the one hardware button; confirm sheet), and entry points to `/device/settings` and `/device/alarms`.
- **Bring the settings tree into the design system** — today it is Material-default and is the largest visual inconsistency; restyle every row with the ThemeExtension tokens.

### C.6 `/device/alarms` — Alarm rule editor (both tiers) — see §G.

### C.7 `/device/settings/:section` — full settings tree — see §F.

---

## D. Cook / session model redesign

### D.1 Core reframe
Today a "cook" is a modal plan; the team already suspects this is wrong. **Reframe: the bridge records one continuous sample stream per probe forever (until buffer rollover). A "cook" is an editable annotation — a named, time-bounded, targeted window over that stream.** This makes start-now/target-later, backdating, splitting and merging trivial, and matches "the bridge always records."

### D.2 Drift schema changes (schema v1 → v2)
Use drift's `stepByStep` migration (generate with `drift_dev schema steps`; keep the golden schema files). Concrete changes:
- **Samples** table: keep `(bridge, session, t, probe, value)`; the insert key `(bridge, session, t)` stays idempotent. **OPEN DECISION:** decouple samples from `session` — store samples against `(bridge, probe, t)` only, and derive session membership by time-window join to the Cooks table. *Option A (recommended):* samples are session-agnostic; a Cook is `(bridge, startT, endT?, name, …)` and membership is a range query. This is what makes backdate/split/merge pure metadata edits with zero sample rewriting. *Option B:* keep `session` FK on samples and rewrite the column on edit (heavier, race-prone). Recommend A.
- **New `Cooks` table:** `id, bridgeId, name (nullable → auto "Cook #N"/date), startT, endT (nullable = running), createdAt, isAnnotationOnly (bool), notes (text, nullable), presetId (nullable), status`.
- **New `ProbeRoles` table:** `cookId, jack, role (pit|food|ambient|unused), targetTemp (nullable), pullOffset, doneness (nullable), hazardClass`.
- **New `AlarmRules` table:** `id, scope (device|app), jack (nullable), type (ambient_below|ambient_above|internal_below|internal_above|target_reached|time_elapsed|time_before_end|pit_out_of_band|pit_crash|probe_unplugged|base_lost|battery_low|storage_full|restart), threshold, window, enabled, pushedToDevice (bool), lastConfirmedAt`.
- Keep **Marks** and **AlarmLog**; add `Marks.autoAnchor` (bool) to support re-anchoring start to a detected event. Add a **`SyncState`** table/columns for per-(bridge,session) high-water marks (§E.4).
- Migration must be upsert-safe and preserve existing sessions by converting each old session row into a Cook annotation spanning its min/max sample `t`. Drift `stepByStep` shape: `onUpgrade: stepByStep(from1To2: (m, schema) async { … m.createTable(cooks); m.createTable(probeRoles); m.addColumn(marks, marks.autoAnchor); … })` inside `runMigrationSteps`, with `PRAGMA foreign_keys = OFF` around the transaction per drift's own migration guidance.

### D.3 The retroactive-start problem (core feature)
Prior art extracted:
- **Strava** lets you edit a manual activity's *"start time, distance, and duration"* on mobile; and shipped "Quick Edit" so you can adjust name/visibility immediately after an activity uploads (Strava's own help center + TechRadar coverage, Sept 2024). Lesson: editing start time after the fact is a normal, expected affordance — expose it plainly.
- **FireBoard** auto-creates a date-named session *"once temperature data is being pushed"*, and lets you *"give your session a unique name, adjust the start and/or end time, and add additional information"* later from the Session Detail pencil. Lesson: **auto-create silently, name/bound later.**
- **Toggl/Harvest-style** backdated entries and **Garmin lap re-definition** (a community GitHub project exists precisely because Garmin *"won't let a user manipulate when/where a new lap was started in an already uploaded activity"* — a cautionary tale: users want it badly enough to build workarounds).

Concrete UX:
1. **Start a cook now** → creates a Cook with `startT = now`. Immediately offer "Actually, it started earlier" → a time picker that snaps to **detected candidate anchors**: the last probe-insertion event, the last temperature inflection (a probe crossing ambient), or a manual mark. Re-anchoring just changes `startT` (metadata only, per §D.2 Option A).
2. **Set the target/timer later** → a running cook with no target shows a persistent "Set a target" affordance on `/live` and `/cooks/:id`. Adding a target installs the guided overlay retroactively; ETA/gauges appear once enough samples exist.
3. **Backdate before the app was opened** → because samples exist independently in the device buffer (and are backfilled on connect), a cook whose `startT` precedes app launch is fully valid; the chart simply renders the backfilled range.
4. **Start time in the future** (user's phrasing "a start time to be set before you started") → allow `startT > now` = a *scheduled* cook; the app arms the guided overlay and alarms to activate when samples begin arriving after that time.

### D.4 Presets, custom cooks, and the food-safety gate
Keep the existing `CookPlan` constructor as a **food-safety gate** and harden it with authoritative USDA FSIS data. Enforced floors (hard) vs preference (soft):

| Protein class | Enforced floor | Basis (USDA FSIS unless noted) |
|---|---|---|
| Whole-muscle **intact** red meat (beef/lamb/veal steak/roast) | **No hard floor** below doneness preference; medium-rare 130–135 °F allowed | Interior of an intact cut is effectively sterile; contamination is surface-only and killed by the sear. USDA NAL, *"Examination of the Microbiological Safety of Rare Steak"*: *"Muscle is considered a sterile tissue … in theory the steak should not prove hazardous even though the centre is uncooked."* |
| Ground meat (beef/pork/veal/lamb) | **160 °F** | USDA FSIS: *"All raw ground beef, pork, lamb, and veal should be cooked to an internal temperature of 160°F (71°C)."* |
| Poultry (all, whole/pieces/ground) | **165 °F** | USDA FSIS |
| Fresh pork (chops/roasts) | **145 °F + 3-min rest** | USDA FSIS *"Doneness Versus Safety"*: 145 °F *"before removing meat from the heat source"* then *"allow meat to rest for at least three-minutes."* (2011 rule change: *"only 3 numbers to remember: 145 for whole meats, 160 for ground meats and 165 for all poultry."*) |
| Fish / seafood | **145 °F** (or opaque & flakes) | USDA FSIS |
| Egg dishes | **160 °F** | USDA FSIS |

**Critical liability caveat to encode:** the "no floor" logic applies ONLY to *intact* whole-muscle cuts. Mechanically-tenderized / blade-tenderized / injected ("needled") beef pushes surface bacteria into the interior and behaves like ground meat — it MUST get the 160 °F ground-meat floor. Add an `isIntact` flag to whole-muscle presets and, if false, enforce 160 °F. Offer two labelled modes: **"USDA compliant"** (145 °F + 3-min rest for red meat) and **"Chef / enthusiast — intact whole-muscle only"** (130–135 °F medium-rare). The gate should `throw` on a poultry/pork/fish/ground target below its floor (as today), and surface the intact-cut warning as copy, not a throw, for red meat. Show a persistent raw-meat safety strip as MEATER does (*"Consuming raw or undercooked meats, poultry, or seafood may increase your risk of foodborne illness"*).

- **Preset doneness targets (MEATER convention, final/post-rest temps, from MEATER's Steak Internal Temperature Guide):** Rare 125 °F, Medium-Rare 135 °F, Medium 145 °F, Medium-Well 155 °F, Well Done 165 °F. Persist as tunable data, not code.
- **Carryover / pull-early (AmazingRibs + ThermoWorks):** AmazingRibs: *"a 1″ steak will not continue to warm more than a degree or two … But a prime rib roast that is 4 to 6″ thick will have significant carryover … large thick roasts … should come out of the heat at 5°F less than the desired temp … If you are cooking at high temps, carryover can be up to 10°F."* So: thin cuts (~1″ steaks/chops/chicken pieces) → pull offset ~0–3 °F; thick roasts (prime rib 4–6″, large turkey breast) → pull 5–10 °F below target; sous-vide = **zero carryover**, disable the offset (ThermoWorks: *"With sous vide cooking, there will be NO carryover cooking"*). Store `pullOffset` per preset and per cook. **Do not double-count**: MEATER publishes targets as post-rest and advises pulling at 135 °F for a final medium-rare thin steak. For **poultry**, USDA notes there is *"no required rest period"* and warns you *"cannot rely on carryover to bring an under-cooked bird up to 165 °F"* — so poultry `pullOffset` defaults to 0 and the app must verify 165 °F by sensor, never predict it up.
- **Custom cook:** allow arbitrary per-jack role + target + pull offset + doneness, subject to the gate. Closes the "presets only" gap. (TempPro proves demand: reviewers complained the max settable alarm was 175 °F when *"Pulled pork needs to go to 193"*; TempPro's fix was a custom-profile "+" button.)
- Editing a **running** cook's targets/name must be allowed (closes a gap).

### D.5 MEATER-style guided progression, done honestly at 30 s cadence
MEATER's app walks approaching → **remove from heat** → **rest** → **ready ("Happy Eating!")**, and its Advanced Estimator predicts the remove and rest phases, not just target-reached; Weber Connect does the same with flip/serve notifications and a *"food readiness countdown"*; Combustion goes further with a physics *"Prediction Engine … creates a virtual model of your food based on heat flow"* using 8 sensors. This app should offer a comparable four-phase progression **but must respect the existing ETA guardrails** given a ~30 s sample cadence (worst case) and possible LoRa packet loss:
- **Phases:** `Approaching` (below pull temp) → `Pull now` (reached pull-early temp = target − pullOffset) → `Resting` (off-heat, carryover countdown by cut thickness) → `Ready` (rested to target). Map to `TargetGauge` sweep mode; keep "Target reached → close the ring + flip pill to 'Reached'" and DO NOT use colour (green is reserved for transport health).
- **Honesty rules (keep verbatim):** ETA answers as a range rounded to 15 minutes, never false-precision "6h 23m"; it **refuses with a stated reason** when the pit is unstable, samples are stale, or the trend is non-monotonic. When refusing, say why ("Not enough steady data to estimate — pit swinging"). Note Combustion itself concedes its countdown *"is usually within 10% of the true cooking time"* and only appears *"about 1/3 of the way through"* — so a rounded range is the honest presentation even for a market-leading estimator.
- **Resting phase** is time+physics based (carryover by thickness), not sensor-based unless the probe stays in during rest; label it as an estimate.
- **OPEN DECISION:** whether to attempt a Combustion-style virtual-core model. Recommendation: **no for v1** — the upstream is a single-point probe at 30 s; a physics virtual core needs multi-point/edge sensing. Keep the OLS-rate + Newton-cooling ETA already built and market it honestly.

### D.6 "Repeat this cook"
Model on MEATER Previous Cooks (*"Tap a cook to reuse its target temperature and alerts for this cook. Swipe from right left … to remove it or add it to your favourites"*; Peak/Target columns). On `/cooks/:id`, add "Repeat": creates a new cook copying roles, targets, pull offsets and alarm rules. Add a favourite flag. High-value and cheap.

---

## E. Connectivity & sync specification

### E.1 The three modes, as presented to the user
Keep the transport internals but present three plain choices on `/device`:

| Mode | What the user is told | When to use | Internet? |
|---|---|---|---|
| **Bluetooth (quick)** | "Fast, close-range. Great for checking in." | Standing near the cooker | No |
| **Wi-Fi — Bridge hosts (SoftAP)** | "Your phone joins the bridge's own network at 192.168.4.1. Longer range, no router needed, still no internet." | Backyard, no good router coverage | No (provably) |
| **Wi-Fi — Join my network (station)** | "The bridge joins your home Wi-Fi. Monitor from anywhere in the house." | Home with good Wi-Fi | Router's internet, but app never needs it |

Keep the connection supervisor: BLE leads so data appears instantly, upgrades to Wi-Fi in the background, holds BLE as warm standby, fails over silently; exactly one transport active so capability flags stay honest. Keep the six-lane race (manual → cachedIp → mdns → mdnsName → apDefault → ble) and backoff (1,2,4,8,15,30 s); a lane wins only on a real `GET /status` 200; link loss verified by a `status()` read, not assumed.

### E.2 Android platform mechanics for SoftAP (the hard part)
When the phone joins the bridge's SoftAP, Android sees "no internet" and may show a "Wi-Fi has no internet, stay connected?" prompt and/or route traffic back to cellular. Concrete handling:
- Use the **`WifiNetworkSpecifier` / network-request (IoT) API** (Android 10+) to request the bridge's SSID; this scopes connectivity to the requesting app and avoids the system silently abandoning the no-internet network. This API *"scopes the internet connectivity only to the app that requested it"* — so use `ConnectivityManager.bindProcessToNetwork()` (via the `NetworkCallback`) so `dio`/WebSocket traffic goes over the bridge network, not cellular.
- The Wi-Fi Suggestion API alternative persists a suggestion but gives less control and still hits the no-internet UX; the network-request API is the better fit for a display-less device. Document that the connection drops when the app is closed (a property of the request API) — acceptable because BLE is the warm standby.
- Provide explicit copy for the "stay connected?" dialog: a pre-dialog coach mark "Android will ask if you want to stay on a network with no internet — tap Yes. The bridge has no internet by design."

### E.3 Driving the ESP32's mode change from the phone (the drop-the-link case)
The genuinely hard case: telling the bridge over BLE/current-Wi-Fi to switch modes, when the switch **kills the very link that carried the command**. Protocol:
1. **Command is a request for a *future* state with a rollback timer.** App sends `POST /netmode {target, ssid, psk, revertAfterS: 120}`. Device ACKs on the *current* transport before switching.
2. Device applies the new mode but starts a **revert timer**: if the phone does not re-establish and send `POST /netmode/commit` within 120 s, the device reverts to the previous known-good mode. Prevents bricking connectivity on a bad credential.
3. App tears down the current transport, runs the connection race against the *expected* new endpoint (`192.168.4.1` for SoftAP, or mDNS for station), and on first `GET /status` 200 sends the commit.
4. UI is a stateful wizard: "Switching… (the app will reconnect automatically)" → success or "Couldn't reach the bridge on the new network — it will return to <previous> in <countdown>." Never leave a dead control or an unexplained spinner.
5. **Always keep BLE as the escape hatch:** even when switching Wi-Fi modes, BLE can carry the revert/commit if Wi-Fi fails. This is why "hold BLE as backup" should default ON.

### E.4 Backfill protocol against a small ring buffer
Formalise the existing delta-sync engine as a **high-water-mark protocol**:
- On connect: `GET /status` returns per-session `{minT, maxT, count}` (the device's current buffer extent).
- For each session where phone's `cachedMaxT < device.maxT`, fetch from `cachedMaxT + 1` forward. Inserts keyed `(bridge, session, t)`, idempotent upsert.
- **Resumable:** chunk requests by time range (`GET /samples?from=&to=`) so an interrupted BLE transfer resumes at the last stored `t`. Track per-(bridge,session) high-water mark in `SyncState`.
- **Reconcile is upsert-only** so a cook the device has purged still exists on the phone.

### E.5 Buffer rollover / genuine data loss — represent it honestly
This is a house-rule case ("never present stale data as current"; extend to "never hide a gap"):
- If, on connect, `device.minT > cachedMaxT + 1`, there is an **unrecoverable gap** — the device rolled its buffer past what the phone has. Do not paper over it.
- Store an explicit `Gap` record `(bridge, fromT, toT, reason: buffer_rollover)`. Render it on the chart as a visibly broken series with a hatched band and, in the stats table, as "Gaps in recording: 1 (buffer rolled over — 42 min lost)." The existing gap-detection already excludes gap time from "time in band"; extend it to distinguish *connectivity* gaps (recoverable later) from *rollover* gaps (permanent).
- Mitigate proactively: sync aggressively when connected; surface device storage on `/device` and raise the app-tier advisory when storage is "nearly full" (maps to one of the nine device rules).

### E.6 BLE-only full history (fixing the 2-hour limit)
Today BLE can only preview 2 hours. Decide:
- **Feasibility:** BLE notifications with a negotiated MTU (request 512 on Android via `requestMtu(512)`; useful payload ~244–495 bytes/packet per Punch Through's sizing guidance) and Write-Without-Response / notify pipelining can realistically reach tens of KB/s (Silicon Labs cites theoretical notify rates near 780 kbps at 251-byte PDU; real-world is lower but ample). A 15-hour cook at 30 s cadence × 4 probes ≈ 7,200 samples; at ~6 bytes/sample packed ≈ 43 KB — **seconds to a couple of minutes** over BLE. Full history over BLE is therefore **feasible** with a chunked, resumable, packed binary protocol. Recommendation: **build it** and drop the 2-hour limit.
  - Implementation: dedicated GATT "history" characteristic; app sends `{sessionId, fromT, toT}`; device streams length-prefixed, delta-packed, optionally deflate/RLE-compressed chunks via notifications; app ACKs every N chunks (windowed) and resumes from the last acked `t` on disconnect. Use `flutter_blue_plus` `splitWrite` for outbound control payloads; request max MTU first; fall back to smaller chunks if negotiation fails (iOS/macOS negotiate automatically ~135–255).
- **If firmware can't do it near-term:** keep the honest copy path — a card: "Full history needs Wi-Fi. Over Bluetooth you can see the last 2 hours. Switch to Wi-Fi to sync everything." (Copy over error — a house rule.) Treat this as the fallback, not the plan.

### E.7 Reconciling a session seen over two transports
Because exactly one transport is ever active, true simultaneous double-write is avoided — but a session can be seen over BLE now and Wi-Fi later. Key everything on **device-authoritative IDs** `(bridgeId, sessionId, t)`; never mint phone-side session IDs. Clock-skew handling: the device `t` is authoritative for ordering *within* a bridge; store it verbatim and also record `receivedAtPhoneClock`. If the ESP32 RTC is unset/epoch-zero, detect it (implausible timestamps) and offer a one-tap "set device clock from phone" (a settings write) so future data is wall-clock correct; never silently rewrite historical device timestamps — annotate them as "device clock was unset."

---

## F. Settings redesign — "controls everything"

Complete tree under `/device/settings/:section`. Each row notes **which transports can write it** and **what the UI does when the active transport can't**. Restyle all of it into the design system (kills the biggest visual inconsistency). **Fix the shared-transport bug:** the settings tree currently builds its *own* HTTP transport, so on a BLE-only setup saves silently no-op — **every settings write must go through the shared connection/supervisor and verify by behaviour (read-back), not by return value** (a house rule the settings tree currently violates). Also stop rendering constructor defaults as if read from the device — show "—" until a real read-back arrives.

| Section | Rows | BLE? | SoftAP? | Station? | If current transport can't write |
|---|---|---|---|---|---|
| **Identity** | device name, mDNS name | ✅ | ✅ | ✅ | n/a |
| **Probes** | per-jack name, role, target, pull offset, doneness, calibration offset | ⚠️ names/roles/targets NOT over BLE today — **extend firmware GATT to allow it** | ✅ | ✅ | Disable row w/ reason: "Connect over Wi-Fi to rename probes" (until GATT extended) |
| **Alarms** | both tiers' rule editor (§G) | ⚠️ device rules yes; some config Wi-Fi-only | ✅ | ✅ | Row disabled-with-reason |
| **Display & units** | °F/°C, app theme (dark/daylight §H), **device OLED** brightness/contrast/rotation/what-to-show | OLED needs device write | ✅ | ✅ | Disabled-with-reason on BLE if unsupported |
| **LED** | behaviour (off/status/alarm-only), brightness | ✅ | ✅ | ✅ | — |
| **Power & sleep** | auto-sleep timeout, **power off now** (mirrors the 1 button), restart | ✅ | ✅ | ✅ | — |
| **Network** | mode switch (§E.3), station SSID/PSK, SoftAP SSID/PSK, revert timer | ✅ (carries the switch safely) | ✅ | ✅ | — |
| **MQTT / Home Assistant** | broker, topic, HA discovery on/off | ❌ BLE | ✅ | ✅ | Disabled: "MQTT setup needs Wi-Fi" |
| **Firmware** | current version, check/update, **file picker for local .bin** (missing today) | ❌ OTA not over BLE | ✅ | ✅ | Disabled: "Update over Wi-Fi" |
| **Data & export** | retention, CSV export + **share sheet** (share_plus, currently unused), wipe device buffer (cost sheet) | export from cache always ✅ | ✅ | ✅ | Export is cache-only, always available |
| **Diagnostics** | transport state, last error (named), signal, buffer extent, sync high-water marks, RTC status | ✅ | ✅ | ✅ | Replace today's stub with real read-outs |

**OPEN DECISION — how much transport detail to show:** recommendation: a simple health chip everywhere + a Diagnostics page for power users. Do not surface lane-by-lane race internals in normal UI.

---

## G. Alarms & notifications redesign

### G.1 Two tiers, still visibly separate (keep)
Keep the deliberate separation: **Device tier** = the nine rules running on the ESP32 (base-station alarm, target reached, pit out of band, pit crashing, probe unplugged, base station lost, battery low, storage nearly full, unexpected restart) — these keep working with the phone off and the app **mirrors** their state, never re-decides. **App tier** = advisory only (ETA-soon, stall started/ended, lid open, bridge unreachable, phone offline). Keep the notification policy as one pure function over device alarms, on-screen keys, wall clock, app findings, quiet hours and the monitoring flag. This mirrors FireBoard's "Failsafe monitor" concept (which *"notify[s] you if your FireBoard has lost power or stopped pushing temperature data"*) but done device-side so it survives the phone.

### G.2 Editable rule system (the biggest missing feature)
Today no rule is editable and the alarms page has no entry point (URL-only). Build a rule editor at `/device/alarms`, modelled on **MEATER's Add Alert taxonomy** (grouped: AMBIENT — falls below / rises above; INTERNAL — falls below / rises above; TIME — an amount has elapsed / time before the cook ends) plus this app's existing device rules. Also mirror FireBoard's per-channel high/low bounds and TempPro's **pre-alarm** (*"notify you when the temp is 5/10/15 degrees away from target temp"*) — a beloved, cheap feature.
- UI: per probe (and per cook), a list of rules with type, threshold, enable toggle, and a device/app tier badge. Add-rule sheet uses the MEATER taxonomy.
- **Data:** the `AlarmRules` table (§D.2).

### G.3 Pushing rule edits to the ESP32 and confirming
- Device-tier edits are written over the active transport, then **verified by read-back** (house rule: verify by behaviour). Store `pushedToDevice` + `lastConfirmedAt`; show "Saved to bridge" only after the read-back matches. If the transport can't push (e.g. BLE lacks the characteristic), disable the row with a reason — don't let it appear to save then write nothing (the exact bug that exists today).
- App-tier rules are local only and always editable.

### G.4 Quiet hours, escalation, and the 3 a.m. wake — Android delivery mechanics
Keep quiet hours 22:00–06:00 silencing warning/info but **never critical**. Concrete Android plumbing to actually wake someone:
- **Four channels** (keep): critical (sound + heads-up + **full-screen intent**), warning, info, ongoing (silent, non-dismissible).
- **Full-screen intent:** per Google Play Console Help (answer 13392821), *"Starting January 22, 2025, for apps targeting Android 14+, only apps that have calling or alarm functionalities will have this permission enabled by default. Otherwise, you must get user permission."* **This app qualifies as an alarm app** — declare `USE_FULL_SCREEN_INTENT`, complete the Play Console declaration (required since May 31, 2024), and at runtime check `NotificationManager.canUseFullScreenIntent()` and route to `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` if missing. This is the mechanism that lights the screen at 3 a.m.
- **Exact alarms:** for time-based rules (elapsed / time-before-end) hold `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` so haptics-only alarms fire on time even in Doze.
- **Battery optimisation exemption:** prompt for it during onboarding, explaining why ("so we can wake you at 3 a.m.").
- **Background monitoring** runs the same reconciliation loop with no UI and maintains the ongoing notification (a live readout built from the same `buildDashboard()` projection).
- **Foreground service type:** run the monitor as a **`connectedDevice`** foreground service on Android 14/15 (Android 15 *"silently broke background BLE scanning"* without `foregroundServiceType="connectedDevice"` + `FOREGROUND_SERVICE_CONNECTED_DEVICE`). **Do NOT use `dataSync`:** per Android's Android 15 behavior-changes doc, *"the system permits dataSync and mediaProcessing foreground services to run for a total of 6 hours in a 24-hour period, after which the system calls … Service.onTimeout()"* — fatal for a 14-hour cook. `connectedDevice` has no such cap. Consider **CompanionDeviceManager** association (the path Google is steering IoT apps toward; it *"bypasses some background restrictions because the OS itself manages the device association"* and lets you scan without `ACCESS_FINE_LOCATION`) with `REQUEST_COMPANION_RUN_IN_BACKGROUND` / `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND`.
- **BLE permissions (Android 12+):** `BLUETOOTH_SCAN` (with `neverForLocation` if you don't derive location) + `BLUETOOTH_CONNECT`; request at runtime; don't gate the UX on location.
- **Live Updates (Android 16):** upgrade the ongoing cook notification to a `Notification.ProgressStyle` progress-centric / promoted Live Update showing the phase (Approaching → Pull → Rest → Ready) as segmented progress with pit/food temps — the 2026 "AAA" glanceable surface. Just Eat Takeaway reported *"a significant 22% increase in post-order screen views"* and that 42% of users kept the progress notification active through the entire flow. Fall back to a standard ongoing notification below Android 16 (full Live Updates system handling landed after the June 10 2025 Android 16 stable via QPR).

### G.5 Escalation
For critical rules, escalate: silent → heads-up → full-screen intent + repeat sound if unacknowledged after N minutes. Acknowledge from the notification (action button) so the user can silence without unlocking fully.

---

## H. Visual & interaction design direction

### H.1 Keep verbatim (already AAA-grade; competitors lack them)
- **Series-hue vs status-hue separation.** Keep the hard rule: a series hue (per-probe) only ever appears as a *mark* (chart stroke, gauge arc, ≤12 dp dot, card left rule), never fills a large shape or carries a word; a status hue only ever appears as *chrome* (12–16% fill, 22–35% border, always with icon AND word), and banner text is always high-contrast ink. This is why "target reached" flips a pill to "Reached" rather than turning green — because green means transport health. Keep it; it prevents the colour-soup that makes competitor dashboards ambiguous (FireBoard's colour-coded alarm chips, red/blue keys, are legible but overloaded).
- **Never scale a temperature.** Hero number fixed at 96 pt with a width axis + tabular figures; the gauge is the flexible child. The single most important "glanceable across the room at 3 a.m." rule. Keep it.
- **The freshness ladder** (≤45 s live / ≤90 s aging / ≤600 s stale-with-veil / >600 s frozen), with derived values *removed* not greyed when stale. The honesty spine and a real differentiator versus apps that show a last-known number as if it were live. Keep verbatim.
- Copy discipline (no jargon; failures name their cause; a control that can't work is absent or disabled-with-reason), the ten house rules, five motion tokens, no `Duration` literals in `ui/`, four radii, 4 dp spacing scale, fourteen type styles. **Recommendation: preserve the copy discipline verbatim** — it is a moat, not overhead.

### H.2 What must change to feel like a 2026 flagship
- **Hero temperature treatment:** add subtle depth — a large, high-contrast readout with a thin series-hue underline/arc, on a near-black surface, tuned for OLED and sunlight. Keep the pulse dot as the liveness tell.
- **Gauges:** keep `TargetGauge` sweep/band modes; modernise with smoother arc easing (within the motion tokens) and a clearer pull-early tick. Consider phase segmentation on the arc (approaching/pull/rest) as marks, not colour — echoing MEATER's three colour badges (Internal / Target / Ambient) and huge central radial gauge, but keeping this app's hue discipline.
- **Chart styling:** converge live + history into one widget (§C.2). **Charting library OPEN DECISION:** keep the hand-rolled `fl_chart` + custom viewport (pan/pinch/crosshair) *or* move to a `CustomPainter`-based renderer for tens of thousands of points at 120 Hz. Recommendation: **keep fl_chart for now but push heavy series through the existing LTTB decimation + min/max envelope**; if 120 Hz gesture smoothness on 15-hour datasets is inadequate, migrate the plotting layer to a bespoke `CustomPainter`. (Syncfusion is capable, has built-in zoom/pan/trackball and a free community license under $1M revenue / ≤5 devs, but adds a dependency and its own gesture model; `graphic`/`cristalyse` are grammar-of-graphics options, less battle-tested for live streaming.) Decide via a profiling spike on a real 15-hour dataset.
- **Motion & haptics:** disciplined haptics on phase transitions (pull-now, ready) and on crossing a target — a light impact for advisory, a distinct pattern for critical. Respect reduced-motion.
- **Live Updates / widgets / Wear:** Android 16 Live Update for the cook; a home-screen **Glance** widget showing pit + food temps and phase; Wear OS tile/complication showing the same glanceable trio. Always-on-display friendliness via the ongoing notification.
- **Accessibility:** TalkBack labels on every probe row and gauge (announce temp + freshness + phase); large-text support (the never-scale rule must degrade gracefully — allow the hero to grow, reflow the gauge); **colour-blind-safe multi-series** (series hues distinguishable by luminance + a shape/label token, not hue alone — pair each series with a glyph in the legend); reduced-motion path.

### H.3 Light / daylight mode — OPEN DECISION
Today is deliberately dark-only, carried as a ThemeExtension so a daylight profile "can lift the ink ramp and kill glows." Outdoor sunlight legibility is a real 14-hour-cook need. Recommendation: **build the daylight profile** (high-contrast, no glows, boosted ink ramp) as a *third* option (Dark / Daylight / Auto-by-ambient-light), reusing the existing token architecture — it was designed for exactly this. Keep dark as default.

---

## I. Migration & sequencing plan for the codebase

### I.0 Delete outright (from the gap list)
- Dead pre-shell code that still compiles and is partly routed — remove and delete its routes.
- The **two competing implementations of the same destructive verbs** — pick the one that goes through the shared connection; delete the other.
- The settings tree's **private HTTP transport** — delete; route all writes through the shared supervisor.
- `/alerts` as a primary destination — remove the branch; relocate its verdict to onboarding + banners, its test button to `/device/alarms`.
- Legacy redirects that no longer point anywhere real.
- Device-settings screens that render **constructor defaults as if read from the device** — delete that behaviour; show "—" until a real read-back arrives (absent ≠ zero).

### I.1 Phased build order

**Phase 0 — De-risk & unblock (no user-visible redesign yet)**
- Fix the shared-transport bug so settings writes actually write and verify by read-back.
- Wire the dead controls: Cook action row (Mark/Test/Export callbacks), probe-row chevrons, cook-rename route, CSV share sheet, OTA file picker.
- Add `SyncState` high-water-mark tracking; formalise §E.4 backfill.
- Golden impact: minimal; mostly repository/integration tests. Add "settings write → read-back matches" tests.

**Phase 1 — Data model & IA (the foundation)**
- Drift v1→v2 migration (§D.2), Option A (session-agnostic samples). Generate step-by-step migration + new golden schema files.
- New route tree (§B.2): split `/live` vs `/cooks`, fold `/alerts`, rename `/bridge`→`/device`.
- Domain: extend `buildDashboard()` inputs for cook-as-annotation; keep it a pure projection.
- Golden impact: **high** — most screen goldens change. Strategy in §I.2.
- **Riverpod decision point:** if migrating state (J8), do it here as the shell is reshaped.

**Phase 2 — Cook system & retroactive start (§D)**
- Cook create/rename/backdate/retarget/split/merge; anchor detection; scheduled (future-start) cooks; custom cooks; harden food-safety gate with the intact-cut flag and dual USDA/enthusiast modes; "Repeat this cook".
- Guided four-phase progression on `TargetGauge` with ETA guardrails intact.

**Phase 3 — Alarms & notifications (§G)**
- `AlarmRules` editor (MEATER taxonomy + pre-alarm offset), push+confirm, `/device/alarms` with a real entry point.
- Android delivery hardening: full-screen-intent qualification, exact alarms, `connectedDevice` FGS (avoid `dataSync` cap), CompanionDeviceManager association, battery-exemption prompt, BLE-12 permissions.
- Android 16 Live Update progress notification; ongoing notification from the shared projection.

**Phase 4 — Connectivity depth (§E)**
- In-app mode switching with rollback timer + BLE escape hatch; SoftAP `WifiNetworkSpecifier` + `bindProcessToNetwork` + "no internet, stay connected" coaching.
- BLE full-history chunked/resumable transfer (drop the 2-hour limit) — or ship the honest-copy fallback if firmware slips.
- Rollover-gap records + honest gap rendering.

**Phase 5 — Settings, polish, AAA (§F, §H)**
- Full settings tree in the design system; diagnostics real read-outs; device OLED/LED control.
- Daylight theme profile; haptics; Glance widget; Wear tile; accessibility pass (TalkBack, colour-blind-safe series, reduced motion).

### I.2 Test / golden strategy given ~75 test files
- **Preserve the layering tests** (domain = zero Flutter imports; ui/ = stateless over plain values; features/ composes; data/ owns transports/cache/repos). The redesign must not violate these; they are your safety net.
- **Golden churn is the biggest tax.** Do goldens **last within each phase**, and regenerate in a single reviewed commit per phase so diffs are auditable. Introduce the new tokens/daylight profile before regenerating so you don't regenerate twice.
- **Keep the UX Lab web target** — iterate the new `/live`, gauges and guided progression hardware-free before touching device code.
- Add **new domain tests** for: cook backdating/split/merge (pure metadata invariants), the food-safety gate (intact vs non-intact, each protein floor), rollover-gap detection, and the high-water-mark backfill (idempotent upsert, resume-from-last-t).
- Add **integration tests** for mode-switch rollback (simulate the link dropping) and settings write→read-back.

---

## J. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| J1 | **Android background unreliability** — Doze/OEM killers drop the monitor; the 3 a.m. alarm never fires | High | Critical (safety + trust) | `connectedDevice` FGS (not `dataSync`, capped at 6 h/24 h); CompanionDeviceManager association; battery-exemption prompt; **rely on device-tier alarms as the true safety net** (they run on the ESP32 regardless) and market that honestly. Test on Samsung/Xiaomi/OnePlus specifically. |
| J2 | **BLE throughput for full history** underdelivers on old phones / lossy links | Medium | Medium | Chunked, resumable, packed/compressed protocol with windowed ACKs; keep the honest 2-hour-preview copy as a graceful fallback; profile on a real 15 h dataset before dropping the limit. |
| J3 | **Food-safety liability** in preset data & predictive done-times | Medium | High (legal) | Hard-enforced USDA FSIS floors for poultry (165 °F) / pork (145 °F + 3-min rest) / fish (145 °F) / ground (160 °F); intact-cut flag forcing 160 °F on tenderized/injected beef; dual "USDA-compliant" vs labelled "enthusiast, intact only" modes; persistent raw-meat safety strip (as MEATER shows); never present a predicted done-time without the ETA guardrails and an "estimate" label; verify poultry 165 °F by sensor, never by carryover (USDA: you *"cannot rely on carryover to bring an under-cooked bird up to 165 °F"*). Store presets as tunable data; cite USDA FSIS in-app. |
| J4 | **Settings-tree scope creep** ("controls everything" is unbounded) | High | Medium | Ship the §F table as frozen v1 scope; anything not in it is post-v1. Every row must go through the shared transport and verify by read-back or it doesn't ship. |
| J5 | **Golden-suite rewrite cost** stalls the redesign | High | Medium | Phase goldens last; one regeneration commit per phase; land tokens/daylight before regenerating; lean on the UX Lab + layering tests for confidence without goldens mid-flight. |
| J6 | **SoftAP "no internet" UX** confuses users / Android abandons the network | Medium | Medium | `WifiNetworkSpecifier` + `bindProcessToNetwork`; pre-dialog coaching copy; BLE warm standby so a failed Wi-Fi join never leaves the user disconnected. |
| J7 | **Mode-switch bricks connectivity** (bad creds over a link the switch drops) | Medium | High | Rollback timer on the device (auto-revert after 120 s); BLE escape hatch carries the revert/commit; stateful wizard with a visible countdown. |
| J8 | **Riverpod migration churn** — ProviderScope exists but unused; ChangeNotifier is the de-facto container | Medium | Low/Medium | **OPEN DECISION:** migrate the live session to a Riverpod `Notifier`/`StreamNotifier` OR keep ChangeNotifier and remove the unused ProviderScope. Note Riverpod 3.0 (Sept 2025) moved `ChangeNotifierProvider`/`StateNotifierProvider`/`StateProvider` to `package:flutter_riverpod/legacy.dart`, signalling `NotifierProvider`/`StreamNotifier` as the go-forward — but Riverpod itself calls 3.0 *"a transition version"* with a 4.0 expected *"relatively soon,"* so don't over-invest. Recommendation: migrate incrementally to `StreamNotifier` for the live stream (better testability, compile-time safety, no BuildContext) in Phase 1+, not a big-bang rewrite. |

### J.9 Summary of OPEN DECISIONS to route to the codebase owner
1. Samples session-agnostic (recommended) vs keep `session` FK (§D.2).
2. Attempt Combustion-style virtual core? (recommend no for v1) (§D.5).
3. Charting: keep fl_chart+custom vs migrate to CustomPainter/Syncfusion (decide via profiling) (§H.2).
4. Daylight theme now vs later (recommend now — architecture already supports) (§H.3).
5. How much transport detail to expose (recommend health chip + Diagnostics page) (§F).
6. Riverpod migration scope (recommend incremental StreamNotifier for live) (J8).
7. BLE full history now vs honest-copy fallback (recommend build it, fallback ready) (§E.6).
8. Converge live + history chart into one widget? (recommend yes) (§C.2).

---

### Appendix: the one-line brief for each phase (paste into the LLM session)
- **P0:** "Fix the settings shared-transport bug (write+read-back verify); wire all dead controls; add SyncState high-water marks."
- **P1:** "Drift v1→v2 (session-agnostic samples + Cooks/ProbeRoles/AlarmRules tables); new route tree (/live, /cooks, /device); keep buildDashboard pure."
- **P2:** "Cook-as-annotation: create/backdate/retarget/split/merge/repeat; four-phase guided progression on TargetGauge; harden food-safety gate with intact-cut flag + USDA floors."
- **P3:** "Editable alarm rules (MEATER taxonomy + pre-alarm), push+confirm; connectedDevice FGS, full-screen-intent as an alarm app, exact alarms, CDM association, Android 16 Live Update."
- **P4:** "In-app mode switch with device rollback timer + BLE escape hatch; SoftAP WifiNetworkSpecifier+bindProcessToNetwork; BLE full-history chunked resumable transfer; honest rollover-gap rendering."
- **P5:** "Settings tree into the design system; real diagnostics; daylight theme; haptics; Glance widget; Wear tile; accessibility pass."