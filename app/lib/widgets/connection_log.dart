import 'package:flutter/material.dart';

import '../app/formatters.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

/// A single timeline for Bridge pairing, phone connections and Billows. Billows
/// is discovered through the Smoke X4, so a dropped fan belongs beside the
/// regular connection history rather than in a hidden monitoring mode.
class ConnectionLogList extends StatelessWidget {
  const ConnectionLogList({
    super.key,
    required this.events,
    this.billowsOnly = false,
    this.limit,
  });

  final List<ConnectionEvent> events;
  final bool billowsOnly;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = limit == null ? events : events.take(limit!).toList();
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          billowsOnly
              ? 'No Billows events yet. Billows will appear here when the Smoke X detects it.'
              : 'No connection events yet.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const Divider(height: 18),
          _EventRow(event: visible[i], use24Hour: use24Hour),
        ],
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.use24Hour});

  final ConnectionEvent event;
  final bool use24Hour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (event.kind) {
      ConnectionEventKind.bridgeConnected => (
        StatusColors.live(context),
        Icons.bluetooth_connected,
      ),
      ConnectionEventKind.bridgeLost => (
        StatusColors.aging(context),
        Icons.bluetooth_disabled,
      ),
      ConnectionEventKind.smokeXPaired => (
        StatusColors.live(context),
        Icons.sensors,
      ),
      ConnectionEventKind.smokeXLost => (
        StatusColors.aging(context),
        Icons.sensors_off,
      ),
      ConnectionEventKind.billowsConnected => (
        StatusColors.live(context),
        Icons.air,
      ),
      ConnectionEventKind.billowsLost => (
        StatusColors.aging(context),
        Icons.air,
      ),
      ConnectionEventKind.repair => (
        StatusColors.info(context),
        Icons.sync_alt,
      ),
      ConnectionEventKind.sync => (StatusColors.info(context), Icons.sync),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 1),
              Text(
                event.detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${shortDate(event.time)} · ${clockLabel(event.time, use24Hour: use24Hour)}',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
