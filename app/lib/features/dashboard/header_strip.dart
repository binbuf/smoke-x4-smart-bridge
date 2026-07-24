/// A9.3 — the dashboard header (design 08 §8.6).
///
/// Session name, elapsed time, and the honest answer to "how am I talking
/// to this thing". Three states the strip exists to distinguish, and the
/// screen is the only place any of them can be said:
///
///  * **degraded** — the winner was BLE, so there is no full history and
///    the chart already says so (A10.5). The chip says why.
///  * **base lost** — the *bridge* is reachable, the *base station* is
///    not. Reading temperatures that stopped updating twelve minutes ago
///    is the failure this row prevents.
///  * **no battery data** — `soc_pct` is unknowable until F12 (M5), and
///    the real device returns `null` today. It renders as absence. A `0%`
///    on an MVP screenshot is a bug report filed against the hardware.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'dashboard_snapshot.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('dashboard-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                snapshot.sessionName.isEmpty
                    ? (snapshot.sessionActive ? 'Cook' : 'No cook running')
                    : snapshot.sessionName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (snapshot.sessionActive)
              Text(
                formatElapsed(snapshot.elapsedS),
                key: const Key('dashboard-elapsed'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LinkChip(snapshot: snapshot),
            if (snapshot.batteryKnown)
              _Chip(
                key: const Key('dashboard-battery'),
                icon: snapshot.charging
                    ? Icons.battery_charging_full
                    : Icons.battery_std,
                label: '${snapshot.socPct}%',
              )
            else
              _Chip(
                key: const Key('dashboard-battery-unknown'),
                icon: Icons.battery_unknown,
                // Not "0%". The device cannot report a battery yet
                // (F12, M5) and saying so is the whole point.
                label: 'battery n/a',
              ),
            if (snapshot.baseLost)
              _Chip(
                key: const Key('dashboard-base-lost'),
                icon: Icons.sensors_off,
                label: snapshot.lastPacketSAgo == null
                    ? 'base station not heard from'
                    : 'base station silent for '
                          '${formatDuration(snapshot.lastPacketSAgo!)}',
                emphasis: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.snapshot});
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => switch (snapshot.link) {
    LinkKind.http => _Chip(
      key: const Key('dashboard-link-http'),
      icon: Icons.wifi,
      label: snapshot.address.isEmpty
          ? 'connected'
          : snapshot.address.replaceFirst(RegExp('^https?://'), ''),
    ),
    LinkKind.ble => const _Chip(
      key: Key('dashboard-link-ble'),
      icon: Icons.bluetooth,
      label: 'Bluetooth — no full history',
    ),
    LinkKind.offline => const _Chip(
      key: Key('dashboard-link-offline'),
      icon: Icons.cloud_off,
      // Offline is a state, not an error: the cache serves every
      // historical screen with the bridge unplugged (A4.4).
      label: 'offline — showing saved data',
      emphasis: true,
    ),
  };
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.emphasis = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = emphasis
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 6),
        // The chips sit in a Wrap on a phone that may be 320 dp wide, and
        // "base station silent for 12m" is a long thing to say. Let it
        // shrink rather than overflow.
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: fg),
          ),
        ),
      ],
    );
  }
}
