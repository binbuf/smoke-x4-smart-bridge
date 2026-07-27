# 14 — Design System

The normative token set, component library and rendering rules for the Flutter app. This is the
document that turns [`docs/ui/`](../ui/design-system.md) — a mood board with real hex values — into
`app/lib/design/` and `app/lib/ui/`, and it is the document a widget PR is reviewed against.

Confidence is marked the way [02](02-smoke-x-protocol.md) marks it: **[K]** verified against the
repo or measured here · **[I]** inferred, consistent but unproven · **[?]** unknown until someone
measures it.

Two decisions up front, because everything else follows from them:

> **Does a light theme ship?**
> No. v1.0 is dark-only, and `SmokeTheme.light` (`app/lib/app/theme.dart:40-50`) is deleted along
> with 12 `*-light.golden.txt` files. A white screen in a dark yard is worse than a high-contrast
> dark one, and a second `Brightness` is a full token pass plus a doubling of every golden for a
> case nobody has asked for. Daylight legibility is handled by a **contrast profile** on the same
> surfaces (§14.3), not by a second theme. The light `ProbePalette` values survive as the
> **export/print** palette for CSV plots and share images.

> **Does probe colour follow the role or the jack?**
> The jack, as it already does (`app/lib/app/palette.dart:11-24`). `docs/ui/design-system.md` §4
> keys colour to role; that loses two structural properties the existing palette was built to hold —
> re-roling a probe mid-cook must not repaint the history behind it, and the OLED can only name a
> probe by its number ([07 §7.2](07-display-and-controls.md)). The prototype's role hues are not
> discarded: `--color-pit #FF6B00` becomes the app's **chrome accent** (§14.6), which is exactly
> what the separation rule says a role hue may be.

## 14.1 What this document is

`docs/ui/` is a mood board that happens to carry real tokens. It is a 894-line single-file HTML
prototype with a working dashboard, a working presets card (`index.html:679`) and **three empty
screens** — history (`:696`), alarms (`:704`), settings (`:712`). It loads fonts from Google
(`index.html:10`), icons from unpkg (`:12`) and Chart.js from jsDelivr (`:776`); it renders one
frozen data shape; it has no detached probe, no gap, no alarm and no offline state.

That is the correct amount of prototype and the wrong amount of specification.

**Precedence.** `docs/design/` wins. Where this document and `docs/ui/` disagree, the disagreement
is recorded in §14.9 with a reason; where they agree, this document restates the value so an
implementer never has to open the HTML. `docs/ui/` is not updated to match — it is a dated artefact
and rewriting it would destroy the record of what was proposed.

**What this document does not own.** Screen composition, routing, the state machine and the truth
model belong to the app-architecture document. Firmware, protocol and connectivity facts belong to
[03](03-firmware-architecture.md), [05](05-connectivity-and-provisioning.md),
[06](06-device-api.md) and [07](07-display-and-controls.md); where this document depends on one it
cites it rather than restating it. Nothing here specifies what a screen *says* beyond §14.11's
discipline for where the strings live.

**Scope.** Android only for v1.0 — there is no `app/ios/` directory and `app/pubspec.yaml:1` says so
**[K]**. Every token, type style and widget below is platform-neutral and ports; the *actions* some
of them invoke do not (`FlutterBluePlus.turnOn()`, `ACTION_*` settings intents, `WifiNetworkSpecifier`,
the foreground service, and an app-timed bond countdown iOS cannot express because its pairing sheet
is OS-driven off the first encrypted read). Widgets in `ui/` never invoke those directly — they take
a `VoidCallback` — which is what keeps this library portable even though the product is not.

## 14.2 File layout

```
app/lib/design/            values only — no widgets, no BuildContext beyond `of(context)`
  tokens.dart              SmokeTokens (ThemeExtension): surfaces, ink, radii, spacing, shadow, glow
  motion.dart              SmokeMotion: named durations, curve, disableAnimations collapse
  typography.dart          SmokeType: the 14 named styles; the ONLY file naming a font asset
  series_palette.dart      ProbePalette + ProbeStyle  (moved from app/lib/app/palette.dart)
  status_palette.dart      StatusPalette             (replaces AlarmPalette)
  theme.dart               SmokeTheme.dark + the ColorScheme mapping

app/lib/ui/                widgets — StatelessWidget over values, no providers, no transports
  surface/    SmokeCard · SmokeSheet
  probe/      ProbeHeroCard · ProbeCompactCard · ProbeStripRow · TargetGauge · AnimatedTemp
              TargetPill · TrendChip · StrokeSwatch · Sparkline
  chart/      CookChart · ChartControls · CrosshairReadout   (moved from features/chart/)
  insight/    InsightBanner
  chrome/     TransportChip · PulseDot · AlarmBar · TruthBanner
  controls/   PrimaryAction · ActionRow · SegmentedChips · StatRow · MonoWell · CostSheet
  state/      EmptyState · ProblemState · CapabilityNotice · StaleVeil
  setup/      SetupScaffold · SetupRail
```

**The layering rule.** `ui/` may import `design/`, `core/`, `domain/` and Flutter. It may not import
`data/`, `features/`, `app/`, or `flutter_riverpod`. A widget that needs the time takes a computed
`Freshness`; a widget that needs a string takes the string; a widget that needs to do something
takes a callback. Enforced by `app/test/app/layering_test.dart`, which walks `lib/ui/**` and fails
on a forbidden import, a `Duration(` literal (§14.4) or a `DateTime.now()`.

**`Freshness` lives in `core/`**, not in the truth layer, precisely so this rule holds.

### 14.2.1 Migrating `app/lib/app/palette.dart`

Five files import it **[K]**: `features/chart/cook_chart.dart`, `features/dashboard/probe_tile.dart`,
`features/sessions/sessions_screen.dart`, `features/settings/settings_probes.dart`, and
`test/app/palette_test.dart`.

| Step | Change | Golden churn |
| --- | --- | --- |
| 1 | `git mv` to `design/series_palette.dart`; split `AlarmPalette` (`palette.dart:162-178`) into `design/status_palette.dart` as `StatusPalette`, keeping `of(AlarmSeverity)`/`iconOf(AlarmSeverity)` so call sites migrate by import change. **No value changes in this commit.** `app/lib/app/palette.dart` becomes two `export` lines. `test/app/palette_test.dart` moves to `test/design/series_palette_test.dart` unchanged | **none** — that is the point of separating the move from any retune |
| 2 | The two status-hue changes in §14.6, and the contrast gate re-pointed at `SmokeTokens.card` | colour diffs only, reviewable as text |
| 3…n | Feature by feature, widgets move to `ui/` and drop the `app/palette.dart` import | per feature |
| last | Delete `app/lib/app/palette.dart` once `grep -r "app/palette.dart" app/lib` is empty | none |

`probe_tile.dart` and `cook_chart.dart` are deleted, not edited: `ProbeHeroCard` /
`ProbeCompactCard` replace the first, and the second moves to `ui/chart/` with the §14.8 changes.
`SparklinePainter` (`probe_tile.dart:333-372`) and `_StrokePainter` (`:241-274`) are lifted verbatim
into `ui/probe/` — they are correct and they are already the cheap path.

## 14.3 Surfaces and ink

Six surfaces, four inks, two hairlines. Everything else is a composite of these.

| Token | Value | `docs/ui/` name | Used by |
| --- | --- | --- | --- |
| `bg` | `#07090E` | `--bg-darkest` (`:16`) | `scaffoldBackgroundColor`, the space between cards |
| `surface` | `#0F131D` | `--bg-surface` (`:17`) | shell chrome: system status bar, nav bar, sheet body |
| `card` | `#161C2A` | `--bg-card` (`:18`) | `SmokeCard` default — **the surface most marks are drawn on** |
| `cardSubtle` | `#121824` | `--bg-card-subtle` (`:20`) | insets: chip rows, segmented tracks, list wells, disabled fills |
| `cardRaised` | `#1E2638` | `--bg-card-hover` (`:19`) | pressed card, selected option card, nav indicator |
| `well` | `#04060A` | — (new) | deepest inset, **mono readouts only**: passkey, AP PSK, device id, crosshair |
| `hairline` | `#FFFFFF` @ 8 % | `--border-subtle` (`:21`) | 1 dp decorative border on cards and chips |
| `hairlineStrong` | `#FFFFFF` @ 14 % | — (new) | dividers *inside* a card |
| `scrim` | `#000000` @ 72 %, 6 σ blur | `index.html:425` | sheet and modal backdrop |
| `textHi` | `#F8FAFC` | `--text-main` (`:39`) | numbers, titles, **all banner and chip text** |
| `textBody` | `#CBD5E1` | — (new) | prose |
| `textMuted` | `#94A3B8` | `--text-muted` (`:40`) | labels, secondary values, **axis ticks and timestamps** |
| `chromeDim` | `#64748B` | `--text-dim` (`:41`) | **non-text only**: gap connectors, disabled fills, inactive rules |

