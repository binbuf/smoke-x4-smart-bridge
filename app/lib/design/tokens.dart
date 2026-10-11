/// The slim app's design tokens — presentation only, no logic.
///
/// Deliberately small: the full token architecture lives in the `newui`
/// prototype (`docs/design/14-design-system.md`). The rules that survive the
/// slash are the load-bearing ones:
///
///  * **Dark-only.** A white screen outdoors at 3 a.m. is worse than a
///    high-contrast dark one.
///  * **A series hue is a mark, never a surface.** Per-probe colours are only
///    ever a chart stroke or a small dot; they never fill a large shape and
///    never carry a word.
///  * **A temperature is never scaled to fit.** The hero number is fixed; the
///    layout around it flexes instead.
library;

import 'package:flutter/material.dart';

/// Surfaces and ink.
abstract final class SmokePalette {
  static const bg = Color(0xFF0B0B0D);
  static const surface = Color(0xFF141417);
  static const card = Color(0xFF1B1B1F);
  static const cardRaised = Color(0xFF232329);
  static const hairline = Color(0xFF2C2C33);

  static const textHi = Color(0xFFF5F5F7);
  static const textBody = Color(0xFFC9C9D1);
  static const textMuted = Color(0xFF8A8A94);

  /// The app's one accent, used for chrome that is *ours* (active tab, the
  /// connect action), never for a status.
  static const ember = Color(0xFFFF6A3D);

  /// Per-probe series hues, index 0 = jack 1. Marks only.
  static const series = <Color>[
    Color(0xFFFF7A45),
    Color(0xFF4FC3F7),
    Color(0xFF81C784),
    Color(0xFFBA8CFF),
  ];

  /// Status hues. Chrome only, always paired with an icon and a word.
  static const positive = Color(0xFF43B581);
  static const warning = Color(0xFFE0A33E);
  static const critical = Color(0xFFE5484D);

  /// The series hue for a jack number (1..4), wrapping defensively.
  static Color forJack(int n) => series[(n - 1) % series.length];
}

/// A 4 dp spacing scale. "A 6 or a 10 is a bug."
abstract final class SmokeSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Four radii and no others.
abstract final class SmokeRadius {
  static const card = 20.0;
  static const control = 14.0;
  static const chip = 8.0;
}
