# 17. Identity and warmth — what the competitors have that we do not

Read with `16-experience-spine.md`, which this does not replace. 16 is about
*honesty*. This is about the thing honesty alone does not buy: an app that looks
like it belongs to cooking rather than to instrumentation.

The trigger was direct user feedback after a bench session: *"The UI/UX of the
app is still extremely poor. Looking nothing like the 3 big apps."* The
reference screenshots are in `docs/reference/apps/`.

---

## 17.1 What the teardown actually shows

Nine screenshots across MEATER, FireBoard and TempPro. The gap is **not**
layout quality, spacing or copy — ours is better than FireBoard's and TempPro's
on all three. The gap is four things we have none of.

### 1. Food identity — the biggest single difference

Every competitor puts **food** on the screen:

- **TempPro** — a circular *photograph* of the dish on every profile row
  (`TemProBBQ-2`) and on every probe card (`TemProBBQ-1`, `-3`).
- **MEATER** — bold circular animal glyphs, one per protein, in saturated
  colour (`Meater-1`), reused as the avatar on every previous-cook row
  (`Meater-2`).

We have **zero** food identity anywhere. A probe is a coloured rule, a name and
a number. That is an instrument panel. It is why the app reads as a lab tool
next to three apps that read as cooking.

### 2. Per-probe richness

- **TempPro** (`TemProBBQ-1`): a numbered channel badge in that channel's own
  accent colour, a meat-type chip, a large readout, `EST. TIME LEFT`, the
  target, and inline alarm/vibration toggles — all on one card, per probe.
- **MEATER** (`Meater-3`): three large circular badges (Internal / Target /
  Ambient) over a huge radial gauge carrying the phase word.
- **FireBoard** (`FireBoard-2`): per-channel High / Avg / Low over 24 h, with
  the alarm bounds printed above the reading.

Ours is one row: swatch, name, state word, number, chevron.

### 3. Chart richness

- **FireBoard** (`FireBoard-1`): filled area under each series, legend with
  swatches, direct axis labelling.
- **TempPro** (`TemProBBQ-3`): a channel-dot selector above the chart, a food
  header strip carrying photo + current + target, a **dashed target line with
  its value printed on the line**, and a crosshair tooltip card.

Ours draws lines on a grid.

### 4. Onboarding presence

`Meater-1` and `Meater-3` sell the product on the setup screen. Our hop 1 is
correct, calm and *empty*: a rail, a title, a sentence, one device row.

---

## 17.2 The tension, and how it resolves

The obvious objection: §16.5 forbids most of what makes those screens feel
warm. A series hue may not fill a large shape or carry a word; green means
transport health; status hues are chrome only.

**Those rules are about status, and food identity is not status.** They exist
so that a colour never lies about how the cook is going. A photograph of a
brisket makes no claim about temperature, freshness or link health, so it
cannot violate a rule about what colour *means*. The rules were never a vow of
austerity — they were a vow that colour stays honest.

So the resolution is an explicit **third colour channel**, alongside series and
status:

| Channel | Carries | May it fill? | May it carry a word? |
|---|---|---|---|
| **Series** | which probe | mark only, ≤12 dp, or ≤16 % tint | no |
| **Status** | how it is going | 12–16 % fill, 22–35 % border | only with an icon *and* a word |
| **Identity** (new) | *what is cooking*, *which jack* | yes — imagery, avatars, badges | yes |

Identity never encodes state. A brisket avatar is the same whether the cook is
perfect or ruined. That is precisely what makes it safe.

**Two sanctioned extensions of the series channel**, both narrow:

1. **The jack badge.** A numbered badge (1–4) may be filled with that probe's
   series hue. The hue *is* the probe's identity and the numeral names the same
   thing the hue names — it is a legend, not a claim. This is the TempPro
   channel-tab pattern and it is the cheapest identity win available.
2. **The chart area fill.** A series may carry a ≤16 % tint below its stroke,
   through `ProbePalette.tint` and nothing else. Already sanctioned for bands;
   this extends it to the area under the line.

Everything else in §16.5 stands unchanged. In particular: **the hero
temperature stays ink**, never a hue, and green still means transport health
alone.

---

## 17.3 What to build

Priority order. Each item names the reference it comes from.

### A. Food identity system (the foundation)

- A `FoodGlyph` set — one per `HazardClass` and per common preset (brisket,
  pork butt, poultry, steak, fish, ribs, ambient/pit). **Vector, not
  photographic**: photos need licensing, blow up the bundle, and cannot be
  tinted for the daylight profile. MEATER's animal glyphs are the model
  (`Meater-1`), not TempPro's photos.
