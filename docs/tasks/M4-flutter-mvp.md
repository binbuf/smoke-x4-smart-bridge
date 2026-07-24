# M4 — Flutter MVP

**The milestone where the project becomes a thing you cook with.** Everything under
`app/lib/data/` and `app/lib/domain/` has been true and tested for three milestones without a
single screen to prove it: the transport contract runs against three implementations, LTTB and ETA
and the stall detector are table-tested, the drift cache holds a full copy of every cook, and the
sim serves an 18-hour brisket over the real API. M4 spends all of it. Nothing here invents a wire
format, a decimation algorithm, or a second source of truth — **A9–A12 are projections of work that
already exists**, and the two places that is not true (there is no production `DiscoverySource`, and
nothing remembers the bridge's address between launches) are M3 bench findings closed here as A7.4
and A7.5.

[§12.6 rule 1](../design/12-task-planning-notes.md) — _"no A-track UI before `tools/sim`"_ — is
satisfied and retired: the sim has existed since M0, and A8's wizard was its one deliberate early
exception. From here, screens are the work.

**Exit gate** ([M4 outline](M2-M6-outline.md), [11 §11.1](../design/11-roadmap-and-risks.md)) —
**this is the MVP.** Start to finish on real hardware:

- install the APK, onboard over BLE, choose a mode
- watch a live cook, scroll 15 hours of history
- export a CSV

28 tasks — **26 `board: no`, 2 `board: yes`**. The two board rows (A15.5 and A14.4b) are **one
sitting** ([§12.6 rule 7](../design/12-task-planning-notes.md)) at the end, and A14.4b is the M3
rider that was always going to land here: the binder-alone / shim-alone matrix
([hardware-verified](../hardware-verified.md)) needs app screens to have anything to observe. The
lanes inside M4 are A10 (chart) and A11 (sessions) behind A9's shell, A12 beside them, and A15 last
because pinning a screen that is still moving is how goldens get a reputation for churn.

> **Status 2026-07-23 — all 26 `board: no` tasks are done.** App suite 448/448 (from M3's 230),
> firmware host suite still 21/21 and untouched, `protocol/gen` unchanged, generated code fresh. The
> two `board: yes` rows (A15.5, A14.4b) are the only remainder and are the single sitting described
> above; they are owed, not done, and nothing below claims otherwise.
>
> Decisions this milestone was asked to make, and made:
>
> | Question | Answer | Recorded in |
> | --- | --- | --- |
> | The probe palette (§8.7 fixes the constraints, not the values) | **P1 ember `#EB6834`/`#D95926`, P2 violet `#4A3AA7`/`#9085E9`, P3 green `#008300`, P4 blue `#2A78D6`/`#3987E5`**, each with its own stroke pattern. All 24 orderings were run through the validator; this one maximises the minimum adjacent separation in both modes (CVD ΔE 26.0, normal 27.0, every slot ≥ 3:1 on our own surfaces) | `app/lib/app/palette.dart`, with the measurements beside the values |
> | Does colour follow the probe or its role? | **The probe.** Re-roling must not repaint the history behind it, and the OLED — the same data with one bit of ink — can only identify a probe by its number. Role carries its weight through stroke weight and overlays | `app/lib/app/palette.dart` |
> | Golden form: bitmaps or descriptions? | **Deterministic text.** Pixel goldens are not portable across platform or Flutter version, and the fix everyone applies is `skip:` — a skipped golden protects nothing. The snapshots pin every string, semantics label, disabled state, and each series' resolved colour and stroke | `app/test/golden/golden.dart` |
> | The §8.7 45 s gap threshold against bucketed data | **1.5× the series' own median cadence, floored at 45 s.** At 30 s it is exactly the documented value; at a 5-minute retention cadence it stops calling every interval a dropout. Fewer than three intervals is not a cadence and falls back to the floor | `app/lib/domain/analysis/chart_series.dart` |
> | Where does probe configuration come from? | **`GET /live`**, which §6.2 already carries — one call answers both "what is it reading" and "what is it called". No new transport method, so the A6.2 contract harness is untouched. BLE cannot know, and falls back to the device's own convention: jack 1 is the pit | `LiveState.probes`, `HttpTransport.live()` |
>
> Three deviations, stated rather than discovered:
>
> - **A15.4 spawns the sim; it does not fake it.** `tools/sim` is a root-workspace member and `app/`
>   is standalone, so `dart run sim` cannot resolve in CI's app-only job — the same constraint A8.3
>   hit in M3. The suite runs the real sim when the workspace is bootstrapped and **skips with a
>   stated reason** when it is not, rather than growing a second in-process fake of an API the sim
>   already implements. It also drops `TestWidgetsFlutterBinding`'s `HttpOverrides`, which otherwise
>   answers every request `400` without opening a socket.
> - **`path_provider` and `path` were added to `pubspec.yaml`.** Not §8.2 choices — §8.2 lists the
>   interesting ones — but what `drift` needs to point at a real file on Android. Resolved offline
>   from the existing pub cache; `app/pubspec.lock` moves with it.
> - **Two layout defects were found by the goldens, not by a phone**: the window-chip row overflowed
>   at 388 dp (now horizontally scrollable) and the header's status chips overflowed on their longer
>   copy (now `Flexible` with ellipsis). Both are exactly the class of bug A15 exists to catch, and
>   both were invisible to the widget tests because the offending rows were below the fold.

> **What M4 does not depend on.** V3a.1 measured free heap at ≈ 90.5 KB against a 150 KB target and
> the plan requires that conversation *before* M4
> ([hardware-verified](../hardware-verified.md)). It is opened and recorded there, and the answer
> for M4 specifically is _nothing here consumes device heap_ — M4 is app-side only, the firmware is
> not touched. The decision is owed before **M5**, and M6's 24 h soak is what should settle it. This
> paragraph exists so the deferral is a decision rather than an oversight.

---

## A7 — the two seams M3 left open

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** neither of these is new
> design; both are a production implementation behind a seam that already has a fake and a passing
> test. The uncertainty is entirely platform-shaped and lands in the same place R3/R7 always land —
> `nsd` wraps Android's `NsdManager`, whose resolve step is famously serialized and famously
> flaky on some OEM builds, and `shared_preferences` needs a binding that `flutter test` does not
> have by default. **Both therefore stay behind their seams**: the `nsd` calls sit in one adapter
> whose logic is tested against a fake service registry, and the preference store is an interface
> with an in-memory implementation for tests. The board proves them; the host suite proves
> everything around them.

A7.2 shipped `DiscoverySource`, the §5.5 TXT parser, and a fake — and never the `nsd`-backed
implementation, so the mDNS lane of the §8.4 race has been permanently empty. A7.1 shipped
`writeCache` as a typedef and every production call site passes `(_) async {}`, so a bridge
provisioned at 19:00 is a stranger at 19:05. Both were invisible while onboarding was the only
screen. The dashboard is where they bite.

### A7.4 data/transport: implement the nsd-backed DiscoverySource

- **blocked-by:** A7.2 · **verify:** H · **board:** no
- **design:** [08 §8.4](../design/08-flutter-app.md), [05 §5.5](../design/05-connectivity-and-provisioning.md)

The production half of A7.2's seam: `discover()` starts an `nsd` discovery for `_smokebridge._tcp`,
resolves each service, and maps the TXT map through the **existing** `bridgeFromTxt` — which is
already table-tested against the §5.5 record, so this task adds an adapter, not a parser. The
platform calls hide behind a narrow injected façade (start / stop / the discovery event stream),
exactly as `flutter_blue_plus` hides behind `BleGattClient`, so the logic runs in the host suite
against a fake registry. Discovery is **one lane of five**: it swallows its own errors, never
throws into the race, and a stop that fails is logged and forgotten rather than propagated.

**Done when:** the adapter's tests cover a resolve that succeeds, one that fails, a service with no
TXT record at all, a duplicate advertisement, and `dispose()` mid-discovery; the stream is
cancellable without leaking a native discovery; and `flutter test` touches no platform channel.

### A7.5 data/prefs: persist the winning base URL and the known bridge

- **blocked-by:** A7.1 · **verify:** H · **board:** no
- **design:** [08 §8.4, §8.5](../design/08-flutter-app.md)

`ConnectionManager.writeCache` has been a no-op at every production call site since A7.1, which
means the `cachedIp` lane — _"the common case: same bridge, same network, second launch — is one
50 ms request"_ — has never once been warm. Introduce a tiny `BridgePrefs` interface (last base
URL, last bridge id, last-seen timestamp, display units, theme mode) with a `shared_preferences`
implementation and an in-memory one for tests, hand it to the ConnectionManager as `writeCache`,
and read it back at launch as `cachedBaseUrl`. **The BLE lane deliberately does not write it**
(A6.5's comment already explains why: there is no address, and blanking the cache would break the
next launch's fastest lane) — that behaviour is now asserted rather than commented.

**Done when:** a launch → connect → relaunch sequence over the fake reads the cached URL first; a
BLE win leaves the cached URL untouched; a corrupt or absent preference degrades to "no cached
lane" instead of throwing; and the onboarding route's `writeCache` no longer discards its argument.

---

## A9 — Dashboard, probe tiles, session controls

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** the risk here is not
> technical, it is that **the dashboard is where four independent sources of truth meet** — the
> drift cache, the live WebSocket/notify stream, `GET /status`, and the app-tier analysis — and the
> obvious way to build it is a widget that subscribes to all four and reconciles them in `build()`.
> That is untestable and it is where "sometimes it shows the old temperature" comes from. So the
> reconciliation is a **pure function** of the four inputs into one immutable snapshot, tested
> without a widget tree, and the widgets render the snapshot and nothing else — the same shape A8.1
> gave the wizard, for the same reason.
>
> The second flag is smaller and specific: [08 §8.6](../design/08-flutter-app.md)'s mock shows a
> battery percentage in the header. `soc_pct` is `SOC_UNKNOWN` until F12 lands in M5
> ([ble-gatt §5.1.1](../../protocol/ble-gatt.md)), and `device_info.caps` b5 exists precisely to say
> so. The header must render the *absence* correctly from day one; a `0%` battery on an MVP
> screenshot is the kind of bug that gets filed against the hardware.

### A9.1 features/dashboard: implement the dashboard snapshot as a pure projection

- **blocked-by:** A4.4, A2.2, A2.3, A2.4 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [09 §9.3, §9.4](../design/09-alarms-and-insights.md)

One immutable `DashboardSnapshot` built by a pure function from `BridgeStatus`, the cached sample
history, the live `LiveState`, and the probe configuration: per-probe current value, rate of change,
ETA, stall flag, target, role, and the two "headline" slots (the pit and the primary food probe)
that [08 §8.6](../design/08-flutter-app.md)'s layout is built around. Every analysis call is an
existing A2 function; this task calls them, it does not re-derive them. **Detached is `null`, at
every layer, forever** — the projection has no code path that can produce a temperature of 0, and a
test asserts the whole snapshot for an all-detached input.

**Done when:** the projection is table-tested for no probes, all detached, one probe mid-gap, a
stalled food probe (ETA suppressed with the §9.4 reason, not a number), a target above pit
temperature, and a session with fewer than 30 minutes of history; and the headline-slot choice is
asserted for a cook with no `pit`-role probe at all.

### A9.2 features/dashboard: implement the probe tiles

- **blocked-by:** A9.1, A10.2 · **verify:** H · **board:** no
- **design:** [08 §8.6, §8.7](../design/08-flutter-app.md)

The two tile forms §8.6's mock draws: the headline tile (enormous value, target, trend arrow,
sparkline, °F/hr) and the compact tile (name, value, rate). **The two numbers that matter are
enormous** — you are reading this from four feet away, in a dark yard, possibly through a screen
door — which is why `SmokeTheme.headlineTemp` has existed at 88 pt since A1.2 and why this task
uses it rather than inventing a size. A detached probe renders `—` and the word `unplugged`; it
never renders a number, and it never disappears (a probe that vanishes from the grid reads as an
app bug, not as an unplugged jack).

**Done when:** widget tests cover attached / detached / no-target / target-reached / alarm-raised
for both tile forms, the detached tile contains no digit at all, and every tile carries a semantics
label that reads correctly out loud (`"Pit, 243 degrees, falling 2 per hour"`).

### A9.3 features/dashboard: implement the header strip

- **blocked-by:** A9.1, A7.5 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [05 §5.6](../design/05-connectivity-and-provisioning.md)

Session name, elapsed time, and the connection chip: which transport won, over what address, and —
when the winner is BLE — the honest degraded notice that A3.1's capability flags were built to
drive. Battery renders from `socPct`, and renders its own absence when battery reporting does not
exist yet (F12, M5) rather than showing `0%`. `base_lost` and `lastPacketSAgo` surface here too,
because a bridge that is reachable while the *base station* is not is a distinct failure the header
is the only place to say.

**Done when:** the strip is widget-tested for HTTP-connected, BLE-degraded, offline-from-cache, no
battery data, base-lost, and a session that has no clock (`startedUnixMs == null` renders elapsed
time, not an epoch date).

### A9.4 features/dashboard: implement the session controls

- **blocked-by:** A9.1, A3.3 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [06 §6.2](../design/06-device-api.md)

Start / stop cook, add mark, export — the three buttons on the bottom bar. Each dispatches a
`ControlCommand` through the transport and **nothing else**: no local optimistic session state, no
second copy of "is a cook running", because the device is the source of truth and a session the app
thinks is running while the bridge disagrees is exactly the class of bug D7 and §9.1 exist to
prevent. Stopping a cook asks first. A transport whose capabilities cannot control (there is no
such transport today, and there might be tomorrow) disables the buttons with a stated reason rather
than failing on tap.

**Done when:** each control is asserted to emit exactly one correctly-typed command against
`MockTransport`'s `controlLog`, the stop confirmation is required before the command is sent, a
`BridgeControlException` surfaces its typed meaning rather than a stack trace, and the mark sheet
offers §4's mark kinds by name.

### A9.5 app: implement the launch flow and the connection bootstrap

- **blocked-by:** A7.4, A7.5, A6.5 · **verify:** H · **board:** no
- **design:** [08 §8.4](../design/08-flutter-app.md), [05 §5.7](../design/05-connectivity-and-provisioning.md)

The composition root the placeholder home screen has been standing in for since A1.2: on launch,
read the cached bridge, race the ConnectionManager with the real discovery source and the real BLE
lane, and land on the dashboard — or on the onboarding wizard when no bridge has ever been
provisioned. A dropped connection re-races on A7.3's backoff ladder rather than showing an error
page. **Offline is a first-class outcome, not an error**: the cache serves every historical screen
with the bridge unplugged, which has been the acceptance test for the whole data layer since A4.4.

**Done when:** the launch state machine is table-tested for never-provisioned, cached-and-reachable,
cached-and-unreachable (offline-from-cache), BLE-only, and a mid-session drop that reconnects; and
no test needs a radio, a network, or a platform channel.

### A9.6 features/dashboard: assemble the dashboard screen

- **blocked-by:** A9.2, A9.3, A9.4, A9.5, A10.3 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md)

