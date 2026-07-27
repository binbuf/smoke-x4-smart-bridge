/// A23.2 — SetupScaffold (design 14 §14.7.1/§14.7.4, states in 13 §13.5.1).
///
/// The frame every `/setup` state wears: the [SetupRail] at the top, a title and
/// optional subtitle, a body, and a pinned footer. Design 13 §13.5.1 states the
/// contract each of the ~34 states honours — *"a SetupScaffold, one primary
/// action, a named secondary, an exit"* — and this widget is where that contract
/// is made structural rather than remembered:
///
/// * **at most one PrimaryAction.** There is exactly one [primary] slot and the
///   scaffold renders nothing else in the action position. A screen cannot show
///   two ember buttons because there is nowhere to put the second — which is
///   rail R1 (13 §13.2) enforced by shape, not by review.
/// * **an exit on every non-terminal state.** [onExit] renders a close control;
///   a terminal instruction screen passes `null` and gets none (14 §14.7.1 — a
///   button that leads nowhere is worse than an admitted dead end).
///
/// [errorTint] flows straight to the rail: it recolours the active circle, or
/// the eyebrow at hop 0. The title is **never** tinted — the status hue rides
/// the icon and the border, never the words (§14.6.5).
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'setup_rail.dart';

class SetupScaffold extends StatelessWidget {
  const SetupScaffold({
    super.key,
    required this.hop,
    this.of = 3,
    required this.title,
    this.subtitle,
    required this.body,
    this.primary,
    this.secondary,
    this.onExit,
    this.errorTint = false,
    this.skipped = const {},
  }) : assert(hop >= 0 && hop <= of, 'hop must be in 0..of');

  final int hop;
  final int of;
  final String title;
  final String? subtitle;

  /// The screen's content. The caller wraps it in a scroll view when it can
  /// grow past the viewport — the scaffold gives it a bounded [Expanded] slot.
  final Widget body;

  /// The single ember action. This is the *only* place a `PrimaryAction` may be
  /// rendered on a setup screen.
  final Widget? primary;

  /// The named secondary — a text action under the primary.
  final Widget? secondary;

  /// Present on every non-terminal state; `null` on a terminal instruction.
  final VoidCallback? onExit;

  final bool errorTint;
  final Set<int> skipped;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeTokens.s5,
          vertical: SmokeTokens.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar — the exit lives here, right-aligned, on every
            // non-terminal state. The row height is reserved even when there is
            // no exit so the rail sits at a stable y across states.
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  const Spacer(),
                  if (onExit != null)
                    IconButton(
                      key: const Key('setup-exit'),
                      onPressed: onExit,
                      icon: Icon(Icons.close_rounded, color: t.textMuted),
                    ),
                ],
              ),
            ),
            SetupRail(hop: hop, of: of, errorTint: errorTint, skipped: skipped),
            const SizedBox(height: SmokeTokens.s6),
            Text(title, style: SmokeType.displayL.copyWith(color: t.textHi)),
            if (subtitle != null) ...[
              const SizedBox(height: SmokeTokens.s2),
              Text(
                subtitle!,
                style: SmokeType.body.copyWith(color: t.textBody),
              ),
            ],
            const SizedBox(height: SmokeTokens.s5),
            Expanded(child: body),
            // Footer: the one primary, then the named secondary beneath it.
            if (primary != null) ...[
              const SizedBox(height: SmokeTokens.s4),
              primary!,
            ],
            if (secondary != null) ...[
              const SizedBox(height: SmokeTokens.s2),
              Center(child: secondary!),
            ],
          ],
        ),
      ),
    );
  }
}