`cardRaised` is named `bg-card-hover` in `docs/ui/design-system.md:66`; "hover" has no meaning on a
touch device, so the token is renamed and the provenance recorded here **[K]**.

### 14.3.1 Measured contrast

WCAG relative-luminance ratios, computed with the same formula already committed at
`app/test/app/palette_test.dart:19-31` **[K]**:

| ink | `bg` | `surface` | `card` | `cardSubtle` | `cardRaised` | `well` |
| --- | --- | --- | --- | --- | --- | --- |
| `textHi` | 19.03 | 17.74 | 16.27 | 16.98 | 14.44 | 19.38 |
| `textBody` | 13.41 | 12.50 | 11.47 | 11.97 | 10.18 | 13.66 |
| `textMuted` | 7.77 | 7.24 | 6.64 | 6.93 | 5.89 | 7.91 |
| `chromeDim` | 4.18 | 3.90 | 3.58 | 3.73 | **3.18** | 4.26 |

Three rules fall out of that table rather than out of taste:

1. **`chromeDim` is never text.** The draft this document replaces used `--text-dim` for axis ticks
   and timestamps at 11–12 px, where AA requires 4.5:1. It reaches 3.18:1 on `cardRaised` and 3.58:1
   on `card` — a fail. Axis ticks and timestamps use `textMuted` (6.64:1 on `card`). `chromeDim`
   survives as a *graphic* ink, where the floor is 3:1, and its worst surface still clears it.
2. **No alpha-white border clears 3:1 on `card`.** Measured composites: 8 % → `#292E3B`, 1.26:1;
   14 % → `#373C48`, 1.54:1; even 30 % → `#5C606A`, 2.70:1. `hairline` is therefore **decorative**
   and may never be the only thing identifying a control. Selection, focus and enabled/disabled all
   need a second channel — a surface change, an accent ring, or a leading icon.
3. **The focus ring is 2 dp `pit` at full opacity**, measured 5.99:1 on `card`, 6.25:1 on
   `cardSubtle`, 5.32:1 on `cardRaised`. Not a white ring, for the reason above.

### 14.3.2 The `ColorScheme` mapping

Unmigrated Material widgets must land somewhere sane during the port, so the mapping is explicit
rather than left to `ColorScheme.fromSeed`:

| `ColorScheme` slot | Token | Why |
| --- | --- | --- |
| `surface` | `card` | M3 draws cards, sheets and dialogs on `surface` |
| `surfaceContainerLowest` / `Low` | `well` / `surface` | |
| `surfaceContainer` / `High` / `Highest` | `cardSubtle` / `card` / `cardRaised` | today's `probe_tile.dart:44,156` reads these two |
| `onSurface` / `onSurfaceVariant` | `textHi` / `textMuted` | |
| `primary` / `onPrimary` | `pit` / `bg` | `bg` on `pit` measures 7.01:1 |
| `error` | `critical` | |
| `outline` | `hairlineStrong` composite `#373C48` | decorative, per rule 2 |

`scaffoldBackgroundColor` is `bg`, not `surface`. `MaterialApp` sets `theme:`, `darkTheme:` **and**
`themeMode: ThemeMode.dark`, all to `SmokeTheme.dark`, so an OS light-mode setting cannot leak
system chrome into a screen that has no light variant.

### 14.3.3 The daylight profile

Not a second theme — a contrast profile over the same surfaces, persisted as `prefs.screenProfile`
and reachable from Bridge → Device → Screen. It exists because the same phone is read at 3 a.m. in
a yard and at noon on a patio, and those want different ink, not different surfaces.

| Property | Night (default) | Daylight |
| --- | --- | --- |
| `textBody` | `#CBD5E1` | `#E2E8F0` |
| `textMuted` | `#94A3B8` | `#CBD5E1` |
| `chromeDim` | `#64748B` | `#94A3B8` |
| `hairline` | 8 % | 14 % |
| `shadowCard`, all glows | as §14.4 | `null` — a glow is invisible in sunlight and costs a saveLayer |
| `ProbeStyle.strokeWidth` | 2 / 3 (pit) | 3 / 4 |
| surfaces | — | unchanged |

The daylight profile's own contrast column is **[?]** until the token test in §14.12 runs it; the
values above are chosen to move monotonically in the safe direction, which is an argument and not a
measurement.

## 14.4 Geometry, elevation and motion

```dart
// app/lib/design/tokens.dart
@immutable
class SmokeTokens extends ThemeExtension<SmokeTokens> {
  // Radii — four, and no fifth.
  static const double radiusCard    = 20;  // SmokeCard, sheet top, modal            (index.html:44)
  static const double radiusControl = 14;  // buttons, inputs, option cards, compact  (:45)
  static const double radiusChip    =  8;  // range chips, target pill, banner        (:46)
  static const double radiusPill    = 999; // transport chip, nav indicator, swatch

  // Spacing — a 4 dp scale. Nothing between steps; a 6 or a 10 is a bug.
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 20, s6 = 24, s7 = 32;

  // Elevation. One shadow, two glows, and glows are nullable so the daylight
  // profile switches them off without every call site knowing.
  final BoxShadow? shadowCard;      // 0 10 30 −10  #000 @ 55 %   (index.html:47)
  BoxShadow? glow(Color c);         // 0  0 24   0  c    @ 20 %   (index.html:48)
  BoxShadow? glowTight(Color c);    // 0  0  8   0  c    @ 55 %   (index.html:168)
}
```

`glow()` is the only reason a `saveLayer` appears in this app. It is permitted on exactly three
things: the accent card's border, the gauge's current-value dot, and `MonoWell`. Anywhere else it is
a rejected review comment.

### 14.4.1 Motion

```dart
// app/lib/design/motion.dart
abstract final class SmokeMotion {
  static const quick    = Duration(milliseconds: 120); // chips, pills, taps, ripples
  static const standard = Duration(milliseconds: 220); // cards, sheets, banner slide, cross-fades
  static const value    = Duration(milliseconds: 600); // temperature tween
  static const gauge    = Duration(milliseconds: 800); // arc sweep        (index.html:370)
  static const pulse    = Duration(seconds: 2);        // liveness dot     (index.html:172)
  static const curve    = Curves.easeOutCubic;

  static SmokeMotionValues of(BuildContext context); // honours disableAnimations
}
```

**No widget reads a `Duration` literal.** Everything goes through `SmokeMotion.of(context)`, and the
layering test greps for `Duration(` under `lib/ui/**` to keep it that way. That is not tidiness: it
is the single seam where `MediaQuery.disableAnimations` is honoured, and a literal anywhere defeats
it silently.

| Token | `disableAnimations` | Why not zero for all |
| --- | --- | --- |
| `quick`, `standard`, `gauge` | `Duration.zero` | |
| `value` | `Duration.zero` — the number snaps | |
| `pulse` | **opacity-only, 2 s** | the dot stopping *is* the staleness signal (§14.7); removing the animation removes the information. Reduced motion removes the 1.3× scale, not the fade |

### 14.4.2 Tickers

`PulseDot`, `TargetGauge` and `AnimatedTemp` own `AnimationController`s and are the only
`StatefulWidget`s in `ui/`. None of them uses a `Timer`.

The *freshness label* ("last reading 4 minutes ago") does need a periodic tick, and it lives in the
shell, not in `ui/` — the widget takes a computed `Freshness` and a formatted string. That ticker is
the **first periodic** `Timer` in `app/lib/`; two one-shot `Timer`s already exist at
`data/transport/ble_gatt_fbp.dart:71,113` **[K]**. One ticker for the whole app, at 10 s while a
cook is live and cancelled when the route is not visible.

## 14.5 Typography