The screen itself: header, tile grid with the §8.6 emphasis (pit and the primary food probe get the
space, secondary probes collapse), the chart, the control bar — laid out so the two headline numbers
survive a small phone in portrait and a text-scale setting of 1.3. Providers are Riverpod, thin, and
hold no logic: they wire A9.1's projection to A9.5's connection and A10's chart, and that is all.

**Done when:** the screen renders from a seeded snapshot with no network, survives 320 dp width and
1.3× text scale without overflow, and a golden-shape smoke test covers no-probes and all-detached
before A15 pins the rest.

---

## A10 — Chart

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** the design note is explicit
> and it is the reason A10.4 exists as its own row — **`fl_chart` has no native zoom**; pan and
> pinch are a custom transform over `minX`/`maxX` that we own. Treating interaction as part of
> "render the chart" is how that estimate blows up, so it is separated here by instruction.
>
> A second flag the outline names as a decision rather than a risk: **probe colour is chosen at
> implementation time against the project's data-visualisation guidance, and the constraints are
> requirements** — colourblind-safe, legible in direct sunlight *and* in a dark theme, consistent
> across the app, the exports and the OLED's single bit of ink, with roles carrying semantic weight.
> That is A10.2, and it is placed **before** the renderer on purpose: a palette chosen after the
> chart exists is a palette chosen to match the chart.

