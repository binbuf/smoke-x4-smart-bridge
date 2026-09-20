/// A19.6 — StaleVeil (design 14 §14.7).
///
/// The single most important safety component in the app, and one that did not
/// exist in any form before M8. It wraps a live layout that has gone stale and
/// makes it impossible to mistake for fresh: it desaturates the children,
/// dims them, and pins an advisory saying exactly how old the reading is.
///
/// A stale number that still looks live is the failure this whole app is built
/// to prevent — a four-hour-old pit temperature under a green chip. The veil is
/// what guarantees the number *looks* as old as it is.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../insight/insight_banner.dart';

class StaleVeil extends StatelessWidget {
  const StaleVeil({
    super.key,
    required this.child,
    required this.ageLabel,
    this.frozen = false,
  });

  final Widget child;

  /// "Last reading 14 minutes ago" — the pinned advisory's text.
  final String ageLabel;

  /// True past the frozen boundary (the firmware's `base_lost_s`): a stronger
  /// tint and a critical, not advisory, banner.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    // Greyscale-ish matrix at ~25% saturation — enough that a red probe line
    // stops reading as an alarm, not so much that the layout looks broken.
    const s = 0.25;
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final matrix = <double>[
      r + (1 - r) * s,
      g - g * s,
      b - b * s,
      0,
      0,
      r - r * s,
      g + (1 - g) * s,
      b - b * s,
      0,
      0,
      r - r * s,
      g - g * s,
      b + (1 - b) * s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
          child: InsightBanner(
            kind: frozen ? InsightKind.alarm : InsightKind.advisory,
            label: ageLabel,
            icon: frozen
                ? Icons.report_gmailerrorred_rounded
                : Icons.history_rounded,
          ),
        ),
        Opacity(
          opacity: frozen ? 0.40 : 0.55,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(matrix),
            // Tell everything underneath that the dimming is already being
            // done for it. Without this the veil and each probe card both
            // applied `freshness.ink`, and opacity composes by multiplying:
            // 0.40 × 0.40 = **0.16** at frozen, 0.55² = 0.30 at stale — a
            // hero temperature at well under half the ink 13 §13.6.1
            // specifies, on the screen whose whole job is being readable
            // across a dark yard.
            child: _VeilScope(child: child),
          ),
        ),
      ],
    );
  }
}

/// Marks a subtree as already dimmed by a [StaleVeil].
///
/// A card that dims itself is right when it stands alone (the lab, a test, a
/// list that has no veil above it) and wrong inside a veil, which dims the
/// whole body at once. Rather than thread a flag through every caller, the
/// veil says so and each card asks.
class _VeilScope extends InheritedWidget {
  const _VeilScope({required super.child});

  @override
  bool updateShouldNotify(_VeilScope oldWidget) => false;
}

/// Whether a [StaleVeil] above this context is already applying the dim.
///
/// Widgets that carry their own `Opacity(freshness.ink)` must skip it when
/// this is true, or the two multiply.
bool veilAlreadyDims(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_VeilScope>() != null;
