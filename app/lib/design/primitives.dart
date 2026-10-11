/// Stateless presentation primitives over plain values.
///
/// These honour the two colour rules from the tokens: a status hue is only ever
/// chrome (a tinted fill with a border, carrying an icon *and* a word, with the
/// text in the high-contrast ink), and it never fills a large shape.
library;

import 'package:flutter/material.dart';

import '../domain/domain.dart';
import 'tokens.dart';

/// A raised card with the standard radius and hairline border.
class SmokeCard extends StatelessWidget {
  const SmokeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SmokeSpace.lg),
    this.raised = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: raised ? SmokePalette.cardRaised : SmokePalette.card,
        borderRadius: BorderRadius.circular(SmokeRadius.card),
        border: Border.all(color: SmokePalette.hairline),
      ),
      child: child,
    );
  }
}

/// A pill carrying a status hue as a tinted fill + border, with an icon and a
/// word. The label is always high-contrast ink, never the status hue.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeSpace.md,
        vertical: SmokeSpace.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SmokeRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: SmokePalette.textHi),
          const SizedBox(width: SmokeSpace.xs + 2),
          Text(
            label,
            style: const TextStyle(
              color: SmokePalette.textHi,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps the freshness ladder to a status hue, an icon and a word.
({Color color, IconData icon, String label}) freshnessChrome(Freshness f) {
  switch (f) {
    case Freshness.live:
      return (color: SmokePalette.positive, icon: Icons.sensors, label: 'Live');
    case Freshness.aging:
      return (
        color: SmokePalette.warning,
        icon: Icons.schedule,
        label: 'Aging',
      );
    case Freshness.stale:
      return (
        color: SmokePalette.warning,
        icon: Icons.history_toggle_off,
        label: 'Stale',
      );
    case Freshness.frozen:
      return (
        color: SmokePalette.critical,
        icon: Icons.signal_wifi_off,
        label: 'No signal',
      );
    case Freshness.unknown:
      return (
        color: SmokePalette.textMuted,
        icon: Icons.help_outline,
        label: 'No reading',
      );
  }
}

/// A freshness chip built from [freshnessChrome].
class FreshnessChip extends StatelessWidget {
  const FreshnessChip({super.key, required this.freshness});

  final Freshness freshness;

  @override
  Widget build(BuildContext context) {
    final c = freshnessChrome(freshness);
    return StatusChip(icon: c.icon, label: c.label, color: c.color);
  }
}

/// Glyph + title + one sentence + exactly one optional action. The house shape
/// for every "nothing here yet" state, so no screen dead-ends.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.tone = SmokePalette.textMuted,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SmokeSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tone),
            const SizedBox(height: SmokeSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SmokePalette.textHi,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SmokeSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SmokePalette.textBody,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: SmokeSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A small series-hue dot — the only place a series colour appears outside the
/// chart, and it never carries a word.
class SeriesDot extends StatelessWidget {
  const SeriesDot({super.key, required this.jack, this.size = 10});

  final int jack;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SmokePalette.forJack(jack),
        shape: BoxShape.circle,
      ),
    );
  }
}
