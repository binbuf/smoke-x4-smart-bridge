# 16. The experience spine

**Read this before changing any screen.** It is the contract every screen, every
piece of copy and every recovery path conforms to. It exists because the last
pass rebuilt the app's *skeleton* — data model, routes, cook model — and left the
*experience* almost untouched, and because six people (or six agents) working on
six screens against no shared spine produce six apps.

Three sources: `docs/newapp.md` (the spec), `docs/design/13-ux-architecture.md`
(the UX contract), `docs/design/14-design-system.md` (tokens). This document does
not replace them. It says what they leave implicit.

---

## 16.1 The one-sentence product

> *A quick temperature reader for four probes, plus the synced history —
> everything else controllable in-app, because the device has one button.*

Every screen is judged against that sentence. If a screen does not help someone
**read a temperature**, **find a past cook**, or **control the device**, it is
not earning its place.

---

## 16.2 The failure this app exists to prevent

Not "a bad chart". **A fourteen-hour cook that fails silently.** Every rule below
descends from that:

- a stale number that looks live is worse than no number;
- a control that appears to work and does nothing is worse than an absent one;
- a spinner with no words is worse than an error with words;
- **an app that knows what is wrong and does not say so is the worst of all.**

That last one is the gap this document is mostly about.

---

## 16.3 Reconciliation: the missing layer

### The problem, stated

The app has a **connection supervisor** that reconnects. It has no layer that
**reconciles** — that compares *what the phone remembers* with *what is actually
observable* and *what the device says when reached*, and turns the difference
into a named situation with a remedy.

Because that layer is missing, `LaunchState` has four variants
(`NeedsOnboarding`, `Connecting`, `Connected`, `Offline`) and **every mismatch in
the world collapses into "Offline · retry 6"**. Observed on the bench: the bridge
was reflashed, came up hosting its own AP, and the app — which knew its Bluetooth
bond, its device id and its last address — sat on a retry counter indefinitely.

### The model

```
        REMEMBERED                OBSERVABLE                 DEVICE SAYS
   ┌────────────────────┐   ┌──────────────────────┐   ┌────────────────────┐
   │ bridgeId           │   │ bluetooth on?        │   │ deviceId           │
   │ baseUrl            │ + │ bond present?        │ + │ paired (to Smoke X)│
   │ bleDeviceId        │   │ SmokeBridge-* AP seen│   │ netMode / ssid     │
   │ lastSeenUnixMs     │   │ mDNS answer?         │   │ clock valid?       │
   │ running cook       │   │ cachedIp answers?    │   │ firmware / caps    │
   └────────────────────┘   └──────────────────────┘   └────────────────────┘
                                      │
                                      ▼
                             ┌──────────────────┐
                             │  ONE Situation   │
                             │  cause + remedy  │
                             └──────────────────┘
```

**One situation at a time**, highest-priority first. Never a list of problems —
a list is a triage job handed to the user.

### The situations

Each has: a **cause** in plain words, a **remedy**, and whether the app performs
it **automatically**. `auto` means the app does it and *reports* it; it does not
ask.

| # | Situation | Cause (what the user is told) | Remedy | Auto |
|---|---|---|---|---|
| 1 | `bluetoothOff` | "Bluetooth is off, so the app can't reach your bridge the fast way." | turn on / open settings | no — OS |
| 2 | `permissionMissing` | names the permission and the consequence | one grant | no — OS |
| 3 | `neverSetUp` | "No bridge set up yet." | run setup | no |
| 4 | `phoneForgotBridge` | "This phone was reset, but it's still paired to *SmokeBridge-8274*." | adopt it | **yes** |
| 5 | `bridgeHostingOwnNetwork` | "Your bridge is hosting its own network — it couldn't reach yours." | join it, or tell it a new network | **yes** (join) |
| 6 | `bridgeMovedAddress` | "Your bridge is on a different address than last time." | re-learn address over the lane that works | **yes** |
| 7 | `bridgeWasReset` | "This bridge has been reset. It isn't the one this phone was set up with." | adopt as new / set up again | no — identity |
| 8 | `bridgeNotPairedToBase` | "Your bridge hasn't met your Smoke X yet." | guided pairing (hop 2) | no |
| 9 | `deviceClockUnset` | "Your bridge doesn't know the time, so cooks can't be dated." | set from phone | **yes** |
| 10 | `firmwareTooOld` | names the missing capability, not a version number | update over Wi-Fi | no |
| 11 | `bridgeOutOfRange` | "Can't reach your bridge. Last seen 12 minutes ago." | keeps trying, says so | **yes** (retry) |
| 12 | `staleCook` | "The cook on screen belongs to a bridge this phone no longer talks to." | end it / keep it | no |
| 13 | `healthy` | nothing rendered | — | — |

**Rules:**

- **Act, then report.** Anything marked auto happens without asking, and the
  banner says what was done in the past tense — *"Reconnected on your bridge's
  own network"* — not what could be done.
- **Identity is never automatic.** #7 is the one case the app must not resolve
  itself: adopting a reset bridge silently would attach a phone's history to a
  device that is not the one that recorded it.
- **A situation names the cause, never the mechanism.** "Your bridge is hosting
  its own network" — never "mDNS resolution failed".
- **`lastSeenUnixMs` is always in the copy** when the app cannot reach the
  bridge. "Can't reach it" is a state; "can't reach it, last seen 12 minutes
  ago" is information.

### Where situations render

