import 'package:flutter/material.dart';

import '../../prototype/fixtures.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_widgets.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key, required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: () async {
            if (controller.isOffline) {
              controller.retryConnection();
            } else {
              controller.simulateSync();
            }
            await Future<void>.delayed(const Duration(milliseconds: 900));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.syncState == SyncState.recent ||
                        controller.syncState == SyncState.backfill)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SyncCard(controller: controller),
                      ),
                    if (controller.syncState == SyncState.error)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InlineNotice(
                          icon: Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                          title: 'Couldn’t catch up',
                          message: 'The last sync did not finish. Live readings can continue; retry when the link is stable.',
                          action: TextButton(
                            onPressed: controller.retryConnection,
                            child: const Text('Retry sync'),
                          ),
                        ),
                      ),
                    if (!controller.smokeXLiveHint)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InlineNotice(
                          icon: Icons.sensors_off_outlined,
                          title: 'Bridge connected · no Smoke X4',
                          message: 'The bridge is connected but has not heard your Smoke X4. Put the Smoke X4 in SYNC.',
                          action: TextButton(
                            onPressed: () => _showSmokeXHelp(context),
                            child: const Text('Pairing instructions'),
                          ),
                        ),
                      ),
                    if (!controller.storageOk)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InlineNotice(
                          icon: Icons.sd_card_alert_outlined,
                          color: Theme.of(context).colorScheme.error,
                          title: 'Storage unavailable',
                          message: 'The bridge can show live readings, but this session is not being recorded.',
                        ),
                      ),
                    if (controller.probePresence == ProbePresence.none)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InlineNotice(
                          icon: Icons.graphic_eq,
                          title: 'No probes connected',
                          message: 'Plug a probe into the Smoke X4. Detached jacks are shown as —, never 0 °F.',
                        ),
                      ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 4,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.84,
                          ),
                      itemBuilder: (context, index) {
                        final probe = controller.probes[index];
                        return ProbeCard(
                          probe: probe,
                          controller: controller,
                          accent: ProbeColors.forIndex(context, index),
                          history: buildSparklinePoints(
                            index,
                            hasData: controller.probeHasHistory(index),
                          ),
                          onTap: () => controller.openProbeHistory(index),
                        );
                      },
                    ),
                    if (controller.billowsMode != BillowsMode.disabled) ...[
                      const SizedBox(height: 14),
                      _BillowsCard(controller: controller),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSmokeXHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pair the Smoke X4',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text('1. Put the Smoke X4 into SYNC mode.'),
            const SizedBox(height: 6),
            const Text('2. Hold its button until it beeps.'),
            const SizedBox(height: 6),
            const Text(
              '3. The bridge scans 915/920 MHz and confirms the pairing.',
            ),
            const SizedBox(height: 16),
            Text(
              'Re-pairing does not delete the bridge log or any phone pairing.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backfill = controller.syncState == SyncState.backfill;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  backfill ? 'Loading older history' : 'Syncing',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (controller.slowLink)
                Text(
                  'slow link',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StatusColors.aging(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: controller.syncProgressPercent / 100,
            borderRadius: BorderRadius.circular(8),
            minHeight: 7,
          ),
          const SizedBox(height: 8),
          Text(
            backfill
                ? 'Recent history is already available. Older readings continue in the background.'
                : 'Recent history first, then a forward catch-up.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BillowsCard extends StatelessWidget {
  const _BillowsCard({required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attached = controller.billowsAttachment == BillowsAttachment.attached;
    final statusColor = attached
        ? StatusColors.live(context)
        : StatusColors.stale(context);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.air, color: scheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Billows',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      controller.billowsSourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(
                label: controller.billowsAttachmentLabel,
                color: statusColor,
                icon: attached ? Icons.link : Icons.link_off,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'TARGET',
                  value: controller.billowsTargetKnown
                      ? controller.tempFor(controller.billowsTargetF.toDouble())
                      : '—',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'MODE',
                  value: controller.billowsModeLabel,
                ),
              ),
              if (controller.isBillowsControl)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => _setTarget(context),
                  child: const Text('Set target'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _setTarget(BuildContext context) {
    var target = controller.billowsTargetF.toDouble();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set Billows target',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The bridge controls the fan. Valid range ${controller.tempFor(32)}–${controller.tempFor(572)}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      controller.tempFor(target),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  Slider(
                    value: target,
                    min: 32,
                    max: 572,
                    divisions: 540,
                    label: controller.tempFor(target),
                    onChanged: (value) => setSheetState(() => target = value),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(controller.tempFor(32)),
                      Text(controller.tempFor(572)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      final messenger = ScaffoldMessenger.of(context);
                      controller.setBillowsTarget(target.round());
                      Navigator.of(context).pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Target set to ${controller.tempFor(target)} (simulated).',
                          ),
                        ),
                      );
                    },
                    child: const Text('Set target'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
