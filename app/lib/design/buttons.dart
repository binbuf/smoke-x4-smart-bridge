/// N3.14 — `PrimaryAction` and `SmokeButton`.
///
/// `PrimaryAction` is the **only** ember-filled button in the system, and a
/// screen has at most one (I14). `SmokeButton` is everything else: `normal`,
/// `ghost` and `danger`, each in `md` or `sm`.
///
/// **No dead controls (I5).** A disabled button either states its reason inline
/// or is absent; [SmokeButton] takes [reason] and [PrimaryAction] takes
/// [enabledReason], both rendered as muted copy under the button.
library;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

/// The non-primary button variants.
enum SmokeButtonVariant { normal, ghost, danger }

/// The button size.
enum SmokeButtonSize { md, sm }

/// The one ember primary action on a surface.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.enabledReason,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final SmokeGlyph? icon;

  /// Why the action is unavailable (I5). Shown when [onPressed] is null.
  final String? enabledReason;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(tokens.radii.control);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[tokens.p1, tokens.pit],
                  )
                : null,
            color: enabled ? null : tokens.cardRaised,
            borderRadius: radius,
            border: Border.all(
              color: enabled
                  ? tokens.tint(tokens.textHi, 0.12)
                  : tokens.hairlineStrong,
            ),
            boxShadow: enabled && tokens.glow > 0
                ? <BoxShadow>[
                    BoxShadow(
                      color: tokens.tint(tokens.pit, 0.55),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      spreadRadius: -8,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (busy)
                      SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.tint(tokens.textHi, 0.9),
                        ),
                      )
                    else if (icon != null)
                      SmokeIcon(
                        icon!,
                        size: 17,
                        color: enabled
                            ? const Color(0xFF0A0400)
                            : tokens.textMuted,
                      ),
                    if (busy || icon != null) const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SmokeText.bodyStrong.copyWith(
                          color: enabled
                              ? const Color(0xFF0A0400)
                              : tokens.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!enabled && enabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              enabledReason!,
              textAlign: TextAlign.center,
              style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
            ),
          ),
      ],
    );
  }
}

/// A non-primary button.
class SmokeButton extends StatelessWidget {
  const SmokeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SmokeButtonVariant.normal,
    this.size = SmokeButtonSize.md,
    this.icon,
    this.reason,
  });

  final String label;
  final VoidCallback? onPressed;
  final SmokeButtonVariant variant;
  final SmokeButtonSize size;
  final SmokeGlyph? icon;

  /// Why the button is disabled (I5).
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final disabled = onPressed == null;
    final (background, border, foreground) = switch (variant) {
      SmokeButtonVariant.ghost => (
        Colors.transparent,
        tokens.hairlineStrong,
        tokens.textHi,
      ),
      SmokeButtonVariant.danger => (
        tokens.tint(tokens.critical, 0.10),
        tokens.tint(tokens.critical, 0.40),
        tokens.critical,
      ),
      SmokeButtonVariant.normal => (
        tokens.cardRaised,
        tokens.hairlineStrong,
        tokens.textHi,
      ),
    };
    final vertical = size == SmokeButtonSize.sm ? 8.0 : 12.0;
    final horizontal = size == SmokeButtonSize.sm ? 12.0 : 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Opacity(
          opacity: disabled ? 0.45 : 1,
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              side: BorderSide(color: border),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(tokens.radii.control),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: vertical,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      SmokeIcon(icon!, size: 17, color: foreground),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SmokeText.label.copyWith(
                          fontSize: size == SmokeButtonSize.sm ? 12.5 : 14,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (disabled && reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              reason!,
              textAlign: TextAlign.center,
              style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
            ),
          ),
      ],
    );
  }
}

/// A button spec for [ActionRow].
@immutable
class SmokeActionSpec {
  const SmokeActionSpec({
    required this.label,
    required this.onPressed,
    this.variant = SmokeButtonVariant.normal,
    this.icon,
    this.reason,
  });

  final String label;
  final VoidCallback? onPressed;
  final SmokeButtonVariant variant;
  final SmokeGlyph? icon;

  /// Shown when [onPressed] is null (I5).
  final String? reason;
}

/// A row of actions, each of which states why it is disabled.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.actions, this.expand = true});

  final List<SmokeActionSpec> actions;

  /// Whether each action shares the width equally.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      final action = actions[i];
      final button = SmokeButton(
        label: action.label,
        onPressed: action.onPressed,
        variant: action.variant,
        icon: action.icon,
        reason: action.reason,
      );
      children.add(expand ? Expanded(child: button) : button);
      if (i < actions.length - 1) {
        const SizedBox(width: 8);
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
