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