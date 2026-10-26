import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../prototype/scenario_lab.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_widgets.dart';
import 'bridge_details.dart';
import 'settings_details.dart';
import 'settings_views.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return ListView(
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BridgeCard(
                    controller: controller,
                    onTap: () => _push(
                      context,
                      BridgeDetailsScreen(controller: controller),
                    ),
                  ),
                  SettingsGroup(
                    title: 'Preferences',
                    children: [
                      _UnitsTile(controller: controller),
                      _SettingsTile(
                        icon: Icons.palette_outlined,
                        title: 'Appearance',
                        subtitle: controller.themeModeLabel,
                        onTap: () => _push(
                          context,
                          AppearanceScreen(controller: controller),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: 'Bridge',
                    children: [
                      _SettingsTile(
                        icon: Icons.sensors,
                        title: 'Smoke X4',
                        subtitle: controller.smokeXLabel,
                        onTap: () => _push(
                          context,
                          SmokeX4DetailsScreen(controller: controller),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.air,
                        title: 'Billows',
                        subtitle: controller.billowsMode == BillowsMode.disabled
                            ? 'Off'
                            : '${controller.billowsModeLabel} · ${controller.billowsTargetKnown ? controller.tempFor(controller.billowsTargetF.toDouble()) : 'Target unknown'}',
                        onTap: () => _push(
                          context,
                          BillowsSettingsScreen(controller: controller),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.timer_outlined,
                        title: 'Bridge screen timeout',
                        subtitle: controller.canEdit
                            ? controller.displayTimeoutLabel
                            : '${controller.displayTimeoutLabel} · connect to change',
                        onTap: controller.canEdit
                            ? () => showBridgeTimeoutSheet(context, controller)
                            : null,
                      ),
                      _SettingsTile(
                        icon: Icons.badge_outlined,
                        title: 'Bridge name',
                        subtitle: controller.canEdit
                            ? controller.deviceName
                            : '${controller.deviceName} · connect to change',
                        onTap: controller.canEdit
                            ? () => showBridgeNameDialog(context, controller)
                            : null,
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: 'History & storage',
                    children: [
                      _SettingsTile(
                        icon: Icons.phone_android,
                        title: 'Phone history',
                        subtitle:
                            '${commaInt(controller.phoneRecords)} readings · ${controller.savedDataSize}',
                        onTap: () => _push(
                          context,
                          HistoryStorageScreen(controller: controller),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.sd_storage_outlined,
                        title: 'Bridge log',
                        subtitle:
                            '${commaInt(controller.bridgeRecords)} readings · rolling',
                        onTap: () => _push(
                          context,
                          HistoryStorageScreen(controller: controller),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: 'About',
                    children: [
                      _SettingsTile(
                        icon: Icons.info_outline,
                        title: 'About',
                        subtitle: 'App 0.1.0 · firmware ${controller.firmware}',
                        onTap: () => _push(
                          context,
                          AboutScreen(
                            controller: controller,
                            onOpenLab: () => _push(
                              context,
                              ScenarioLabScreen(controller: controller),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Smoke X4 Smart Bridge · local only',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _BridgeCard extends StatelessWidget {
  const _BridgeCard({required this.controller, required this.onTap});

  final PrototypeController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = controller.isConnected;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.bluetooth, color: scheme.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.deviceName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'SmokeX4-${controller.deviceId}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                connected
                    ? 'Updated 4s ago · battery ${controller.batteryPercent}% · signal good'
                    : 'Last sync 2 hours ago. Recording continues on the bridge.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    if (connected) {
                      controller.simulateSync();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Syncing forward (simulated)…'),
                        ),
                      );
                    } else {
                      controller.retryConnection();
                    }
                  },
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(connected ? 'Sync now' : 'Reconnect'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitsTile extends StatelessWidget {
  const _UnitsTile({required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.thermostat, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Temperature units',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      controller.isConnected
                          ? 'Every reading, target and the bridge OLED'
                          : 'The bridge OLED updates when you reconnect',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Units>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Units.fahrenheit, label: Text('°F')),
                ButtonSegment(value: Units.celsius, label: Text('°C')),
              ],
              selected: {controller.units},
              onSelectionChanged: (selection) =>
                  controller.setUnits(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      enabled: enabled,
      leading: Icon(
        icon,
        color: enabled ? scheme.onSurfaceVariant : scheme.outline,
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: enabled ? scheme.onSurfaceVariant : scheme.outline,
      ),
      onTap: onTap,
    );
  }
}
