# 15b. The experience pass — five things that were built but not connected

The `newapp` redesign (see `15-newapp-decisions.md`) rebuilt the app's
*skeleton* and left the *experience* almost untouched, which is what
`16-experience-spine.md` was written to fix. Playing with the build made that
concrete: it did not feel redesigned, because five load-bearing pieces existed,
were tested, and were **not wired to anything a user could see**.

Each is worth knowing because each is easy to reintroduce.

---

## 1. The reconciliation layer only ran on one tab

`SituationResolver` was constructed in `BridgeTab.initState`. Branches of a
`StatefulShellRoute` are not preloaded, so for anyone who opened the app and
stayed on the reader — the expected way to use a temperature reader — the
resolver was never built at all: no OS fact gathered, no automatic remedy run.
`/live` fell back to `liveSituation`, which can only diagnose. All thirteen
situations existed and passed their tests; five of thirteen could fire.

It now lives on `ShellSession`, so it starts with the app and both screens read
the *same* verdict — which §16.3 requires and which two engines could never
guarantee. `BridgeTab` borrows it, and builds its own only when a test injects
a `SituationProbe`. Pinned by `test/features/situation_is_app_wide_test.dart`.

## 2. The freshness ladder was frozen at connect time

The honesty spine ran on `BridgeStatus.lastPacketSAgo` — a *device* counter
measuring the **base station's** silence, not ours, read once in
`BridgeSession.start()` and re-read only when an alarm, session or pairing
frame happened to arrive. A quiet fourteen-hour cook read it once and reported
`live` for the duration: no veil, no stopped pulse, a four-hour-old number
under a green chip. On the BLE lane, which has no `/status` at all, an absent
age was read as *live*.

It now runs on `DashboardSnapshot.readingAtUnixMs` — **the phone's** wall clock
at the moment a reading actually arrived, seeded from `samples.unix_ms` on a
cache read — and is computed at read time, so a screen nobody is pushing data
to goes stale on its own. A 15 s ticker on `ShellSession` keeps the frame up.
Absent is now `unknown`, never `live`. Pinned by
`test/features/freshness_ladder_test.dart`.

## 3. Going offline never reached the snapshot

`_handleLink` set the launch state and returned without touching `_snapshot`,
so `link` kept its last value: the chip went on saying "Wi-Fi" with a breathing
pulse dot above unrefreshed temperatures, while the masthead two lines down
said the bridge could not be reached. `snapshot.disconnected()` restates the
same readings as unreachable without touching their age.

## 4. An offline cold start showed four dashes over a full cook

§B.3 requires `/live` to render from drift *before* a lane is raced. The cache
read lived inside `BridgeSession`, which is only built once the supervisor
yields a transport — so out of range, it never ran. `ShellSession.start()` now
renders from drift first. Probe *names* are not cached, so jacks read
"Probe 1"…"Probe 4" until a lane answers: a known, stated degradation, because
the contract is that the temperatures are on screen instantly, not that every
label is.

## 5. Every golden rendered a theme that no longer shipped

There were **two** `SmokeTheme` classes. `design/theme.dart` is what `app.dart`
builds with; `app/theme.dart` was the pre-redesign Material one, imported only
by `test/golden/golden.dart` and two app tests. Worse, it carries no
`SmokeTokens` extension, so `context.tokens` fell back to `SmokeTokens.dark` —
every `-light` golden was measuring **dark** tokens, and the daylight profile
had never been exercised by a single golden. One test asserted
`displayLarge == 88`, that theme's value; what ships is 96.

`app/theme.dart` is deleted. Golden variants are now `dark` and `daylight`,
the two profiles that exist. Two corrections fell out:

* **`daylight` is `Brightness.dark`.** It is a *contrast* profile — lifted ink,
  glows off, same surfaces (14 §14.3.3) — not a Material light theme. Tests now
  identify a profile by its `SmokeTokens`, not by Material brightness.
* **The light series hues are export-only.** `series_palette.dart` says so
  outright: they are for CSV plots and share images, "not used in-app". A
  golden asserted them rendering on screen, and passed only because of the dead
  light theme. It now pins the opposite.