- Rendered as a circular avatar on: each cook row (`/cooks`), the cook detail
  header, the cook setup sheet's preset picker, and each food probe.
- The avatar's circle is an **identity** fill and is exempt from the series
  rule. It never changes with state.

### B. Probe UI (`TemProBBQ-1`, `Meater-3`, `FireBoard-2`)

- **Jack badge**: a numbered, series-hue-filled badge leading every probe row
  and card. Replaces the current 4 dp left rule as the primary identity mark.
- **Richer strip row**: badge · food glyph · name · role chip · readout ·
  trend · chevron, with target and `ETA`/`EST. TIME LEFT` on a second line when
  a target exists.
- **Per-probe stats** on `/live/probe/:jack`: High / Avg / Low for the window,
  as `FireBoard-2` does. We already compute these in `cookStats`.
- Keep the hero at 96 pt ink, keep the gauge, keep `PhaseTrack`. Do **not**
  copy MEATER's coloured number circles — that is the one pattern that would
  break the honesty rule outright.

### C. Bluetooth onboarding (`Meater-1`)

- Give hop 1 a **subject**: an illustration of the bridge itself, and a
  found-device row that shows signal strength and a food-neutral device glyph.
- Say what will happen next, in three short steps, before it happens — the
  pairing passkey especially, since Android's own dialog says *"Usually 0000 or
  1234"*, which is wrong for this device and is the last thing a user reads
  before being asked for six digits. **Coach the passkey before the dialog.**
- Keep the rail, the one action and the calm copy. Add presence, not noise.

### D. Chart (`FireBoard-1`, `TemProBBQ-3`)

- Area fill under each series at `ProbePalette.tint`.
- A real legend with swatches and probe names (`SeriesLegend` already exists
  and has **no call sites** — wire it).
- Target lines **labelled with their value on the line**, not just drawn.
- A channel-dot selector above the chart to isolate one probe.

---

## 17.4 What not to take

- **MEATER's coloured temperature circles.** A magenta disc reading `133°`
  makes hue carry the number, and at a glance nothing distinguishes "internal"
  from "alarm". This is the pattern §16.5 exists to prevent.
- **TempPro's seven-segment LCD face.** It is a skeuomorph of a cheap
  thermometer and it throws away the tabular-figures work in `SmokeType`.
- **FireBoard's stock Material chrome.** Red app bar, hamburger, overflow dots.
  We already beat it.
- **Photographic food imagery.** See A — vector glyphs instead, for licensing,
  bundle size and theming.

---

## 17.5 The rule scales with live state

The colour discipline in §16.5 is not a house style. It is a guard against one
specific failure: **colour lying about how the cook is going.** A magenta disc
reading `133°` is dangerous because a tired person reads hue before digits, and
at a glance nothing separates "this is the internal probe" from "this is an
alarm".

That failure requires live state to fail about. **Where there is none, the
guard has nothing to guard**, and the austerity it imposes buys nothing while
costing the app its whole personality.

So the rule is proportional:

| Screen state | Discipline |
|---|---|
| **No session, no live data** — onboarding, the empty reader, the preset picker, the cook setup sheet, an empty `/cooks`, device pages before a bridge answers | **Rich.** Saturated identity colour, filled shapes, illustration, food glyphs at full strength, colour carrying category. Nothing on screen is claiming a temperature, so nothing can misstate one. Match the competitors' warmth here without hesitation. |
| **A session is running / live readings on screen** | **Strict §16.5.** Series hue is a mark, status hue is chrome with an icon *and* a word, green means transport health alone, and the hero temperature is ink. |

The transition is the interesting part, and it must be deliberate rather than a
surprise: as a cook starts, the screen **cools** — saturated category colour
recedes to marks, and the ink-and-chrome discipline takes over. That is not a
loss of personality; it is the app visibly changing register from *choosing*
to *watching*, which is exactly the mental shift the user is making.

**What stays true in both states:** the hero temperature is never a hue, green
never means "good", and no colour is the sole carrier of meaning (§H.2's
colour-blind requirement). Identity colour may be bold, but it still may not be
the *only* thing distinguishing two items.

**Practical consequences**

- The **preset / meat picker** may look like `Meater-1` — big saturated
  circular category glyphs. There is no cook yet.
- **Onboarding** may be fully illustrated and coloured throughout. There is no
  cook yet.
- The **empty reader** (no probes, no session) may carry a warm illustrated
  empty state rather than a grey glyph.
- A **running cook's probe rows** stay disciplined. This is where the rule
  earns its keep, and it does not bend.