Three families, bundled as assets. **No `google_fonts`, no network fetch.** The prototype's
`<link>` to `fonts.googleapis.com` (`index.html:10`) is not portable to an app that must render on a
phone joined to a bridge's AP with no internet (`WifiNetworkSpecifier` + `bindProcessToNetwork`
removes `NET_CAPABILITY_INTERNET` by design, [05 §5.8.1](05-connectivity-and-provisioning.md)), and a
golden that depends on a font download is a golden that fails in CI.

```yaml
# app/pubspec.yaml
flutter:
  fonts:
    - family: Archivo
      fonts: [{ asset: assets/fonts/Archivo[wdth,wght].ttf }]
    - family: Inter
      fonts: [{ asset: assets/fonts/Inter[opsz,wght].ttf }]
    - family: JetBrainsMono
      fonts: [{ asset: assets/fonts/JetBrainsMono[wght].ttf }]
```

All three are SIL OFL 1.1 and redistributable inside the APK. The three `OFL-*.txt` files are
committed beside them and registered with `LicenseRegistry.addLicense` in `bootstrap()` — the about
screen's licence page is not optional for OFL.

**Size: measured, and over budget.** The three upstream variable fonts are **1.64 MB of TTF**
(Inter 876 KB, Archivo 659 KB, JetBrains Mono 187 KB) against a stated budget of ≤ 1.2 MB **[K]**,
2026-07-24, from the files as committed. `--tree-shake-icons` does not touch fonts, and the APK
figure will be lower than the raw total only by whatever the packer achieves. **Inter is the
problem and subsetting it is A19.2b:** this app renders Latin-1 plus `°`, so an `fonttools`
`pyftsubset` pass keeping the `wght` axis and dropping `opsz` should recover most of it. Until that
lands the budget is knowingly exceeded, which is a recorded overage rather than an unmeasured
claim.

| Name | Family / axis | Size | Weight | Tracking | Features | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| `heroTemp` | Archivo `wdth 112` | 96 | 800 | −3.0 | `tnum` | pit + primary food hero number |
| `heroUnit` | Archivo `wdth 100` | 30 | 600 | 0 | | the `°F` on the hero baseline |
| `bigTemp` | Archivo `wdth 112` | 56 | 800 | −1.6 | `tnum` | instrument rows, stat hero |
| `midTemp` | Archivo `wdth 100` | 34 | 700 | −1.0 | `tnum` | compact probe card |
| `displayL` | Archivo `wdth 100` | 26 | 700 | −0.4 | | screen titles, cook name |
| `displayS` | Archivo `wdth 100` | 20 | 700 | −0.2 | | card titles, sheet headers |
| `title` | Inter | 18 | 700 | 0 | | list rows, settings rows |
| `body` | Inter | 16 | 400 | 0 | | prose |
| `bodySm` | Inter | 14 | 400 | 0 | | secondary prose, banner text |
| `label` | Inter | 12 | 700 | +1.6 | uppercase | probe name, eyebrow, chip |
| `labelSm` | Inter | 11 | 700 | +1.2 | uppercase | axis ticks, timestamps |
| `mono` | JetBrainsMono | 16 | 500 | +0.5 | `tnum` | ids, addresses, crosshair |
| `monoBig` | JetBrainsMono | 22 | 700 | +1.0 | `tnum` | elapsed timer badge |
| `monoKey` | JetBrainsMono | 34 | 800 | +12.0 | `tnum` | BLE passkey, AP PSK |

`SmokeTheme` maps `displayLarge→heroTemp`, `displayMedium→midTemp`, `titleLarge→displayS`,
`bodyLarge→body`, `labelLarge→title`, so widgets that have not migrated yet inherit something
correct rather than a Material default. Today's `headlineTemp` at 88 pt (`theme.dart:57-63`) and
`secondaryTemp` at 40 pt (`:66-72`) are replaced by `heroTemp` and `midTemp`.

**Deviation from the prototype:** `index.html:10` and every `font-family` rule in it specify Outfit
for display. This spec uses **Archivo at `wdth 112`** instead. The hero number is *width*-constrained
— it shares a 208 dp card row with an 84 dp gauge — and a width axis buys optical size at ten feet
without buying line height, which is what principle 1 (`design-system.md:8`) actually asks for.
**[I]** — that is a design judgement, not a measurement. It is settled by a held-phone read at 3 m
against an Archivo `wdth 100` control, and until that test runs `wdth 100` is the fallback. Inter and
JetBrains Mono are taken from the prototype unchanged.

### 14.5.1 A temperature is never scaled to fit

`probe_tile.dart:54` and `:165` wrap the number in `FittedBox(fit: BoxFit.scaleDown)` **[K]**. That
is deleted and forbidden. Three reasons, all of which have bitten someone:

- the glyph height changes between frames as a probe crosses 99 → 100 °F, which reads as the layout
  breaking rather than as a temperature rising;
- two cards side by side print the same value at different sizes;
- a text golden cannot see a scale factor, so the regression is invisible in review.

Instead: `heroTemp` at a fixed 96, `maxLines: 1`, `softWrap: false`, tabular figures, and **the
gauge is the flexible child**. The row is laid out `[number][unit][spacer][gauge]`, sized for four
tabular glyphs plus the unit at 360 dp — the narrowest width v1.0 supports — and that layout is a
golden (§14.12). Four glyphs is the real worst case: the wire clamps to `-40.0 … 572.0` and the
display rounds to whole degrees.

### 14.5.2 Sentinels and units

The wire carries two sentinels, `-32768 detached` and `-32767 invalid` (`protocol/records.yaml:148`)
**[K]**; `ProbeView.tempF10` collapses both to `null` today. A detached probe renders `—` and the
word *unplugged*, never a number and never a zero — the invariant `probe_tile.dart:70-77` already
holds and this document keeps. Distinguishing *invalid* from *detached* needs a field on `ProbeView`
that does not exist; that is an obligation on the app-architecture document, not a licence for the
widget to guess.

**Storage is canonical tenths °F** (`records.yaml:143-147`, [04 §4.2](04-storage-and-history.md)) and
display conversion is presentation-only, so a cook recorded before the user switched to °C renders in
°C with no migration. `source_celsius` (`records.yaml:161`, `04:83`) does **not** contradict that: it
is a *provenance* bit recording that the Smoke X base reported °C and the bridge converted on the way
in, which means such a sample carries one °F rounding step and converting it back to °C is not
bit-exact with what the base displayed. That is a ±0.05 °C artefact, it is documented in
`core/units.dart`'s doc comment, and it is not a reason to store two units.

## 14.6 Colour

### 14.6.1 The separation rule

Written verbatim into `status_palette.dart`'s doc comment, because it is the rule that keeps a
four-series chart and an alarm-driven UI from impersonating each other:

> A **series hue** may only be drawn as a *mark*: a chart stroke, a gauge arc, a 10 dp probe dot, a
> card's left rule, a stroke swatch. It never fills a shape larger than 12 dp, and it never carries a
> word.
>
> A **status hue** may only be drawn as *chrome*: a filled pill or banner at 12–15 % alpha with a
> 30–35 % border, always containing an icon **and** a word. It is never a chart stroke.
>
> Consequence: a lit chart line and a "this needs attention" banner cannot be confused, because one
> is a 2 dp line and the other is a bordered slab with text in it.

The pit's alarm band is the **one sanctioned exception** — a series hue filling an area, at
`ProbePalette.tint(c) = c.withValues(alpha: .16)`, bounded above and below by two horizontal rules
and carrying no text. Also used for the gauge track. Nowhere else.

### 14.6.2 The series palette does not change

The draft this document replaces retuned all four dark hues on the grounds that they were validated
against `#0D0F12` and the new background is `#07090E`. Measured, that argument inverts:

| Slot | dark hue | on `#0D0F12` (validated) | on `#07090E` (new `bg`) | Δ | on `card #161C2A` |
| --- | --- | --- | --- | --- | --- |
| P1 ember | `#D95926` | 4.94 | **5.13** | +0.19 | 4.38 |
| P2 violet | `#9085E9` | 6.14 | **6.37** | +0.23 | 5.45 |
| P3 green | `#008300` | 3.88 | **4.03** | +0.15 | 3.44 |
| P4 blue | `#3987E5` | 5.27 | **5.47** | +0.20 | 4.68 |

**[K]**, same formula as `palette_test.dart:19-31`.