### A10.1 domain/analysis: implement the chart series builder

- **blocked-by:** A2.6, A2.7, A4.2 · **verify:** H · **board:** no
- **design:** [08 §8.7](../design/08-flutter-app.md), [06 §6.2](../design/06-device-api.md)

Pure Dart, in `domain/analysis/` — **zero Flutter imports**, the hard rule CI greps for. From a list
of samples and a viewport it produces the render model: window slice, per-probe extraction with
detached points dropped (never zeroed), **run splitting at the §8.7 45-second gap threshold** using
A2.7's existing `findGaps`, LTTB decimation to ~2 points per pixel using A2.6's existing `lttb`, and
— for very wide ranges — a min/max envelope so an excursion is visible as a widening band even where
the mean is smooth. A 30-minute dropout must come out of this function as **two runs and a gap**,
not as one line pretending everything was fine.

**Done when:** the builder is table-tested for an empty series, a single point, all-detached, a
mid-gap series (asserting run boundaries land exactly at the gap), 15 h at 30 s cadence, 54 days of
data, and a decimation target smaller than the run count; and a property test asserts that
decimation never moves the series' first or last point and never invents a timestamp.

### A10.2 app/theme: choose, validate, and pin the probe palette

- **blocked-by:** A1.2 · **verify:** H · **board:** no
- **design:** [08 §8.7](../design/08-flutter-app.md), [07 §7.1](../design/07-display-and-controls.md)

