# N3 — Design system

**Goal:** the token set and the reusable component primitives every screen
composes. Stateless over plain values; no repository access. This is where the
prototype's `styles.css` becomes a Flutter `ThemeExtension` + a widget library.

**Design:** [`newui/styles.css`](../styles.css) (tokens + every component) ·
[`newui/app.js`](../app.js) §3 (SVG/icon helpers) · `newui/NOTES.md` §3.6–§3.7, §8
· `newui/components_research_notes.md` §9–§10.

---

## Invariants this epic must encode

| Rule | Where |
|---|---|
| Series hue (P1 ember/P2 violet/P3 green/P4 blue) is a **mark** only; identity is hue + stroke pattern + glyph | `SeriesPalette`, `LegendSwatch` |
| Status hue is **chrome** only; always icon **and** word | `StatusPalette`, `InsightBanner` |
| Green = transport health only; "target reached" closes the ring, never green | `TargetGauge` |
| One ember primary action per screen (I14) | `PrimaryAction` |
| No dead controls (I5): disabled controls state their reason | `ActionRow`, `SettingsRow` |
| 4 dp spacing scale ("a 6 or a 10 is a bug") | `SmokeSpacing` |

## 3.1 Tokens & theme

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N3.1 | `SmokeTokens` ThemeExtension: 6 surfaces, 3 lines, 4 inks, one elevation + glow, radii 20/14/8/999, 4 dp spacing | N0.7 | H | `styles.css` `:root` |
| N3.2 | Dark token set (default) matching the prototype hexes | N3.1 | H | NOTES §8 |
| N3.3 | **Light** token set with weightier series hues for legibility on white | N3.1 | H | `styles.css` `theme-light` |
| N3.4 | `daylight` **contrast profile** layered on either theme (lifted ink, thicker hairlines, no shadow/glow) | N3.1 | H | NOTES §2.1 |
| N3.5 | `themeMode` (system/light/dark) + `density` (compact/comfortable) applied at the app root | N3.2, N3.3 | W | `app.js` applyBodyClasses |
| N3.6 | `--*-rgb` companions so every tint is `rgba(var(--x-rgb), a)` and retints with the theme | N3.1 | H | NOTES §8 |
| N3.7 | Motion tokens (`quick 120`, `standard 220`, `value 600`, `gauge 800`, `pulse 2s`); **no `Duration` literal outside design/** (layering test) | N3.1 | H | research notes §9.4 |
| N3.8 | `reducedMotion` zeroes all but `pulse` (the pulse stopping *is* the staleness signal) | N3.7 | W | research notes §9.4 |

## 3.2 Typography & icons

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N3.9 | `SmokeText` scale: `heroTemp` 96 → `labelSm` 11, `monoKey`; tabular figures on numeric styles | N0.5 | W | research notes §9.2 |
| N3.10 | `SmokeTextScale` reflow ladder: gauge 84→64 at 1.3×; above that hero demotes to 56. **A temperature is never scaled to fit.** | N3.9 | W | research notes §9.2 |
| N3.11 | Icon set: port the prototype's ~80 inline SVG paths to a Flutter `SmokeIcon` set (or `lucide` equivalent) | N3.9 | W | `app.js` ICON_PATHS |
| N3.12 | `FoodAvatar` identity discs (13 glyphs, two registers: disciplined/vivid); never encodes state | N3.1 | W | `app.js` foodAvatar, research notes §9.3 |

## 3.3 Component primitives

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N3.13 | `SmokeCard` (accent, spine, raised, inset, onTap, footer) — the one container | N3.1 | W | `styles.css` `.card` |
| N3.14 | `PrimaryAction` (the only ember-filled button; busy spinner; one per screen) + `SmokeButton` (ghost/danger/sm) | N3.13 | W | research notes I14 |
| N3.15 | `SegmentedChips` + `FilterChips` single-select rows (°F/°C, ranges, saver) | N3.13 | W | `app.js` `.seg`, `.seg-chips` |
| N3.16 | `SmokeToggle` | N3.13 | W | `styles.css` `.toggle` |
| N3.17 | `SettingsRow` (icon, name, sub, trailing, disabled-with-reason) | N3.16 | W | `app.js` setRow, I5 |
| N3.18 | `LinkRow` (transport/health row with signal bars) + `SignalBars` (neutral, never a status hue) | N3.13 | W | `app.js` signalBars |
| N3.19 | `JackBadge`, `TargetPill`, `TrendChip`, `ModeBadge`, `TierTag` (Device/Insight) atoms | N3.13 | W | `app.js` §6 |
| N3.20 | `PulseDot` (7 dp liveness; hollow when not live) + `TransportChip` (link pill with pulse + two radio dots) | N3.18, N3.19 | W | `app.js` linkInfo |
| N3.21 | `Sparkline` (tiny straight-segment recent line) + `TargetGauge` (84 dp sweep/band) + `PhaseTrack` (4-segment, position by height not hue) | N3.13 | W | `app.js` sparkline/gauge/phaseTrack |
| N3.22 | `InsightBanner` / `CapabilityNotice` (icon + word, hue on chrome only, text always `textHi`) | N3.13 | W | `app.js` `.cap-notice` |
| N3.23 | `AlarmBar` (highest-severity unacked, inline acknowledge, role haptic) | N3.19, N3.22 | W | `app.js` alarmStrips |
| N3.24 | `MonoWell` (deepest surface, mono type, tap-to-copy for passkey/AP PSK) | N3.13 | W | `app.js` `.mono-well` |
| N3.25 | `EmptyState` / `ProblemState` / `LoadingState` (each exactly one action) | N3.13 | W | `app.js` emptyState, I6 |
| N3.26 | `StaleVeil` (desaturate + dim + pin age label; no double-dimming) | N3.20 | W | research notes §10 |
| N3.27 | `StatGrid` / `RecapRow` / `StatMini` | N3.13 | W | `app.js` §6 |
| N3.28 | `SeriesLegend` (glyph + stroke swatch + name + value; tap-to-isolate) — currently unwired in legacy, wire it here | N3.21 | W | `app.js` legendSwatch |
| N3.29 | Haptic map: selection/advisory/confirm/warning/critical; critical is the only two-event pattern; positive/pit silent | N3.13 | W | research notes §9.4 |
| N3.30 | `CostSheet` / `showCostSheet`: destructive confirm with keeps / loses and named buttons | N3.14, N3.22 | W | research notes I8 |

## Exit gate

A component gallery screen renders every primitive in all three theme
combinations (dark/light/daylight) × both densities, with goldens. No screen
introduces a raw colour or a `Duration` literal.

## Must-not-regress

The three colour channels (series/status/identity), I14, I5, and "temperature is
never scaled to fit".

---

## Hand-off

**Landed.** N3.1–N3.30, all 30 sub-tasks. `app/lib/design/` now holds the token
set (`SmokeTokens` ThemeExtension + dark/light/daylight + density), `SmokeMotion`
(quick/standard/value/gauge/pulse, reduced-motion rule), `SmokeText` +
`SmokeTextScale`, the `SmokeGlyph`/`SmokeIcon` set, `FoodAvatar`, and every
component primitive through `CostSheet`. The barrel is
`package:smoke_bridge/design/design.dart`; `DesignGallery` is mounted at
`/design`.

**Verification (real commands, run in `app/`).**
- `flutter analyze` → `No issues found!`
- `dart format --output=none --set-exit-if-changed lib test` → clean
- `flutter test` → `All tests passed!` (**201**; was 152)
- `dart test test/domain test/data` → **131** pass (N2 gate intact)
- `flutter test test/design` → **44** pass (tokens, icons, primitives, layering)
- `flutter test test/golden/design_gallery_golden_test.dart` → **6** gallery
  goldens (dark/light/daylight × compact/comfortable)

**Deviations from the plan, and why.**
1. **Icons are mapped to Material glyphs, not the prototype's SVG paths.**
   Flutter's SDK has no SVG path renderer and N0 pinned the package set (no
   `flutter_svg`). The load-bearing contract is the icon *name* (`SmokeGlyph`,
   67 of them); `SmokeIcons.data` maps each name to its closest Material glyph
   and `SmokeIcons.byName` keeps prototype-name parity. The artwork is now a
   one-file swap.
2. **`FoodGlyph` has 21 identities, not 13.** The generated catalog uses 18
   food glyphs plus `ambient`/`pit`/`unstated`; the research notes' "13" is
   stale (same class of error as T03's counts).
3. **PulseDot is stateless and the ticker is deferred to N4.** A repeating
   controller at the app root makes `pumpAndSettle` unusable for every golden,
   and `lib/design/` must stay stateless. `SmokePulseScope` is the seam: the
   shell owns one controller and every dot reads it. Without a scope the dot is
   static; a test proves the wiring. Reduced motion keeps the pulse (the still
   dot is the staleness signal).
4. **`SmokeApp` defaults to `ThemeMode.system`** (was hard-coded dark) and takes
   `profile`/`density`/`reducedMotion`, satisfying N3.5 at the root; N4 supplies
   the `AppSettings` values.
5. **Golden harness extended** with `pumpForGolden(..., settle: false)` because
   the gallery intentionally renders a spinner and a loading state. Existing
   callers are unchanged.
6. **The three colour channels are enforced by tests, not convention:**
   `primitives_test.dart` pins "status banner = icon + word", "gauge reached is
   never green", "identity stops never reuse a status hue", I3/I5/I6/I14,
   no-double-dimming, and the haptic map. `design_layering_test.dart` pins "no
   raw colour or `Duration` literal outside `lib/design/`".

**What the next task (N4 shell) must know.**
- Mount one repeating `AnimationController` (`SmokeMotion.pulse`) in a
  `SmokePulseScope` beside the shell chrome; otherwise PulseDot is static.
- Pass `AppSettings.themeMode/displayProfile/density/reducedMotion` through
  `SmokeApp` (or build `SmokeThemeData` directly).
- Read tokens with `SmokeTokens.of(context)` and motion with
  `SmokeMotion.of(context)`; do not write `Color(...)` or `Duration(...)` in
  `lib/features/`.
- `showCostSheet` resolves `true` on confirm; `PrimaryAction` is the only ember
  button and a screen may have one (the gallery is the deliberate exception).
- `/design` is a live route; N16 may gate it behind a debug flag.
- Not done here (other tasks): N7 wires `SeriesLegend.onIsolate` to the chart;
  N5/N6 wire `TargetGauge`/`Sparkline`/`PhaseTrack` to real projections.