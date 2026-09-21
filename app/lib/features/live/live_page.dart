/// N5 — the Live screen, the "now" glance.
///
/// Assembled from the N3 primitives and the N2 snapshot. It owns no business
/// state: the snapshot, preferences and every mutation go through the
/// repository seam. Invariants encoded here:
///
/// * **I2** — the cook header states that the bridge records without the phone.
/// * **I3** — absent probes render `—`, never `0` (compact tile).
/// * **I4** — derived values are removed when the reading is not current.
/// * **I14** — at most one ember primary action on screen.
/// * **§7.3** — pausing the stopwatch freezes the display only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/content/catalog.dart';
import '../../data/dev_panel.dart';
import '../../data/model/bridge_snapshot.dart';
import '../../data/model/connection_state.dart';
import '../../data/model/cook_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../onboarding/onboarding_model.dart';
import '../shell/phone_frame.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import 'alarm_strips.dart';
import 'cook_header.dart';
import 'instrument_card.dart';
import 'live_format.dart';
import 'mini_graph.dart';
import 'probe_rail.dart';
import 'summary_strip.dart';

/// The clock the Live screen reads. Overridable so the stopwatch is
/// deterministic in tests. No ticker is owned here (a repeating clock would
/// make `pumpAndSettle` unusable); the page reads this once per build.
final liveNowProvider = Provider<DateTime>((ref) => DateTime.now());

class LivePage extends ConsumerWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider).value;
    final unit =
        ref.watch(settingsProvider).value?.units ?? TempUnit.fahrenheit;
    final now = ref.watch(liveNowProvider);

    if (snapshot == null) {
      return const LoadingState(
        title: 'Reading the bridge',
        copy: 'Waiting for the first snapshot.',
        actionLabel: 'Retry',
        onAction: _noop,
      );
    }
    return _LiveBody(snapshot: snapshot, unit: unit, now: now);
  }
}

void _noop() {}

class _LiveBody extends ConsumerWidget {
  const _LiveBody({
    required this.snapshot,
    required this.unit,
    required this.now,
  });

