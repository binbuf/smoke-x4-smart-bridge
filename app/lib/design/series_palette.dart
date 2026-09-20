/// A19.3 — the series palette (design 14 §14.6.2).
///
/// Ported from `app/lib/app/palette.dart` (A10.2) **with the four dark hues
/// unchanged**. An earlier draft retuned them on the theory that they were
/// validated against `#0D0F12` and the shipping background is now `#07090E`.
/// Measured, that argument inverts: contrast is the *only* background-dependent
/// term in the validation, and moving the surface darker lifted every slot's
/// contrast (§14.6.2). Adjacent CVD ΔE and adjacent normal ΔE are pair
/// comparisons between two series hues and do not move when the surface moves.
/// So the surface change alone invalidated nothing, and the hues move here
/// byte-for-byte.
///
/// ## What was decided, and why (carried from A10.2, still true)
///
/// **Colour follows the probe, never its role.** Probe 1 is orange whether
/// the user calls it the pit or the point. Re-roling a probe mid-cook must not
/// repaint the history behind it, and the OLED can only identify a probe by its
/// number. Role carries its weight through *form*: the pit is the reference
/// series (heaviest stroke, the alarm band, the target line).
///
/// **Identity does not rest on hue.** Each probe owns a stroke pattern — P1
/// solid, P2 dashed, P3 dotted, P4 dash-dot — which survives a monochrome
/// export, a photocopy, and the SSD1306.
///
/// **Yellow and red are excluded from the series set on purpose.** They are the
/// status hues; a series wearing one would impersonate an alarm.
///
/// ## Measurements
///
/// The dark hues, on the surface each is actually drawn on. The `card` column
/// is new (§14.6.2); it is the surface `SmokeCard` and therefore the chart
/// uses, so it is the one the validator now checks against:
///
/// | slot     | hue       | on `bg #07090E` | on `card #161C2A` |
/// | -------- | --------- | --------------- | ----------------- |
/// | P1 ember | `#D95926` | 5.13            | 4.38              |
/// | P2 violet| `#9085E9` | 6.37            | 5.45              |
/// | P3 green | `#008300` | 4.03            | 3.44              |
/// | P4 blue  | `#3987E5` | 5.47            | 4.68              |
///
/// All ≥ 3:1 on both. The ordering (all 24 permutations run through the
/// validator) maximises the minimum adjacent CVD ΔE at 26.0 dark, with ember
/// pinned to slot 1. The **light** values below are retained as the export /
/// print palette — CSV plots and share images render on paper-white, not on
/// the app's obsidian — and are not used in-app.
///
/// ## Standing obligation on any future retune (§14.6.3)
///
/// 1. No hue ships that has not been through the validator — committed as
///    `app/test/design/series_channels_test.dart`, which is the file §14.6.3
///    asks for under the working name `series_palette_cvd_test.dart` — run
///    against `card`, on the adjacent pairlist, plus the status hues.
/// 2. Paste the measured table here; a hue whose measurements are not beside
///    it is not reviewable.
/// 3. The floor is the current dark adjacent-CVD ΔE of 26.0. If a pair drops
///    below it: permute the four slots (ember pinned → 6 orderings) first, then
///    re-step lightness, and only then change a family.
/// 4. Never lower the floor — the same rule the repo applies to the heap gate.
///
/// **Nothing below retunes a hue.** [SeriesFill] and [dim] added named alphas
/// so that the chart stopped hand-rolling them; every `Color` constant in this
/// file is byte-for-byte what the validator last measured.
library;

import 'package:flutter/material.dart';

import '../domain/entities/entities.dart';
import 'tokens.dart';

