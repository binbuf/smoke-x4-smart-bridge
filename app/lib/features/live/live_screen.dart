/// The reader: what is everything right now, and can it be trusted?
///
/// The probes are always four, in jack order, and never leave the screen. The
/// connection card sits above them; the cook clock below.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/format.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../common/connection.dart';
import '../cook/cook_clock_card.dart';
import 'probe_card.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live readings'),
        actions: [
          const ConnectionChip(),
          const SizedBox(width: SmokeSpace.sm),
          _UnitToggle(controller: controller),
          const SizedBox(width: SmokeSpace.sm),
        ],
      ),
      body: controller.connected
          ? RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(SmokeSpace.lg),
                children: [
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
    return Column(
      children: [
        for (final jack in ProbeJack.values) ...[
          ProbeCard(
            jack: jack,
            f10: snapshot?.tempAt(jack.n - 1),
            unit: controller.unit,
            freshness: freshness,
            hasReading: snapshot != null,
          ),
          if (jack != ProbeJack.values.last)
            const SizedBox(height: SmokeSpace.sm),
        ],
      ],
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

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TempUnit>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
        ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
      ],
      selected: {controller.unit},
      onSelectionChanged: (s) => controller.setUnit(s.first),
    );
  }
}