- **`/live`** — one banner, above the temperatures, never covering them.
- **`/device`** — the same situation as the lead card, with the full explanation.
- **Nowhere else.** A situation repeated on four screens is four things to
  dismiss.

---

## 16.4 Copy rules

Non-negotiable, and the reason this app reads as one voice. Every string:

1. **Says what happened, not what failed.** "Your bridge is hosting its own
   network" — not "Connection failed".
2. **Names a cause the user could act on**, or states plainly that the app is
   handling it.
3. **No jargon.** "Gaps in recording", not "dropouts". "Pit steadiness", not
   "σ". No "mDNS", "GATT", "MTU", "RSSI" outside Diagnostics.
4. **No status codes, ever**, outside Diagnostics.
5. **Sentence case. One idea per sentence.** Two short sentences beat one long
   one.
6. **Exactly one action** per empty state, per banner, per error.
7. **Buttons are verbs that name the outcome.** "End cook" / "Keep cooking" —
   never "OK" / "Cancel".
8. **Destructive actions state keeps *and* loses** before they run.
9. **Absent is "—" or a sentence, never 0.** A temperature, a battery, a
   signal, a timeout the device has not reported.
10. **Never claim a write succeeded without a read-back.**

**Voice:** calm, specific, second person. It is 3 a.m. and the reader is tired.
Never cute. Never exclamation marks. Never blame the user.

---

## 16.5 Layout system

Every screen is built from these and nothing else.

| Element | Rule |
|---|---|
| **Screen title** | `displayS`, left, in the content — not an AppBar title, except on pushed routes |
| **Section label** | `label`, upper case, `textMuted`, `s5` above / `s2` below |
| **Card** | `SmokeCard`. Groups rows that share a subject. Never one card per row |
| **Row** | 52 dp min. Label left (`title`), value right (`body`, `textHi`) |
| **Row subtitle** | `bodySm`, `textMuted`. Explains, never repeats the label |
| **Disabled row** | rendered, dimmed, **with its reason directly beneath** |
| **Spacing** | the 4 dp scale. `s3` between cards, `s5` between sections |
| **Hero number** | 96 pt fixed, tabular, **never scaled**. The gauge is the flexible child |
| **Extra width** | buys chart, never stretched numbers. Readouts cap at 480 dp |

**Colour, restated because it is the most-broken rule:**

- a **series hue** (per probe) is only ever a *mark* — chart stroke, gauge arc,
  ≤12 dp dot, card left rule. It never fills a large shape and never carries a
  word;
- a **status hue** is only ever *chrome* — 12–16% fill, 22–35% border, always
  with an icon **and** a word. Banner text is always `textHi`;
- **green means transport health and nothing else.** Target reached closes the
  gauge ring; it does not turn green.

---

## 16.6 Per-screen contracts

Each screen answers **one question**. If you cannot say which, the screen is
wrong.

### `/live` — "What is everything at, and can I trust it?"

- Renders from cache **on the first frame**, before any transport connects, with
  freshness computed from stored timestamps. Never a full-screen spinner.
- Always on screen: every plugged probe's temperature, its freshness, the
  transport chip. Nothing pushes temperatures below the fold at any width.
- Detached probes render **in place**, 45% opacity, "—" and "unplugged".
- The action row is real: Mark · Set a target / Edit cook · Export · Test alarm.
- Rows open `/live/probe/:jack`.
- One situation banner, above, never covering the numbers.
- Guided mode: pit + primary food become hero cards with gauge and phase.

### `/cooks` — "Show me my cooks, past and running"

- Cache-only. Works with the bridge unplugged.
- Row: name · date · duration · peak · probes · sparkline; "Recording" badge.
- "+" creates a cook **now**, over readings that already exist.
- Empty state reinforces the model: *"Your bridge is still recording. Start one
  any time — you can even name a stretch that already happened."*

### `/cooks/:id` — "What happened in this cook?"

- Chart, statistics, marks, notes, gaps (rollover vs not-yet-synced, told apart).
- Edits reachable in ≤2 taps: rename, **move start**, retarget, split, merge,
  repeat, delete.
- Delete's cost sheet states the recording does not stop.

### `/device` — "Is my bridge healthy, and how do I control it?"

- Lead card **is the situation** (§16.3), with the full explanation.
- Then: connection mode with a plain-language explainer and a switch control;
  battery; storage; firmware + update; OLED/LED; power off.
- Then entry points to alarms and settings. Never a wall of dashes.

### `/device/settings/*` — "controls everything"

- The §F table is the frozen scope. Every row states which transports can write
  it and what happens when the active one cannot.
- **Every write verifies by read-back.** No exceptions.
- **No constructor default is ever rendered as a device fact.** "—" until read.
  (`NetMode _netMode = NetMode.sta` rendered as "Joined a network" while the
  bridge hosted an AP — this is the bug, do not reintroduce it.)

---

## 16.7 Definition of done

A screen is done when:

- [ ] it answers its one question above the fold;
- [ ] every state in the ladder renders: **empty · loading · partial · stale ·
      offline · error · permission-blocked**;
- [ ] no control is dead — absent, or disabled with its reason on screen;
- [ ] no default is rendered as a device fact;
- [ ] every derived value disappears when stale rather than greying;
- [ ] copy passes §16.4 read aloud;
- [ ] it uses only §16.5 elements;
- [ ] the colour rule holds;
- [ ] it works at 360 dp, 600 dp, 840 dp, and at 200% text scale;
- [ ] tests cover the states, not just the happy path.