The decision the outline defers to here, made with the project's data-visualisation guidance
open and its validator actually run rather than reasoned about. The constraint set is the
specification: colourblind-safe, legible in direct sunlight and in a dark theme, consistent across
app / exports / the OLED, roles carrying semantic weight. Two consequences fall straight out and
should be expected rather than discovered: **the OLED has no hue at all**, so identity cannot rest
on colour alone and a second, colour-free channel (per-probe stroke pattern) is required, not
optional; and **colour follows the probe, never its role** — a probe that is re-roled mid-cook must
not change colour, because the graph behind it did not.

**Done when:** the palette is validated in *both* modes against the app's own surfaces with the
recorded numbers written into the source next to the values, every slot is a documented hex rather
than an eyeballed one, the light and dark sets are selected separately (not an automatic flip), and
a test asserts that probe → colour and probe → stroke are stable under re-roling and under a probe
detaching.

### A10.3 features/chart: render the chart with its overlays

- **blocked-by:** A10.1, A10.2 · **verify:** H · **board:** no
- **design:** [08 §8.7](../design/08-flutter-app.md)

The `fl_chart` `LineChart` — with all the work already done before it ever sees the data. Runs
become separate `LineChartBarData` segments so gaps are gaps; the min/max envelope renders as a
faint band behind the mean; overlays are §8.7's list and no more: dashed horizontal lines at each
probe's target, vertical lines at marks, a shaded band for the pit's alarm min/max. Axis labels are
wall-clock when the session has a clock and elapsed time when it does not. Detached probes
contribute no points — **never a zero** — which by construction is what A10.1 already guarantees.

**Done when:** a mid-gap series is asserted to produce more than one bar segment with no spot inside
the gap, the envelope renders only when the builder produced one, the alarm band and target lines
appear and disappear with their configuration, and the whole chart renders with an empty series
without throwing.

### A10.4 features/chart: implement the viewport — chips, pan, zoom, jump-to-now

