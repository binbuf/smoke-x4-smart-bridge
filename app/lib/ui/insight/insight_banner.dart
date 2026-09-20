/// A19.6 — InsightBanner (design 14 §14.7.1, §14.6.5).
///
/// A slim strip for a single derived insight — a stall, an out-of-band pit, an
/// ETA, a lid-open grace, a capability notice. It is *chrome*, so it obeys the
/// separation rule: a status-hue fill and border, and **the text is `textHi`,
/// never the hue.** Measured, `critical` on its own 14% fill is 3.19:1 while
/// `textHi` is 12.6–14.1:1 — the hue is carried by the icon and the border, the
/// words at 13:1 (§14.6.5). Trailing values use `textBody`.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

enum InsightKind { stall, band, eta, lid, alarm, advisory, capability }

class InsightBanner extends StatelessWidget {
  const InsightBanner({
    super.key,
    required this.kind,
    required this.label,
    this.trailing,
    this.icon,
    this.action,
  });

  final InsightKind kind;
  final String label;
  final String? trailing;
  final IconData? icon;
  final Widget? action;

  StatusRole get _role => switch (kind) {
    InsightKind.stall || InsightKind.band => StatusRole.warning,
    InsightKind.eta ||
    InsightKind.advisory ||
    InsightKind.capability => StatusRole.info,
    InsightKind.lid || InsightKind.alarm => StatusRole.critical,
  };

  IconData get _icon =>
      icon ??
      switch (kind) {
        InsightKind.stall => Icons.trending_flat_rounded,
        InsightKind.band => Icons.speed_rounded,
        InsightKind.eta => Icons.schedule_rounded,
        InsightKind.lid => Icons.door_front_door_outlined,
        InsightKind.alarm => Icons.notifications_active_rounded,
        InsightKind.advisory => Icons.info_outline_rounded,
        InsightKind.capability => Icons.lock_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final role = _role;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 16, color: StatusPalette.hue(role)),
          const SizedBox(width: SmokeTokens.s2),
          // **Both texts are flex children, and that is the whole fix.**
          //
          // The trailing used to be a bare `Text` beside an `Expanded` label:
          // a non-flex child of a `Row` is laid out against unbounded width,
          // so it never wrapped and never ellipsised — it overflowed, and the
          // strip that carries the app's honesty rendered a yellow-and-black
          // bar instead. That takes a 200 % text scale and a label like *"No
          // estimate — the temperature is holding steady."*, which is to say
          // it takes exactly the reader this component exists for.
          //
          // The inner row is `spaceBetween` so the value still sits at the
          // right edge when there is room, and each side is capped at half the
          // strip and wraps inside its own half when there is not.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: SmokeType.bodySm.copyWith(
                      color: t.textHi,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: SmokeTokens.s2),
                  Flexible(
                    child: Text(
                      trailing!,
                      textAlign: TextAlign.end,
                      // A trailing is a *value* — a duration, a band, a
                      // count. Two lines is already generous; a third would
                      // mean the caller put a sentence in the wrong slot.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SmokeType.bodySm.copyWith(color: t.textBody),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: SmokeTokens.s1),
            action!,
          ],
        ],
      ),
    );
  }
}
