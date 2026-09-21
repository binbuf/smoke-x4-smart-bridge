/// N3.19 — the small atoms.
///
/// `JackBadge` (probe jack), `TargetPill` (a target readout), `TrendChip`
/// (direction of travel), `ModeBadge` (transport mode) and `TierTag`
/// (Device/Insight). They take plain values; none of them reaches for a
/// repository or a domain model.
///
/// Series hue appears only on [JackBadge] and [TrendChip], and only as a mark.
/// [ModeBadge] is green because it describes transport health — the one place
/// green is allowed. [TierTag] keeps the two alarm tiers visibly separate
/// (I2/§6.4).
library;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

/// The rounded jack number.
class JackBadge extends StatelessWidget {
  const JackBadge({super.key, required this.jack, this.detached = false});

  final int jack;

  /// A detached probe: absent, never zero (I3).
  final bool detached;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      label: 'Jack $jack${detached ? ', unplugged' : ''}',
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: detached ? tokens.cardRaised : tokens.series(jack),
          borderRadius: BorderRadius.circular(8),
          border: detached ? Border.all(color: tokens.hairlineStrong) : null,
        ),
        child: Text(
          detached ? '—' : '$jack',
          style: SmokeText.label.copyWith(
            fontFamily: SmokeText.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: detached ? tokens.textMuted : const Color(0xFF0A0400),
          ),
        ),
      ),
    );
  }
}

/// A target readout pill.
class TargetPill extends StatelessWidget {
  const TargetPill({super.key, required this.label, this.reached = false});

  final String label;

  /// Reaching the target closes the ring and says so; it is never green.
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.cardSubtle,
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SmokeIcon(
            reached ? SmokeGlyph.check : SmokeGlyph.target,
            size: 12,
            color: tokens.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: SmokeText.monoSmall.copyWith(color: tokens.textHi),
          ),
        ],
      ),
    );
  }
}

/// Direction of travel.
enum TrendDirection { up, down, flat }

/// A trend chip.
class TrendChip extends StatelessWidget {
  const TrendChip({super.key, required this.direction, required this.label});

  final TrendDirection direction;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final color = switch (direction) {
      TrendDirection.up => tokens.p1,
      TrendDirection.down => tokens.p4,
      TrendDirection.flat => tokens.textMuted,
    };
    final icon = switch (direction) {
      TrendDirection.up => SmokeGlyph.arrowUp,
      TrendDirection.down => SmokeGlyph.arrowDown,
      TrendDirection.flat => SmokeGlyph.minus,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.cardSubtle,
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SmokeIcon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label, style: SmokeText.monoSmall.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// A transport-mode badge. Green: this is transport health.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.tint(tokens.positive, 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tokens.tint(tokens.positive, 0.30)),
      ),
      child: Text(
        label.toUpperCase(),
        style: SmokeText.labelSm.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: tokens.positive,
        ),
      ),
    );
  }
}

/// Which tier an alarm belongs to.
enum AlarmTier { device, app }

/// The Device/Insight tag. The two tiers are never merged without it.
class TierTag extends StatelessWidget {
  const TierTag({super.key, required this.tier});

  final AlarmTier tier;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final device = tier == AlarmTier.device;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: device
            ? tokens.tint(tokens.pit, 0.18)
            : tokens.tint(tokens.info, 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: device ? tokens.tint(tokens.pit, 0.35) : tokens.hairlineStrong,
        ),
      ),
      child: Text(
        device ? 'Device' : 'Insight',
        style: SmokeText.labelSm.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: device ? tokens.p1 : tokens.textMuted,
        ),
      ),
    );
  }
}