/// The **shape** channel: one glyph per slot, so a series can be named without
/// naming a colour (§14.10, newapp §H.2).
///
/// Hue alone was never sufficient here, and measurement says so rather than
/// taste. Relative luminance of the four dark hues on `bg #07090E`, derived
/// from the contrast figures in the table above:
///
/// | slot | hue | L |
/// | --- | --- | --- |
/// | P3 green | `#008300` | 0.162 |
/// | P1 ember | `#D95926` | 0.220 |
/// | P4 blue | `#3987E5` | 0.238 |
/// | P2 violet | `#9085E9` | 0.286 |
///
/// **P1 and P4 are 0.018 apart.** Printed in monochrome, or seen by a
/// deuteranope, ember and blue are near enough the same grey that luminance
/// cannot separate them — which is precisely why the stroke pattern has
/// existed since A10.2 and why a *legend* now needs a mark it can draw at
/// 12 dp, where a dash pattern is illegible. Hence the glyph.
///
/// The four shapes are chosen to survive both a 12 dp render and a 1-bit
/// display: a disc has no corners, a square has four, a triangle has three and
/// one flat edge, a diamond has four corners rotated 45°. No two share a
/// silhouette. Each also has a [SeriesGlyph.label] because a shape alone is
/// exactly as bad as a hue alone for a screen reader (§14.10).
enum SeriesGlyph {
  disc('circle', Icons.circle),
  square('square', Icons.square_rounded),
  triangle('triangle', Icons.change_history_rounded),
  diamond('diamond', Icons.diamond_rounded);

  const SeriesGlyph(this.label, this.icon);

  /// Speakable. Read by the legend's semantics and by the goldens, so a
  /// channel disappearing is a text diff rather than a rendering discovery.
  final String label;

  final IconData icon;
}

/// The **complete** list of places a series hue is allowed to fill a shape,
/// and the alpha each fills at (design 14 §14.6.1, 16 §16.5, 17 §17.2).
///
/// An enum rather than a `double` parameter on purpose. §16.5's colour rule is
/// the one the spine itself calls *"the most-broken rule"*, and the way it
/// breaks is never a manifesto — it is a `withValues(alpha: 0.18)` typed at the
/// call site because 16 % looked a little thin that afternoon. A named set of
/// three means the sanctioned exception is a list a reviewer can read to the
/// end, and a fourth fill is a diff to *this* file rather than a number nobody
/// notices in a renderer.
///
/// The audit that produced this found three hand-rolled alphas in
/// `cook_chart.dart` — `0.18` twice for the min/max envelope and `0.08` for the
/// pit's alarm band — none of which went through [ProbePalette.tint]. The
/// envelope's 18 % was over §17.2's stated 16 % ceiling; folding it in here is
/// what brought it back under.
///
/// **16 % is the ceiling, and it is a ceiling on the composite.** Two fills of
/// the same series stacked over one region read as 26 %, not 16 %, so the
/// renderer draws exactly one fill per series: [envelope] where the window is
/// wide enough to have one, [area] otherwise. [band] is the pit's alarm range,
/// drawn *behind* every series and bounded above and below by two rules, which
/// is why it is half strength — it has to be readable through whatever crosses
/// it.
enum SeriesFill {
  /// §17.2's second sanctioned extension: the area under a series stroke, the
  /// `FireBoard-1` pattern. Drawn per **run**, never across a gap — a filled
  /// slab bridging a 30-minute dropout would be the exact lie the run-splitting
  /// exists to prevent.
  area(0.16),

  /// The min/max band behind a decimated series (08 §8.7), which makes an
  /// excursion visible as a *widening* where the mean line has been smoothed
  /// flat. Where this is drawn, [area] is not: the band already is the fill.
  envelope(0.16),

  /// The pit's alarm min/max range. The one fill that predates §17.2 and the
  /// only one that is not "under a line".
  band(0.08);

  const SeriesFill(this.alpha);

  /// Never above 0.16 (§17.2). Pinned by `series_channels_test.dart`.
  final double alpha;
}

/// How a probe's series is drawn: a hue plus a colour-free stroke.
class ProbeStyle {
  const ProbeStyle({
    required this.probe,
    required this.color,
    required this.dashArray,
    required this.strokeWidth,
  });

