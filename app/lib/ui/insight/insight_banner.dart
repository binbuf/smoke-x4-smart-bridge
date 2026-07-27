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
          Expanded(
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
            Text(
              trailing!,
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ],
          if (action != null) ...[
            const SizedBox(width: SmokeTokens.s1),
            action!,
          ],
        ],
      ),
    );
  }
}
