/// A26 — the top bar a failed refresh puts up (design 13 §13.5.7).
///
/// The rule this exists for: **a pull that could not get a new reading must
/// say so.** Leaving the previous number on screen is indistinguishable from
/// a refresh that worked and found nothing new, and on this app that
/// difference is "your pit is at 225 °F" versus "your pit was at 225 °F
/// before the bridge went off an hour ago".
///
/// It is deliberately the *narrowest* member of §13.5.7's banner family: one
/// message, one action, dismissible. It rides above every tab — including
/// Cook, which owns its own chrome and would otherwise be the one screen
/// where a failed pull said nothing at all.
///
/// Collapsed to zero height when there is nothing to report, and always
/// mounted, so it animates in and out rather than jumping the layout.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'shell_session.dart';

class RefreshBanner extends StatelessWidget {
  const RefreshBanner({
    super.key,
    required this.failure,
    this.busy = false,
    this.onRetry,
    this.onDismiss,
  });

  /// Null → nothing to say → zero height.
  final RefreshFailure? failure;

  /// A pull is in flight. The banner says so rather than leaving the
  /// previous failure on screen while we are already fixing it.
  final bool busy;

  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    final f = failure;
    return AnimatedSize(
      duration: motion.standard,
      curve: motion.curve,
      alignment: Alignment.topCenter,
      child: f == null
          ? const SizedBox(width: double.infinity)
          : _bar(context, f),
    );
  }

  Widget _bar(BuildContext context, RefreshFailure f) {
    final t = context.tokens;
    // Not reaching the bridge at all is the loud one; a bridge that answered
    // and then stumbled is an advisory, not an alarm.
    final role = f.notConnected ? StatusRole.critical : StatusRole.warning;
    final hue = StatusPalette.hue(role);
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${f.title}. ${f.detail}',
      child: Container(
        key: const Key('refresh-banner'),
        width: double.infinity,
        color: StatusPalette.fill(role),
        padding: const EdgeInsets.fromLTRB(
          SmokeTokens.s4,
          SmokeTokens.s3,
          SmokeTokens.s2,
          SmokeTokens.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              busy
                  ? Icons.sync_rounded
                  : (f.notConnected
                        ? Icons.cloud_off_rounded
                        : Icons.error_outline_rounded),
              color: hue,
              size: 22,
            ),
            const SizedBox(width: SmokeTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busy ? 'Trying again…' : f.title,
                    key: const Key('refresh-banner-title'),
                    // The words are carried at 13:1, never in the status hue
                    // (14 §14.6.5) — the hue is the icon's job.
                    style: SmokeType.title.copyWith(color: t.textHi),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    f.detail,
                    key: const Key('refresh-banner-detail'),
                    style: SmokeType.bodySm.copyWith(color: t.textBody),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SmokeTokens.s2),
            // Both controls vanish while a retry is running: a Retry button
            // that does nothing because one is already in flight is a dead
            // control (rail R2).
            if (!busy) ...[
              if (onRetry != null)
                TextButton(
                  key: const Key('refresh-banner-retry'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: t.textHi,
                    backgroundColor: hue.withValues(alpha: 0.2),
                  ),
                  child: const Text('Try again'),
                ),
              if (onDismiss != null)
                IconButton(
                  key: const Key('refresh-banner-dismiss'),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: t.textMuted),
                  tooltip: 'Dismiss',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
