import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/view_state.dart';
import '../../app/lab_gate.dart';
import '../../debug/scenario_lab.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_widgets.dart';
import 'bridge_details.dart';
import 'settings_details.dart';
import 'settings_views.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.enableExperimentalLab = experimentalLabEnabled,
  });

  final BridgeController controller;
  final bool enableExperimentalLab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.settingsView;
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
                      view: view,
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
                        title: 'Storage',
                        subtitle:
                            '${view.phoneRecordsLabel} readings on this phone · ${view.bridgeRecordsLabel} on the Bridge',
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
                      _UnitsTile(view: view, controller: controller),
                      SettingsTile(
                        key: const Key('settings.appearance'),
                        icon: Icons.palette_outlined,
                        title: 'Appearance',
                        subtitle: view.themeModeLabel,
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
                        title: 'About this app',
                        subtitle: 'App 0.1.0 · Firmware ${view.firmware}',
                        onTap: () => _push(
                          context,
                          AboutScreen(
                            controller: controller,
                            onOpenLab: enableExperimentalLab
                                ? () => _push(
                                    context,
                                    ScenarioLabScreen(controller: controller),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Smoke X4 Smart Bridge · No account needed',
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
  const _BridgeStatusHeader({required this.view, required this.onOpen});

  final SettingsViewState view;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = view.connected;
    final color = connected
        ? StatusColors.live(context)
        : view.phase == ConnectionPhase.reconnecting
        ? StatusColors.aging(context)
        : view.phase == ConnectionPhase.blocked
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
                        view.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Bridge ${view.deviceId}',
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
                  view.bridgeLinkStatusLabel,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (connected)
                  Text(
                    'Battery ${view.batteryPercent}%',
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
                    level: view.signalBars,
                    color: StatusColors.signal(context, view.signalBars),
                    semanticLabel:
                        '${view.signalQualityLabel} signal, ${view.rssi} dBm',
                  ),
                  const SizedBox(width: 7),
                  Text(
                    view.signalQualityLabel,
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
              view.bridgeLastContactDetail,
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
  const _UnitsTile({required this.view, required this.controller});

  final SettingsViewState view;
  final BridgeController controller;

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
                      view.connected
                          ? 'All temperatures, including the Bridge screen.'
                          : 'The Bridge screen will update when you reconnect.',
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
              selected: {view.units},
              onSelectionChanged: (selection) =>
                  controller.setUnits(selection.first),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Live change window',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              DropdownButton<int>(
                key: const Key('settings.tempChangeWindow'),
                value: view.tempChangeWindowMinutes,
                underline: const SizedBox.shrink(),
                items: const [1, 5, 10, 15, 30, 60]
                    .map(
                      (minutes) => DropdownMenuItem<int>(
                        value: minutes,
                        child: Text('$minutes min'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    controller.setTempChangeWindowMinutes(value);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
