/// N3.13 — `SmokeCard`, the one container.
///
/// Every surface is a card: `card` (default), `subtle`, `raised` or `inset`
/// (the well). An `accent` draws the prototype's left spine — a **series
/// mark**, never a status fill. `onTap` makes it a tappable card; `footer`
/// renders below a hairline. Colour and elevation come from the tokens, so a
/// card is the same widget in dark, light and daylight.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

class SmokeCard extends StatelessWidget {
  const SmokeCard({
    super.key,
    required this.child,
    this.accent,
    this.spineWidth = 3,
    this.subtle = false,
    this.raised = false,
    this.inset = false,
    this.onTap,
    this.footer,
    this.padding,
    this.margin,
  });

  final Widget child;

  /// The left-spine colour (a series mark). Null draws no spine.
  final Color? accent;
  final double spineWidth;

  /// The `--card-subtle` surface.
  final bool subtle;

  /// The `--card-raised` surface.
  final bool raised;

  /// The `--well` surface (deepest).
  final bool inset;

  final VoidCallback? onTap;

  /// Rendered below a hairline divider.
  final Widget? footer;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final background = inset
        ? tokens.well
        : raised
        ? tokens.cardRaised
        : subtle
        ? tokens.cardSubtle
        : tokens.card;
    final pad = padding ?? EdgeInsets.all(tokens.density.cardPadding);
    final noShadow = subtle || raised || inset;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(padding: pad, child: child),
        if (footer != null) ...<Widget>[
          Divider(height: 1, thickness: 1, color: tokens.hairline),
          Padding(
            padding: EdgeInsets.all(tokens.density.cardPadding),
            child: footer,
          ),
        ],
      ],
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      );
    }

    final radius = BorderRadius.circular(tokens.radii.card);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(color: tokens.hairline),
          boxShadow: noShadow ? const <BoxShadow>[] : tokens.shadowCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            content,
            if (accent != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: spineWidth,
                child: ColoredBox(color: accent!),
              ),
          ],
        ),
      ),
    );
  }
}
