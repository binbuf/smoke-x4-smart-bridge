/// N3.1–N3.10 — token, theme, motion and type-scale contracts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

void main() {
  group('palette', () {
    test('dark matches the prototype hexes', () {
      final t = SmokeTokens.dark();
      expect(t.bg, const Color(0xFF07090E));
      expect(t.surface, const Color(0xFF0F131D));
      expect(t.card, const Color(0xFF161C2A));
      expect(t.cardSubtle, const Color(0xFF121824));
      expect(t.cardRaised, const Color(0xFF1E2638));
      expect(t.well, const Color(0xFF04060A));
      expect(t.p1, const Color(0xFFD95926));
      expect(t.p2, const Color(0xFF9085E9));
      expect(t.p3, const Color(0xFF008300));
      expect(t.p4, const Color(0xFF3987E5));
      expect(t.critical, const Color(0xFFF04444));
      expect(t.warning, const Color(0xFFFAB219));
      expect(t.positive, const Color(0xFF10B981));
      expect(t.glow, 1);
      expect(t.shadowCard, isNotEmpty);
    });

    test('light uses weightier series hues', () {
      final t = SmokeTokens.light();
      expect(t.p1, const Color(0xFFC2410C));
      expect(t.p2, const Color(0xFF6D5BD0));
      expect(t.p3, const Color(0xFF0F7A0F));
      expect(t.p4, const Color(0xFF2563EB));
      expect(t.glow, 0);
      expect(t.textHi, const Color(0xFF0B1220));
    });

    test('daylight lifts ink, thickens hairlines and removes shadow/glow', () {
      final dark = SmokeTokens.dark();
      final darkDaylight = SmokeTokens.dark(profile: SmokeProfile.daylight);
      expect(darkDaylight.textHi, const Color(0xFFFFFFFF));
      expect(darkDaylight.shadowCard, isEmpty);
      expect(darkDaylight.glow, 0);
      expect(darkDaylight.hairline.a, greaterThan(dark.hairline.a));
      expect(darkDaylight.hairlineStrong.a, greaterThan(dark.hairlineStrong.a));

      final lightDaylight = SmokeTokens.light(profile: SmokeProfile.daylight);
      expect(lightDaylight.textHi, const Color(0xFF000000));
      expect(lightDaylight.shadowCard, isEmpty);
    });

    test('tint derives from the token, not a hardcoded rgb', () {
      final t = SmokeTokens.dark();
      final tinted = t.tint(t.critical, 0.14);
      expect(tinted.a, closeTo(0.14, 0.001));
      expect(tinted.r, closeTo(t.critical.r, 0.0001));
      expect(tinted.g, closeTo(t.critical.g, 0.0001));
      expect(tinted.b, closeTo(t.critical.b, 0.0001));
    });

    test('series follows the jack, never the role', () {
      final t = SmokeTokens.dark();
      expect(t.series(1), t.p1);
      expect(t.series(2), t.p2);
      expect(t.series(3), t.p3);
      expect(t.series(4), t.p4);
      expect(t.series(9), t.p4);
    });
  });

  group('geometry', () {
    test('spacing is the 4 dp scale with no 6 or 10', () {
      const s = SmokeSpacing();
      final values = <double>[s.s1, s.s2, s.s3, s.s4, s.s5, s.s6, s.s7];
      expect(values, <double>[4, 8, 12, 16, 20, 24, 32]);
      for (final v in values) {
        expect(v % 4, 0, reason: '$v is off the 4 dp scale');
      }
    });

    test('radii are card 20 / control 14 / chip 8 / pill 999', () {
      const r = SmokeRadii();
      expect(
        <double>[r.card, r.control, r.chip, r.pill],
        <double>[20, 14, 8, 999],
      );
    });

    test('density selects a spacing step, never a new scale', () {
      expect(SmokeDensity.compact.pageGutter, 16);
      expect(SmokeDensity.comfortable.pageGutter, 18);
      expect(SmokeDensity.compact.cardPadding, 16);
      expect(SmokeDensity.comfortable.cardPadding, 20);
    });
  });

  group('motion', () {
    test('the five tokens', () {
      const m = SmokeMotion();
      expect(m.quick, const Duration(milliseconds: 120));
      expect(m.standard, const Duration(milliseconds: 220));
      expect(m.value, const Duration(milliseconds: 600));
      expect(m.gauge, const Duration(milliseconds: 800));
      expect(m.pulse, const Duration(seconds: 2));
    });

    test('reduced motion zeroes all but the pulse', () {
      const m = SmokeMotion(reducedMotion: true);
      expect(m.effective(m.quick), Duration.zero);
      expect(m.effective(m.standard), Duration.zero);
      expect(m.effective(m.value), Duration.zero);
      expect(m.effective(m.gauge), Duration.zero);
      expect(m.effective(m.pulse), const Duration(seconds: 2));
    });
  });

  group('text scale ladder', () {
    test('1.0 keeps the 96 hero and 84 gauge', () {
      const scale = SmokeTextScale(1);
      expect(scale.heroSize, 96);
      expect(scale.gaugeSize, 84);
      expect(scale.gaugeVisible, isTrue);
      expect(scale.heroStyle.fontSize, 96);
    });

    test('the gauge shrinks 84→64 between 1.0 and 1.3', () {
      const scale = SmokeTextScale(1.15);
      expect(scale.gaugeSize, greaterThan(64));
      expect(scale.gaugeSize, lessThan(84));
      expect(scale.heroSize, 96);
    });

    test('1.3 is the smallest gauge', () {
      const scale = SmokeTextScale(SmokeTextScale.gaugeShrinkAt);
      expect(scale.gaugeSize, 64);
      expect(scale.heroSize, 96);
    });

    test('above 1.3 the hero demotes to 56 and the gauge drops', () {
      const scale = SmokeTextScale(1.4);
      expect(scale.heroSize, 56);
      expect(scale.gaugeSize, 0);
      expect(scale.gaugeVisible, isFalse);
      expect(scale.heroDemotedNow, isTrue);
    });
  });

  group('theme data', () {
    test('carries the tokens and motion as extensions', () {
      final theme = SmokeThemeData.dark(
        profile: SmokeProfile.daylight,
        density: SmokeDensity.comfortable,
        reducedMotion: true,
      );
      final tokens = theme.extension<SmokeTokens>()!;
      expect(tokens.profile, SmokeProfile.daylight);
      expect(tokens.density, SmokeDensity.comfortable);
      expect(theme.extension<SmokeMotion>()!.reducedMotion, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, tokens.bg);
    });

    test('light and dark build different palettes', () {
      final dark = SmokeThemeData.dark().extension<SmokeTokens>()!;
      final light = SmokeThemeData.light().extension<SmokeTokens>()!;
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.bg, isNot(light.bg));
    });
  });

  group('typography', () {
    test('numeric styles carry tabular figures', () {
      for (final style in <TextStyle>[
        SmokeText.heroTemp,
        SmokeText.tempXl,
        SmokeText.tempLg,
        SmokeText.tempMd,
        SmokeText.monoKey,
        SmokeText.monoValue,
      ]) {
        expect(
          style.fontFeatures?.any((f) => f.feature == 'tnum'),
          isTrue,
          reason: '${style.fontSize} should be tabular',
        );
      }
    });

    test('the three bundled families', () {
      expect(SmokeText.displayFont, 'Archivo');
      expect(SmokeText.textFont, 'Inter');
      expect(SmokeText.monoFont, 'JetBrainsMono');
    });
  });
}
