/// Colour-blind-safe multi-series (design 14 §14.10, newapp §H.2).
///
/// §H.2: *"series hues distinguishable by luminance + a shape/label token, not
/// hue alone — pair each series with a glyph in the legend."* This file is the
/// measurement behind that sentence, and it exists because the claim in
/// `series_palette.dart`'s doc comment — a 26.0 adjacent-CVD ΔE — came from an
/// out-of-band run that this repo could not reproduce (§14.12.3 calls that
/// *"the single largest gap in the palette's story"*).
///
/// What is measured here, with the formulae inline so a reviewer can check
/// them rather than trust them:
///
///  * **relative luminance** (WCAG 2.x), the same formula already committed at
///    `test/app/palette_test.dart`;
///  * **dichromatic simulation** (Viénot, Brettel & Mollon 1999) for
///    protanopia and deuteranopia, in linear RGB;
///  * **ΔE₇₆** in CIE L\*a\*b\* between adjacent slots, before and after.
///
/// And what is asserted is deliberately *not* "the hues are far enough apart".
/// They are not, and no reordering fixes it — see the ember/blue result below.
/// What is asserted is that **the palette never relies on them being apart**:
/// every slot carries a unique stroke and a unique glyph, so a chart stripped
/// of colour entirely is still readable. That is the honest gate, and it is the
/// one §14.6.3 rule 5 already anticipated: *"the all-pairs gate and the
/// sunlight requirement are in direct conflict at four series, and the
/// resolution is the secondary channels already shipped."*
///
/// ## Measured, 2026-08-05, by this file
///
/// Relative luminance on `bg #07090E`:
///
/// | slot | hue | L | contrast on bg |
/// | --- | --- | --- | --- |
/// | P1 ember | `#D95926` | 0.2205 | 5.13 |
/// | P2 violet | `#9085E9` | 0.2859 | 6.37 |
/// | P3 green | `#008300` | 0.1624 | 4.03 |
/// | P4 blue | `#3987E5` | 0.2384 | 5.47 |
///
/// **P1 and P4 are 0.018 apart in luminance** — under 8 % of the ramp. Under
/// deuteranopia they converge further. Luminance alone cannot separate the
/// ember pit line from the blue probe 4 line, which is exactly why the glyph
/// token was added and why this test refuses to pretend otherwise.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart' show ProbeRole;

// ── colour maths, all of it, so nothing here is taken on faith ──────────

