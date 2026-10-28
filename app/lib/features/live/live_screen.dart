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
            await controller.refreshLink();
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
                      onShowSmokeXHelp: () => _showSmokeXHelp(context),
                    ),
                    if ((view.phase == ConnectionPhase.offline ||
                            view.phase == ConnectionPhase.failed) &&
                        view.showSavedReadings &&
                        !view.lookingForBridge) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.savedReadings'),
                        icon: Icons.history,
                        color: StatusColors.stale(context),
                        title: view.telemetryStatusLabel,
                        message: 'These are saved readings, not live values. Retry when the Bridge is back in range.',
                        action: TextButton(
                          key: const Key('live.savedReadings.retry'),
                          onPressed: controller.retryConnection,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                    if (view.phase == ConnectionPhase.failed &&
                        !view.showSavedReadings) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.unreachable'),
                        icon: Icons.link_off,
                        color: Theme.of(context).colorScheme.error,
                        title: 'Can’t reach the Bridge',
                        message: 'The app tried six times. Recording continues on the Bridge. Move closer and try again, or forget this phone and set it up again.',
                        action: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              key: const Key('live.unreachable.retry'),
                              onPressed: controller.refreshLink,
                              child: const Text('Retry'),
                            ),
                            TextButton(
                              key: const Key('live.unreachable.forget'),
                              onPressed: controller.forgetPhone,
                              child: const Text('Forget this phone'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (view.lookingForBridge) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.lookingForBridge'),
                        icon: Icons.bluetooth_searching,
                        title: 'Looking for the Bridge…',
                        message: view.showSavedReadings
                            ? 'Showing saved readings. Turn the Bridge on and keep it nearby.'
                            : 'Turn the Bridge on and keep it nearby. Nothing is saved on this phone yet.',
                        action: view.launchScanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                key: const Key('live.lookingForBridge.connect'),
                                onPressed: controller.connectSavedBridge,
                                child: const Text('Connect'),
                              ),
                      ),
                    ],
                    if (view.phase == ConnectionPhase.blocked) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.blocked'),
                        icon: Icons.bluetooth_disabled,
                        color: Theme.of(context).colorScheme.error,
                        title: view.connectionTitle,
                        message: view.connectionSubtitle,
                        action: TextButton(
                          key: const Key('live.blocked.settings'),
                          onPressed: () => _showBluetoothSettingsHelp(
                            context,
                            view.connectionTitle,
                          ),
                          child: Text(
                            view.phase == ConnectionPhase.blocked &&
                                    view.connectionTitle == 'Bluetooth is off'
                                ? 'Open Bluetooth settings'
                                : 'Open app settings',
                          ),
                        ),
                      ),
                    ],
                    if (view.isOffline &&
                        !view.showSavedReadings &&
                        !view.lookingForBridge &&
                        view.phase != ConnectionPhase.failed &&
                        view.phase != ConnectionPhase.blocked) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.noCache'),
                        icon: Icons.cloud_off_outlined,
                        title: 'Bridge disconnected · nothing saved yet',
                        message: 'This phone has no saved readings. Connect to your Bridge to see live values.',
                        action: TextButton(
                          key: const Key('live.noCache.retry'),
                          onPressed: controller.retryConnection,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                    if (view.isConnected &&
                        !view.smokeXReceiving &&
                        view.smokeXStatus == SmokeXStatus.unpaired) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.smokeXUnpaired'),
                        icon: Icons.sensors_off_outlined,
                        color: StatusColors.aging(context),
                        title: 'No data from Smoke X4',
                        message: 'The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.',
                        action: TextButton(
                          onPressed: () => _showSmokeXHelp(context),
                          child: const Text('Pairing steps'),
                        ),
                      ),
                    ],
                    if (view.phase != ConnectionPhase.blocked &&
                        (view.syncState == SyncState.recent ||
                            view.syncState == SyncState.backfill)) ...[
                      const SizedBox(height: 10),
                      _SyncCard(view: view),
                    ],
                    if (view.syncState == SyncState.error) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.syncFailed'),
                        icon: Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        title: 'History sync failed',
                        message: 'Live readings are still updating. Retry when the Bluetooth connection is stable.',
                        action: TextButton(
                          onPressed: controller.refreshLink,
                          child: const Text('Retry sync'),
                        ),
                      ),
                    ],
                    if (!view.storageOk) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.storageUnavailable'),
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
                    if (view.probePresence == ProbePresence.none &&
                        !(view.isOffline && !view.showSavedReadings)) ...[
                      const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('live.noProbes'),
                        icon: Icons.graphic_eq,
                        title: 'No probes connected',
                        message:
                            'Plug a probe into the Smoke X4 to see a reading.',
                        action: TextButton(
                          key: const Key('live.noProbes.bridgeDetails'),
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
                            childAspectRatio: 0.78,
                          ),
                      itemBuilder: (context, index) {
                        return ProbeCard(
                          key: Key('live.probe.${index + 1}'),
                          probe: view.probes[index],
                          units: view.units,
                          isOffline: view.isOffline,
                          accent: ProbeColors.forIndex(context, index),
                          onTap: () => controller.openProbeHistory(index),
                        );
                      },
                    ),
                    if (view.billows != null) ...[
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

  void _showBluetoothSettingsHelp(BuildContext context, String title) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.settings_bluetooth),
        title: Text(title),
        content: Text(
          title == 'Bluetooth is off'
              ? 'Turn Bluetooth on in Android settings, then come back. The Bridge keeps recording while you do.'
              : 'Allow Nearby devices for this app in Android settings, then come back.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showSmokeXHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pair the Smoke X4',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const _PairingStep(
                number: '1',
                text: 'Put the Smoke X4 into SYNC mode.',
              ),
              const _PairingStep(
                number: '2',
                text: 'Hold its button until it beeps.',
              ),
              const _PairingStep(
                number: '3',
                text: 'Keep it near the Bridge while the pairing is confirmed.',
              ),
              const SizedBox(height: 4),
              Text(
                'No reset is needed. Pairing the X4 keeps the Bridge’s history, settings, and phone pairings.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairingStep extends StatelessWidget {
  const _PairingStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.view,
    required this.onOpenBridge,
    required this.onShowSmokeXHelp,
  });

  final LiveViewState view;
  final VoidCallback onOpenBridge;
  final VoidCallback onShowSmokeXHelp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bridgeColor = _bridgeColor(context);
    final smokeColor = _smokeColor(context);
    final appColor = _appColor(context);
    final bleSignalColor = StatusColors.signal(context, view.bleSignalBars);
    final loraSignalColor = StatusColors.signal(context, view.signalBars);

    return Card(
      key: const Key('status.connection'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenBridge,
        child: Semantics(
          button: true,
          label:
              'Connection details. App ${view.appBridgeConnectedForLabel}. '
              'Bridge ${view.bridgeLinkStatusLabel}. '
              'Smoke X4 ${view.smokeXLinkStatusLabel}, '
              '${view.smokeXConnectedForLabel}.',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
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
                    _ChainLink(
                      key: const Key('status.appBridgeLink'),
                      signalLevel: view.bleSignalBars,
                      signalColor: bleSignalColor,
                      signalLabel:
                          '${view.bleSignalQualityLabel} Bluetooth signal, ${view.bleRssi ?? '—'} dBm',
                      color: _bluetoothLinkColor(context),
                      durationLabel: view.appBridgeConnectedForLabel,
                      durationSemantics:
                          'App to Bridge: ${view.appBridgeConnectedForLabel}',
                    ),
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.bluetooth_rounded,
                        label: 'Bridge',
                        status: view.bridgeLinkStatusLabel,
                        color: bridgeColor,
                      ),
                    ),
                    _ChainLink(
                      key: const Key('status.x4Link'),
                      signalLevel: view.signalBars,
                      signalColor: loraSignalColor,
                      signalLabel:
                          '${view.signalQualityLabel} radio signal, ${view.rssi} dBm',
                      color: _x4LinkColor(context),
                      durationLabel: view.smokeXConnectedForLabel,
                      durationSemantics:
                          'Bridge to Smoke X4: ${view.smokeXConnectedForLabel}',
                    ),
                    Expanded(
                      child: _ChainNode(
                        icon: Icons.sensors_rounded,
                        label: 'Smoke X4',
                        status: view.smokeXLinkStatusLabel,
                        color: smokeColor,
                        warning:
                            view.isConnected &&
                            !view.smokeXReceiving &&
                            view.smokeXStatus != SmokeXStatus.unpaired,
                        warningColor: smokeColor,
                        onWarningTap: () => _showSmokeXWarning(context),
                      ),
                    ),
                  ],
                ),
                if (view.isConnected && view.smokeXReceiving) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Tooltip(
                          message:
                              'Time since last data was received from Smoke X4',
                          triggerMode: TooltipTriggerMode.tap,
                          child: Icon(
                            Icons.sensors,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            view.telemetryStatusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSmokeXWarning(BuildContext context) {
    final lost = view.smokeXStatus == SmokeXStatus.pairedLost;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(lost ? 'Smoke X4 signal lost' : 'No data from Smoke X4'),
        content: Text(
          lost
              ? 'The Bridge is connected but hasn’t received data from the Smoke X4 for a while. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.'
              : 'The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onShowSmokeXHelp();
            },
            child: const Text('Pairing steps'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Color _appColor(BuildContext context) {
    switch (view.phase) {
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
      case ConnectionPhase.syncing:
        return StatusColors.live(context);
      case ConnectionPhase.reconnecting:
        return StatusColors.aging(context);
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
      case ConnectionPhase.blocked:
      case ConnectionPhase.setup:
        return Theme.of(context).colorScheme.error;
    }
  }

  Color _bridgeColor(BuildContext context) {
    switch (view.phase) {
      case ConnectionPhase.live:
      case ConnectionPhase.syncing:
        return StatusColors.live(context);
      case ConnectionPhase.stale:
        return StatusColors.aging(context);
      case ConnectionPhase.reconnecting:
        return StatusColors.aging(context);
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
      case ConnectionPhase.blocked:
      case ConnectionPhase.setup:
        return Theme.of(context).colorScheme.error;
    }
  }

  Color _bluetoothLinkColor(BuildContext context) {
    if (view.isConnected) return StatusColors.live(context);
    if (view.phase == ConnectionPhase.reconnecting) {
      return StatusColors.aging(context);
    }
    return Theme.of(context).colorScheme.error;
  }

  Color _x4LinkColor(BuildContext context) {
    if (!view.isConnected) return Theme.of(context).colorScheme.error;
    if (view.smokeXReceiving) return StatusColors.live(context);
    if (view.smokeXStatus == SmokeXStatus.pairedLive) {
      return StatusColors.aging(context);
    }
    return Theme.of(context).colorScheme.error;
  }

  Color _smokeColor(BuildContext context) {
    if (!view.isConnected) return Theme.of(context).colorScheme.error;
    if (view.smokeXReceiving) return StatusColors.live(context);
    switch (view.smokeXStatus) {
      case SmokeXStatus.pairedLive:
        return StatusColors.aging(context);
      case SmokeXStatus.pairedLost:
      case SmokeXStatus.unpaired:
        return Theme.of(context).colorScheme.error;
    }
  }
}

class _ChainNode extends StatelessWidget {
  const _ChainNode({
    required this.icon,
    required this.label,
    required this.status,
    required this.color,
    this.warning = false,
    this.warningColor,
    this.onWarningTap,
  });

  final IconData icon;
  final String label;

  /// Spoken status; the visible sub-label is intentionally gone so the node
  /// colour carries healthy / issue / not-connected state.
  final String status;
  final Color color;
  final bool warning;
  final Color? warningColor;
  final VoidCallback? onWarningTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label, $status',
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
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
              if (warning)
                Positioned(
                  top: -5,
                  right: -7,
                  child: Material(
                    color: scheme.surface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onWarningTap,
                      child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          key: const Key('live.smokeXWarning'),
                          size: 18,
                          color: warningColor ?? scheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// One radio link between two chain nodes: signal and connected duration sit
/// together. Their colour carries the health code.
class _ChainLink extends StatelessWidget {
  const _ChainLink({
    super.key,
    required this.signalLevel,
    required this.signalColor,
    required this.signalLabel,
    required this.color,
    required this.durationLabel,
    required this.durationSemantics,
  });

  final int signalLevel;
  final Color signalColor;
  final String signalLabel;
  final Color color;
  final String durationLabel;
  final String durationSemantics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          // Mirrors the chain node above: the bars sit on the icon centre...
          SizedBox(
            height: 48,
            child: Center(
              child: SignalBars(
                level: signalLevel,
                color: signalColor,
                semanticLabel: signalLabel,
              ),
            ),
          ),
          const SizedBox(height: 7),
          // ...and the elapsed time sits on the node label baseline.
          SizedBox(
            height: 12,
            child: Center(
              child: Semantics(
                label: durationSemantics,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    durationLabel,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
      key: const Key('live.sync'),
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
