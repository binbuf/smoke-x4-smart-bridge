import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_log.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'settings_details.dart';
import 'settings_views.dart';

class BridgeDetailsScreen extends StatelessWidget {
  const BridgeDetailsScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.bridgeDetailsView;
        final scheme = Theme.of(context).colorScheme;
        final connected = view.connected;
        final statusColor = connected
            ? StatusColors.live(context)
            : view.phase == ConnectionPhase.reconnecting
            ? StatusColors.aging(context)
            : view.phase == ConnectionPhase.blocked
            ? scheme.error
            : StatusColors.stale(context);
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Bridge'),
          body: ListView(
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.bluetooth,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      view.deviceName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      'Bridge ${view.deviceId}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              StatusLed(color: statusColor, active: connected),
                              const SizedBox(width: 2),
                              Text(
                                view.bridgeLinkStatusLabel,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const Spacer(),
                              if (connected)
                                Text(
                                  'Battery ${view.batteryPercent}%',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                          if (connected) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'Signal',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(width: 9),
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
                              ],
                            ),
                          ],
                          const SizedBox(height: 3),
                          Text(
                            view.bridgeLastContactDetail,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (!connected) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Recording continues on the Bridge.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () {
                                    if (connected) {
                                      controller.simulateSync();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Syncing saved readings…',
                                              ),
                                            ),
                                          );
                                    } else {
                                      controller.retryConnection();
                                    }
                                  },
                                  icon: const Icon(Icons.sync, size: 18),
                                  label: Text(
                                    connected ? 'Sync now' : 'Reconnect',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    if (connected) {
                                      controller.disconnect();
                                    } else {
                                      controller.retryConnection();
                                    }
                                  },
                                  icon: Icon(
                                    connected
                                        ? Icons.bluetooth_disabled
                                        : Icons.bluetooth_searching,
                                    size: 18,
                                  ),
                                  label: Text(
                                    connected ? 'Disconnect' : 'Connect',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sensors,
                                color: scheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Smoke X4 pairing',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Pill(
                                label: view.smokeXLabel,
                                color: !connected
                                    ? StatusColors.stale(context)
                                    : view.smokeXReceiving
                                    ? StatusColors.live(context)
                                    : StatusColors.aging(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            view.smokeXSubtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const Key('bridge.repair'),
                            onPressed: connected
                                ? () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          RePairScreen(controller: controller),
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.sync_alt, size: 18),
                            label: const Text('Re-pair Smoke X4'),
                          ),
                          if (!connected) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Connect to the Bridge to re-pair.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          SettingsTile(
                            key: const Key('bridge.name'),
                            icon: Icons.badge_outlined,
                            title: 'Bridge name',
                            subtitle: view.canEdit
                                ? view.deviceName
                                : '${view.deviceName}\nConnect to change',
                            onTap: view.canEdit
                                ? () =>
                                      showBridgeNameDialog(context, controller)
                                : null,
                          ),
                          const Divider(),
                          SettingsTile(
                            key: const Key('bridge.timeout'),
                            icon: Icons.timer_outlined,
                            title: 'Bridge screen timeout',
                            subtitle: view.canEdit
                                ? view.timeoutSubtitle
                                : '${view.timeoutSubtitle}\nConnect to change',
                            onTap: view.canEdit
                                ? () => showBridgeTimeoutSheet(
                                    context,
                                    controller,
                                  )
                                : null,
                          ),
                          const Divider(),
                          SettingsTile(
                            key: const Key('bridge.billows'),
                            icon: Icons.air,
                            title: 'Billows',
                            subtitle: view.billows.settingsSubtitle,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BillowsSettingsScreen(
                                  controller: controller,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      padding: EdgeInsets.zero,
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          leading: Icon(
                            Icons.info_outline,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: const Text('Technical details'),
                          subtitle: const Text(
                            'Firmware, signal, and connection details',
                          ),
                          children: [
                            KeyValueRow(
                              label: 'Bridge ID',
                              value: view.deviceId,
                            ),
                            KeyValueRow(
                              label: 'Firmware',
                              value: view.firmware,
                            ),
                            KeyValueRow(
                              label: 'Protocol',
                              value: view.protocol,
                            ),
                            KeyValueRow(
                              label: 'Signal',
                              value: '${view.rssi} dBm',
                            ),
                            KeyValueRow(
                              label: 'MTU',
                              value: view.slowLink
                                  ? '23 · slow connection'
                                  : '247',
                            ),
                            KeyValueRow(
                              label: 'Connected for',
                              value: view.connected
                                  ? view.bridgeConnectedForLabel
                                  : '—',
                            ),
                            KeyValueRow(
                              label: 'Last synced',
                              value: view.lastSyncedLabel.replaceFirst(
                                'Synced ',
                                '',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      padding: EdgeInsets.zero,
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: const Key('bridge.connectionLog'),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          leading: Icon(
                            Icons.history,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: const Text('Connection log'),
                          subtitle: const Text(
                            'Bridge, Smoke X4, and Billows events',
                          ),
                          children: [ConnectionLogList(events: view.connectionLog)],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Bridge actions',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SectionCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ListTile(
                            enabled: connected,
                            leading: const Icon(Icons.power_settings_new),
                            title: const Text('Power off the Bridge'),
                            subtitle: Text(
                              connected
                                  ? 'Stop recording until you turn it back on'
                                  : 'Connect to the Bridge first',
                            ),
                            onTap: connected
                                ? () => powerOff(context, controller)
                                : null,
                          ),
                          const Divider(),
                          ListTile(
                            enabled: connected,
                            leading: Icon(
                              Icons.restart_alt,
                              color: scheme.error,
                            ),
                            title: Text(
                              'Factory reset Bridge',
                              style: TextStyle(color: scheme.error),
                            ),
                            subtitle: Text(
                              connected
                                  ? 'Erases pairings, settings, and saved readings'
                                  : 'Connect to the Bridge first',
                            ),
                            onTap: connected
                                ? () => factoryReset(context, controller)
                                : null,
                          ),
                          const Divider(),
                          ListTile(
                            leading: Icon(Icons.link_off, color: scheme.error),
                            title: Text(
                              'Forget this phone',
                              style: TextStyle(color: scheme.error),
                            ),
                            subtitle: const Text(
                              'Removes this phone’s pairing; keeps history on this phone',
                            ),
                            onTap: () => showForgetFlow(context, controller),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Power off and factory reset require a connection to the Bridge. '
                      'You can forget this phone while offline.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
