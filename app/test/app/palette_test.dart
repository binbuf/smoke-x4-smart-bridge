/// A10.2 — the probe palette.
///
/// The numbers in `palette.dart` came out of the project's
/// data-visualisation validator, run against the app's own surfaces. This
/// file pins the two properties code can regress without anybody noticing:
/// **identity is stable**, and **identity does not rest on hue alone.**
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/palette.dart';
import 'package:smoke_bridge/app/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

/// WCAG relative luminance contrast, so the sunlight/dark-theme
/// requirement is checked rather than asserted in a comment.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a);
  final l2 = lum(b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('every probe has a colour and a stroke, in a fixed order', () {
    for (final b in Brightness.values) {
      final seen = <Color>{};
      final strokes = <String>{};
      for (var n = 1; n <= 4; n++) {
        final s = ProbePalette.styleFor(n, b);
        expect(seen.add(s.color), isTrue, reason: 'probe $n reused a hue');
        expect(
          strokes.add(s.strokeName),
          isTrue,
          reason: 'probe $n reused a stroke',
        );
      }
      expect(strokes, {'solid', 'dashed', 'dotted', 'dash-dot'});
    }
  });

  test('colour follows the probe, not its role', () {
    // Re-roling a probe mid-cook must not repaint the history behind it.
    final asFood = ProbePalette.styleFor(
      1,
      Brightness.dark,
      role: ProbeRole.food,
    );
    final asPit = ProbePalette.styleFor(
      1,
      Brightness.dark,
      role: ProbeRole.pit,
    );
    expect(asFood.color, asPit.color);
    expect(asFood.dashArray, asPit.dashArray);
    // Role carries its weight through form instead: the pit is the
    // reference series and draws heaviest.
    expect(asPit.strokeWidth, greaterThan(asFood.strokeWidth));
  });

  test('a detached probe keeps its identity', () {
    // Nothing about attachment reaches the palette — a probe that comes
    // back must come back the same colour.
    expect(
      ProbePalette.styleFor(3, Brightness.dark).color,
      ProbePalette.styleFor(3, Brightness.dark).color,
    );
  });

  test('light and dark are selected separately, not flipped', () {
    var differ = 0;
    for (var n = 1; n <= 4; n++) {
      if (ProbePalette.styleFor(n, Brightness.light).color !=
          ProbePalette.styleFor(n, Brightness.dark).color) {
        differ++;
      }
    }
    // Three of four are re-stepped for the dark surface; green is
    // mode-invariant because it clears 3:1 on both.
    expect(differ, 3);
  });

  test('every series clears 3:1 on the surface it is drawn on', () {
    // The §8.7 requirement, checked rather than claimed: legible in
    // direct sunlight AND in a dark theme.
    final lightSurface = SmokeTheme.light.colorScheme.surface;
    final darkSurface = SmokeTheme.dark.colorScheme.surface;
    for (var n = 1; n <= 4; n++) {
      expect(
        _contrast(
          ProbePalette.styleFor(n, Brightness.light).color,
          lightSurface,
        ),
        greaterThanOrEqualTo(3.0),
        reason: 'probe $n is not legible in sunlight',
      );
      expect(
        _contrast(ProbePalette.styleFor(n, Brightness.dark).color, darkSurface),
        greaterThanOrEqualTo(3.0),
        reason: 'probe $n is not legible in the dark theme',
      );
    }
  });

  test('no series wears a status hue', () {
    // A series in warning-amber or critical-red would impersonate an
    // alarm on a screen whose whole job is alarms.
    final status = {AlarmPalette.warning, AlarmPalette.critical};
    for (final b in Brightness.values) {
      for (var n = 1; n <= 4; n++) {
        expect(status.contains(ProbePalette.styleFor(n, b).color), isFalse);
      }
    }
  });

  test('severity carries an icon as well as a colour', () {
    for (final s in AlarmSeverity.values) {
      expect(AlarmPalette.iconOf(s), isNotNull);
      expect(AlarmPalette.of(s), isNotNull);
    }
    expect(
      AlarmPalette.iconOf(AlarmSeverity.critical),
      isNot(AlarmPalette.iconOf(AlarmSeverity.info)),
    );
  });

  test('a probe number out of range clamps rather than throwing', () {
    expect(ProbePalette.styleFor(0, Brightness.dark).color, isNotNull);
    expect(ProbePalette.styleFor(9, Brightness.dark).color, isNotNull);
  });
}
