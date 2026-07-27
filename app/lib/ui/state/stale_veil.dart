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
            child: child,
          ),
        ),
      ],
    );
  }
}