  final BridgeSnapshot snapshot;
  final TempUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ShellScope.maybeOf(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    final cook = snapshot.cook;
    final catalog = repo.catalog;
    final pending = snapshot.pendingSession;
    final showAdopt = pending != null && !cook.active;

    void openOverlay(
      DevOverlay overlay, [
      Map<String, String> props = const {},
    ]) {
      scope?.openOverlay(overlay, props);
    }

    // N14.13 — a skipped onboarding must never be a dead end: the shell offers
    // a way to connect instead of pretending there is a cook to show.
    if (ref.watch(onboardingSkippedProvider)) {
      return ShellScrollHost(
        resetToken: ShellScreen.live,
        child: EmptyState(
          key: const ValueKey<String>('live-connect-bridge'),
          icon: SmokeGlyph.bluetooth,
          title: 'Connect a bridge',
          copy:
              'No bridge is set up yet. Pair one to start reading '
              'temperatures — the bridge records on its own once it is.',
          actionLabel: 'Set up your bridge',
          onAction: () => openOverlay(DevOverlay.onboarding),
        ),
      );
    }

    return ShellScrollHost(
      resetToken: ShellScreen.live,
      child: Column(
        key: const ValueKey<String>('live-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LiveAlarmStrips(
            alarms: snapshot.alarms,
            unit: unit,
            onAcknowledge: (alarm) => unawaited(repo.ackAlarm(alarm.id)),
            onAcknowledgeAll: () {
              for (final alarm in orderedUnackedAlarms(snapshot.alarms)) {
                unawaited(repo.ackAlarm(alarm.id));
              }
            },
            onOpen: (alarm) => openOverlay(DevOverlay.alarmDetail, {
              'id': alarm.id,
              'tier': alarm.tier.name,
            }),
          ),
          if (snapshot.notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CapabilityNotice(
                key: const ValueKey<String>('live-notice'),
                message: snapshot.notice!,
                severity: BannerSeverity.warn,
              ),
            ),
          if (showAdopt)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AdoptBanner(
                pending: pending,
                now: now,
                onAdopt: () => openOverlay(DevOverlay.adopt),
                onDiscard: () => unawaited(repo.discardSession()),
              ),
            ),
          if (cook.active)
            CookHeaderCard(
              name: cook.name.isEmpty ? 'Cook' : cook.name,
              glyph: _cookGlyph(cook, catalog),
              cook: cook,
              now: now,
              onSettings: () =>
                  openOverlay(DevOverlay.setup, const {'context': 'edit'}),
              onEditStart: () => openOverlay(DevOverlay.editStart),
            )
          else
            InstrumentModeCard(
              primary: !showAdopt,
              onStartCook: () => openOverlay(DevOverlay.setup),
              onViewGraph: () => scope?.openScreen(ShellScreen.graph),
            ),
          SectionLabel(label: 'At a glance'),
          LiveSummaryStrip(
            probes: snapshot.probes,
            cook: cook,
            catalog: catalog,
            unit: unit,
          ),
          SectionLabel(
            label: 'Probes',
            trailing: TextButton(
              key: const ValueKey<String>('live-probes-details'),
              onPressed: () => scope?.openScreen(ShellScreen.temps),
              style: TextButton.styleFrom(
                foregroundColor: SmokeTokens.of(context).textHi,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Details',
                style: SmokeText.label.copyWith(
                  color: SmokeTokens.of(context).textHi,
                ),
              ),
            ),
          ),
          LiveProbeRail(
            probes: snapshot.probes,
            cook: cook,
            catalog: catalog,
            unit: unit,
            onOpenProbe: (probe) =>
                openOverlay(DevOverlay.probe, {'jack': '${probe.jack.n}'}),
          ),
          const SizedBox(height: 12),
          LiveMiniGraphCard(
            probes: snapshot.probes,
            cook: cook,
            unit: unit,
            now: now,
            onTap: () => scope?.openScreen(ShellScreen.graph),
          ),
          SectionLabel(label: 'Quick actions'),
          ActionRow(
            actions: <SmokeActionSpec>[
              SmokeActionSpec(
                label: 'Mark',
                icon: SmokeGlyph.bookmark,
                onPressed: () => openOverlay(DevOverlay.mark),
              ),
              SmokeActionSpec(
                label: 'Add food',
                icon: SmokeGlyph.plus,
                variant: SmokeButtonVariant.ghost,
                onPressed: () => openOverlay(DevOverlay.setup),
              ),
            ],
          ),
        ],
      ),
    );
  }

  FoodGlyph _cookGlyph(CookState cook, CatalogTable catalog) {
    if (cook.items.isEmpty) {
      return FoodGlyph.unstated;
    }
    final entry = catalog.byId(cook.items.first.presetId);
    return FoodGlyph.parse(entry?.glyph);
  }
}

class _AdoptBanner extends StatelessWidget {
  const _AdoptBanner({
    required this.pending,
    required this.now,
    required this.onAdopt,
    required this.onDiscard,
  });

  final PendingSession pending;
  final DateTime now;
  final VoidCallback onAdopt;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final elapsed = now.millisecondsSinceEpoch - pending.startedAtMs;
    return SmokeCard(
      key: const ValueKey<String>('live-adopt-banner'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SmokeIcon(SmokeGlyph.history, size: 17, color: tokens.textBody),
              const SizedBox(width: 8),
              Text(
                'A cook is already running',
                style: SmokeText.cardTitle.copyWith(color: tokens.textHi),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: SmokeText.sub.copyWith(color: tokens.textBody),
              children: <InlineSpan>[
                const TextSpan(text: 'Your bridge has been recording for '),
                TextSpan(
                  text: fmtDuration(elapsed),
                  style: SmokeText.bodyStrong.copyWith(color: tokens.textHi),
                ),
                TextSpan(
                  text:
                      ' with ${pending.probeCount} probes attached '
                      '(${pending.samples} samples). We can pull that history '
                      'in and build the cook around it.',
                ),
              ],
            ),
            key: const ValueKey<String>('live-adopt-copy'),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: PrimaryAction(
                  key: const ValueKey<String>('live-adopt'),
                  label: 'Adopt session',
                  icon: SmokeGlyph.download,
                  onPressed: onAdopt,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('live-discard-session'),
                  label: 'Start fresh',
                  variant: SmokeButtonVariant.ghost,
                  onPressed: onDiscard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