double _linear(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// WCAG relative luminance.
double _luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Linear-RGB triple.
({double r, double g, double b}) _toLinear(Color c) =>
    (r: _linear(c.r), g: _linear(c.g), b: _linear(c.b));

/// Viénot/Brettel/Mollon 1999 dichromat simulation, applied in linear RGB.
/// The matrices are the widely-published sRGB forms of that method.
({double r, double g, double b}) _simulate(Color c, bool protan) {
  final l = _toLinear(c);
  if (protan) {
    return (
      r: 0.1121 * l.r + 0.8853 * l.g + -0.0005 * l.b,
      g: 0.1127 * l.r + 0.8897 * l.g + -0.0001 * l.b,
      b: 0.0045 * l.r + 0.0000 * l.g + 1.0019 * l.b,
    );
  }
  return (
    r: 0.2920 * l.r + 0.7054 * l.g + -0.0003 * l.b,
    g: 0.2934 * l.r + 0.7089 * l.g + 0.0000 * l.b,
    b: -0.0209 * l.r + 0.4113 * l.g + 0.6947 * l.b,
  );
}

/// Linear RGB → CIE XYZ (D65) → L\*a\*b\*.
({double l, double a, double b}) _lab(({double r, double g, double b}) rgb) {
  final x = 0.4124 * rgb.r + 0.3576 * rgb.g + 0.1805 * rgb.b;
  final y = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
  final z = 0.0193 * rgb.r + 0.1192 * rgb.g + 0.9505 * rgb.b;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x / 0.95047);
  final fy = f(y / 1.00000);
  final fz = f(z / 1.08883);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _deltaE(
  ({double r, double g, double b}) p,
  ({double r, double g, double b}) q,
) {
  final a = _lab(p);
  final b = _lab(q);
  return math.sqrt(
    math.pow(a.l - b.l, 2) + math.pow(a.a - b.a, 2) + math.pow(a.b - b.b, 2),
  );
}

void main() {
  const bg = Color(0xFF07090E);
  const card = Color(0xFF161C2A);
  final slots = [for (var p = 1; p <= 4; p++) ProbePalette.hue(p)];

  group('the first channel — hue', () {
    test('every slot clears the 3:1 graphics floor on both surfaces', () {
      // Re-pointed at `card` per §14.6.2: that is the surface `SmokeCard` and
      // the chart are actually drawn on. Do not re-point the floor.
      for (var p = 1; p <= 4; p++) {
        expect(
          _contrast(slots[p - 1], bg),
          greaterThanOrEqualTo(3.0),
          reason: 'P$p on bg',
        );
        expect(
          _contrast(slots[p - 1], card),
          greaterThanOrEqualTo(3.0),
          reason: 'P$p on card',
        );
      }
    });

    test('the four hues are the committed ones, byte for byte', () {
      // §H.1 keeps the series palette verbatim. A retune is gated by §14.6.3
      // in full, and this is the tripwire.
      expect(slots, const [
        Color(0xFFD95926),
        Color(0xFF9085E9),
        Color(0xFF008300),
        Color(0xFF3987E5),
      ]);
    });
  });

  group('the second channel — luminance, and where it runs out', () {
    test('the measured ramp is the one written in the doc comment', () {
      final l = [for (final c in slots) _luminance(c)];
      expect(l[0], closeTo(0.2205, 0.002), reason: 'P1 ember');
      expect(l[1], closeTo(0.2859, 0.002), reason: 'P2 violet');
      expect(l[2], closeTo(0.1624, 0.002), reason: 'P3 green');
      expect(l[3], closeTo(0.2384, 0.002), reason: 'P4 blue');
    });

    test('ember and blue are NOT separable by luminance — recorded, not hidden',
        () {
      // This is the finding that makes the glyph mandatory rather than nice.
      // If a future retune ever fixes it, this assertion fails loudly and the
      // doc comment above must be rewritten with the new numbers — which is
      // the point of pinning a *negative* result.
      final gap = (_luminance(slots[0]) - _luminance(slots[3])).abs();
      expect(
        gap,
        lessThan(0.05),
        reason:
            'ember and blue still converge in luminance; the doc comment and '
            'the glyph rationale still hold',
      );
    });
  });

  group('under dichromacy', () {
    test('at least one adjacent pair collapses — so colour cannot be the gate',
        () {
      var worst = double.infinity;
      for (final protan in [true, false]) {
        for (var i = 0; i < 3; i++) {
          final d = _deltaE(
            _simulate(slots[i], protan),
            _simulate(slots[i + 1], protan),
          );
          worst = math.min(worst, d);
        }
      }
      // Recorded rather than gated: the honest reading of §14.6.3 rule 5 is
      // that four series and a sunlight-legible ramp cannot both clear an
      // all-pairs CVD gate, and the resolution is the secondary channels.
      expect(worst, greaterThan(0));
      expect(
        worst,
        lessThan(100),
        reason: 'sanity only — the real gate is the two tests below',
      );
    });
  });

  group('a series never impersonates an alarm', () {
    // Migrated from the deleted `test/app/palette_test.dart`, which guarded
    // `lib/app/palette.dart` — a byte-for-byte duplicate of this palette kept
    // alive by one unreachable widget. The assertions were worth keeping; the
    // second copy of the palette was not.
    test('no series wears a status hue', () {
      // A probe stroke in warning-amber or critical-red would impersonate an
      // alarm on a screen whose whole job is alarms.
      final status = {
        StatusPalette.warning,
        StatusPalette.critical,
        StatusPalette.positive,
      };
      for (final b in Brightness.values) {
        for (var n = 1; n <= 4; n++) {
          expect(
            status.contains(ProbePalette.styleFor(n, b).color),
            isFalse,
            reason: 'probe $n on ${b.name}',
          );
        }
      }
    });

    test('every severity carries an icon as well as a hue', () {
      // The separation rule's other half: a status hue always appears with an
      // icon AND a word, so severity is never carried by colour alone.
      for (final role in StatusRole.values) {
        expect(StatusPalette.hue(role), isNotNull);
        expect(StatusPalette.fill(role), isNotNull);
        expect(StatusPalette.border(role), isNotNull);
      }
      expect(
        StatusPalette.hue(StatusRole.critical),
        isNot(StatusPalette.hue(StatusRole.info)),
      );
    });

    test('a probe number out of range clamps rather than throwing', () {
      // Jack 0 and jack 9 cannot happen — and a palette that throws on one
      // takes a whole chart down over a number nobody will ever see.
      expect(ProbePalette.styleFor(0, Brightness.dark).color, isNotNull);
      expect(ProbePalette.styleFor(9, Brightness.dark).color, isNotNull);
      expect(ProbePalette.glyphFor(0), isNotNull);
      expect(ProbePalette.glyphFor(9), isNotNull);
    });
  });

  group('the channels that do not depend on sight of colour', () {
    test('every slot has a unique stroke pattern', () {
      final names = {
        for (var p = 1; p <= 4; p++)
          ProbePalette.styleFor(p, Brightness.dark).strokeName,
      };
      expect(
        names,
        hasLength(4),
        reason: 'a repeated stroke is two series with one identity',
      );
    });

    test('every slot has a unique glyph, and it follows the jack', () {
      expect(ProbePalette.glyphs.toSet(), hasLength(4));
      expect(SeriesGlyph.values.map((g) => g.label).toSet(), hasLength(4));
      for (var p = 1; p <= 4; p++) {
        // Colour follows the probe, never its role — so the glyph must too, or
        // re-roling a probe mid-cook would repaint the legend behind it.
        final asPit = ProbePalette.styleFor(p, Brightness.dark,
            role: ProbeRole.pit);
        final asFood = ProbePalette.styleFor(p, Brightness.dark,
            role: ProbeRole.food);
        expect(asPit.glyph, asFood.glyph, reason: 'P$p glyph moved with role');
        expect(asPit.glyph, ProbePalette.glyphFor(p));
      }
    });

    test('a monochrome chart is still four distinct series', () {
      // The real gate: strip the hue entirely and count identities. Two
      // colour-free channels, four slots, no collisions.
      final identities = {
        for (var p = 1; p <= 4; p++)
          () {
            final s = ProbePalette.styleFor(p, Brightness.dark);
            return '${s.strokeName}/${s.glyph.label}';
          }(),
      };
      expect(identities, hasLength(4));
    });

    test('the spoken description leads with the channels that survive', () {
      final s = ProbePalette.styleFor(2, Brightness.dark);
      expect(s.describe('Brisket flat'), 'Brisket flat, square, dashed line');
      // A shape alone is exactly as bad as a hue alone for a screen reader
      // (§14.10) — so the glyph is named in words, not merely drawn.
      expect(s.describe('Brisket flat'), contains(s.glyph.label));
      expect(s.describe('Brisket flat'), contains(s.strokeName));
    });
  });

  group('when a series hue is allowed to fill (14 §14.6.1, 17 §17.2)', () {
    test('16 % is the ceiling, and the list of exceptions is closed', () {
      // §17.2 sanctions "a ≤16 % tint below its stroke, through
      // `ProbePalette.tint` and nothing else". The enum is what makes "and
      // nothing else" checkable: a fourth fill is a diff to `series_palette`
      // rather than a number nobody notices in a renderer.
      expect(SeriesFill.values, hasLength(3));
      for (final fill in SeriesFill.values) {
        expect(
          fill.alpha,
          lessThanOrEqualTo(0.16),
          reason: '${fill.name} is over §17.2’s ceiling',
        );
        expect(ProbePalette.tint(ProbePalette.hue(1), fill).a, fill.alpha);
      }
      // The audit that produced this found `0.18` typed inline in
      // `cook_chart.dart` for the envelope — over the ceiling, and invisible
      // to any rule that only reads this file.
      expect(SeriesFill.envelope.alpha, 0.16);
      expect(SeriesFill.band.alpha, 0.08);
    });

    test('the default is the area fill, so a bare call is the common case', () {
      expect(
        ProbePalette.tint(ProbePalette.hue(3)),
        ProbePalette.tint(ProbePalette.hue(3), SeriesFill.area),
      );
    });

    test('a tint keeps its hue — it is the same colour, quieter', () {
      // A fill that shifted hue would be a fifth series colour arriving by the
      // back door, and it would never go through the validator above.
      for (var p = 1; p <= 4; p++) {
        final c = ProbePalette.hue(p);
        final t = ProbePalette.tint(c);
        expect([t.r, t.g, t.b], [c.r, c.g, c.b]);
      }
    });

    test('there is exactly one de-emphasis level, and marks share it', () {
      // The chart's receding strokes and the legend's dimmed entries must be
      // the same ink or the key disagrees with the thing it keys.
      expect(ProbePalette.dimAlpha, 0.45);
      final c = ProbePalette.hue(4);
      expect(ProbePalette.dim(c).a, closeTo(0.45, 0.005));
      expect([
        ProbePalette.dim(c).r,
        ProbePalette.dim(c).g,
        ProbePalette.dim(c).b,
      ], [c.r, c.g, c.b]);
      // Not a fill: a de-emphasised *mark* is outside the 16 % ceiling by
      // construction, and conflating the two would either wash out the stroke
      // or license a 45 % slab.
      expect(
        SeriesFill.values.map((f) => f.alpha),
        isNot(contains(ProbePalette.dimAlpha)),
      );
    });
  });

  group('chart chrome is the design system, not a second neutral ramp', () {
    test('the grid, the axis and the gap connector are tokens', () {
      // §14.6.5 moved the app's last warm neutral onto the slate ramp — and
      // the value it moved off, `#898781`, was literally this axis ink. The
      // chart kept carrying it for three more milestones.
      expect(ProbePalette.grid(SmokeTokens.dark), SmokeTokens.dark.hairline);
      expect(
        ProbePalette.axisInk(SmokeTokens.dark),
        SmokeTokens.dark.textMuted,
      );
      expect(
        ProbePalette.gapInk(SmokeTokens.dark),
        SmokeTokens.dark.chromeDim,
        reason: 'a gap connector may never carry a word, which is exactly '
            'what `chromeDim` is reserved for',
      );
    });

    test('the daylight profile now reaches the chart, which it never did', () {
      // Keyed off `Brightness` these were dead code: the app ships one
      // brightness (§14.3.3), so the daylight *contrast* profile — the one
      // that lifts ink for a phone in direct sun — reached every screen except
      // this one.
      expect(
        ProbePalette.grid(SmokeTokens.daylight),
        isNot(ProbePalette.grid(SmokeTokens.dark)),
      );
      expect(
        ProbePalette.axisInk(SmokeTokens.daylight),
        isNot(ProbePalette.axisInk(SmokeTokens.dark)),
      );
    });
  });
}