Contrast is the **only** background-dependent term in the palette's validation. Adjacent CVD ΔE and
adjacent normal ΔE are pair comparisons between two series hues and do not move when the surface
moves. So the surface change alone invalidates nothing, and every slot got *better*. The four hues
move to `series_palette.dart` byte-for-byte, and the measured table at `palette.dart:36-39` stays
true — with one correction added beneath it: the numbers above.

Two claims in the draft are wrong and are recorded here so they are not re-derived: the "muddy
3.9:1" attributed to P1 ember is P3 green's 3.88 on the old surface, and P1 measures 4.94; and
`#008300` on `#07090E` is 4.03:1, which **clears** the 3:1 floor at `palette_test.dart:103`. The
case for a brighter green is perceptual — at 4.03 it is the weakest mark in the set, drawn 2 dp
wide, dark-on-near-black — and it is **[I]**, to be settled by the same 3 m read test as §14.5, not
by a table.

**One gate does move.** `palette_test.dart:95-111` checks each series against
`SmokeTheme.dark.colorScheme.surface`. Under §14.3.2 that is `card`, which is the surface the chart
is actually drawn on, and the measured column becomes 4.38 / 5.45 / 3.44 / 4.68 — all ≥ 3:1 **[K]**.
Re-point the test; do not re-point the floor.

### 14.6.3 The standing obligation on any retune

Nothing above licenses a future hue change. The rule, in force from this document forward:

1. **No hue ships that has not been through the validator.** Run it against the surface the mark is
   drawn on (`card`), on the *adjacent* pairlist the method prescribes for line charts, in the one
   remaining mode.
2. **Paste the measured table into `series_palette.dart`'s doc comment**, replacing the `#0D0F12`
   table at `palette.dart:36-39`. A hue whose measurements are not beside it is not reviewable.
3. **The floor is the current dark adjacent-CVD ΔE of 26.0.** If a pair drops below it:
   permute the four slots first — slot 1 is pinned to ember (§14.6.4), so that is 3! = 6 orderings,
   not 24; then re-step the *lightness* of the failing family and re-run; only then change a family,
   and if a family changes, the rationale in the doc comment changes with it.
4. **Never lower the floor.** Same rule the repo already applies to the heap gate at
   `docs/hardware-verified.md:450` — *"if it does bite, the answer is not 'lower the bar'"*.
5. If nothing clears at four slots, the honest caveat at `palette.dart:47-58` still governs: the
   all-pairs gate and the sunlight requirement are in direct conflict at four series, and the
   resolution is the secondary channels already shipped — **stroke pattern, legend, direct labels** —
   never a new channel invented at render time.
6. **The status set is in the pairlist too.** A warning banner sits directly beneath an ember hero
   number; checking the series against each other and not against `warning` and `critical` checks
   the wrong thing.

**The validator itself must be committed.** `palette_test.dart` pins identity (`:34-49`), role
independence (`:51-68`) and contrast (`:92-112`) — it contains no CVD or ΔE code at all **[K]**. The
26.0/27.0 numbers in the doc comment came from an out-of-band run and are currently unreproducible in
this repo, which is exactly why a retune is dangerous. Commit it as
`app/test/design/series_palette_cvd_test.dart` so the table is regenerable and a hue change is a red
test rather than a paragraph.

### 14.6.4 Reconciling with `docs/ui/`

`docs/ui/design-system.md` §4 assigns Thermal Fire `#FF6B00` to "Pit Thermometer", Smoked Amber
`#FF9500` to "Probe 1 (Primary Food)", and so on — colour keyed to **role**. That is rejected as a
*series* scheme for the two structural reasons in the preamble, and `palette_test.dart:51-68`
already pins the behaviour ("colour follows the probe, not its role").

But the prototype's pit orange is not thrown away, because under the separation rule it was never a
series hue in the first place — it is the brand ember that fills the primary button, the AP transport
chip, the cook-header gradient and the passkey well. It becomes **`StatusPalette.pit`**.

Which forces one decision: **`StatusPalette.pit` and series slot 1 must be the same hue, not two
similar ones.** An ember chart line beside an ember button in a near-miss orange reads as a rendering
bug. So slot 1 is pinned first — it is the pit on essentially every X4, it is already the tie-break
`palette.dart:41-45` used, and it is now also the brand — and the other three permute around it.

The candidate is `#FF6B2C` (7.01:1 on `bg`, 5.99:1 on `card`, 7.14:1 on `well`) against the
prototype's `#FF6B00` (6.98 / 5.96) **[K]** — within 0.5 % of each other on contrast, so contrast
does not decide it. The tie-break is adjacent separation from `warning` and from P2 violet, which is
a validator run: **[?]**, default `#FF6B2C`, and the validator may substitute `#FF6B00`. Adopting
either one *is* a retune of slot 1 and is therefore gated by §14.6.3 in full.

Role still carries semantic weight — through **form**, as it already does: stroke width
(`palette.dart:139`), card rank (hero vs compact vs strip), the accent border and glow on the pit
card, and gauge *type* (band vs sweep, §14.7).

### 14.6.5 Status palette

| Role | Hue | Fill / border | Change | Where |
| --- | --- | --- | --- | --- |
| `critical` | `#F04444` | 14 % / 35 % | **from `#D03B3B`** | pit crash, base lost, probe detached, link dead |
| `warning` | `#FAB219` | 14 % / 35 % | unchanged | out of band, stall, battery low, storage low |
| `positive` | `#10B981` | 12 % / 30 % | new | **transport healthy only** — never a probe state |
| `info` | `#94A3B8` | 10 % / 22 % | **from `#898781`** | advisory, "this is normal", capability notices |
| `pit` | slot 1 (§14.6.4) | 15 % / 35 % | new | primary action, AP chip, cook header, passkey well |

Both changes are measured, not stylistic:

**`critical` moves** because at a 14 % fill over `card` (`#30202C`) the shipped `#D03B3B` leaves its
own icon at **3.19:1** — 0.19 above the 3:1 graphics floor, on the single most important glyph in
the app. `#F04444` measures 3.96:1 on its fill and 4.55:1 on `card` **[K]**. That it converges with
the prototype's `#EF4444` (4.52) is a coincidence worth noting and not the reason.

**`info` moves** because `#898781` is a warm grey and every other neutral in the app is now on the
slate ramp; carrying two neutral ramps for one enum value is not a decision anyone would defend. It
measures 3.95:1 on its own fill against `#94A3B8`'s 5.23:1 **[K]**. `info` is a neutral, not a
semantic hue, so it carries no validation debt.

`warning` stays at `#FAB219`. The draft moved it to the prototype's `#F5A524` to "avoid being 15°
from a series hue"; measured, `#FAB219` reads 9.28:1 on `card` and 7.04:1 on its own fill, `#F5A524`
reads 8.34 and 6.47, and both sit ~20° from ember. Changing a validated status hue to match a mood
board is the casual override this document is under instructions not to make.

**Banner and chip text is `textHi`, never the status hue.** Measured on each role's own 14 % fill,
`textHi` lands between 12.62 and 14.14:1, while the hue itself lands between 3.19 and 7.04 — and
`critical`, the one that matters most, is the worst. The prototype draws banner text in the hue
(`index.html:388-390`); that is rejected. The hue is carried by the icon and the border; the words
are carried at 13:1. Trailing values use `textBody`.

### 14.6.6 Target reached is not a colour

**The ring closes.** When a food probe reaches its target, `TargetGauge` sweeps past its 270° end to
a full 360°, thickens 8 → 10 dp, goes solid in the probe's own hue, and the centre glyph cross-fades
to a check over `standard`. One `HapticFeedback.mediumImpact()` on the transition edge, once per
probe per target — re-armed on the device's `target_rearm_f10` hysteresis so a value oscillating
across the line does not buzz repeatedly. **No green.**

This removes a three-way collision — series slot 3 is green, `positive` is emerald, and the
prototype paints success emerald too (`index.html:389`) — and buys the app its one memorable moment
in the same decision.

It does not remove the word. `TargetPill` changes from `Target 203°` to **`Reached 203°`**, and the
semantics value says "reached", because a shape alone is exactly as bad as a hue alone for a screen
reader (§14.10). Under `disableAnimations` the ring is drawn closed and the check is drawn — no
sweep, no cross-fade, same haptic.

## 14.7 The component library

Five rules, then the table.

