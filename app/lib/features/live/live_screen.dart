import 'package:flutter/material.dart';

import '../../prototype/fixtures.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_widgets.dart';
import '../settings/bridge_details.dart';
import '../settings/settings_details.dart';

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
                    _ConnectionCard(
                      controller: controller,
                      onOpenBridge: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              BridgeDetailsScreen(controller: controller),
                        ),
                      ),
                    ),
                    if (controller.isConnected &&
                        !controller.smokeXReceiving) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.sensors_off_outlined,
                        color: StatusColors.aging(context),
                        title: 'Smoke X4 not sending',
                        message: 'The Bridge is connected but has no recent data. Put the Smoke X4 in SYNC and keep it in range.',
                        action: TextButton(
                          onPressed: () => _showSmokeXHelp(context),
                          child: const Text('Pairing instructions'),
                        ),
                      ),
                    ],
                    if (controller.syncState == SyncState.recent ||
                        controller.syncState == SyncState.backfill) ...[
                      const SizedBox(height: 10),
                      _SyncCard(controller: controller),
                    ],
                    if (controller.syncState == SyncState.error) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        title: 'Couldn’t catch up',
                        message: 'The last sync did not finish. Live readings can continue; retry when the link is stable.',
                        action: TextButton(
                          onPressed: controller.retryConnection,
                          child: const Text('Retry sync'),
                        ),
                      ),
                    ],
                    if (!controller.storageOk) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.sd_card_alert_outlined,
                        color: Theme.of(context).colorScheme.error,
                        title: 'Storage unavailable',
                        message: 'The Bridge can show live readings, but this session is not being recorded.',
                      ),
                    ],
                    if (controller.probePresence == ProbePresence.none) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.graphic_eq,
                        title: 'No probes connected',
                        message: 'Plug a probe into the Smoke X4. Detached probes are shown as —, never 0 °F.',
                      ),
                    ],
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 4,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.86,
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
                    if (controller.billowsDetected) ...[
                      const SizedBox(height: 14),
                      _BillowsCard(controller: controller),
                    ],
                    if (controller.billowsLostThisSession) ...[
                      const SizedBox(height: 14),
                      InlineNotice(
                        icon: Icons.air,
                        color: StatusColors.aging(context),
                        title: 'Billows disconnected',
                        message: 'It was detected earlier this session. Check the fan’s power and its link to the Smoke X4. The connection log records the drop.',
                        action: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  BillowsSettingsScreen(controller: controller),
                            ),
                          ),
                          child: const Text('View connection log'),
                        ),
                      ),
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
              '3. The Bridge scans 915/920 MHz and confirms the pairing.',
            ),
            const SizedBox(height: 16),
            Text(
              'Re-pairing does not delete the Bridge log or any phone pairing.',
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

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller, required this.onOpenBridge});

  final PrototypeController controller;
  final VoidCallback onOpenBridge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bridgeColor = _bridgeColor(context);
    final smokeColor = _smokeColor(context);
    final appColor = controller.isConnected
        ? StatusColors.live(context)
        : StatusColors.stale(context);

    return Card(
      key: const Key('status.connection'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenBridge,
        child: Semantics(
          button: true,
          label: 'Connection details. App to Bridge to Smoke X4.',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.phone_android_rounded,
                        label: 'App',
                        status: 'This phone',
                        color: appColor,
                        active: controller.isConnected,
                      ),
                    ),
                    _ChainArrow(color: scheme.outline),
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.bluetooth_rounded,
                        label: 'Bridge',
                        status: controller.bridgeLinkStatusLabel,
                        color: bridgeColor,
                        active: controller.isConnected,
                      ),
                    ),
                    _ChainArrow(color: scheme.outline),
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.sensors_rounded,
                        label: 'Smoke X4',
                        status: controller.smokeXLinkStatusLabel,
                        color: smokeColor,
                        active:
                            controller.isConnected &&
                            controller.smokeXStatus != SmokeXStatus.unpaired,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _detailLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _detailLine => controller.bridgeLinkDetail;

  Color _bridgeColor(BuildContext context) {
    switch (controller.phase) {
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
      case ConnectionPhase.syncing:
        return StatusColors.live(context);
      case ConnectionPhase.reconnecting:
        return StatusColors.aging(context);
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
        return StatusColors.stale(context);
      case ConnectionPhase.blocked:
        return Theme.of(context).colorScheme.error;
      case ConnectionPhase.setup:
        return StatusColors.stale(context);
    }
  }

  Color _smokeColor(BuildContext context) {
    if (!controller.isConnected) return StatusColors.stale(context);
    if (controller.smokeXReceiving) return StatusColors.live(context);
    switch (controller.smokeXStatus) {
      case SmokeXStatus.pairedLive:
      case SmokeXStatus.pairedLost:
        return StatusColors.aging(context);
      case SmokeXStatus.unpaired:
        return StatusColors.stale(context);
    }
  }
}

class _ChainNode extends StatelessWidget {
  const _ChainNode({
    required this.icon,
    required this.label,
    required this.status,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String status;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = active ? color : color.withValues(alpha: 0.6);
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tint.withValues(alpha: 0.26)),
          ),
          child: Icon(icon, size: 24, color: tint),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 1),
        Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: active ? color : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ChainArrow extends StatelessWidget {
  const _ChainArrow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Icon(Icons.arrow_forward_rounded, size: 17, color: color),
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
    return SectionCard(
      key: const Key('live.billows'),
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
                child: Text(
                  'Billows',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'CH 4 SET TEMP',
                  value: controller.smokeXChannel4SetKnown
                      ? controller.tempFor(
                          controller.smokeXChannel4SetF.toDouble(),
                        )
                      : '—',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'STATUS',
                  value: controller.billowsAttachmentLabel,
                ),
              ),
            ],
          ),
        ],
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
