import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/view_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_widgets.dart';
import '../settings/bridge_details.dart';
import '../settings/settings_details.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.liveView;
        return RefreshIndicator(
          onRefresh: () async {
            if (view.isOffline) {
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
                      view: view,
                      onOpenBridge: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              BridgeDetailsScreen(controller: controller),
                        ),
                      ),
                    ),
                    if (view.isConnected && !view.smokeXReceiving) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.sensors_off_outlined,
                        color: StatusColors.aging(context),
                        title: 'No data from Smoke X4',
                        message: 'The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.',
                        action: TextButton(
                          onPressed: () => _showSmokeXHelp(context),
                          child: const Text('Troubleshoot'),
                        ),
                      ),
                    ],
                    if (view.syncState == SyncState.recent ||
                        view.syncState == SyncState.backfill) ...[
                      const SizedBox(height: 10),
                      _SyncCard(view: view),
                    ],
                    if (view.syncState == SyncState.error) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        title: 'History sync failed',
                        message: 'Live readings are still updating. Retry when the Bluetooth connection is stable.',
                        action: TextButton(
                          onPressed: controller.retryConnection,
                          child: const Text('Retry sync'),
                        ),
                      ),
                    ],
                    if (!view.storageOk) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.sd_card_alert_outlined,
                        color: Theme.of(context).colorScheme.error,
                        title: 'Not recording',
                        message: 'Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.',
                        action: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  BridgeDetailsScreen(controller: controller),
                            ),
                          ),
                          child: const Text('Bridge details'),
                        ),
                      ),
                    ],
                    if (view.probePresence == ProbePresence.none) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        icon: Icons.graphic_eq,
                        title: 'No probes connected',
                        message:
                            'Plug a probe into the Smoke X4 to see a reading.',
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Probes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: view.probes.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.86,
                          ),
                      itemBuilder: (context, index) {
                        return ProbeCard(
                          probe: view.probes[index],
                          units: view.units,
                          isOffline: view.isOffline,
                          accent: ProbeColors.forIndex(context, index),
                          onTap: () => controller.openProbeHistory(index),
                        );
                      },
                    ),
                    if (view.billows!.detected) ...[
                      const SizedBox(height: 14),
                      _BillowsCard(view: view.billows!),
                    ],
                    if (view.billowsLostThisSession) ...[
                      const SizedBox(height: 14),
                      InlineNotice(
                        icon: Icons.air,
                        color: StatusColors.aging(context),
                        title: 'Billows not detected',
                        message: 'Billows was detected earlier this session. Make sure the fan is powered on and in range of the Smoke X4.',
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
            const Text('3. The Bridge confirms the pairing.'),
            const SizedBox(height: 16),
            Text(
              'Re-pairing doesn’t delete history on the Bridge or remove paired phones.',
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
  const _ConnectionCard({required this.view, required this.onOpenBridge});

  final LiveViewState view;
  final VoidCallback onOpenBridge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bridgeColor = _bridgeColor(context);
    final smokeColor = _smokeColor(context);
    final appColor = view.isConnected
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
                      ),
                    ),
                    _ChainArrow(color: scheme.outline),
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.bluetooth_rounded,
                        label: 'Bridge',
                        status: view.bridgeLinkStatusLabel,
                        color: bridgeColor,
                      ),
                    ),
                    _ChainArrow(color: scheme.outline),
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.sensors_rounded,
                        label: 'Smoke X4',
                        status: view.smokeXLinkStatusLabel,
                        color: smokeColor,
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              view.bridgeConnectedLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                          if (view.isConnected) ...[
                            const SizedBox(width: 6),
                            SignalBars(
                              level: view.signalBars,
                              color: StatusColors.signal(
                                context,
                                view.signalBars,
                              ),
                              semanticLabel:
                                  '${view.signalQualityLabel} signal, ${view.rssi} dBm',
                            ),
                            const SizedBox(width: 7),
                            Text(
                              view.signalQualityLabel,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            view.isConnected ? Icons.sensors : Icons.history,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              view.telemetryStatusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color:
                                        view.isConnected &&
                                            !view.smokeXReceiving
                                        ? StatusColors.aging(context)
                                        : scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          if (!view.isConnected)
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                        ],
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

  Color _bridgeColor(BuildContext context) {
    switch (view.phase) {
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
    if (!view.isConnected) return StatusColors.stale(context);
    if (view.smokeXReceiving) return StatusColors.live(context);
    switch (view.smokeXStatus) {
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
  });

  final IconData icon;
  final String label;

  /// Spoken status; the visible sub-label is intentionally gone so the node
  /// colour carries healthy / issue / not-connected state.
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, $status',
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.26)),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
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
  const _SyncCard({required this.view});

  final LiveViewState view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backfill = view.syncState == SyncState.backfill;
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
                  backfill
                      ? 'Loading saved readings'
                      : 'Syncing saved readings',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (view.slowLink)
                Text(
                  'Slow connection',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: StatusColors.aging(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: view.syncProgressPercent / 100,
            borderRadius: BorderRadius.circular(8),
            minHeight: 7,
          ),
          const SizedBox(height: 8),
          Text(
            backfill
                ? 'Your latest readings are ready. Older readings continue in the background.'
                : 'Newest readings load first.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BillowsCard extends StatelessWidget {
  const _BillowsCard({required this.view});

  final BillowsView view;

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
                  label: view.setTempLabel,
                  value: view.setTempKnown ? view.setTempText : '—',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Last detected',
                  value: view.lastDetectedLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Set on the Smoke X4.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
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
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
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
