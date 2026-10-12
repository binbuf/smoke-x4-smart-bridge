/// The reader: what is everything right now, and can it be trusted?
///
/// The probes are always four, in jack order, and never leave the screen. The
/// connection card sits above them; the cook clock below.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/format.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../common/bridge_app_bar.dart';
import '../common/connection.dart';
import '../cook/cook_clock_card.dart';
import 'probe_card.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);

    return Scaffold(
      appBar: const BridgeAppBar(title: 'Live readings'),
      body: controller.connected
          ? RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(SmokeSpace.lg),
                children: [
                  _PairingCard(controller: controller),
                  const SizedBox(height: SmokeSpace.lg),
                  _ProbeList(controller: controller),
                  const SizedBox(height: SmokeSpace.lg),
                  _ReadingFooter(controller: controller),
                  const SizedBox(height: SmokeSpace.lg),
                  CookClockCard(controller: controller),
                ],
              ),
            )
          // The cook clock is phone-owned, so it keeps running with no link.
          // Hiding it here would make a live cook silently vanish on a drop or
          // a cold, unconnected launch; show it whenever one is running.
          : controller.cookRunning
          ? Column(
              children: [
                const Expanded(child: ConnectionEmpty(primaryAction: true)),
                Padding(
                  padding: const EdgeInsets.all(SmokeSpace.lg),
                  child: CookClockCard(controller: controller),
                ),
              ],
            )
          : controller.firstRun
          ? const FirstRunGuide()
          : const ConnectionEmpty(primaryAction: true),
    );
  }
}

class _ProbeList extends StatelessWidget {
  const _ProbeList({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.latestLive;
    final freshness = controller.freshness;
    // Only the jacks this bridge actually has: a 2-probe device rendering two
    // extra "unplugged" rows would read as a fault, not as "not present".
    final jacks = ProbeJack.values.take(controller.probeCount).toList();
    return Column(
      children: [
        for (final jack in jacks) ...[
          ProbeCard(
            jack: jack,
            f10: snapshot?.tempAt(jack.n - 1),
            unit: controller.unit,
            freshness: freshness,
            hasReading: snapshot != null,
          ),
          if (jack != jacks.last) const SizedBox(height: SmokeSpace.sm),
        ],
      ],
    );
  }
}

/// Smoke X4 pairing, made visible and drivable. The bridge's defining action
/// is the single LoRa hop to the Smoke X4; without this card the user can
/// neither see whether it happened nor start it.
class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.latestLive;
    if (live == null) {
      return const SizedBox.shrink();
    }
    final paired = live.paired;
    return SmokeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                paired ? Icons.link : Icons.link_off,
                size: 18,
                color: paired ? SmokePalette.positive : SmokePalette.textMuted,
              ),
              const SizedBox(width: SmokeSpace.sm),
              Expanded(
                child: Text(
                  paired ? 'Smoke X4 paired' : 'No Smoke X4 paired',
                  style: const TextStyle(
                    color: SmokePalette.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (paired)
                Text(
                  'LoRa ${live.rssiLora} dBm',
                  style: const TextStyle(
                    color: SmokePalette.textMuted,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: SmokeSpace.sm),
          Text(
            paired
                ? 'Readings are arriving from your Smoke X4.'
                : 'Put your Smoke X4 into SYNC, then pair it here. The '
                      'bridge screen confirms the link.',
            style: const TextStyle(
              color: SmokePalette.textBody,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SmokeSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: paired
                ? TextButton.icon(
                    onPressed: controller.unpairSmokeX,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Unpair Smoke X4'),
                  )
                : FilledButton.icon(
                    onPressed: controller.pairSmokeX,
                    icon: const Icon(Icons.link),
                    label: const Text('Pair with Smoke X4'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The honest line under the readings: when the last reading arrived, and a
/// nudge the bridge's own clock can be set from the phone.
class _ReadingFooter extends StatelessWidget {
  const _ReadingFooter({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final at = controller.liveAt;
    final text = at == null
        ? 'No reading yet'
        : 'Last reading ${formatAge(at)}';
    // The bridge's own clock is unset until the phone writes it; say so rather
    // than let every session it records carry a null (em-dash) timestamp.
    final clockUnset = controller.latestLive?.clockValid == false;
    return Row(
      children: [
        Expanded(
          child: Text(
            clockUnset ? '$text · bridge clock unset' : text,
            style: const TextStyle(color: SmokePalette.textMuted, fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: controller.syncClock,
          child: const Text('Set bridge clock'),
        ),
      ],
    );
  }
}
