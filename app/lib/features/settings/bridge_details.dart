import 'package:flutter/material.dart';

import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_log.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'settings_details.dart';
import 'settings_views.dart';

class BridgeDetailsScreen extends StatelessWidget {
  const BridgeDetailsScreen({super.key, required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final connected = controller.isConnected;
        final statusColor = connected
            ? StatusColors.live(context)
            : controller.phase == ConnectionPhase.reconnecting
            ? StatusColors.aging(context)
            : controller.phase == ConnectionPhase.blocked
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
                                      controller.deviceName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      'Bridge ${controller.deviceId} · Bluetooth',
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
                                controller.bridgeLinkStatusLabel,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const Spacer(),
                              if (connected)
                                Text(
                                  'Battery ${controller.batteryPercent}%',
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
                                  level: controller.signalBars,
                                  color: StatusColors.signal(
                                    context,
                                    controller.signalBars,
                                  ),
                                  semanticLabel:
                                      '${controller.signalQualityLabel} signal, ${controller.rssi} dBm',
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  controller.signalQualityLabel,
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
                            controller.bridgeLastContactDetail,
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
                                                'Syncing forward (simulated)…',
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
                                label: controller.smokeXLabel,
                                color: !connected
                                    ? StatusColors.stale(context)
                                    : controller.smokeXReceiving
                                    ? StatusColors.live(context)
                                    : StatusColors.aging(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            controller.smokeXSubtitle,
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
                            label: Text(
                              connected
                                  ? 'Re-pair Smoke X4'
                                  : 'Connect to re-pair',
                            ),
                          ),
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
                            subtitle: controller.canEdit
                                ? controller.deviceName
                                : '${controller.deviceName} · connect to change',
                            onTap: controller.canEdit
                                ? () =>
                                      showBridgeNameDialog(context, controller)
                                : null,
                          ),
                          const Divider(),
                          SettingsTile(
                            key: const Key('bridge.timeout'),
                            icon: Icons.timer_outlined,
                            title: 'Bridge screen timeout',
                            subtitle: controller.canEdit
                                ? _timeoutSubtitle()
                                : '${_timeoutSubtitle()} · connect to change',
                            onTap: controller.canEdit
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
                            subtitle: controller.billowsSettingsSubtitle,
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
                            'Firmware, signal, MTU and identifiers',
                          ),
                          children: [
                            KeyValueRow(
                              label: 'Device ID',
                              value: controller.deviceId,
                            ),
                            KeyValueRow(
                              label: 'Firmware',
                              value: controller.firmware,
                            ),
                            KeyValueRow(
                              label: 'Protocol',
                              value: controller.protocol,
                            ),
                            KeyValueRow(
                              label: 'Signal',
                              value: '${controller.rssi} dBm',
                            ),
                            KeyValueRow(
                              label: 'MTU',
                              value: controller.slowLink
                                  ? '23 (slow link)'
                                  : '247',
                            ),
                            KeyValueRow(
                              label: 'Last connected',
                              value: connected ? 'Just now' : '2 hours ago',
                            ),
                            KeyValueRow(
                              label: 'Last sync',
                              value: connected
                                  ? '2 minutes ago'
                                  : '2 hours ago',
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
                          title: const Text('Connection & pairing log'),
                          subtitle: const Text(
                            'Bridge, Smoke X4 and Billows events together',
                          ),
                          children: [ConnectionLogList(controller: controller)],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'BRIDGE ACTIONS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
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
                            title: const Text('Power off Bridge'),
                            subtitle: Text(
                              connected
                                  ? 'Stop recording until you wake it'
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
                                  ? 'Wipes pairing, settings and the Bridge log'
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
                              'Removes this phone’s pairing; keeps device log',
                            ),
                            onTap: () => showForgetFlow(context, controller),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Power off and factory reset need a live connection. '
                      'Forget this phone can still clear this phone locally.',
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

  String _timeoutSubtitle() {
    if (controller.displayTimeoutSeconds == 0) return 'OLED stays on';
    return '${controller.displayTimeoutLabel} · OLED sleep';
  }
}