---

## Also closed in this pass

* **A custom cook bypassed the food-safety gate entirely.** There was no
  per-jack hazard control, so a custom cook fell back to `wholeMuscleRedMeat` +
  `enthusiast` — the one combination with no floor — and a 140 °F poultry
  target constructed silently. There is now a per-jack picker, a new
  `HazardClass.unstated` carrying the 160 °F ground-meat floor for anything
  unanswered, and `safePullF10`, because carryover subtraction was unclamped
  and could recommend pulling ground beef at 152 °F. Three further floor-free
  defaults were closed: `CookAnnotation.hazard`, the `cooks.hazard` storage
  read's fallback, and `CooksTab._startNow`.
* **Settings forms rendered constructor defaults and wrote them back.** The
  probes page seeded four blank probes before `live()` landed, and "Save to the
  bridge" wrote them over a real configuration — then read back the blank it
  had just written and reported success. Home Assistant did the same to a
  working broker. Both now gate on a `…Known` flag and re-seed.
* **The notes field on a cook discarded everything typed.** A multi-line
  `TextField` gets `TextInputAction.newline`, so `onFieldSubmitted` could never
  fire, and nothing else persisted it.
* **`"Offline · retry N"`** — the literal string §16.3 opens by naming — was
  still rendered by `TransportChip`, in the loudest chrome in the app. A retry
  count is a status code (§16.4 rule 4). The chip states the link; the banner
  states the cause; lane detail belongs to Diagnostics.
* **Green meant six different things** — "what you keep" on every cost sheet,
  "this check passed", "the disruptive command finished" (drawn at the moment
  power-off makes transport health gone by design), "we don't track you", "the
  wipe succeeded". §16.5 reserves it for transport health.
  `features/bridge/situation_card.dart` is the model, and
  `test/design/colour_rule_test.dart` now walks the element tree matching green
  by RGB at any alpha.
* **A series hue carried a word at 34 pt** on the first screen a new user ever
  sees working: hop 2's probe readout painted the *temperature itself* in the
  probe's hue. Every sibling readout keeps the number at `textHi` and spends
  the hue on a 3 dp underline.
* **`/device` was a wall of taps.** One unlabelled card held twelve unrelated
  rows — a rule editor, ten settings pages and a setup re-run. It is now three
  labelled groups, power sits above the navigation rows per §16.6, and
  `_FactRow` meets the 52 dp minimum (it was ~30 dp, with the five-tap
  diagnostics gate wrapped around one of them).

---

## What is still open

* `phoneForgotBridge` is reachable now — setup takes the OS bond name, so a
  reset phone adopts its still-paired bridge instead of running the full
  three-hop wizard. But a **stale BLE bond against a reflashed bridge is still
  reported as "can't reach it"** rather than as a reset.
  `BleRebondRequiredException` surfaces as a *stream* error, so `start()`
  returns a live-looking transport, and both bond exceptions are handled only
  in `setup_machine.dart`. The manual "Run setup again" path recovers
  correctly.
* **Automatic joining of a hosted AP is not built, and should not be.** It
  needs a Wi-Fi key the app stores none of (05 §5.9), and naming networks in
  range needs the location permission the manifest promises never to take
  (A6.6). The bridge now reports its own SSID over Bluetooth instead, so the
  banner reads "Your bridge is hosting SmokeBridge-8274" — a network a person
  can act on. That is as automatic as it gets without breaking a stated
  promise.
* The `cooks.hazard` **column default** is still `wholeMuscleRedMeat`, so cooks
  created by the v1→v2 migration carry the floor-free class. Low risk — they
  have no targets, and a retarget re-asks — and deferred because changing a
  drift column default needs a version bump and a migration step.
* The **safety strip** (`plan.safetyStripLines`) renders only on the cook setup
  sheet. §D.4 wants it persistent, as MEATER's is: it still needs to reach
  `/live`'s guided overlay and `/cooks/:id`.