- **blocked-by:** A10.3 · **verify:** H · **board:** no
- **design:** [08 §8.7](../design/08-flutter-app.md)

The task §12.8 says to separate, kept separate. A pure `ChartViewport` value type owns `minX`/`maxX`
and every operation over them — the window chips (15 m / 1 h / 6 h / 15 h / All), pinch scaling
about a focal point, drag panning, double-tap reset, and clamping so no gesture can leave the
session's bounds or invert the window. **Live mode auto-scrolls until the user pans, and then
stops** and offers a _"jump to now"_ pill: the standard log-viewer behaviour, and the one people
expect. All of it is testable without a gesture, because none of it is a widget.

**Done when:** the transform is table-tested for zoom about a focal point (the focal timestamp stays
under the finger), zoom clamped at both ends, pan clamped at both ends, a chip selection while
panned, auto-follow suppression and its release, and a session shorter than the selected window.

### A10.5 features/chart: implement the crosshair readout and the capability notice

- **blocked-by:** A10.4 · **verify:** H · **board:** no
- **design:** [08 §8.7, §8.1](../design/08-flutter-app.md), [ble-gatt §5.8](../../protocol/ble-gatt.md)

Drag anywhere on the chart and read every probe's value at that instant — the one interaction that
turns a shape into a number. It reads the *nearest actual sample* and says how far away it is rather
than interpolating across a gap, because an invented reading in the middle of a 30-minute dropout is
worse than no reading. Alongside it, the notice A3.1 has been waiting three milestones to render:
on a transport whose `fullHistory` is false, the chart shows the 2-hour `history_preview` and says
_"connected over Bluetooth — full history needs Wi-Fi"_ instead of a stub or an error.

**Done when:** the readout is table-tested at a sample, between samples, inside a gap, and past both
ends; the value shown for a detached probe is `—`; and the capability notice is asserted to appear
for `BleTransport` and to be absent for `HttpTransport`, driven by the flag and not by a type check.

---

## A11 — Sessions

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** the sizes here are the ones
> that break things quietly. A 54-day retention window is ~155,000 sample rows
> ([08 §8.5](../design/08-flutter-app.md)); a sessions list that builds a sparkline per row by
> reading every sample of every session will be smooth on the sim's single 18-hour fixture and
> unusable on a real device after two months. **Row summaries come from an aggregate query, not from
> loading the samples** — and the 54-day shape is one of the golden cases in A15 precisely so the
> honest answer is visible rather than assumed. The A4.2 escape hatch (per-session BLOB chunks) is
> the fallback if profiling ever disagrees, and the DAO interface was written so that swap never
> reaches this epic.

### A11.1 domain/analysis: implement cook statistics

- **blocked-by:** A2.2, A2.4, A2.7 · **verify:** H · **board:** no
- **design:** [09 §9.4](../design/09-alarms-and-insights.md), [08 §8.6](../design/08-flutter-app.md)

§9.4's statistics list, as a pure function over a session's samples and marks: total duration, pit
mean and standard deviation, time in band, pit min/max, per-probe start / end / peak, stall
duration, lid-event count, average °F/hr per phase, and total samples with gap count. **This is what
makes cooks comparable, which is what makes the whole thing more than a thermometer with a screen.**
Every value that cannot honestly be computed comes back `null` — a session with no pit-role probe
has no pit σ, and saying so is the correct answer.

**Done when:** the statistics are table-tested against a seeded cook with a known answer, and
separately for a session with no probes, a session of one sample, a session that is entirely one
gap, and a session with no pit role; and `timeInBand` is asserted to exclude gap time rather than
counting a dropout as time in band.

### A11.2 features/sessions: implement the list

- **blocked-by:** A11.1, A4.2 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md)