1. **Every widget is a `StatelessWidget` over values.** No `ConsumerWidget`, no `ref`, no transport,
   no repository, no `DateTime.now()`. Time arrives as a `Freshness` and a formatted string.
2. **Exactly three are `StatefulWidget`s**, each because it owns an `AnimationController`:
   `AnimatedTemp`, `TargetGauge`, `PulseDot`. Any fourth needs a reason in the PR description.
3. **`ui/` owns no user-facing strings** (§14.11). It takes them.
4. **Repeating instances take a stable key** derived from the jack — `Key('probe-hero-3')` — so a
   golden diff points at a probe rather than at an index.
5. **Surfaces come from `SmokeTokens.of(context)`**, never from `Theme.of(context).colorScheme`
   directly. The `ColorScheme` mapping in §14.3.2 exists for widgets we do not own.

Supporting value types, all in `core/` or `design/` so rule 1 holds:

```dart
enum Freshness { live, stale, frozen }                       // core/freshness.dart
enum InsightKind { stall, band, eta, lid, alarm, advisory, capability }
enum TruthTone { critical, warning, info, degraded }
enum GaugeMode { none, band, sweep }
```

### 14.7.1 The table

| Widget | File | Constructor | Anatomy |
| --- | --- | --- | --- |
| `SmokeCard` | `ui/surface/smoke_card.dart` | `({required Widget child, EdgeInsets padding = s4, Color? accent, bool raised = false, bool inset = false, VoidCallback? onTap, Widget? footer, Key? key})` | radius 20, fill `card` (`cardRaised` when `raised`, `cardSubtle` when `inset`), 1 dp `hairline`. With `accent`: 1 dp `accent` @ 35 % + `shadowCard` + `glow(accent)`. `footer` bleeds to the rounded corners — that is how a sparkline goes edge to edge. Replaces the ad-hoc `Container`s at `probe_tile.dart:40,152`, `cook_chart.dart:453,573`, `dashboard_screen.dart:145` |
| `ProbeHeroCard` | `ui/probe/probe_hero_card.dart` | `({required ProbeView view, required Freshness freshness, int? pullF10, int? bandMinF10, int? bandMaxF10, bool celsius = false, required String semanticsLabel, List<Widget> banners = const [], VoidCallback? onTap, Key? key})` | 208 dp. See the diagram below |
| `TargetGauge` | `ui/probe/target_gauge.dart` | `({int? tempF10, int? targetF10, int? startF10, int? pullF10, int? bandMinF10, int? bandMaxF10, required Color hue, required bool reached, required String semanticsValue, Key? key})` | 84×84, 8 dp stroke, 270° sweep from −225°. `GaugeMode` is derived, not passed: band when `bandMin/Max` are set, sweep when `target` is set, `none` otherwise — and `none` renders **nothing**, never an empty ring |
| `ProbeCompactCard` | `ui/probe/probe_compact_card.dart` | `({required ProbeView view, required Freshness freshness, bool celsius = false, required String semanticsLabel, VoidCallback? onTap, Key? key})` | radius 14, `midTemp`, dot + `label` header, `TrendChip` under the number, and a 4 dp progress rule in the footer bleed instead of a gauge |
| `ProbeStripRow` | `ui/probe/probe_strip_row.dart` | `({required ProbeView view, required ProbeStyle style, required Freshness freshness, bool celsius = false, required String semanticsLabel, VoidCallback? onTap, Key? key})` | 72 dp: `StrokeSwatch(18)` · `label` · `Sparkline(56)` · `bigTemp` · `TrendChip` · chevron. A detached row renders at 45 % with `—` **in place** — it never leaves the list |
| `AnimatedTemp` | `ui/probe/animated_temp.dart` | `({required int? f10, bool celsius = false, required TextStyle style, TextStyle? unitStyle, Key? key})` | `TweenAnimationBuilder<double>` over `value` (600 ms). **Rounds inside the tween**, so intermediate frames are whole degrees and never `162.7`. `null` renders `—` with no tween |
| `TargetPill` | `ui/probe/target_pill.dart` | `({required String text, bool reached = false, Key? key})` | radius 8, `cardSubtle` fill, `label` in `textMuted`; `reached` swaps fill to `pit` @ 15 % and text to `textHi`. Text is `Target 203°` / `Reached 203°` / `Band 225–275°` — composed by the caller |
| `TrendChip` | `ui/probe/trend_chip.dart` | `({required double? fPerHour, bool celsius = false, Key? key})` | arrow + rate in `bodySm`. `null` or `abs() < 0.6` renders `–` with **no arrow** and the word *steady* in semantics — the threshold matches `probe_tile.dart:282` |
| `InsightBanner` | `ui/insight/insight_banner.dart` | `({required InsightKind kind, required String label, String? trailing, Widget? action, Key? key})` | 36 dp, radius 8, hue @ 12–15 % fill, hue @ 30–35 % border, icon + `bodySm` 600 in `textHi`, trailing in `textBody`. Kind → role: `stall`/`band` → warning, `lid`/`alarm` → critical, `eta`/`advisory`/`capability` → info. **`label` is produced by `alarmTitle()`** (`domain/alarms/notification_policy.dart:136`), which moves to `core/format.dart` so the banner, `settings_probes.dart` and the notification path all read one table. `view.alarm!.rule` must never reach a user — today `probe_tile.dart:113-115` prints `pit_out_of_band` **[K]** |
| `PulseDot` | `ui/chrome/pulse_dot.dart` | `({required Color hue, required bool live, double size = 7, Key? key})` | filled + `glowTight` while `live`, animating opacity 1→0.4 and scale 1→1.3 over `pulse`; **hollow and still** when not. The dot stopping is the staleness signal, so it is never simply hidden |
| `TransportChip` | `ui/chrome/transport_chip.dart` | `({required Color hue, required IconData icon, required String label, required bool live, String? age, VoidCallback? onTap, Key? key})` | pill, hue @ 15 % fill / 30 % border, height 28, min tap target 48. Takes hue and label rather than a transport enum: `LinkKind` (`dashboard_snapshot.dart:69`) has no AP/STA distinction and teaching `ui/` about transports is how a widget library starts importing `data/` |
| `AlarmBar` | `ui/chrome/alarm_bar.dart` | `({required String title, required String detail, required AlarmSeverity severity, required bool acked, required VoidCallback onAcknowledge, Key? key})` | full width, directly under the system status bar, on **every** tab. 56 dp (76 with a wrapped detail), slide-down over `standard`, one `heavyImpact` per `alarm.id`, inline `[Acknowledge]`. The composing screen must include **device alarms with `probe == 0`**, which `dashboard_snapshot.dart:244` filters out today by keying its `where` on the jack number **[K]** |
| `TruthBanner` | `ui/chrome/truth_banner.dart` | `({required TruthTone tone, required String text, String? actionLabel, VoidCallback? onAction, Key? key})` | 40 dp, hue @ 12 % / 25 %, icon + `bodySm` + a text action. The **stack** (ordering, max 2, `+N` overflow) is a pure function in the app layer — `ui/` renders a list it is given |
| `StaleVeil` | `ui/state/stale_veil.dart` | `({required Widget child, required Freshness freshness, required String ageLabel, Key? key})` | `live` is a pass-through. Otherwise: `ColorFilter.matrix` saturation 0.25, opacity 0.55, and a pinned `InsightBanner.advisory` reading `ageLabel`. **Derived values inside must already have been removed by the caller** — a veiled ETA computed from frozen data is a lie with a filter on it. Nothing like this exists today |
| `SmokeSheet` | `ui/surface/smoke_sheet.dart` | `.action({required String title, required Widget body, Widget? primary})` · `.flow({required String title, required Widget body, required Widget primary, Widget? secondary, Widget? rail, required bool inFlight, VoidCallback? onExit})` · `.detail({required String title, required Widget body, bool expandable = true})` | radius 20 top, `surface` fill over `scrim`. `.action` fits content ≤ 45 % height; `.flow` is 90 %, **non-dismissible while `inFlight`**, pinned footer; `.detail` is 60 % draggable to 95 %. **Every `.flow` disables its primary and swallows back while `inFlight`** — the app-wide fix for the double-tap class at `features/onboarding/onboarding_screens.dart:149,270,469-479` |
| `SetupScaffold` | `ui/setup/setup_scaffold.dart` | `({required int hop, int of = 3, required String title, String? subtitle, required Widget body, Widget? primary, Widget? secondary, VoidCallback? onExit, bool errorTint = false, Set<int> skipped = const {}, Key? key})` | `assert(hop >= 0 && hop <= of)`. `hop == 0` is preflight — see below. `onExit` is present on **every** non-terminal state |
| `SetupRail` | `ui/setup/setup_rail.dart` | `({required int hop, required int of, required bool errorTint, required Set<int> skipped, Key? key})` | `of` × 30 dp circles on a 2 dp connector (`index.html:228-236`) |
| `PrimaryAction` | `ui/controls/primary_action.dart` | `({required String label, required VoidCallback? onPressed, bool busy = false, IconData? icon, Key? key})` | the only `pit`-filled button in the app; **at most one per screen**. `busy` shows a 20 dp indicator and disables. `onPressed: null` renders disabled with `cardSubtle` fill and `textMuted` — never a live-looking dead button |
| `ActionRow` | `ui/controls/action_row.dart` | `({required List<ActionRowItem> items, Key? key})`, `ActionRowItem({required IconData icon, required String label, VoidCallback? onTap})` | 3-up grid of `cardSubtle` tiles, radius 14, icon in `pit`, min 64 dp tall. `onTap: null` dims the tile and the caller supplies a `CapabilityNotice` above it |
| `SegmentedChips<T>` | `ui/controls/segmented_chips.dart` | `({required List<T> values, required T selected, required String Function(T) label, required ValueChanged<T> onChanged, Key? key})` | `cardSubtle` track, radius 14, selected chip `pit` fill + `bg` text (7.01:1) + a leading check for the non-colour channel. Replaces the blind two-state toggle at `settings_screen.dart:122-131` |
| `StatRow` | `ui/controls/stat_row.dart` | `({required String label, required String value, String? hint, bool mono = false, Key? key})` | label `textMuted` left, value `textHi` right (`mono` when it is an id, address or count). `hint` renders `bodySm` beneath in `textMuted` — that is where *"needs probe roles — this cook predates saved names"* goes instead of an unexplained `—` |
| `MonoWell` | `ui/controls/mono_well.dart` | `({required String text, String? groupedSemantics, VoidCallback? onCopy, Key? key})` | `well` fill, 1 dp `pit` @ 35 %, `glow(pit)`, `monoKey`, centred. Selectable, and tappable to copy when `onCopy` is given — the *callback* is passed in so `ui/` never touches `Clipboard` |
| `EmptyState` | `ui/state/empty_state.dart` | `({required IconData glyph, required String title, required String body, Widget? primary, List<Widget> secondary = const [], Key? key})` | glyph 48 in `textMuted`, `displayS` title, one sentence of `body`, one primary action |
| `ProblemState` | `ui/state/problem_state.dart` | `({required IconData glyph, required String title, required String body, Widget? primary, List<Widget> secondary = const [], bool terminal = false, Key? key})` | as above in `critical` ink. `terminal: true` renders the instruction as the whole body **with no button** — see below |
| `CapabilityNotice` | `ui/state/capability_notice.dart` | `({required String text, Widget? action, Key? key})` | an `InsightBanner.capability` sized to sit above a degraded section. Every degraded section renders one instead of dead controls — `settings_screen.dart:5-11` states that rule already **[K]**; this is where it finally gets a widget |
| `CostSheet` | `ui/controls/cost_sheet.dart` | `({required String title, required List<String> loses, List<String> keeps = const [], Widget? exportShortcut, required bool holdToConfirm, required VoidCallback onConfirm, Key? key})` | `.action` sheet: what you lose (critical bullets) above what you keep (info bullets), optional *Export first*, and a hold-to-confirm primary with a visible progress ring for the destructive rows |
| `CookChart` etc. | `ui/chart/` | unchanged from `features/chart/cook_chart.dart:30-59`, plus §14.8 | moved, not rewritten |

