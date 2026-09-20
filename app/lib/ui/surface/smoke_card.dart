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
///
/// ## `spine` — the §H.2 depth cue
///
/// §H.2 asks the hero readout for *"subtle depth — a large, high-contrast
/// readout with a thin series-hue underline"*. [spine] is that, and it is here
/// rather than in the hero card because the separation rule names it as one of
/// the four things a series hue may ever be: *a chart stroke, a gauge arc, a
/// ≤12 dp dot, **a card's left rule***. A 3 dp rule down the leading edge tells
/// you which probe a card belongs to before you have read a word of it, at a
/// glance, from across a yard — and it costs no colour anywhere else on the
/// card, which is exactly why the rule permits it and permits nothing wider.
///
/// [spine] and [accent] are independent: the pit card wears both (its own rule
/// *and* the bloom), a food card wears only the rule, and a settings card
/// wears neither.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class SmokeCard extends StatelessWidget {
  const SmokeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SmokeTokens.s4),
    this.accent,
    this.spine,
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

  /// A 3 dp series-hue rule down the leading edge — the sanctioned "card's
  /// left rule" of §14.6.1. Identity, not status: it never carries a word and
  /// it never widens.
  final Color? spine;

  /// Pressed / selected surface.
  final bool raised;

  /// Wide enough to read at arm's length, narrow enough that it is still a
  /// mark and not a fill.
  static const double spineWidth = 3;

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

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: padding, child: child),
        ?footer,
      ],
    );

    // The spine is drawn *inside* the card's clip, so it takes the card's
    // corner radius at top and bottom and stops being a stripe glued to the
    // edge. Stacked rather than laid out in a Row: the card's height is
    // whatever its content is, and a Row would have to be told that height
    // before it could stretch a sibling to it.
    final content = spine == null
        ? body
        : Stack(
            children: [
              body,
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: spineWidth,
                // Keyed because the goldens are text: a probe's identity mark
                // appearing, moving or vanishing has to be a reviewable line
                // in a diff, not a rendering nobody can see in review.
                child: ColoredBox(
                  key: const Key('smoke-card-spine'),
                  color: spine!,
                ),
              ),
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
