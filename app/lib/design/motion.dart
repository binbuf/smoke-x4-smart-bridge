/// N3.7–N3.8 — motion tokens.
///
/// `quick 120`, `standard 220`, `value 600`, `gauge 800`, `pulse 2 s`, plus the
/// two easing curves from `styles.css`. **No `Duration` literal may appear
/// outside `lib/design/`** — a layering test (`test/design/
/// design_layering_test.dart`) enforces it, so every animation in a screen
/// reads its duration from here.
///
/// Under [reducedMotion] every duration collapses to zero **except** [pulse]:
/// the pulse stopping *is* the staleness signal (research notes §9.4), so it
/// must keep beating.
library;

import 'package:flutter/material.dart';

/// The motion token set, carried on `ThemeData.extensions`.
@immutable
class SmokeMotion extends ThemeExtension<SmokeMotion> {
  const SmokeMotion({this.reducedMotion = false});

  /// Whether the user asked for reduced motion.
  final bool reducedMotion;

  /// Micro-feedback: hover, press, chip select.
  Duration get quick => const Duration(milliseconds: 120);

  /// The default transition: sheets, cards, reveals.
  Duration get standard => const Duration(milliseconds: 220);

  /// A value tween — a temperature easing to its new reading.
  Duration get value => const Duration(milliseconds: 600);

  /// The gauge sweep.
  Duration get gauge => const Duration(milliseconds: 800);

  /// The liveness pulse. Never zeroed: it is the staleness signal.
  Duration get pulse => const Duration(seconds: 2);

  /// The curve for ordinary transitions.
  Curve get easeStandard => const Cubic(0.2, 0, 0, 1);

  /// The curve for emphasis (sheets, modals).
  Curve get easeEmphasis => const Cubic(0.22, 1, 0.36, 1);

  /// The duration actually used for [token] given [reducedMotion].
  Duration effective(Duration token) =>
      reducedMotion && token != pulse ? Duration.zero : token;

  /// The effective `standard` duration.
  Duration get standardEffective => effective(standard);

  /// The effective `quick` duration.
  Duration get quickEffective => effective(quick);

  /// The effective `value` duration.
  Duration get valueEffective => effective(value);

  /// The effective `gauge` duration.
  Duration get gaugeEffective => effective(gauge);

  static SmokeMotion of(BuildContext context) =>
      Theme.of(context).extension<SmokeMotion>() ?? const SmokeMotion();

  @override
  SmokeMotion copyWith({bool? reducedMotion}) =>
      SmokeMotion(reducedMotion: reducedMotion ?? this.reducedMotion);

  @override
  SmokeMotion lerp(covariant SmokeMotion? other, double t) {
    if (other == null || t < 0.5) {
      return this;
    }
    return other;
  }
}