**`ProblemState.terminal` exists for one measured reason.** A phone with no BLE support cannot be
told "use Wi-Fi instead": a factory-fresh bridge is in AP mode with an SSID it does not know and a
random 10-character PSK readable only on the OLED ([05 §5.3](05-connectivity-and-provisioning.md)),
so there is no address to enter and no credential to enter it with. The honest render is the
instruction — *read the SSID and password from the bridge's screen, then join that network in
Android settings* ([07 §7.2](07-display-and-controls.md), Network page) — and no button. A button
that leads nowhere is worse than an admitted dead end, so "every state has an action" is stated
correctly as **every state has an action or an honest terminal instruction**.

### 14.7.2 `ProbeHeroCard` anatomy

```
┌─ SmokeCard(accent: hue when role == pit) ──────── 208 dp ─┐
│ ●10  PIT                              ┌──────────────┐    │   dot · label · TargetPill
│                                       │ Target 250°  │    │   (label: `label`, textMuted)
│                                       └──────────────┘    │
│                                                           │
│   243 °F                                    ╭────╮        │   heroTemp 96 · heroUnit 30
│   ▼ −1.8 °F/hr                              │ 84 │        │   TrendChip · TargetGauge
│                                             ╰────╯        │
│                                                           │
│ ┌───────────────────────────────────────────────────────┐ │   0–2 InsightBanner, 36 dp
│ │ ⚠  Out of band for 6 min                225–275°      │ │   never 3 — the third is a
│ └───────────────────────────────────────────────────────┘ │   TruthBanner, not a card row
└───────────────────────────────────────────────────────────┘
```

The number is fixed at `heroTemp`; the **gauge** is the flexible child (§14.5.1). Layout order is
`[number][unit][spacer][gauge]`, so a four-digit reading eats the spacer and then the gauge, and the
number never moves.

### 14.7.3 `TargetGauge` modes

