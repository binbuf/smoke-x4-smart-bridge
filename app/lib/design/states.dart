/// N3.25–N3.26 — the "nothing here" states and the stale veil.
///
/// `EmptyState`, `ProblemState` and `LoadingState` are the three ways a surface
/// says it has nothing to show. **Each has exactly one way forward (I6)** —
/// the action label is required, so a screen cannot accidentally ship a dead
/// end. `ProblemState` never surfaces a raw exception (I15): it takes named
/// copy, not an `Object error`.
///
/// `StaleVeil` desaturates, dims and pins an age label. It refuses to dim twice
/// ([alreadyDimmed]): a veil over a veil turns a legible "12 min ago" into mud.
library;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

class _StateScaffold extends StatelessWidget {
  const _StateScaffold({
    required this.title,
    required this.copy,
    required this.actionLabel,
    required this.onAction,
    required this.art,
  });

  final String title;
  final String copy;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.s4,
        vertical: tokens.spacing.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          art,
          SizedBox(height: tokens.spacing.s3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SmokeText.cardTitle.copyWith(
              fontSize: 17,
              color: tokens.textHi,
            ),
          ),
          SizedBox(height: tokens.spacing.s1),
          Text(
            copy,
            textAlign: TextAlign.center,
            style: SmokeText.sub.copyWith(color: tokens.textBody),
          ),
          SizedBox(height: tokens.spacing.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: PrimaryAction(label: actionLabel, onPressed: onAction),
          ),
        ],
      ),
    );
  }
}

Widget _art(BuildContext context, SmokeGlyph glyph, Color hue) {
  final tokens = SmokeTokens.of(context);
  return Container(
    width: 88,
    height: 88,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: tokens.tint(hue, 0.14),
      border: Border.all(color: tokens.hairline),
    ),
    child: SmokeIcon(glyph, size: 36, color: hue),
  );
}

/// A surface with nothing to show and one way forward.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.copy,
    required this.actionLabel,
    required this.onAction,
    this.icon = SmokeGlyph.thermometer,
  });

  final String title;
  final String copy;
  final String actionLabel;
  final VoidCallback onAction;
  final SmokeGlyph icon;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return _StateScaffold(
      title: title,
      copy: copy,
      actionLabel: actionLabel,
      onAction: onAction,
      art: _art(context, icon, tokens.pit),
    );
  }
}

/// A named failure with one way forward. Never a raw exception.
class ProblemState extends StatelessWidget {
  const ProblemState({
    super.key,
    required this.title,
    required this.copy,
    required this.actionLabel,
    required this.onAction,
    this.icon = SmokeGlyph.alertTriangle,
  });

  final String title;
  final String copy;
  final String actionLabel;
  final VoidCallback onAction;
  final SmokeGlyph icon;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return _StateScaffold(
      title: title,
      copy: copy,
      actionLabel: actionLabel,
      onAction: onAction,
      art: _art(context, icon, tokens.warning),
    );
  }
}

/// A loading surface with one action (typically Cancel).
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    required this.title,
    required this.copy,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String copy;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return _StateScaffold(
      title: title,
      copy: copy,
      actionLabel: actionLabel,
      onAction: onAction,
      art: SizedBox(
        width: 88,
        height: 88,
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3, color: tokens.pit),
          ),
        ),
      ),
    );
  }
}

/// Desaturate + dim + pin an age label over stale content.
class StaleVeil extends StatelessWidget {
  const StaleVeil({
    super.key,
    required this.ageLabel,
    required this.child,
    this.alreadyDimmed = false,
  });

  final String ageLabel;
  final Widget child;

  /// When the child is already dimmed, pin the label only — no double dimming.
  final bool alreadyDimmed;

  // Rec. 601 luma weights: greyscale while preserving alpha.
  static const List<double> _greyscale = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final veiled = alreadyDimmed
        ? child
        : ColorFiltered(
            colorFilter: const ColorFilter.matrix(_greyscale),
            child: Opacity(opacity: 0.55, child: child),
          );
    return Stack(
      children: <Widget>[
        veiled,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.tint(tokens.bg, 0.45),
                borderRadius: BorderRadius.circular(tokens.radii.card),
              ),
              child: Text(
                ageLabel,
                style: SmokeText.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.textMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
