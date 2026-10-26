import 'package:flutter/material.dart';

import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'settings_details.dart';

class SmokeX4DetailsScreen extends StatelessWidget {
  const SmokeX4DetailsScreen({super.key, required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final connected = controller.isConnected;
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Smoke X4'),
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
                              Icon(
                                Icons.sensors,
                                color: scheme.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
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
                                color:
                                    controller.smokeXStatus ==
                                        SmokeXStatus.pairedLive
                                    ? StatusColors.live(context)
                                    : StatusColors.aging(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            controller.smokeXSubtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
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
                    InlineNotice(
                      icon: Icons.info_outline,
                      title: 'Re-pairing keeps your history',
                      message: 'It clears only the radio pairing. The bridge log and phone pairings are kept.',
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
                                      'SmokeX4-${controller.deviceId}',
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
                              Pill(
                                label: connected ? 'Connected' : 'Offline',
                                color: connected
                                    ? StatusColors.live(context)
                                    : StatusColors.stale(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            connected
                                ? 'Updated 4s ago · battery ${controller.batteryPercent}% · signal good'
                                : 'Last sync 2 hours ago. Recording continues on the bridge.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sensors,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Smoke X4',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Pill(
                                label: controller.smokeXLabel,
                                color:
                                    controller.smokeXStatus ==
                                        SmokeXStatus.pairedLive
                                    ? StatusColors.live(context)
                                    : StatusColors.aging(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            controller.smokeXSubtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
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
                          const SizedBox(height: 6),
                          Text(
                            'Re-pairing keeps the bridge log and phone pairings.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
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
                            title: const Text('Power off bridge'),
                            subtitle: Text(
                              connected
                                  ? 'Stop recording until you wake it'
                                  : 'Connect to the bridge first',
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
                              'Factory reset bridge',
                              style: TextStyle(color: scheme.error),
                            ),
                            subtitle: Text(
                              connected
                                  ? 'Wipes pairing, settings and the bridge log'
                                  : 'Connect to the bridge first',
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
                              'Removes this phone’s pairing; keeps phone history',
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
}
