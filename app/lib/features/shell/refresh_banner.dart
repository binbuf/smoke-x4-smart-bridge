/// A26 — the notice a failed refresh puts up (design 13 §13.5.7, newapp §H.2).
///
/// The rule this exists for: **a pull that could not get a new reading must
/// say so.** Leaving the previous number on screen is indistinguishable from
/// a refresh that worked and found nothing new, and on this app that
/// difference is "your pit is at 225 °F" versus "your pit was at 225 °F
/// before the bridge went off an hour ago".
///
/// ## Rank, and what it costs a notice to be outranked
///
/// It is the *quietest* member of §13.5.7's banner family and it now behaves
/// like it. An alarm is about the cook; this is about the app's own plumbing,
/// so when both are up the alarm gets the slab and this one **compacts to a
/// single line** — icon, cause, retry — dropping its detail and its dismiss.
/// That is §16.3's "one situation at a time" honoured without throwing away
/// the second fact: the loud thing stays loud, and the quiet thing stays
/// present and quiet instead of competing at the same weight.
///
/// Collapsed to zero height when there is nothing to report, and always
/// mounted, so it animates in and out rather than jumping the layout — the
/// reveal itself is [ChromeSlot]'s, shared with the alarm so the two cannot
/// drift apart.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../ui/ui.dart';
import 'shell_session.dart';

class RefreshBanner extends StatelessWidget {
  const RefreshBanner({
    super.key,
    required this.failure,
    this.busy = false,
    this.onRetry,
    this.onDismiss,
    this.compact = false,
  });

  /// Null → nothing to say → zero height.
  final RefreshFailure? failure;

  /// A pull is in flight. The banner says so rather than leaving the
  /// previous failure on screen while we are already fixing it.
  final bool busy;

  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  /// Something louder is already on screen. One line, no detail, no dismiss.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    return ChromeSlot(
      // Same gutter as the alarm — the two notices are siblings and must sit
      // on the same rhythm even though one outranks the other.
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s3,
        vertical: SmokeTokens.s2,
      ),
      child: f == null ? null : _slab(context, f),
    );
  }

  Widget _slab(BuildContext context, RefreshFailure f) {
    final t = context.tokens;
    // Not reaching the bridge at all is the loud one; a bridge that answered
    // and then stumbled is an advisory, not an alarm.
    final role = f.notConnected ? StatusRole.critical : StatusRole.warning;
    final hue = StatusPalette.hue(role);
    final icon = busy
        ? Icons.sync_rounded
        : (f.notConnected ? Icons.cloud_off_rounded : Icons.error_outline_rounded);
    final title = busy ? 'Trying again…' : f.title;
    // At large text a title, a detail and two controls cannot share a row.
    final stacked = !compact && SmokeTextScale.isLarge(context);

    return Semantics(
      liveRegion: true,
      container: true,
      label: compact ? title : '$title. ${f.detail}',
      child: Container(
        key: const Key('refresh-banner'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: StatusPalette.fill(role),
          borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
          border: Border.all(color: StatusPalette.border(role)),
        ),
        padding: const EdgeInsets.all(SmokeTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: hue, size: compact ? 18 : 22),
                const SizedBox(width: SmokeTokens.s3),
                Expanded(child: _words(f, t, title)),
                if (!stacked) ...[
                  const SizedBox(width: SmokeTokens.s2),
                  ..._controls(t, hue),
                ],
              ],
            ),
            if (stacked && !busy && onRetry != null) ...[
              const SizedBox(height: SmokeTokens.s3),
              Row(children: [..._controls(t, hue)]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _words(RefreshFailure f, SmokeTokens t, String title) {
    // Compacted: the cause only. A detail nobody can read under a ringing
    // alarm is noise, and the full sentence is one tap away on /device.
    final style = compact ? SmokeType.bodySm : SmokeType.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          key: const Key('refresh-banner-title'),
          // The words are carried at 13:1, never in the status hue
          // (14 §14.6.5) — the hue is the icon's job.
          style: style.copyWith(
            color: t.textHi,
            fontWeight: compact ? FontWeight.w700 : null,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 2),
          Text(
            f.detail,
            key: const Key('refresh-banner-detail'),
            style: SmokeType.bodySm.copyWith(color: t.textBody),
          ),
        ],
      ],
    );
  }

  /// Both controls vanish while a retry is running: a Retry button that does
  /// nothing because one is already in flight is a dead control (rail R2).
  List<Widget> _controls(SmokeTokens t, Color hue) {
    if (busy) {
      return const [];
    }
    return [
      if (onRetry != null)
        TextButton(
          key: const Key('refresh-banner-retry'),
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: t.textHi,
            backgroundColor: hue.withValues(alpha: 0.22),
            textStyle: SmokeType.bodySm.copyWith(fontWeight: FontWeight.w700),
            minimumSize: const Size(64, 40),
            padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
              side: BorderSide(color: hue.withValues(alpha: 0.35)),
            ),
          ),
          child: const Text('Try again'),
        ),
      // Dismiss is the outranked banner's first casualty: with an alarm above
      // it, a second ✕ on screen is a coin toss about which one you closed.
      if (onDismiss != null && !compact)
        IconButton(
          key: const Key('refresh-banner-dismiss'),
          onPressed: onDismiss,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close_rounded, size: 18, color: t.textMuted),
          tooltip: 'Dismiss',
        ),
    ];
  }
}
