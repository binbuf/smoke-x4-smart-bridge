/// N3.9–N3.10 — typography: the named scale and the reflow ladder.
///
/// Three bundled variable fonts (`Archivo` display/temps, `Inter` text/labels,
/// `JetBrainsMono` keys/ids) and fourteen named styles from `heroTemp` 96 down
/// to `labelSm` 11. Numeric styles carry tabular figures so a changing digit
/// never shifts its neighbours.
///
/// [SmokeTextScale] is the accessibility reflow ladder: the gauge is 84 dp at
/// 1.0×, shrinks 84→64 as the text scale rises to 1.3×, and above that the
/// hero temperature **demotes to 56 pt and the gauge drops**. A temperature is
/// never scaled to fit its container — an unreadably small number is a safety
/// bug, so the layout reflows instead.
library;

import 'dart:ui' show FontFeature, lerpDouble;

import 'package:flutter/material.dart';

/// The named type scale. Sizes and weights only; colour comes from the tokens.
abstract final class SmokeText {
  const SmokeText._();

  static const String displayFont = 'Archivo';
  static const String textFont = 'Inter';
  static const String monoFont = 'JetBrainsMono';

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature('tnum')];

  /// The giant live temperature. Ink, never a hue.
  static const TextStyle heroTemp = TextStyle(
    fontFamily: displayFont,
    fontSize: 96,
    fontWeight: FontWeight.w700,
    height: 0.95,
    letterSpacing: -3,
    fontFeatures: _tabular,
  );

  /// A big per-probe card temperature.
  static const TextStyle tempXl = TextStyle(
    fontFamily: displayFont,
    fontSize: 52,
    fontWeight: FontWeight.w700,
    height: 1,
    letterSpacing: -2,
    fontFeatures: _tabular,
  );

  /// A timer-tile temperature.
  static const TextStyle tempLg = TextStyle(
    fontFamily: displayFont,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1,
    letterSpacing: -1,
    fontFeatures: _tabular,
  );

  /// A compact-probe temperature.
  static const TextStyle tempMd = TextStyle(
    fontFamily: displayFont,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    fontFeatures: _tabular,
  );

  /// The value inside a gauge.
  static const TextStyle gaugeValue = TextStyle(
    fontFamily: displayFont,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1,
    fontFeatures: _tabular,
  );

  /// A screen title (the prototype's `.ab-title`).
  static const TextStyle title = TextStyle(
    fontFamily: displayFont,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// A card title.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: displayFont,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  /// A passkey / AP PSK readout.
  static const TextStyle monoKey = TextStyle(
    fontFamily: monoFont,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 8,
    fontFeatures: _tabular,
  );

  /// A mono value in a stat tile.
  static const TextStyle monoValue = TextStyle(
    fontFamily: monoFont,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  /// A small mono label (times, ids).
  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );

  /// Body copy.
  static const TextStyle body = TextStyle(
    fontFamily: textFont,
    fontSize: 14,
    height: 1.45,
  );

  /// Emphasised body copy.
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: textFont,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// Secondary copy.
  static const TextStyle sub = TextStyle(fontFamily: textFont, fontSize: 13);

  /// A control label.
  static const TextStyle label = TextStyle(
    fontFamily: textFont,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  /// The smallest label.
  static const TextStyle labelSm = TextStyle(
    fontFamily: textFont,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// An uppercase kicker (`.hero-kicker`, `.section-label`).
  static const TextStyle kicker = TextStyle(
    fontFamily: textFont,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
  );
}

/// The reflow ladder (research notes §9.2).
///
/// This is deliberately *not* a `FittedBox`: it steps at breakpoints rather
/// than shrinking continuously, and past 1.3× it removes the gauge entirely
/// because there is no honest way to keep a 64 dp dial and a legible number on
/// a phone.
@immutable
class SmokeTextScale {
  const SmokeTextScale(this.factor);

  /// The largest text scale that keeps the 84 dp gauge.
  static const double gaugeShrinkAt = 1.3;

  /// The base hero temperature size.
  static const double heroBase = 96;

  /// The base gauge diameter.
  static const double gaugeBase = 84;

  /// The gauge diameter at [gaugeShrinkAt].
  static const double gaugeMin = 64;

  /// The demoted hero size above [gaugeShrinkAt].
  static const double heroDemoted = 56;

  /// The text-scale factor (1.0 = no scaling).
  final double factor;

  /// Reads the effective factor from the platform text scaler.
  factory SmokeTextScale.of(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SmokeTextScale(scaler.scale(16) / 16);
  }

  /// The hero temperature size for this factor.
  double get heroSize => factor <= gaugeShrinkAt ? heroBase : heroDemoted;

  /// The gauge diameter for this factor, or 0 when the gauge has dropped.
  double get gaugeSize {
    if (factor <= 1) {
      return gaugeBase;
    }
    if (factor >= gaugeShrinkAt) {
      return factor > gaugeShrinkAt ? 0 : gaugeMin;
    }
    return lerpDouble(gaugeBase, gaugeMin, (factor - 1) / (gaugeShrinkAt - 1))!;
  }

  /// Whether the gauge is still shown at this factor.
  bool get gaugeVisible => gaugeSize > 0;

  /// Whether the hero has demoted to [heroDemoted].
  bool get heroDemotedNow => factor > gaugeShrinkAt;

  /// The hero style at this factor.
  TextStyle get heroStyle => SmokeText.heroTemp.copyWith(fontSize: heroSize);
}