  /// 1..4 — the physical jack. The identity this style belongs to.
  final int probe;
  final Color color;

  /// Null for a solid line. `[on, off, …]`, in logical pixels — the same
  /// language `fl_chart`, an SVG export, and the OLED all speak.
  final List<int>? dashArray;
  final double strokeWidth;

  /// A short, speakable name for the stroke — goldens and semantics read this,
  /// so a colour change is reviewable in text.
  String get strokeName => switch (dashArray) {
    null => 'solid',
    [8, 4] => 'dashed',
    [2, 5] => 'dotted',
    _ => 'dash-dot',
  };

  /// The legend's mark. Derived from the jack rather than stored, for the same
  /// reason the hue is: re-roling a probe mid-cook must not repaint the
  /// history behind it.
  SeriesGlyph get glyph => ProbePalette.glyphFor(probe);

  /// "Probe 2, violet, dashed, square" — everything that identifies this
  /// series, in the order a reader needs it, with the colour word present but
  /// never load-bearing.
  String describe(String name) =>
      '$name, ${glyph.label}, $strokeName line';
}

/// The four probe slots, in fixed order, plus the chart's ink.
///
/// Slots are **never cycled**: there is no fifth probe, and if there ever were
/// it would not be a generated hue.
abstract final class ProbePalette {
  // Slot 1 — ember/orange. The pit's conventional jack.
  static const Color _orangeLight = Color(0xFFEB6834);
  static const Color _orangeDark = Color(0xFFD95926);
  // Slot 2 — violet.
  static const Color _violetLight = Color(0xFF4A3AA7);
  static const Color _violetDark = Color(0xFF9085E9);
  // Slot 3 — green (mode-invariant; clears 3:1 on both surfaces).
  static const Color _green = Color(0xFF008300);
  // Slot 4 — blue.
  static const Color _blueLight = Color(0xFF2A78D6);
  static const Color _blueDark = Color(0xFF3987E5);

  /// The dark hues in slot order, for the validator and for direct reads.
  static const List<Color> dark = [_orangeDark, _violetDark, _green, _blueDark];

  /// P1 solid, P2 dashed, P3 dotted, P4 dash-dot. Ordered by ink laid down, so
  /// the reference series is the strongest mark.
  static const List<List<int>?> strokes = [
    null,
    [8, 4],
    [2, 5],
    [10, 4, 2, 4],
  ];

  /// P1 disc, P2 square, P3 triangle, P4 diamond. The **third** identity
  /// channel, after the hue and the stroke pattern, and the only one of the
  /// three that is legible at 12 dp — which is the size a legend entry, a
  /// probe-row swatch and a crosshair dot are actually drawn at.
  static const List<SeriesGlyph> glyphs = [
    SeriesGlyph.disc,
    SeriesGlyph.square,
    SeriesGlyph.triangle,
    SeriesGlyph.diamond,
  ];

  /// The hue for [probe] (1..4), dark surface. The mark colour, nothing else.
  static Color hue(int probe) => dark[(probe - 1).clamp(0, 3)];

  /// The glyph for [probe] (1..4).
  static SeriesGlyph glyphFor(int probe) => glyphs[(probe - 1).clamp(0, 3)];

  /// The **only** sanctioned fill of a series hue, at one of [SeriesFill]'s
  /// three strengths. A series hue may otherwise appear only as a mark — a
  /// stroke, an arc, a ≤12 dp dot, a card's left rule — never as a filled shape
  /// and never carrying a word (the separation rule, [StatusPalette]).
  ///
  /// Default [SeriesFill.area], because that is now the common case: every
  /// series on the chart carries one, and the gauge track and the pit band
  /// name their strength explicitly.
  static Color tint(Color c, [SeriesFill fill = SeriesFill.area]) =>
      c.withValues(alpha: fill.alpha);

