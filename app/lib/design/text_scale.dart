/// How the instrument answers a user who has turned text up (design 14 §14.10,
/// newapp §H.2).
///
/// Two rules in this app look like they contradict each other:
///
///  * **§14.5.1 — a temperature is never scaled to fit.** The hero is 96 pt,
///    full stop. A glyph that changes height as a probe crosses 99 → 100 °F
///    reads as the layout breaking rather than as a temperature rising, and two
///    cards side by side must print the same value at the same size.
///  * **§14.10 — text scale is honoured to 1.3 without clipping**, and §H.2:
///    *"the never-scale rule must degrade gracefully — allow the hero to grow,
///    reflow the gauge"*.
///
/// They are reconciled by deciding **what the scaler buys**. It does not buy a
/// bigger number: at 360 dp, four tabular glyphs at 96 pt plus the unit already
/// consume the card, so scaling the number is not "bigger", it is *clipped*,
/// which is the one outcome nobody wants at 3 a.m. What the scaler buys is
/// **room for everything else** — the probe name, the target pill, the trend,
/// the banner under it, all of which are prose and all of which grow — and the
/// gauge is the flexible child that pays for it (§14.5.1's own words).
///
/// So the ladder reflows, in three steps, and the number is the last thing to
/// move:
///
/// | scale | number | gauge | layout |
/// | --- | --- | --- | --- |
/// | ≤ 1.0 | `heroTemp` 96 | 84 dp | number and gauge share the row |
/// | 1.0 – 1.3 | `heroTemp` 96 | shrinks 84 → 64 | same row, gauge gives ground |
/// | ≥ 1.3 | `bigTemp` 56 | **dropped** | number takes the full width, chips stack under it |
///
/// The demotion at 1.3 is §14.10's, verbatim, and it is deliberately a *smaller*
/// number: past that point the labels around it are 1.3× and the card has run
/// out of room, so the honest move is to give the width to the words that grew
/// rather than to clip the number that did not. Nothing is ever hidden — the
/// gauge's information (progress toward a target) is carried in words by the
/// target pill, which is why the gauge is the safe thing to drop and the
/// number is not.
library;

import 'package:flutter/material.dart';

import 'typography.dart';

/// The resolved hero layout for one text scale.
@immutable
class SmokeHeroMetrics {
  const SmokeHeroMetrics({
    required this.number,
    required this.unit,
    required this.gauge,
    required this.stacked,
  });

  /// The temperature's style. Render it inside [SmokeType.unscaled] — the
  /// size here is final (§14.5.1).
  final TextStyle number;

  /// The `°F` on the hero baseline, likewise unscaled.
  final TextStyle unit;

  /// The gauge's edge length, or **null when the gauge is dropped**. Null is
  /// not "draw it at zero": `TargetGauge` with nothing to say renders nothing
  /// at all (§14.7.3), and a reflow that leaves an empty ring behind would be
  /// the same lie.
  final double? gauge;

  /// True once the trend chip and target pill must sit *under* the number
  /// rather than beside it, because at this scale they no longer fit on a row
  /// with it.
  final bool stacked;

  /// Whether the gauge survives at this scale. Convenience for call sites that
  /// only need the boolean.
  bool get showsGauge => gauge != null;
}

abstract final class SmokeTextScale {
  /// The gauge's size at normal text.
  static const double gaugeFull = 84;

  /// The smallest a gauge may be drawn before the pull tick and the value dot
  /// stop being separable. Below this it is dropped rather than drawn badly.
  static const double gaugeMin = 64;

  /// Past this, §14.10 drops the gauge and demotes the hero. It is Material's
  /// own "large text" threshold and the point at which a 360 dp card can no
  /// longer hold a 96 pt number and a 1.3× label row on the same line.
  static const double reflowAt = 1.3;

  /// The pure core, so the whole ladder is pinned by a plain `test` with no
  /// `MediaQuery` and no widget in sight.
  static SmokeHeroMetrics metricsFor(double scale) {
    if (scale >= reflowAt) {
      return const SmokeHeroMetrics(
        number: SmokeType.bigTemp,
        unit: SmokeType.displayS,
        gauge: null,
        stacked: true,
      );
    }
    // Linear give-back across 1.0 → 1.3, clamped at both ends so a scaler
    // below 1 never *grows* the gauge past its designed size.
    final t = ((scale - 1.0) / (reflowAt - 1.0)).clamp(0.0, 1.0);
    return SmokeHeroMetrics(
      number: SmokeType.heroTemp,
      unit: SmokeType.heroUnit,
      gauge: gaugeFull - (gaugeFull - gaugeMin) * t,
      stacked: false,
    );
  }

  /// The effective scale factor for [context], measured the only way that is
  /// meaningful under a non-linear `TextScaler`: ask it what it does to a real
  /// size. `bodySm` is the size the labels around a hero are set at, so it is
  /// the size whose growth the layout has to absorb.
  static double factorOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14;

  /// [metricsFor] resolved against [context].
  static SmokeHeroMetrics heroOf(BuildContext context) =>
      metricsFor(factorOf(context));

  /// True when the window is at large text and a layout should stack rather
  /// than fight for a row. Used by chrome as well as by the hero — a banner
  /// with a trailing button has the same problem at 200%.
  static bool isLarge(BuildContext context) => factorOf(context) >= reflowAt;
}
