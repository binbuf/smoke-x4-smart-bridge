/// N6.1–N6.6 — the Temps destination: every probe, up close.
///
/// The header (attached count + live/stale word + °F/°C toggle), one big
/// [TempCard] per attached probe, and a "Not attached" section for detached or
/// unused jacks. Tapping a card opens the probe detail sheet (N6.7–N6.12).
///
/// Invariants encoded here:
/// * **I3** — a detached probe is never rendered as a number: it lives in the
///   "Unplugged — absent, never 0°" section, and a card for it would read `—`.
/// * **I6** — an empty board offers exactly one next step ("View graph").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/bridge_snapshot.dart';
import '../../data/model/connection_state.dart';
import '../../data/model/cook_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../shell/phone_frame.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import 'temp_card.dart';
import 'temps_format.dart';

class TempsPage extends ConsumerWidget {
  const TempsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider).value;
    final unit =
        ref.watch(settingsProvider).value?.units ?? TempUnit.fahrenheit;

    if (snapshot == null) {
      return const LoadingState(
        title: 'Reading the bridge',
        copy: 'Waiting for the first snapshot.',
        actionLabel: 'Retry',
        onAction: _noop,
      );
    }
    return _TempsBody(snapshot: snapshot, unit: unit);
  }
}

void _noop() {}

class _TempsBody extends ConsumerWidget {
  const _TempsBody({required this.snapshot, required this.unit});

  final BridgeSnapshot snapshot;
  final TempUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ShellScope.maybeOf(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    final catalog = repo.catalog;
    final attached = attachedProbes(snapshot.probes);
    final detached = detachedProbes(snapshot.probes);
    final connected = snapshot.connection.phase == ConnectionPhase.connected;

    void openProbe(ProbeState probe) {
      scope?.openOverlay(DevOverlay.probe, <String, String>{
        'jack': '${probe.jack.n}',
      });
    }

    if (attached.isEmpty) {
      return ShellScrollHost(
        resetToken: ShellScreen.temps,
        child: EmptyState(
          key: const ValueKey<String>('temps-empty'),
          title: 'No probes attached',
          copy:
              'Plug a probe into the Smoke X4 and it will appear here the '
              'moment the bridge hears it.',
          actionLabel: 'View graph',
          onAction: () => scope?.openScreen(ShellScreen.graph),
        ),
      );
    }

    return ShellScrollHost(
      resetToken: ShellScreen.temps,
      child: Column(
        key: const ValueKey<String>('temps-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _TempsHeader(
            attachedCount: attached.length,
            connected: connected,
            unit: unit,
            onUnit: (next) =>
                ref.read(prefsProvider).update((s) => s.copyWith(units: next)),
          ),
          const SizedBox(height: 12),
          for (final probe in attached) ...<Widget>[
            TempCard(
              probe: probe,
              cook: snapshot.cook,
              catalog: catalog,
              unit: unit,
              onTap: () => openProbe(probe),
            ),
            const SizedBox(height: 10),
          ],
          if (detached.isNotEmpty) ...<Widget>[
            const SectionLabel(label: 'Not attached'),
            SmokeCard(
              key: const ValueKey<String>('temps-detached'),
              subtle: true,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final probe in detached)
                    LinkRow(
                      key: ValueKey<String>('temps-detached-${probe.jack.n}'),
                      icon: SmokeGlyph.thermometer,
                      name: 'Jack ${probe.jack.n}',
                      sub: 'Unplugged — absent, never 0°',
                      off: true,
                      right: SizedBox(
                        width: 88,
                        child: SmokeButton(
                          key: ValueKey<String>(
                            'temps-detached-role-${probe.jack.n}',
                          ),
                          label: 'Set role',
                          variant: SmokeButtonVariant.ghost,
                          size: SmokeButtonSize.sm,
                          onPressed: () => openProbe(probe),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ActionRow(
            actions: <SmokeActionSpec>[
              SmokeActionSpec(
                label: 'Mark',
                icon: SmokeGlyph.bookmark,
                onPressed: () => scope?.openOverlay(DevOverlay.mark),
              ),
              SmokeActionSpec(
                label: 'Add food',
                icon: SmokeGlyph.plus,
                variant: SmokeButtonVariant.ghost,
                onPressed: () => scope?.openOverlay(DevOverlay.setup),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// N6.1 — attached count, the live/stale word and the °F/°C toggle.
class _TempsHeader extends StatelessWidget {
  const _TempsHeader({
    required this.attachedCount,
    required this.connected,
    required this.unit,
    required this.onUnit,
  });

  final int attachedCount;
  final bool connected;
  final TempUnit unit;
  final ValueChanged<TempUnit> onUnit;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      key: const ValueKey<String>('temps-header'),
      children: <Widget>[
        Expanded(
          child: Text(
            '$attachedCount attached · updated ${updatedWord(connected: connected)}',
            key: const ValueKey<String>('temps-attached-count'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SmokeText.labelSm.copyWith(
              fontSize: 11.5,
              color: tokens.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedChips<TempUnit>(
          key: const ValueKey<String>('temps-unit-toggle'),
          segments: const <SmokeSegment<TempUnit>>[
            SmokeSegment<TempUnit>(value: TempUnit.fahrenheit, label: '°F'),
            SmokeSegment<TempUnit>(value: TempUnit.celsius, label: '°C'),
          ],
          value: unit,
          onChanged: onUnit,
        ),
      ],
    );
  }
}
