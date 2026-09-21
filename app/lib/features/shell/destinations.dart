/// N4.3/exit gate — placeholder destination screens.
///
/// The real Live / Temps / Timeline / Graph / Settings / History / Cook detail
/// screens arrive in N5–N13. Until then each route renders a placeholder that
/// still lives inside the real chrome and reads its state from the N2
/// providers, never from the shell. The demo actions exist so the shell's
/// overlay, fullscreen-graph and toast seams are reachable and testable from
/// every surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import 'shell.dart';
import 'shell_screen.dart';

/// The shared destination body.
class DestinationPlaceholder extends ConsumerWidget {
  const DestinationPlaceholder({super.key, required this.screen});

  final ShellScreen screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final scope = ShellScope.maybeOf(context);
    final snapshot = ref.watch(snapshotProvider).value;
    final unacked = snapshot?.alarms.where((alarm) => !alarm.acked).length ?? 0;
    final phase = snapshot?.connection.phase.name ?? 'unknown';

    return Column(
      key: ValueKey<String>('destination-${screen.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SmokeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                screen.title,
                style: SmokeText.title.copyWith(color: tokens.textHi),
              ),
              const SizedBox(height: 4),
              Text(
                screen.subtitle ?? 'A placeholder destination.',
                style: SmokeText.body.copyWith(color: tokens.textBody),
              ),
              const SizedBox(height: 8),
              Text(
                'Connection: $phase · unacked alarms: $unacked',
                key: const ValueKey<String>('destination-state'),
                style: SmokeText.monoSmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('destination-connect'),
                label: 'Connect',
                icon: SmokeGlyph.link,
                onPressed: () => scope?.openOverlay(DevOverlay.connect),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('destination-alerts'),
                label: 'Alerts',
                icon: SmokeGlyph.bell,
                onPressed: () => scope?.openOverlay(DevOverlay.alarms),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('destination-fullscreen'),
                label: 'Fullscreen',
                icon: SmokeGlyph.expand,
                onPressed: () => scope?.toggleFullGraph(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('destination-toast'),
                label: 'Toast',
                icon: SmokeGlyph.info,
                onPressed: () => scope?.showToast('Hello from ${screen.title}'),
              ),
            ),
          ],
        ),
        if (screen == ShellScreen.settings) ...<Widget>[
          const SizedBox(height: 12),
          SmokeCard(
            child: SettingsRow(
              key: const ValueKey<String>('destination-open-history'),
              icon: SmokeGlyph.history,
              name: 'History',
              sub: 'Past cooks',
              onTap: () => scope?.showToast('History is N12'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Live destination (N5).
class LiveDestination extends StatelessWidget {
  const LiveDestination({super.key});

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.live);
}

/// Temps destination (N6).
class TempsDestination extends StatelessWidget {
  const TempsDestination({super.key});

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.temps);
}

/// Timeline destination (N8).
class TimelineDestination extends StatelessWidget {
  const TimelineDestination({super.key});

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.timeline);
}

/// Graph destination (N7).
class GraphDestination extends StatelessWidget {
  const GraphDestination({super.key});

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.graph);
}

/// Settings destination (N13).
class SettingsDestination extends StatelessWidget {
  const SettingsDestination({super.key});

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.settings);
}

/// History destination (N12).
class HistoryDestination extends StatelessWidget {
  const HistoryDestination({super.key});

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.history);
}

/// Cook detail destination (N12).
class CookDetailDestination extends StatelessWidget {
  const CookDetailDestination({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) =>
      const DestinationPlaceholder(screen: ShellScreen.cookDetail);
}