One row per cook: name, date, duration, peak temperature, probe count, and a sparkline — read from
an **aggregate query** over the cache, never by materialising each session's samples (see the epic
flag). The list is cache-first like everything else, so it renders with the bridge unplugged, and a
cook the device has since purged still appears because the app owns a full copy of every cook it has
seen (A4.2's deliberate upsert-only reconcile).

**Done when:** the list renders from the cache with no transport at all, an empty cache renders an
honest empty state rather than a spinner, a 54-day cache is asserted not to read sample rows to
build the rows, and an in-progress session is distinguishable from a finished one at a glance.

### A11.3 features/sessions: implement the detail view

- **blocked-by:** A11.2, A10.4, A11.1 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [09 §9.4](../design/09-alarms-and-insights.md)

The dashboard chart without the live tiles, plus A11.1's statistics, plus the mark timeline. Marks
are rendered as what they are — a wrap, a lid open, a fuel add, an alarm — with their time and text,
and tapping one moves the chart's viewport to it. Renaming a session and pinning it are here because
this is where the user is when they decide a cook was worth keeping.

**Done when:** the detail view renders offline from the cache, the mark timeline is asserted for a
session with no marks and one with all eight kinds, tapping a mark is asserted to move the viewport,
and a rename dispatches exactly one `PATCH` and updates the cache.

### A11.4 features/sessions: implement CSV export

- **blocked-by:** A11.3 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [04 §4.2](../design/04-storage-and-history.md)

The exit gate's last clause. The CSV is **byte-compatible with the device's own
`format=csv`** — `t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi`, detached probes as *empty fields* —
because two spellings of the same export is how a support conversation becomes unanswerable. Built
from the cache so it works offline, streamed rather than concatenated so a 54-day export does not
allocate itself into an OOM, and written through a platform seam so `flutter test` covers the
content without touching a file system.

**Done when:** the generated CSV is asserted byte-for-byte against the device's `format=csv` output
for the same fixture, a detached probe is an empty field and never `0`, a session with no clock
emits an empty `iso8601` column rather than an epoch date, and the export path is exercised end to
end against a fake file sink.

---

## A12 — Settings

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** settings is where a UI
> quietly claims authority it does not have, and this project has two specific traps already
> written down. **The alarm tiers are not interchangeable**
> ([09 §9.1, §9.5–9.6](../design/09-alarms-and-insights.md)): the device tier is authoritative,
> latched, and runs with no phone in existence; the app tier is advisory. A settings screen that
> lists them together implies the phone can be switched off, and it cannot. **And the bearer token
> has no transport that can set it** — P3.2 decided that in M3 and the obligation landed here
> verbatim: _"M4's settings UI hides the toggle"_ ([ble-gatt §5.6.6](../../protocol/ble-gatt.md)).
> Showing a control that cannot work is worse than showing nothing.

### A12.1 features/settings: implement the settings home and the probe editor

- **blocked-by:** A9.5 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [06 §6.2](../design/06-device-api.md)

The settings shell — probes, alarms, network, device, advanced, firmware, about — and the first
page. Probe name, role, and target, where **roles drive which tile is large and which rules apply**,
so this screen is the one that decides what the dashboard emphasises. Writes go through
`transport.configure()`; a transport that cannot configure probes says so with A6's typed condition
rather than silently dropping the write (`BleTransport` is exactly that transport, today).

**Done when:** editing a role is asserted to change A9.1's headline-slot choice, a target below
absolute zero or above the probe's range is refused in the form rather than on the wire, the
unsupported-transport path renders its typed reason, and a `configure()` failure leaves the form
populated rather than clearing it.

### A12.2 features/settings: implement the alarms screen

- **blocked-by:** A12.1 · **verify:** H · **board:** no
- **design:** [09 §9.1, §9.2, §9.3, §9.5](../design/09-alarms-and-insights.md)

The two tiers, visibly separate, with the difference stated in the UI and not just in this document:
device rules are edited and pushed to `POST /config/alarms` and **keep working with the phone
switched off**; app-tier rules are advisory and say so. The alarm log mirrors and acknowledges the
device's state — an alarm that fired at 03:40 while the phone was face-down is still latched and
unacknowledged at 07:00, and this screen is where the app says so. Acknowledging silences; it does
not resolve. Quiet hours and the notification channels are configured here but **are not wired to a
foreground service** — that is A13, in M5, and the screen must not imply otherwise.

**Done when:** the two tiers are asserted to render as distinct sections with distinct copy, an
unacked alarm raised before the app connected is shown as still latched, acknowledging emits exactly
one `ack_alarm` and flips the state to acked-not-cleared, and no control on this screen claims a
capability M5 has not built yet.

### A12.3 features/settings: implement network settings and the manual-address escape hatch

- **blocked-by:** A12.1, A7.5 · **verify:** H · **board:** no
- **design:** [05 §5.4, §5.8](../design/05-connectivity-and-provisioning.md), [08 §8.4](../design/08-flutter-app.md)

Current mode and status, the AP/STA switch with the same honest battery-versus-range copy A8 uses,
credentials, and — the promise §5.8 makes and §8.4 repeats — **manual IP entry, always available,
jumping the queue.** That escape hatch is the one path that works when discovery, mDNS, the AP
default and BLE have all failed, and A7.1 built `enterManual` to pre-empt a race in flight
specifically so this screen could exist. Switching mode re-uses the deferred-apply contract the
device already implements; the app does not invent a second handoff.

**Done when:** a manual address is asserted to pre-empt an in-flight race and to be persisted
through A7.5, a mode switch to AP surfaces the returned PSK (the user needs it to join), a mode
switch that leaves the phone unable to reach the bridge lands on the recovery copy rather than a
spinner, and a malformed address is refused in the field.

### A12.4 features/settings: implement device, advanced, and about

- **blocked-by:** A12.1 · **verify:** H · **board:** no
- **design:** [08 §8.6](../design/08-flutter-app.md), [06 §6.2](../design/06-device-api.md), [02 §2.7](../design/02-smoke-x-protocol.md)

Device (units, display timeout, LED, retention), Advanced (LoRa parameters, the raw packet view from
`/debug/packets`, the novelty log from `/debug/novelty`, and the in-app log ring), and About
(versions, licences — **D9's MIT attribution for the reference parser is a legal obligation, not a
nicety**). Units default to °F (D14) and the setting travels to the device, because the *device*
renders temperatures on its own OLED and the two must agree. Battery calibration is present but
disabled with its reason until F12 (M5) exists.

**Done when:** the raw packet and novelty views render the sim's fixtures verbatim including an
empty one, the log ring exports without a cable, units round-trip through `configure()` and back,
about lists the MIT attribution, and every control that depends on an M5/M6 component is disabled
with a stated reason rather than absent-without-explanation.

### A12.5 features/settings: implement the firmware screen and the OTA upload

- **blocked-by:** A12.4 · **verify:** H · **board:** no
- **design:** [06 §6.2](../design/06-device-api.md), [03 §3.7](../design/03-firmware-architecture.md)

Current version, and an OTA upload that streams a `.bin` to `POST /api/v1/ota` with progress from
the WebSocket's `ota` frames. **The `409` is a feature and the UI must say so**: an OTA is refused
while a session is active unless forced, because nobody should discover a bad flash 14 hours into a
brisket — so the app explains the refusal and offers the force path deliberately rather than
retrying it automatically. A transport whose `ota` capability is false (BLE, always) does not show
an upload button at all.

**Done when:** the upload is driven against the sim including the `409 session_active` path, the
force path is a separate deliberate action, progress renders from real `ota` frames and completes on
`phase: done`, and the screen renders correctly on a transport that cannot do OTA.

---

## A15 — Golden tests and the sim run

> **Uncertainty flag ([§12.8](../design/12-task-planning-notes.md)):** goldens are the tests most
> likely to be disabled six weeks after they are written, and there are two well-known reasons.
> **One:** pixel goldens are not portable — the same widget rasterises differently across platforms
> and Flutter versions, so a PNG rendered on the author's Windows box red-lights on CI's Ubuntu
> runner, and the fix everyone reaches for is `skip:`. **Two:** goldens pinned while the screen is
> still moving churn until nobody reads the diff. Both are handled by placement and by form: A15 is
> last, and the snapshots are **deterministic text** describing what the screen shows — every
> visible string, every probe's resolved colour and stroke, the chart's run and gap structure —
> rather than a bitmap. A one-pixel rendering difference must not fail these; a probe silently
> turning into `0 °F` must.
>
> The outline names the shapes, and they are not negotiable: **no probes, all detached, mid-gap,
> alarm active, 15 h of data, 54 days of data, both themes.**

### A15.1 test/golden: build the snapshot harness

- **blocked-by:** A9.6 · **verify:** H · **board:** no
- **design:** [08 §8.9](../design/08-flutter-app.md), [10 §10.5](../design/10-repo-tooling-and-testing.md)

The harness the other three tasks spend: pump a widget at a fixed size and text scale under a given
theme, walk the tree, and serialise a stable description to a committed `.golden.txt`. It must be
**order-stable** (tree order, not hash order), must include the things that carry meaning silently —
resolved colours, semantics labels, disabled states — and must fail loudly on a missing golden
rather than writing one. An environment variable regenerates, the way `--update-goldens` does, and
CI never sets it.

**Done when:** a deliberate one-character copy change fails the comparison with a readable diff, a
missing golden fails rather than passing, regeneration is a single documented command, and the
harness itself has a test.

### A15.2 test/golden: pin the dashboard at every shape, in both themes

- **blocked-by:** A15.1 · **verify:** H · **board:** no
- **design:** [08 §8.9](../design/08-flutter-app.md)

The outline's list, on the dashboard: **no probes, all detached, mid-gap, alarm active, 15 h of
data, 54 days of data — each in dark and in light.** Dark is the default because dark-first is a
product requirement rather than a preference (§8.7), and light is pinned too because "we have a
light theme" is a claim that only survives if something checks it. The all-detached golden is the
one that matters most: it is the invariant this project has enforced end to end since M0, and a
golden is the cheapest place to catch a regression that turns `—` into `0`.

**Done when:** twelve dashboard goldens are committed and green, the all-detached goldens are
asserted to contain no digit in a temperature slot, and the 54-day golden is generated from a
cache-scale fixture rather than a hand-written one.

### A15.3 test/golden: pin the chart at every shape, in both themes

- **blocked-by:** A15.1, A10.5 · **verify:** H · **board:** no
- **design:** [08 §8.7, §8.9](../design/08-flutter-app.md)

The same shapes, on the chart, where the interesting content is structural rather than textual: how
many bar segments, where the gap boundaries fell, which overlays are present, what colour and stroke
each probe drew with, and what the viewport window was. The mid-gap golden is the one worth writing
first — _"a 30-minute dropout must look like a 30-minute dropout"_ is a claim with an exact,
checkable shape.

**Done when:** twelve chart goldens are committed and green, the mid-gap golden shows the run split
at the correct timestamps, and the palette's resolved values appear in the goldens so a colour
change is reviewed rather than absorbed.

### A15.4 test/integration: drive the app against tools/sim

- **blocked-by:** A15.2, A15.3, A11.4, T3.6 · **verify:** S · **board:** no
- **design:** [08 §8.9](../design/08-flutter-app.md), [10 §10.3](../design/10-repo-tooling-and-testing.md)

The claim §8.9 makes: the app is developable and CI-testable against a fake bridge replaying a
recorded 18-hour cook, with no hardware anywhere. Drive the **real** `HttpTransport`, the **real**
`SyncEngine`, the **real** repositories and the real screens against a running `tools/sim`, through
the whole MVP path — connect, sync 18 hours, render the dashboard, scroll the chart, open the
session detail, export the CSV — and against the adverse scenarios that exist for exactly this
(`flaky`, `base-lost`, `stall`, `lid-open`), because passing only the happy path is what the **S**
tier explicitly does not mean.

**Done when:** the run passes against a live sim on the fixture cook and on at least two adverse
scenarios, the exported CSV matches the sim's own `format=csv` byte for byte, and the suite's
relationship to CI is stated in its own header the way A8.3's deviation was — a test that quietly
does not run is worse than one that says why.

### A15.5 bench: run the MVP end to end on the phone and the board

- **blocked-by:** A15.4, A12.5, A8.4 · **verify:** B · **board:** yes
- **design:** [M4 outline](M2-M6-outline.md), [hardware-verified](../hardware-verified.md)

The exit gate, and half of the single M4 sitting. Install the APK on the real phone, onboard the
real bridge over BLE from a factory reset, choose a mode, watch a live cook update, scroll 15 hours
of real history, and export a CSV — in that order, without a cable, and without touching the
hardware after the reset. Record the phone's OEM and Android version, the time to first render, and
every deviation; an OEM quirk becomes a follow-up task rather than a shrug.

**Done when:** all six clauses of the exit gate are recorded in `docs/hardware-verified.md` with the
phone's identity, the exported CSV is committed as evidence, and anything that did not work is a
named row rather than an omission.

### A14.4b bench: complete the AP-routing matrix M3 could not finish

- **blocked-by:** A15.5 · **verify:** B · **board:** yes
- **design:** [05 §5.8.1](../design/05-connectivity-and-provisioning.md), [hardware-verified](../hardware-verified.md)

The M3 rider, closed in the sitting it was always waiting for. A14.4 recorded a **partial by design**
because the binder-alone / shim-alone matrix needs app screens to observe, and now there are screens:
with the bridge in AP mode, exercise binder-on/shim-on, binder-off/shim-on, and binder-on/shim-off
from the dashboard, and record which combinations actually route. §12.8's claim is that **neither
mitigation alone is sufficient**; this is the row that either confirms it on this phone or corrects
it.

**Done when:** the three combinations are recorded in `docs/hardware-verified.md` with the outcome
of each, A14.4's partial row is closed with a pointer to this sitting, and any disagreement with
§5.8.1's prediction is written down as a finding rather than reconciled silently.

---

## What is deliberately _not_ in M4

|                                                        | Why                                                                                                                                                                        |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Foreground service, notifications, quiet-hours delivery | A13 (M5). A12.2 configures the channels and states plainly that nothing delivers them yet; a settings toggle that silently does nothing is worse than an absent one         |
| The alarm **engine**                                    | F13 (M5). The device tier is authoritative ([09 §9.1](../design/09-alarms-and-insights.md)); M4 mirrors, acknowledges, and never claims to have decided an alarm itself     |
| Battery percentage with a real number behind it         | F12 (M5) gates on V1.3. `SOC_UNKNOWN` renders as absence, decided once in P3.2 rather than improvised in the header                                                        |
| Bearer-token setting                                    | P3.2 moved it to v1.1 — no transport can set it, so the toggle is hidden ([ble-gatt §5.6.6](../../protocol/ble-gatt.md)). Shipping a control that cannot work is a lie      |
| Full history over BLE                                   | v1.1. The 2 h `history_preview` plus A10.5's capability notice is the honest v1.0 story                                                                                    |
| Comparing two sessions on one chart                     | [08 §8.6](../design/08-flutter-app.md) names it; it needs a second viewport and a second palette assignment, and the MVP gate does not ask for it. v1.1                     |
| Multi-bridge picker or switcher                         | D12. The cache and A7.5's prefs stay multi-capable; onboarding a second bridge replaces the first                                                                           |
| Billows tile or fan targets                             | D11 — decoded and stored, never surfaced                                                                                                                                   |
| Pixel/bitmap goldens                                    | Not portable across platform or Flutter version, and the fix everyone applies is `skip:`. A15's text snapshots catch what actually regresses (see the A15 flag)              |
| The device-served web UI                                | D13 — the decision is M6's, on evidence from real use                                                                                                                      |
| iOS                                                     | Deferred ([11 §11.2](../design/11-roadmap-and-risks.md))                                                                                                                   |
| Heap remediation on the device                          | V3a.1's finding is real and recorded, but nothing in M4 consumes device heap. Owed before M5, settled by M6's soak                                                          |
