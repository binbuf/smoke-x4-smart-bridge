/// One probe row: the series-hue mark, the jack label, the reading and its
/// freshness.
///
/// A detached jack renders in place — dimmed, an em dash, and the word
/// "unplugged" — because a probe that vanishes reads as an app bug, and a
/// detached probe that renders as `0 °F` reads as a frozen cook.
library;

import 'package:flutter/material.dart';

import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';

class ProbeCard extends StatelessWidget {
  const ProbeCard({
    super.key,
    required this.jack,
    required this.f10,
    required this.unit,
    required this.freshness,
    this.hasReading = true,
  });

  final ProbeJack jack;

  /// Tenths-°F, or null when the jack is detached/invalid.
  final int? f10;
  final TempUnit unit;
  final Freshness freshness;

  /// Whether a live snapshot exists at all. When it does not, every jack is
  /// "no reading" rather than "unplugged" — the bridge has told us nothing, and
  /// four unplugged probes would be a confident wrong story.
  final bool hasReading;

  @override
  Widget build(BuildContext context) {
    final value = f10 == null
        ? const TempValue.absent()
        : TempValue.ofF10(f10!);
    final noReading = !hasReading;
    final detached = !noReading && value.isAbsent;
    final dim = noReading || detached || freshness.isDim;

    return Semantics(
      label: noReading
          ? 'Probe ${jack.n}, no reading'
          : detached
          ? 'Probe ${jack.n}, unplugged'
          : 'Probe ${jack.n}, '
                '${value.format(unit)}, ${freshness.label}',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: dim ? 0.45 : 1,
          child: SmokeCard(
            padding: const EdgeInsets.symmetric(
              horizontal: SmokeSpace.lg,
              vertical: SmokeSpace.md,
            ),
            child: Row(
              children: [
                SeriesDot(jack: jack.n, size: 12),
                const SizedBox(width: SmokeSpace.md),
                Text(
                  'Probe ${jack.n}',
                  style: const TextStyle(
                    color: SmokePalette.textBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (noReading)
                  const Text(
                    'no reading',
                    style: TextStyle(
                      color: SmokePalette.textMuted,
                      fontSize: 13,
                    ),
                  )
                else if (detached)
                  const Text(
                    'unplugged',
                    style: TextStyle(
                      color: SmokePalette.textMuted,
                      fontSize: 13,
                    ),
                  )
                else
                  Text(
                    value.format(unit),
                    style: const TextStyle(
                      color: SmokePalette.textHi,
                      fontFamily: 'JetBrainsMono',
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                const SizedBox(width: SmokeSpace.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
