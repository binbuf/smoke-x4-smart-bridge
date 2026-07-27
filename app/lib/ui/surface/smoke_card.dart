/// A19.5 — SmokeCard (design 14 §14.7.1).
///
/// The one container. It replaces every ad-hoc `Container` with a radius and a
/// border scattered across the old feature code. Default is a flat `card` fill
/// with a 1 dp hairline; give it an [accent] and it gains the accent border,
/// the card shadow and a bloom — that is the pit card, and nothing else earns
/// the glow.
///
/// [footer] bleeds to the rounded bottom corners: it is how a sparkline reaches
/// the card edge. The clip is the card's, so a footer never has to know the
/// radius.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class SmokeCard extends StatelessWidget {
  const SmokeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SmokeTokens.s4),
    this.accent,
    this.raised = false,
    this.inset = false,
    this.onTap,
    this.footer,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When set, the card wears this hue: a 35% border, the card shadow, and a
  /// 20% bloom. Used for the pit hero card and the active-cook header.
  final Color? accent;

  /// Pressed / selected surface.
  final bool raised;

  /// Deep inset surface (a well inside another card), no shadow.
  final bool inset;

  final VoidCallback? onTap;

  /// Bleeds to the bottom corners; the card clips it.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = inset
        ? t.cardSubtle
        : raised
        ? t.cardRaised
        : t.card;
    final borderColor = accent?.withValues(alpha: 0.35) ?? t.hairline;
    final radius = BorderRadius.circular(SmokeTokens.radiusCard);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: padding, child: child),
        ?footer,
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          if (accent != null && !inset) ...[?t.shadowCard, ?t.glow(accent!)],
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ClipRRect(borderRadius: radius, child: content),
        ),
      ),
    );
  }
}
