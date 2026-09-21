/// N4.8 — the fullscreen graph host.
///
/// The prototype appends `renderFullGraph()` after the named overlay, so the
/// fullscreen chart sits above the overlay stack. It dismisses on a scrim tap
/// (and on the compress button, which N7 owns). The chart body is N7's
/// [GraphFullscreenBody]; this is the mount point and the dismissal contract.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Mounts [child] full-screen above everything, over a dismissable scrim.
class ShellFullscreenGraphHost extends StatelessWidget {
  const ShellFullscreenGraphHost({
    super.key,
    required this.onDismiss,
    required this.child,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('shell-graph-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(color: tokens.scrim),
          ),
        ),
        Positioned.fill(
          child: Container(
            key: const ValueKey<String>('shell-graph-host'),
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radii.card),
              border: Border.all(color: tokens.hairlineStrong),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
