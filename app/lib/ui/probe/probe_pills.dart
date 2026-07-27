/// A19.6 — TargetPill and TrendChip (design 14 §14.7.1).
///
/// The two small readouts that ride a probe card's header row. Both are marks +
/// words, never colour alone.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';

/// `Target 203°` — or, once the probe is there, `Reached 203°`. The label
/// changes with the state because a closed gauge ring (a shape) must be backed
/// by a word for a screen reader (§14.6.6).
class TargetPill extends StatelessWidget {
  const TargetPill({
    super.key,
    required this.targetF10,
    required this.reached,
    required this.celsius,
    this.bandMinF10,
    this.bandMaxF10,
  });

  final int? targetF10;
  final bool reached;
  final bool celsius;

  /// When set, the pill reads `Band 225–275°` instead of a single target.
  final int? bandMinF10;
  final int? bandMaxF10;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final String text;
    if (bandMinF10 != null && bandMaxF10 != null) {
      text =
          'Band ${formatSetpoint(bandMinF10, celsius: celsius)}'
          '–${formatSetpoint(bandMaxF10, celsius: celsius)}';
    } else if (targetF10 != null) {
      text =
          '${reached ? "Reached" : "Target"} '
          '${formatSetpoint(targetF10, celsius: celsius)}';
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: reached
            ? StatusPalette.pit.withValues(alpha: 0.14)
            : t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
      ),
      child: Text(
        text,
        style: SmokeType.bodySm.copyWith(
          color: reached ? t.textHi : t.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// An arrow plus a rate, e.g. `▲ +1.2°/hr`. A flat rate (`~0°/hr`) drops the
/// arrow and renders in muted ink — nothing is happening, and the chip says so.
class TrendChip extends StatelessWidget {
  const TrendChip({super.key, required this.rateFPerHr});

  final double? rateFPerHr;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = rateFPerHr;
    if (r == null) {
      return const SizedBox.shrink();
    }
    final flat = r.abs() < 0.6;
    final rising = r > 0;
    final color = flat
        ? t.textMuted
        : rising
        ? StatusPalette.pit
        : ProbePalette.hue(4);
    return Semantics(
      label: flat
          ? 'holding steady'
          : '${rising ? "rising" : "falling"} '
                '${r.abs().toStringAsFixed(1)} degrees per hour',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!flat)
            Icon(
              rising ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16,
              color: color,
            ),
          if (!flat) const SizedBox(width: 4),
          Flexible(
            child: Text(
              formatRate(r),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SmokeType.bodySm.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
