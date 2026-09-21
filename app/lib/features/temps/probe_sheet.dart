/// N6.7–N6.12 — the probe detail sheet.
///
/// Header (jack, food avatar, catalog name), the hero temperature with its
/// sparkline and trend, the phase track for a targeted food probe, the
/// High/Avg/Low stats, then the three editors and actions: role (any jack),
/// target (doneness chips from the assigned preset), and Mark pulled / Test
/// alarm / Share this probe.
///
/// Invariants encoded here:
/// * **I3** — an unplugged probe shows `—`, never `0`, in the hero.
/// * **I4** — the sparkline and trend are removed for a reading that is not
///   current.
/// * **I12** — the "pull at X" notice goes through the floor-clamped
///   [pullForDoneness]; an unassignable probe offers "Set a target" instead of
///   guessing one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/cook_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import '../shell/shell.dart';
import 'temps_format.dart';

class ProbeSheetBody extends ConsumerWidget {
  const ProbeSheetBody({super.key, required this.jack, required this.onDone});

  final ProbeJack jack;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final scope = ShellScope.maybeOf(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    final snapshot = ref.watch(snapshotProvider).value;
    final unit =
        ref.watch(settingsProvider).value?.units ?? TempUnit.fahrenheit;

    final probes = snapshot?.probes ?? const <ProbeState>[];
    final cook = snapshot?.cook ?? const CookState();
    final probe = probeFor(probes, jack);
    final entry = cookEntryFor(cook, repo.catalog, jack);
    final isGrate = probe.role == ProbeRole.pit;
    final live = isLiveProbe(probe);
    final canShow = probe.freshness.showsDerived;
    final parts = tempParts(live ? probe.tempF10 : null, unit);
    final trend = trendFor(canShow ? probe.trendFPerHr : null);
    final name = entry?.name ?? (isGrate ? 'Grate / pit' : 'Probe ${jack.n}');

    void toast(String message) => scope?.showToast(message);

    return Column(
      key: const ValueKey<String>('probe-sheet-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          key: const ValueKey<String>('probe-sheet-header'),
          children: <Widget>[
            JackBadge(jack: jack.n, detached: !live),
            if (entry != null) ...<Widget>[
              const SizedBox(width: 8),
              FoodAvatar(
                FoodGlyph.parse(entry.glyph),
                size: FoodAvatarSize.lg,
                register: FoodAvatarRegister.disciplined,
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    key: const ValueKey<String>('probe-sheet-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SmokeText.cardTitle.copyWith(
                      fontSize: 17,
                      color: tokens.textHi,
                    ),
                  ),
                  Text(
                    live ? 'Live · jack ${jack.n}' : 'Unplugged',
                    key: const ValueKey<String>('probe-sheet-sub'),
                    style: SmokeText.labelSm.copyWith(
                      fontSize: 11,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      text: parts.num,
                      children: <InlineSpan>[
                        if (parts.dec.isNotEmpty)
                          TextSpan(
                            text: parts.dec,
                            style: const TextStyle(fontSize: 30),
                          ),
                        if (parts.unit.isNotEmpty)
                          TextSpan(
                            text: parts.unit,
                            style: TextStyle(
                              fontSize: 18,
                              color: tokens.textMuted,
                            ),
                          ),
                      ],
                    ),
                    key: const ValueKey<String>('probe-sheet-temp'),
                    maxLines: 1,
                    style: SmokeText.tempXl.copyWith(color: tokens.textHi),
                  ),
                  const SizedBox(height: 8),
                  TrendChip(direction: trend.direction, label: trend.label),
                ],
              ),
            ),
            if (live && probe.spark.length > 1)
              Sparkline(
                key: const ValueKey<String>('probe-sheet-spark'),
                values: <double>[
                  for (final value in probe.spark) value.toDouble(),
                ],
                color: tokens.series(jack.n),
                width: 96,
                height: 54,
              ),
          ],
        ),
        if (!isGrate && probe.targetF10 != null) ...<Widget>[
          const SizedBox(height: 16),
          SmokeCard(
            key: const ValueKey<String>('probe-sheet-phase-card'),
            subtle: true,
            padding: const EdgeInsets.all(14),
            child: PhaseTrack(
              key: const ValueKey<String>('probe-sheet-phase'),
              phases: kProbePhases,
              currentIndex: probePhaseIndex(
                tempF10: probe.tempF10,
                pullF10: probe.pullF10,
                targetF10: probe.targetF10,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        StatGrid(
          key: const ValueKey<String>('probe-sheet-stats'),
          stats: <SmokeStat>[
            SmokeStat(label: 'High', value: fmtTempUnit(probe.peakF10, unit)),
            SmokeStat(label: 'Avg', value: fmtTempUnit(probe.avgF10, unit)),
            SmokeStat(label: 'Low', value: fmtTempUnit(probe.lowF10, unit)),
          ],
        ),
        const SizedBox(height: 20),
        _EditorLabel(label: 'Role'),
        const SizedBox(height: 8),
        FilterChips<ProbeRole>(
          key: const ValueKey<String>('probe-sheet-roles'),
          options: const <SmokeSegment<ProbeRole>>[
            SmokeSegment<ProbeRole>(value: ProbeRole.food, label: 'Food'),
            SmokeSegment<ProbeRole>(value: ProbeRole.pit, label: 'Grate (pit)'),
            SmokeSegment<ProbeRole>(value: ProbeRole.unused, label: 'Unused'),
          ],
          value: probe.role,
          onChanged: (role) => repo.probeRole(jack, role),
        ),
        if (!isGrate) ...<Widget>[
          const SizedBox(height: 20),
          _EditorLabel(label: 'Target'),
          const SizedBox(height: 8),
          if (entry != null) ...<Widget>[
            FilterChips<Doneness>(
              key: const ValueKey<String>('probe-sheet-doneness'),
              options: <SmokeSegment<Doneness>>[
                for (final doneness in entry.doneness)
                  SmokeSegment<Doneness>(
                    value: doneness,
                    label:
                        '${doneness.label} · ${fmtTempUnit(doneness.targetF10, unit)}',
                  ),
              ],
              value: selectedDoneness(entry, probe.targetF10),
              onChanged: (doneness) => repo.setTarget(jack, doneness.targetF10),
            ),
            const SizedBox(height: 10),
            CapabilityNotice(
              key: const ValueKey<String>('probe-sheet-pull-notice'),
              message:
                  'Pull at ${fmtTempUnit(probe.pullF10 ?? pullForDoneness(entry, selectedDoneness(entry, probe.targetF10)), unit)} '
                  '— it coasts up to target while it rests.',
            ),
          ] else
            SmokeButton(
              key: const ValueKey<String>('probe-set-target'),
              label: 'Set a target for this probe',
              icon: SmokeGlyph.target,
              variant: SmokeButtonVariant.ghost,
              onPressed: () => scope?.openOverlay(
                DevOverlay.setup,
                <String, String>{'context': 'edit', 'jack': '${jack.n}'},
              ),
            ),
        ],
        const SizedBox(height: 20),
        ActionRow(
          actions: <SmokeActionSpec>[
            SmokeActionSpec(
              label: 'Mark pulled',
              icon: SmokeGlyph.check,
              onPressed: () async {
                await repo.markPulled(jack);
                toast('Pulled — rest timer started');
                onDone();
              },
            ),
            SmokeActionSpec(
              label: 'Test alarm',
              icon: SmokeGlyph.zap,
              variant: SmokeButtonVariant.ghost,
              onPressed: () => toast('Test alarm sent to your phone'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SmokeButton(
          key: const ValueKey<String>('probe-share'),
          label: 'Share this probe',
          icon: SmokeGlyph.share,
          variant: SmokeButtonVariant.ghost,
          onPressed: () => toast('Opening share sheet — probe'),
        ),
      ],
    );
  }
}

class _EditorLabel extends StatelessWidget {
  const _EditorLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Text(
      label.toUpperCase(),
      style: SmokeText.labelSm.copyWith(
        letterSpacing: 0.9,
        color: tokens.textMuted,
      ),
    );
  }
}