| Mode | When | Render |
| --- | --- | --- |
| `none` | no target and no band | **not rendered at all.** The card lays out without it. An empty ring says "there is a target and you are at zero", which is false |
| `band` | `bandMin`/`bandMax` set — the pit | 270° track in `hue` @ 16 %, a tinted sector between the two bounds, and a 7 dp current-value dot with `glowTight`. Out of band beyond the device's sustain window: sector → `warning` @ 16 %, dot → `critical` |
| `sweep` | `target` set — a food probe | solid arc from `start` (or the session's first reading) to `target`, tweened over `gauge`. A 3 dp radial **pull tick** *inside* the ring at `pull` in `hue` @ 60 %. At `reached`, §14.6.6 |

Every mode is `excludeSemantics: true` on the painter with an explicit `Semantics(value:)` on the
wrapper — a `CustomPaint` is invisible to a screen reader otherwise (§14.10).

### 14.7.4 `SetupRail`, including hop 0

Three hops ship: phone ↔ bridge (BLE), bridge ↔ Smoke X (LoRa), bridge ↔ network (Wi-Fi). `of` is a
parameter only so the rail is testable and so a hop can be skipped.

```
hop 0 — preflight            hop 2 active                 hop 2, errorTint
  ┌────────────────────┐       ┌────────────────────┐       ┌────────────────────┐
  │  BEFORE WE START   │       │  ①━━━━━◉━━━━━③     │       │  ①━━━━━◉━━━━━③     │
  │  ①━━━━━②━━━━━③     │       │  done  active      │       │  done  active=red  │
  │  all 45 %, dimmed  │       │                    │       │                    │
  └────────────────────┘       └────────────────────┘       └────────────────────┘
```

- **hop 0** precedes hop 1 and has no active circle. All `of` circles render `hairline` at 45 %
  opacity on a dimmed connector, and the rail's title row carries the eyebrow *Before we start*.
  `errorTint` at hop 0 recolours **the title row**, not a circle — there is no circle to recolour,
  and inventing one would tell the user they had failed a step they have not reached.
- **done** circles fill `pit` with a tick (`index.html:236`).
- **active** is a 2 dp `pit` ring with `glow(pit)` (`:235`).
- **`errorTint`** recolours the **active** circle to `critical`. A failure is a bad hop, not a fourth
  hop — that is the whole reason ~30 setup states stay legible as three.
- **skipped** hops render as done with a **dash**, not a tick, and the state's subtitle says so.
  A bridge already bonded to a base skips hop 2 and must not be shown a tick it did not earn.

### 14.7.5 Blocked dependencies

Three components in the table above depend on plumbing that does not exist. They ship with the
dependency, not before it, and none of them fakes it:

| Component | Blocked on | Verified |
| --- | --- | --- |
| The chart's mark layer | A marks **read** path. `bridge_transport.dart:86-89` has `MarkCommand` and no `marks()` method; `http_transport.dart:341` POSTs one; `MarkDao.replaceMarks` (`data/local/database.dart:348`) has zero production callers. Needs a transport method, an HTTP route and DAO wiring | **[K]** |
| `ProbeHeroCard` with a plan, offline | `schemaVersion: 2` + a `MigrationStrategy`. `database.dart:98` is at version 1 and `Sessions` carries no probe-role or plan columns, so a guided cook cannot be cached | **[K]** |
| `StatRow.hint` on history detail | the same migration — the hint text exists precisely so the blank looks like a known gap rather than a bug | **[K]** |

`CookChart.marks` stays in the constructor and defaults to `const []`. The mark layer is **not**
golden-tested until the read path lands: a golden of a permanently empty layer proves nothing and
reads as coverage.

### 14.7.6 The snapshot type

Widgets in `ui/` take `ProbeView` (`features/dashboard/dashboard_snapshot.dart:24`) and explicit
values. **No widget takes a snapshot type at all** — which is what makes the following an
app-architecture decision this document merely records: `CookSnapshot` does not exist **[K]**; the
codebase has `DashboardSnapshot` (`:74`) and the pure `buildDashboard`. The recommendation is to
**extend in place**: `DashboardSnapshot` gains a nullable `plan`, `buildDashboard` keeps its name,
its purity and its tests, and no rename churns 20 files. Whichever way that lands, `ui/` does not
change — and that is the point of rule 1.

## 14.8 Chart specification

`fl_chart`, with the work done before it sees the data — the arrangement
[08 §8.7](08-flutter-app.md) specifies and `cook_chart.dart` already implements. What changes is
what the prototype would have added.

### 14.8.1 Data-fidelity rejections

| `docs/ui/` | This spec | Why |
| --- | --- | --- |
| `tension: 0.3` on every series (`index.html:871-873`) | `isCurved: false`, straight segments | A Bezier interpolates readings that were never taken, and it rounds off exactly the lid-open spikes and pit crashes the chart exists to show |
| `fill: true`, `rgba(255,107,0,0.08)` (`:871`) | no area fill | Four overlapping translucent areas are unreadable, and an area under a temperature line implies an integral nobody computes |
| implicit straight line across a gap | separate `LineChartBarData` per run at Δt > 45 s, plus a **dotted connector** in `ProbePalette.gapInk` (`palette.dart:155`) | *"A 30-minute dropout must look like a 30-minute dropout"* — 08 §8.7. The connector is drawn in chrome ink, never in the series hue, so it can never be mistaken for data |
| a zero for a detached probe | no spot at all | `records.yaml:148` has a detached sentinel; the reference's `0.0` is a real trap on a graph ([07 §7.2](07-display-and-controls.md)) |
| naive stride decimation | LTTB at ~2 points per pixel, `bucket=90&agg=minmax` for very wide ranges | stride steps over a spike |

### 14.8.2 Windows

**15m · 1h · 6h · 15h · All** — all five already exist as `ChartWindow` (`chart_viewport.dart:20-32`)
with `h15` as the default (`:43`) **[K]**. The prototype offers 15m/1h/6h/All (`index.html:650-653`);
15 h is added back because it is the only window that frames a full brisket, which
`00-overview.md:70` names as scope ("multi-probe chart over 15 h+").

Chips are `SegmentedChips<ChartWindow>`. Pinch and drag adjust `minX`/`maxX`; double-tap resets;
live follow auto-scrolls until the user pans and then offers a *jump to now* pill —
`ChartViewport.following` already implements this.

### 14.8.3 Targets, bands and marks

| Overlay | Render |
| --- | --- |
| target | horizontal dashed rule at the probe's target in its hue @ 60 %, labelled at the **right edge with the probe's short name** — a direct label, not a legend entry (`palette.dart:56-57` names direct labels as one of the three identity channels) |
| pull | a second, shorter dash at `pull` when a plan sets one, same hue @ 40 % |
| pit band | filled sector between `band_min` and `band_max` at `ProbePalette.tint()` = hue @ 16 % — the one sanctioned area fill of a series hue (§14.6.1). Beyond the device's sustain window the sector's **edges** recolour to `warning`; the fill does not, because a screen-filling amber wash is a worse alarm than a line |
| marks | vertical rule in `chromeDim` with a 12 dp glyph at the top. **Blocked** — §14.7.5 |
| axis | `labelSm` in `textMuted` (6.64:1 on `card`); grid `#FFFFFF` @ 6 %, decorative. Elapsed-time labels when `startedUnixMs == null`, because dates in 1970 are worse than an honest `+4:12` |

### 14.8.4 Crosshair

Drag places a vertical rule in `textMuted` and a filled dot per series at that instant, with
`CrosshairReadout` (`cook_chart.dart:557`) below the plot in `mono`.

- It reads **the nearest actual sample within half a bucket** — never an interpolated value.
- Where a series has a gap at that instant it reads `—`, matching the detached rule.
- The crosshair **persists on release** and is cleared by a tap elsewhere, so a value can be read
  aloud or screenshotted. A crosshair that vanishes with your finger is unusable one-handed.
- Under `disableAnimations` there is no fade in or out.

## 14.9 Deliberate deviations from `docs/ui/`

| Prototype decision | This spec | Why |
| --- | --- | --- |
| Six tabs, including Welcome and Presets (`index.html:477-508`) | four; setup is a route, presets is a page inside cook setup | a wizard you can navigate back into mid-cook is a footgun. Owned by the app-architecture document |
| Colour keyed to probe **role** (`design-system.md:70-76`) | keyed to the **jack** | re-roling must not repaint history; the OLED names probes by number |
| `--color-pit #FF6B00` as a series colour | as the **chrome accent**, `StatusPalette.pit` | the separation rule (§14.6.1); the two must be one hue, not two |
| Emerald `--color-success` = target reached (`:33`, `:389`) | **the ring closes**; no green | collides three ways with series green and transport-healthy |
| Banner text drawn in the status hue (`:388-390`) | `textHi` on every banner | measured: `critical` on its own fill is 3.19:1; `textHi` is 14.14:1 |
| `tension: 0.3` + `fill: true` (`:871-873`) | straight segments, no fill | fabricated readings; §14.8.1 |
| Windows 15m/1h/6h/All (`:650-653`) | + **15h** | the brisket window; `00-overview.md:70` |
| `ETA 5h 45m` inside the stall banner (`:606`) | ETA **suppressed** during a stall; otherwise a 15-minute-rounded range | [09 §9.4](09-alarms-and-insights.md); `etaToTarget` already refuses correctly |
| Fonts from `fonts.googleapis.com` (`:10`), icons from `unpkg` (`:12`), Chart.js from `jsDelivr` (`:776`) | all bundled; Material icons only | offline rendering and reproducible goldens; and one icon set, not two |
| Outfit for display | Archivo `wdth 112` | width axis buys optical size without line height. **[I]**, §14.5 |
| `user-select: none` on **everything** (`:51`) | temperatures, ids, addresses, passkeys and PSKs are selectable and copyable | a passkey you cannot copy is a transcription error waiting to happen |
| Five-step wizard with clock sync as a visible step (`design-system.md:19-28`) | three hops; the clock is set silently | a step with no user decision is not a step |
| Gauge hardcoded to `stroke-dasharray: 226` (`:371-372`) | 270° sweep computed from the values | a hardcoded dash array is a picture of a gauge |
| `.pit-card` glow always on (`:317`) | glow on the accent card only, and `null` in the daylight profile | it is invisible in sunlight and costs a `saveLayer` |
| Three empty screens — history `:696`, alarms `:704`, settings `:712` | specified elsewhere | recorded so nobody mistakes the prototype's silence for a decision. Presets (`:679`) is the one non-dashboard screen with real content |

## 14.10 Accessibility

**Not deferred to v1.1.** This app's entire job is to wake someone at 3 a.m. and tell them one
number. A status that rests on hue is a silent failure in exactly the case the product exists for;
retro-fitting semantics onto a `CustomPaint` is a rewrite rather than a patch; and the goldens
already capture semantics labels (`test/golden/golden.dart` describes them), so deferring means
deliberately committing goldens that pin the wrong thing and then re-baselining every one of them
later.

| Requirement | Implementation |
| --- | --- |
| Every temperature is announced with probe, unit and trend | `semanticsLabel` on the number, composed by the caller: *"Brisket flat, 163 degrees Fahrenheit, rising 1.2 per hour"*. `probe_tile.dart:376-389` already builds this string correctly; it moves to `core/format.dart` |
| Detached reads as a word | *"Brisket flat, unplugged"* — never a dash spoken as "dash" |
| `TargetGauge` and `Sparkline` are `CustomPaint` and invisible to a screen reader | `Semantics(value: '80 percent of the way to 203 degrees', child: ExcludeSemantics(child: painter))`. `reached` announces the **word** "reached" (§14.6.6) |
| Alarms announce without focus | `SemanticsService.announce(title, TextDirection.ltr, assertiveness: Assertiveness.assertive)` on a newly-raised unacked alarm, **once**, keyed by `alarm.id` |
| Status never rests on hue | every chip and banner carries an icon **and** a word; every series carries a stroke pattern (`palette.dart:112-117`) plus a legend plus a direct label; selection carries a check as well as a fill |
| The passkey is read as digits | `MonoWell.groupedSemantics` = `'4 1 8, 3 0 2'`. Left to the default it is announced as four hundred eighteen thousand three hundred two, which is unusable for the one screen where a transcription error costs the whole bond |
| Text scale | honoured to 1.3 without clipping. At ≥ 1.3 the gauge is dropped from `ProbeHeroCard` and `heroTemp` demotes to `bigTemp` — golden-tested, both hero and compact |
| Reduced motion | `MediaQuery.disableAnimations` collapses `quick`/`standard`/`value`/`gauge` to zero and degrades `pulse` to opacity-only (§14.4.1) |
| Touch targets | ≥ 48 dp on every action **including** the transport chip, the acknowledge button and the chart's window chips. `theme.dart:92,124` already sets 64×52 for buttons and 52×52 for icon buttons **[K]**; the chip and the ack button are the two that must be checked by hand because they are laid out, not themed |
| Contrast | §14.3.1 for ink, §14.6 for hue, enforced by the token test in §14.12 |

## 14.11 Copy discipline

**Every user-facing string lives in one file per feature** — `features/setup/copy/setup_copy.dart`,
`features/cook/copy/cook_copy.dart`, … — as `static const`. No string literals in widgets. `ui/`
owns **none**: it is a library, and a library that hardcodes a sentence cannot be reused or
reviewed. This is not ARB yet; it is the refactor that makes ARB a mechanical step later, and it is
what makes the review gate below physically possible.

**The OLED's strings live in one table** in `app_ui_render.c`, not in scattered `snprintf` literals,
with the 21-column budget from [07 §7.1](07-display-and-controls.md) asserted at compile time:

```c
#define OLED_STR(name, s)                                             \
    static const char name[] = s;                                     \
    _Static_assert(sizeof(name) - 1 <= 21, #name " exceeds 21 columns")
```

That bounds literals only. Lines composed at runtime — a probe name plus a temperature — go through
`oled_fit(dst, n, …)`, which truncates at column 21 with an ellipsis, and each composed line gets a
host test asserting its worst case. A string that fits in English and overflows in the first
translation is the failure this pair exists to prevent.

**Reading level: US grade 6.** Banned without a plain-language gloss on first use:

> client isolation · association · DHCP · PMF · MAC filtering · enterprise · provisioning ·
> handoff · transport · lane · RSSI · GATT · characteristic · bond · MTU · SSID (say *network name*)

**The review is a merge gate, not a suggestion.** One named owner reads every string in
`features/*/copy/**` and the OLED table **aloud**, once, before the wave ships. In this app the
failure copy *is* the product: a person standing in a dark yard holding a phone that says
*"association failed (reason 15)"* has been abandoned by the software.

> **OWNER: TBD — assign before W8.** Named here rather than left implicit, because a gate with no
> owner is not a gate. The same sentence applies to the coordinated bump of `protocol/records.yaml`
> + `protocol/openapi.yaml` + `protocol/ble-gatt.md`, which four waves depend on and which this
> document does not own: **OWNER: TBD — assign before W8.**

## 14.12 Golden test obligations

The goldens are **text descriptions of the rendered tree**, not bitmaps — the decision at
`test/golden/golden.dart:1-20`, taken because a PNG rendered on Windows red-lights on CI's Ubuntu
runner and the fix everyone reaches for is `skip:`. That decision pays off directly here: the tree
description already includes **every resolved colour and stroke**, so a token change or a hue retune
is a reviewable text diff across every golden, and the diff *is* the proof the change landed
everywhere.

Regenerate with `UPDATE_GOLDENS=1 flutter test test/golden`. CI never sets it (`golden.dart:32`), and
a missing golden fails rather than writing itself.

**Deleting the light theme deletes 12 files** — `chart-{15h,54d,alarm-active,all-detached,mid-gap,no-probes}-light`
and `dashboard-{15h,54d,alarm-active,all-detached,mid-gap,no-probes}-light` **[K]**.
`dashboard-degraded-dark` has no light twin and is unaffected.

### 14.12.1 Variants

Brightness is no longer a variant. Four replace it:

| Variant | Suffix | Applies to |
| --- | --- | --- |
| default | *(none)* | everything |
| text scale 1.3 | `-ts13` | `ProbeHeroCard`, `ProbeCompactCard`, cook instrument, cook guided, `SetupScaffold` |
| reduced motion | `-nomotion` | `TargetGauge` (all modes), `PulseDot`, `AlarmBar`, `AnimatedTemp` |
| daylight profile | `-daylight` | cook instrument, chart, `ProbeHeroCard` |
| Celsius | `-c` | cook instrument, chart, history detail |

### 14.12.2 What must be golden-tested

**A component may not merge without a golden per state its row in §14.7.1 names.**

| Subject | States |
| --- | --- |
| `ProbeHeroCard` | attached · detached · target-reached · unacked alarm · acked alarm · stale · frozen · four-digit value at 360 dp |
| `TargetGauge` | `none` (renders nothing) · band in · band out · sweep · sweep with pull tick · reached |
| `ProbeCompactCard` / `ProbeStripRow` | attached · detached · no target |
| `AnimatedTemp` | null · mid-tween at t=0.5 (rounding proof) · settled |
| `InsightBanner` | one per `InsightKind`, with and without `trailing` and `action` |
| `TransportChip` + `PulseDot` | live · not live with an age · each transport hue |
| `AlarmBar` | critical unacked · warning unacked · **device alarm with `probe == 0`** · acked (absent) |
| `TruthBanner` stack | 0 · 1 · 2 · overflow `+N` |
| `StaleVeil` | pass-through (`live`) · applied (`stale`) · applied (`frozen`) |
| `SetupScaffold` | **hop 0** · hop 1 · hop 2 · hop 3 · `errorTint` at hop 2 · `errorTint` at hop 0 · a skipped hop |
| `SmokeSheet` | `.action` · `.flow` idle · `.flow` `inFlight` (primary disabled) · `.detail` collapsed and expanded |
| `EmptyState` / `ProblemState` / `CapabilityNotice` | with primary · with primary + secondaries · **`terminal`** |
| `CostSheet` | loses-only · loses + keeps + export · hold-to-confirm |
| `CookChart` | the six shapes that already exist — `15h`, `54d`, `alarm-active`, `all-detached`, `mid-gap`, `no-probes` — plus **band-out** and **crosshair-on-a-gap** |
| Screens | cook instrument · cook guided · offline-cached · BLE-degraded · unpaired |

### 14.12.3 Two tests that are not goldens

- **`app/test/design/tokens_test.dart`** — every ink token over every surface token, asserting the
  floors in §14.3.1: 4.5:1 for anything typeset below 19 px, 3:1 for graphics, and `chromeDim`
  asserted to be **absent** from every `TextStyle` in the tree. The table in §14.3.1 is the expected
  output, so a token drifting is a red test rather than a discovery.
- **`app/test/design/series_palette_cvd_test.dart`** — the validator §14.6.3 requires, committed so
  the numbers in `series_palette.dart`'s doc comment are regenerable. It does not exist today
  **[K]**, which is the single largest gap in the palette's story.
</content>