  /// A series **mark** at reduced ink: 45 % of the hue.
  ///
  /// Not a fill, and therefore not bound by [SeriesFill]'s 16 % ceiling — it is
  /// the same 2 dp stroke, the same 12 dp glyph, drawn quieter. Two things
  /// spend it, and they must spend the *same* number or the chart and its key
  /// disagree about which series is speaking:
  ///
  ///  * the strokes of every series that is **not** the isolated channel, while
  ///    one channel is isolated (17 §17.3 D);
  ///  * a legend entry or crosshair row for a series that is not drawing —
  ///    dimmed, never removed, because a series that vanishes when it is
  ///    unplugged takes its identity with it and the rows below appear to
  ///    change jack.
  ///
  /// 45 % rather than something quieter because the point of a de-emphasised
  /// series is that it is still *there*: isolating the pit to read it against
  /// nothing is a worse chart, not a better one.
  static Color dim(Color c) => c.withValues(alpha: dimAlpha);

  /// The one de-emphasis level. See [dim].
  static const double dimAlpha = 0.45;

  /// The style for [probe] (1..4) under [brightness]. [role] does not pick the
  /// hue — it only decides the weight, because the pit is the reference series.
  static ProbeStyle styleFor(
    int probe,
    Brightness brightness, {
    ProbeRole role = ProbeRole.unused,
  }) {
    final isDark = brightness == Brightness.dark;
    final i = (probe - 1).clamp(0, 3);
    final color = switch (i) {
      0 => isDark ? _orangeDark : _orangeLight,
      1 => isDark ? _violetDark : _violetLight,
      2 => _green,
      _ => isDark ? _blueDark : _blueLight,
    };
    return ProbeStyle(
      probe: probe,
      color: color,
      dashArray: strokes[i],
      strokeWidth: role == ProbeRole.pit ? 3 : 2,
    );
  }

  // ── Chart chrome ────────────────────────────────────────────────────
  //
  // These three used to hold their own warm-grey ramp — `#2C2C2A` grid,
  // `#898781` axis, `#4A4A47` gap connector — keyed off `Brightness`. Both
  // halves of that were wrong, and an audit found the chart was the last file
  // in the app not on the design system because of it:
  //
  //  * **the ramp.** §14.6.5 moved the app's last warm neutral (`info`, then
  //    `#898781` — literally this axis ink) onto the slate ramp, because
  //    "carrying two neutral ramps for one enum value is not a decision anyone
  //    would defend". The chart kept carrying it for three more milestones.
  //  * **the key.** The app ships one `Brightness` (§14.3.3: there is no light
  //    theme; `daylight` is a *contrast* profile over the same dark surfaces),
  //    so the light branches here were unreachable and `axisInk` ignored its
  //    argument outright — which meant the daylight profile, the one that lifts
  //    ink for a phone in direct sun, reached every screen in the app **except
  //    the chart**.
  //
  // Keyed off [SmokeTokens] instead, they are three lines of indirection that
  // earn their place: chart chrome stays nameable in one spot, and it now moves
  // with the profile. The names are kept so the call sites still read as chart
  // vocabulary rather than as a grab at a generic ink.

  /// The gridlines. Recessive by rule — the grid must never compete with the
  /// data, which is exactly what `hairline` is for.
  static Color grid(SmokeTokens t) => t.hairline;

  /// Axis ticks and timestamps. `textMuted` is the token's own stated job.
  static Color axisInk(SmokeTokens t) => t.textMuted;

  /// The gap connector: a dotted hint that time passed, drawn in chrome ink
  /// rather than in the series colour so it can never be mistaken for data
  /// ("a 30-minute dropout must look like a 30-minute dropout"). `chromeDim`
  /// is the token reserved for non-text rules for this reason — it does not
  /// clear 4.5:1 anywhere, so it may never carry a word.
  static Color gapInk(SmokeTokens t) => t.chromeDim;
}
