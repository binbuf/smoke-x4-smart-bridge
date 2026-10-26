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
                  SettingsGroup(
                    title: 'Bridge',
                    header: _BridgeStatusHeader(
                      controller: controller,
                      onOpen: () => _push(
                        context,
                        BridgeDetailsScreen(controller: controller),
                      ),
                    ),
                    children: const [],
                  ),
                  SettingsGroup(
                    title: 'History & storage',
                    children: [
                      SettingsTile(
                        key: const Key('settings.history.logs'),
                        icon: Icons.sd_storage_outlined,
                        title: 'Device & Bridge logs',
                        subtitle:
                            '${commaInt(controller.phoneRecords)} device · ${commaInt(controller.bridgeRecords)} Bridge readings',
                        onTap: () => _push(
                          context,
                          HistoryStorageScreen(controller: controller),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: 'Preferences',
                    children: [
                      _UnitsTile(controller: controller),
                      SettingsTile(
                        key: const Key('settings.appearance'),
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
                    title: 'About',
                    children: [
                      SettingsTile(
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
                      'Smoke X4 Smart Bridge · Local only',
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

class _BridgeStatusHeader extends StatelessWidget {
  const _BridgeStatusHeader({required this.controller, required this.onOpen});

  final PrototypeController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = controller.isConnected;
    final color = connected
        ? StatusColors.live(context)
        : controller.phase == ConnectionPhase.reconnecting
        ? StatusColors.aging(context)
        : controller.phase == ConnectionPhase.blocked
        ? scheme.error
        : StatusColors.stale(context);

    return InkWell(
      key: const Key('settings.bridge.status'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Bridge ${controller.deviceId} · Bluetooth',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                StatusLed(color: color, active: connected),
                const SizedBox(width: 2),
                Text(
                  controller.bridgeLinkStatusLabel,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (connected)
                  Text(
                    'Battery ${controller.batteryPercent}%',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            if (connected) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Signal',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 9),
                  SignalBars(
                    level: controller.signalBars,
                    color: StatusColors.signal(context, controller.signalBars),
                    semanticLabel:
                        '${controller.signalQualityLabel} signal, ${controller.rssi} dBm',
                  ),
                  const SizedBox(width: 7),
                  Text(
                    controller.signalQualityLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
          ],
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
                          ? 'Every reading, target and the Bridge OLED'
                          : 'The Bridge OLED updates when you reconnect',
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
              key: const Key('settings.units'),
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
