/// The two small readouts that ride a probe card's header row (design 16
/// §16.5).
///
/// Both were breaking the one rule this design system is most insistent about,
/// in opposite directions, and both are fixed here.
///
///  * [TrendChip] drew its words in a **series hue** — ember for rising, the
///    slot-4 blue for falling. A series hue may be a mark and may never carry a
///    word. Direction is now carried by the arrow, which is a shape: it
///    survives a monochrome screenshot, a colour-blind reader and the stale
///    veil's desaturation, none of which a hue does.
///  * [TargetPill] drew a 14 % accent fill with a word in it and **no icon**.
///    Status chrome is fill + border + icon + word, always all four (§16.5), so
///    *Reached* now carries a check. The shape says done; the word says done;
///    nothing is green, because green is transport health.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';

/// `Target 203.0°` — or, once the probe is there, `✓ Reached 203.0°`.
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
      padding: EdgeInsets.fromLTRB(reached ? 6 : 10, 4, 10, 4),
      decoration: BoxDecoration(
        color: reached ? StatusPalette.fill(StatusRole.pit) : t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
        border: Border.all(
          color: reached ? StatusPalette.border(StatusRole.pit) : t.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reached) ...[
            Icon(Icons.check_rounded, size: 14, color: StatusPalette.pit),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: SmokeType.bodySm.copyWith(
              // Chrome carries its hue in the icon and the border; the words
              // are carried by contrast.
              color: reached ? t.textHi : t.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    return Semantics(
      label: flat
          ? 'holding steady'
          : '${rising ? "rising" : "falling"} '
                '${r.abs().toStringAsFixed(1)} degrees per hour',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!flat) ...[
            Icon(
              rising ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16,
              color: t.textMuted,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              formatRate(r),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SmokeType.bodySm.copyWith(
                color: flat ? t.textMuted : t.textBody,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
