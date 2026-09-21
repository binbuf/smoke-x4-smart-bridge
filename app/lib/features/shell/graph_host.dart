/// N4.8 — the fullscreen graph host.
///
/// The prototype appends `renderFullGraph()` after the named overlay, so the
/// fullscreen chart sits above the overlay stack. It dismisses on a scrim tap
/// (and on the compress button, which N7 owns). The chart body itself is N7's;
/// this is the mount point and the dismissal contract.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'app_bar.dart';

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

/// The placeholder fullscreen-graph body. N7 replaces [child].
class ShellFullscreenGraphPlaceholder extends StatelessWidget {
  const ShellFullscreenGraphPlaceholder({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Graph',
                    key: const ValueKey<String>('shell-graph-title'),
                    style: SmokeText.title.copyWith(color: tokens.textHi),
                  ),
                  Text(
                    'Fullscreen',
                    style: SmokeText.sub.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            ShellIconButton(
              key: const ValueKey<String>('shell-graph-exit'),
              glyph: SmokeGlyph.compress,
              label: 'Exit fullscreen',
              onTap: onDismiss,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: Text(
              'The fullscreen chart lands in N7.',
              style: SmokeText.body.copyWith(color: tokens.textBody),
            ),
          ),
        ),
      ],
    );
  }
}
