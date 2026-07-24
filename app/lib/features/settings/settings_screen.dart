/// A12.1 / A12.4 — the settings shell, the device page, advanced, and
/// about (design 08 §8.6, 06 §6.2, 02 §2.7).
///
/// One rule runs through this whole epic and is worth stating where it is
/// easiest to break: **a control that cannot work is worse than no
/// control.** Battery calibration needs F12 (M5); the bearer token has no
/// transport that can set it (P3.2 moved it to v1.1, and the obligation
/// landed here verbatim: "M4's settings UI hides the toggle"); alarm
/// delivery needs A13's foreground service. Each of those is either
/// absent or present-and-disabled **with its reason on screen** — never a
/// switch that silently does nothing.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../domain/entities/entities.dart';

/// The sections, in the §8.6 order.
enum SettingsSection {
  probes('Probes', 'Names, roles, targets', Icons.thermostat),
  alarms(
    'Alarms',
    'What wakes you, and what only tells you',
    Icons.notifications_outlined,
  ),
  network('Network', 'Hosted or joined, and how to reach it', Icons.wifi),
  device('Device', 'Units, display, retention', Icons.developer_board),
  advanced('Advanced', 'Radio, raw packets, logs', Icons.tune),
  firmware('Firmware', 'Version and updates', Icons.system_update_alt),
  about('About', 'Versions and licences', Icons.info_outline);

  const SettingsSection(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

class SettingsHomeView extends StatelessWidget {
  const SettingsHomeView({required this.onOpen, super.key});

  final ValueChanged<SettingsSection> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('settings-home'),
    children: [
      for (final s in SettingsSection.values)
        ListTile(
          key: Key('settings-section-${s.name}'),
          leading: Icon(s.icon),
          title: Text(s.title),
          subtitle: Text(s.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(s),
        ),
    ],
  );
}

/// A12.4 — device settings.
class DeviceSettingsView extends StatelessWidget {
  const DeviceSettingsView({
    required this.units,
    required this.onUnits,
    this.displayTimeoutS = 60,
    this.ledEnabled = true,
    this.maxSessions = 64,
    this.onDeviceConfig,
    this.batteryCalibrationAvailable = false,
    super.key,
  });

  /// `F` or `C`. D14 makes °F the default, and the setting travels to the
  /// device: the *device* renders temperatures on its own OLED, and the
  /// two screens must agree.
  final String units;
  final ValueChanged<String> onUnits;
  final int displayTimeoutS;
  final bool ledEnabled;
  final int maxSessions;
  final ValueChanged<Map<String, Object?>>? onDeviceConfig;

  /// False until F12 (M5). V1.3 settled the divider (×4.9, GPIO37 HIGH
  /// enables) but nothing reads it yet.
  final bool batteryCalibrationAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-device'),
      children: [
        const _SectionLabel('Display'),
        ListTile(
          title: const Text('Temperature units'),
          subtitle: Text(units == 'C' ? 'Celsius' : 'Fahrenheit'),
          trailing: SegmentedButton<String>(
            key: const Key('settings-units'),
            segments: const [
              ButtonSegment(value: 'F', label: Text('°F')),
              ButtonSegment(value: 'C', label: Text('°C')),
            ],
            selected: {units == 'C' ? 'C' : 'F'},
            onSelectionChanged: (s) => onUnits(s.first),
          ),
        ),
        ListTile(
          title: const Text('Display timeout'),
          subtitle: Text(formatDuration(displayTimeoutS)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onDeviceConfig == null
              ? null
              : () => onDeviceConfig!({
                  'display_timeout_s': displayTimeoutS == 60 ? 300 : 60,
                }),
        ),
        SwitchListTile(
          key: const Key('settings-led'),
          title: const Text('Status LED'),
          value: ledEnabled,
          onChanged: onDeviceConfig == null
              ? null
              : (v) => onDeviceConfig!({'led_enabled': v}),
        ),
        const _SectionLabel('Storage'),
        ListTile(
          title: const Text('Keep at most'),
          subtitle: Text('$maxSessions cooks on the bridge'),
        ),
        ListTile(
          key: const Key('settings-battery-calibration'),
          enabled: batteryCalibrationAvailable,
          title: const Text('Battery calibration'),
          subtitle: Text(
            batteryCalibrationAvailable
                ? 'Enter a meter reading to refine the divider ratio'
                // Present and disabled, with the reason: the alternative
                // is a control that pretends the bridge can measure a
                // battery it cannot yet read.
                : 'Not available yet — this bridge does not report a '
                      'battery voltage',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// A12.4 — advanced: radio, the raw packet ring, the novelty log, and the
/// in-app log ring. **Field diagnosis without a cable** (08 §8.2) is the
/// whole reason this page exists.
class AdvancedSettingsView extends StatelessWidget {
  const AdvancedSettingsView({
    this.radio = const {},
    this.packets = const [],
    this.noveltyLog = '',
    this.logLines = const [],
    this.onExportLogs,
    super.key,
  });

  final Map<String, Object?> radio;
  final List<String> packets;
  final String noveltyLog;
  final List<String> logLines;
  final VoidCallback? onExportLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-advanced'),
      children: [
        const _SectionLabel('LoRa'),
        for (final e in radio.entries)
          ListTile(
            dense: true,
            title: Text(e.key.replaceAll('_', ' ')),
            trailing: Text('${e.value}'),
          ),
        const _SectionLabel('Raw packets'),
        if (packets.isEmpty)
          const ListTile(
            key: Key('settings-packets-empty'),
            subtitle: Text('No packets captured yet.'),
          )
        else
          for (final p in packets.take(32))
            ListTile(
              dense: true,
              title: Text(p, style: theme.textTheme.bodySmall),
            ),
        const _SectionLabel('Novelty log'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            noveltyLog.isEmpty ? 'Nothing new observed.' : noveltyLog,
            key: const Key('settings-novelty'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        const _SectionLabel('App log'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            logLines.isEmpty
                ? 'Nothing logged this session.'
                : logLines.join('\n'),
            key: const Key('settings-logs'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            key: const Key('settings-export-logs'),
            onPressed: onExportLogs,
            icon: const Icon(Icons.ios_share),
            label: const Text('Export logs'),
          ),
        ),
      ],
    );
  }
}

/// A12.4 — about. The MIT attribution for the reference parser is **D9's
/// legal obligation**, not a nicety, which is why it is a committed string
/// and not a link somebody can forget to add.
class AboutView extends StatelessWidget {
  const AboutView({
    required this.appVersion,
    this.firmwareVersion = '',
    this.deviceId = '',
    super.key,
  });

  final String appVersion;
  final String firmwareVersion;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-about'),
      children: [
        ListTile(title: const Text('App version'), trailing: Text(appVersion)),
        ListTile(
          title: const Text('Bridge firmware'),
          trailing: Text(firmwareVersion.isEmpty ? noValue : firmwareVersion),
        ),
        ListTile(
          title: const Text('Bridge id'),
          trailing: Text(deviceId.isEmpty ? noValue : deviceId),
        ),
        const _SectionLabel('Licences'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Text(
            'The Smoke X packet parser is derived from the ThermoWorks '
            'Smoke gateway reference implementation, used under the MIT '
            'licence with attribution retained (D9).',
            key: const Key('settings-attribution'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Shared by the probe editor and the alarms page.
String probeRoleLabel(ProbeRole r) => switch (r) {
  ProbeRole.unused => 'Not used',
  ProbeRole.pit => 'Pit',
  ProbeRole.food => 'Food',
  ProbeRole.ambient => 'Ambient',
};
