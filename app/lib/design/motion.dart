/// Motion tokens (design 14 §14.4.1).
///
/// **No widget under `lib/ui/` may write a `Duration` literal.** Everything
/// goes through [SmokeMotion.of], and the layering test greps for `Duration(`
/// to keep it that way. That is not tidiness: this is the single seam where
/// `MediaQuery.disableAnimations` is honoured, and one literal anywhere
/// defeats it silently for the user who asked for it.
library;

import 'package:flutter/material.dart';

/// Durations resolved against the current accessibility setting.
///
/// Note [pulse]: it is **not** zeroed under reduced motion. The liveness dot
/// ceasing to animate *is* the staleness signal (14 §14.7) — removing the
/// animation would remove the information. What reduced motion drops is the
/// 1.3× scale, leaving the opacity fade.
@immutable
class SmokeMotionValues {
  const SmokeMotionValues({
    required this.quick,
    required this.standard,
    required this.value,
    required this.gauge,
    required this.pulse,
    required this.pulseScales,
    required this.curve,
  });

  /// Chips, pills, taps, ripples.
  final Duration quick;

  /// Cards, sheets, banner slide, cross-fades, the instrument↔guided switch.
  final Duration standard;

  /// The temperature tween. Zeroed under reduced motion — the number snaps.
  final Duration value;

  /// The gauge arc sweep. This is the 800 ms in which confirming a cook
  /// visibly installs its targets.
  final Duration gauge;

  /// The liveness dot period. Never zero — see the class doc.
  final Duration pulse;

  /// Whether the pulse animates scale as well as opacity.
  final bool pulseScales;

  final Curve curve;

  static const SmokeMotionValues full = SmokeMotionValues(
    quick: Duration(milliseconds: 120),
    standard: Duration(milliseconds: 220),
    value: Duration(milliseconds: 600),
    gauge: Duration(milliseconds: 800),
    pulse: Duration(seconds: 2),
    pulseScales: true,
    curve: Curves.easeOutCubic,
  );

  static const SmokeMotionValues reduced = SmokeMotionValues(
    quick: Duration.zero,
    standard: Duration.zero,
    value: Duration.zero,
    gauge: Duration.zero,
    pulse: Duration(seconds: 2),
    pulseScales: false,
    curve: Curves.linear,
  );
}

abstract final class SmokeMotion {
  /// Resolve motion for [context]. Honours `MediaQuery.disableAnimations`,
  /// which is what the OS sets when the user turns animations off.
  static SmokeMotionValues of(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? SmokeMotionValues.reduced
      : SmokeMotionValues.full;
}
