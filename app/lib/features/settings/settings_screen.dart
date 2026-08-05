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

import '../../app/app.dart' show ThemeProfile;
import '../../core/format.dart';
import '../../domain/entities/entities.dart';

/// The sections, in the §8.6 order.
enum SettingsSection {
  probes('Probes', 'Names, roles and targets', Icons.thermostat),
  alarms(
    'Alarms',
    'What wakes you, and what only tells you',
    Icons.notifications_outlined,
  ),
  network('Network', 'Which Wi-Fi it uses, and how to reach it', Icons.wifi),
  device('Device', 'Units, screen and storage', Icons.developer_board),
  advanced('Diagnostics', 'Radio, packet log, app log', Icons.tune),
  firmware('Firmware', 'Version and updates', Icons.system_update_alt),
  homeAssistant(
    'Home Assistant',
    'Publish readings to MQTT over Wi-Fi',
    Icons.home_outlined,
  ),
  power('Power', 'Restart, sleep, and factory reset', Icons.power_settings_new),
  storage(
    'Stored cooks',
    'What this phone keeps, and how to clear it',
    Icons.save_outlined,
  ),
  about('About', 'Versions and licences', Icons.info_outline);

  const SettingsSection(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;

  /// The URL slug under `/bridge/`.
  String get slug => name.toLowerCase();

  /// The sections that belong to the **device**, and therefore to the Bridge
  /// tab (13 §13.3.2).
  ///
  /// Two are deliberately absent. [alarms] moved to the Alerts branch, where
  /// delivery and rules belong together. [power] is not listed because the
  /// Bridge tab already carries those verbs in its own danger zone, each
  /// behind a cost sheet — two routes to a factory reset is one too many.
  /// [advanced] is absent because it is a diagnostics console reached by a
  /// deliberate gesture, not a peer of "Probes" (see `BridgeTab`).
  ///
  /// [storage] is absent for a different reason than the others: it is not
  /// about the device at all. It governs what THIS PHONE keeps, which
  /// survives the bridge being unplugged, factory-reset, or replaced — so
  /// filing it under the bridge would misdescribe what clearing it does.
  static const List<SettingsSection> deviceSections = [
    probes,
    network,
    device,
    homeAssistant,
    firmware,
    about,
  ];
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
    this.displayTimeoutS,
    this.ledEnabled,
    this.maxSessions,
    this.onDeviceConfig,
    this.batteryCalibrationAvailable = false,
    this.batterySaver,
    this.onBatterySaver,
    this.themeProfile = ThemeProfile.dark,
    this.onThemeProfile,
    this.unsupportedReason = '',
    super.key,
  });

  /// `F` or `C`. D14 makes °F the default, and the setting travels to the
  /// device: the *device* renders temperatures on its own OLED, and the
  /// two screens must agree.
  final String units;
  final ValueChanged<String> onUnits;

  /// **Null until the bridge has said so** (newapp §F, §I.0).
  ///
  /// These three used to be `= 60`, `= true` and `= 64` — constructor defaults
  /// rendered as if they had been read from the device, on rows whose write
  /// callback was null. A settings screen that states a value it has never
  /// been told is the same lie as a stale temperature under a live chip, and
  /// this app's fourth house rule ("absent ≠ zero") already forbade it
  /// everywhere except here.
  final int? displayTimeoutS;
  final bool? ledEnabled;
  final int? maxSessions;
  final ValueChanged<Map<String, Object?>>? onDeviceConfig;

  /// Non-empty disables the writable rows and states why, rather than leaving
  /// controls that look live and write nothing.
  final String unsupportedReason;

  /// False until F12 (M5). V1.3 settled the divider (×4.9, GPIO37 HIGH
  /// enables) but nothing reads it yet.
  final bool batteryCalibrationAvailable;

  /// `off` · `on` · `auto` — 01 §1.6's saver profile. Tri-state on purpose:
  /// `auto` engages below 20 % and releases at 30 %, which a switch cannot
  /// say. A String for the same reason [units] is one — the wire spelling is
  /// the contract and the route does the mapping.
  final String? batterySaver;
  final ValueChanged<String>? onBatterySaver;

  /// newapp §H.3. Unlike every other row on this page this one is a **phone**
  /// setting, not a device one — it works with the bridge unplugged, and it is
  /// grouped under Display beside units for that reason rather than being
  /// exiled to an About page nobody opens.
  final ThemeProfile themeProfile;
  final ValueChanged<ThemeProfile>? onThemeProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-device'),
      children: [
        if (unsupportedReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              unsupportedReason,
              key: const Key('settings-device-unsupported'),
              style: theme.textTheme.bodySmall,
            ),
          ),
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
          title: const Text('App theme'),
          subtitle: Text(themeProfile.blurb),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<ThemeProfile>(
            key: const Key('settings-theme-profile'),
            segments: [
              for (final p in ThemeProfile.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {themeProfile},
            onSelectionChanged: onThemeProfile == null
                ? null
                : (s) => onThemeProfile!(s.first),
          ),
        ),
        ListTile(
          title: const Text('Display timeout'),
          subtitle: Text(
            displayTimeoutS == null
                ? '—'
                : formatDuration(displayTimeoutS!),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onDeviceConfig == null || displayTimeoutS == null
              ? null
              : () => onDeviceConfig!({
                  'display_timeout_s': displayTimeoutS == 60 ? 300 : 60,
                }),
        ),
        SwitchListTile(
          key: const Key('settings-led'),
          title: const Text('Status LED'),
          subtitle: ledEnabled == null
              ? const Text('The bridge hasn’t reported this yet')
              : null,
          value: ledEnabled ?? false,
          onChanged: onDeviceConfig == null || ledEnabled == null
              ? null
              : (v) => onDeviceConfig!({'led_enabled': v}),
        ),
        const _SectionLabel('Storage'),
        ListTile(
          // The old phrasing ("Keep at most" / "64 cooks on the bridge") never
          // said what happens when it fills up.
          title: const Text('Cooks kept on the bridge'),
          subtitle: Text(
            maxSessions == null
                ? '—'
                : '$maxSessions — the oldest are deleted first',
          ),
        ),
        const _SectionLabel('Battery'),
        ListTile(
          title: const Text('Battery saver'),
          subtitle: Text(switch (batterySaver) {
            'off' => 'Never slow down — full performance on mains power',
            'on' => 'Always saving: slower chip, dimmer screen, less radio',
            'auto' => 'Turns on below 20%, and off again at 30%',
            _ => 'The bridge hasn’t reported this yet',
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<String>(
            key: const Key('settings-battery-saver'),
            segments: const [
              ButtonSegment(value: 'off', label: Text('Off')),
              ButtonSegment(value: 'on', label: Text('On')),
              ButtonSegment(value: 'auto', label: Text('Auto')),
            ],
            emptySelectionAllowed: true,
            selected: {
              // Nothing selected until the device has said which it is —
              // pre-selecting "Auto" would be a guess wearing a fact's clothes.
              if (batterySaver != null) batterySaver!,
            },
            onSelectionChanged:
                onBatterySaver == null || unsupportedReason.isNotEmpty
                ? null
                : (s) => onBatterySaver!(s.first),
          ),
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
    this.paired = false,
    this.onPair,
    this.onUnpair,
    super.key,
  });

  final Map<String, Object?> radio;
  final List<String> packets;
  final String noveltyLog;
  final List<String> logLines;
  final VoidCallback? onExportLogs;

  /// Whether the bridge is currently bound to a Smoke X base.
  final bool paired;

  /// Re-enter sync/scan (`pairing/sync` · op 1) and drop the binding
  /// (`pairing/unpair` · op 2). D15 moved these off the device button, so
  /// this screen is now the only way a user reaches them.
  final VoidCallback? onPair;
  final VoidCallback? onUnpair;

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
        const _SectionLabel('Base station'),
        ListTile(
          key: const Key('settings-pairing-state'),
          title: const Text('Pairing'),
          subtitle: Text(
            paired
                ? 'Bound to a Smoke X base'
                : 'Not paired — put the base in sync mode, then re-scan',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              OutlinedButton.icon(
                key: const Key('settings-pair'),
                onPressed: onPair,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Re-scan'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('settings-unpair'),
                onPressed: onUnpair,
                icon: const Icon(Icons.link_off),
                label: const Text('Unpair'),
              ),
            ],
          ),
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
        const _SectionLabel('Unrecognised packets'),
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

/// The power page (D15).
///
/// The bridge's button can only cycle views and switch itself off, so every
/// other disruptive verb has to live here. All three are confirmed, each
/// with the consequence spelled out rather than a generic "Are you sure?":
///
///  * **Power off is the sharp one.** Nothing remote can undo it — waking the
///    bridge needs someone to walk over and hold PRG (07 §7.4). A user who
///    taps this from the sofa has stranded their cook, so the dialog says so
///    in those words.
///  * **Factory reset forgets this phone's BLE bond**, so the app has to pair
///    again afterwards; that is a surprise worth pre-empting.
class PowerSettingsView extends StatelessWidget {
  const PowerSettingsView({
    this.onRestart,
    this.onPowerOff,
    this.onFactoryReset,
    this.sessionActive = false,
    super.key,
  });

  final Future<void> Function()? onRestart;
  final Future<void> Function()? onPowerOff;
  final Future<void> Function()? onFactoryReset;

  /// Drives the extra "this ends the cook" line, so the warning is specific
  /// when it matters instead of permanently shouting.
  final bool sessionActive;

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const Key('power-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('power-confirm'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cookWarning = sessionActive
        ? ' A cook is running and will be interrupted.'
        : '';
    return ListView(
      key: const Key('settings-power'),
      children: [
        const _SectionLabel('Power'),
        ListTile(
          key: const Key('power-restart'),
          leading: const Icon(Icons.restart_alt),
          title: const Text('Restart the bridge'),
          subtitle: const Text('Comes back on its own in a few seconds'),
          enabled: onRestart != null,
          onTap: onRestart == null
              ? null
              : () async {
                  final ok = await _confirm(
                    context,
                    title: 'Restart the bridge?',
                    body:
                        'It will be unreachable for a few seconds while it '
                        'reboots, then reconnect by itself.$cookWarning',
                    confirmLabel: 'Restart',
                  );
                  if (ok) {
                    await onRestart!();
                  }
                },
        ),
        ListTile(
          key: const Key('power-off'),
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('Power off'),
          subtitle: const Text('Deep sleep — waking it needs the PRG button'),
          enabled: onPowerOff != null,
          onTap: onPowerOff == null
              ? null
              : () async {
                  final ok = await _confirm(
                    context,
                    title: 'Power off the bridge?',
                    body:
                        'It stops responding on Wi-Fi and Bluetooth, and '
                        'nothing in this app can wake it again. To turn it '
                        'back on you must physically hold the PRG button on '
                        'the bridge for about 5 seconds.$cookWarning',
                    confirmLabel: 'Power off',
                    destructive: true,
                  );
                  if (ok) {
                    await onPowerOff!();
                  }
                },
        ),
        const _SectionLabel('Danger zone'),
        ListTile(
          key: const Key('power-factory-reset'),
          leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
          title: Text(
            'Factory reset',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text(
            'Erases pairing, network settings, cook history and Bluetooth '
            'bonds',
          ),
          enabled: onFactoryReset != null,
          onTap: onFactoryReset == null
              ? null
              : () async {
                  final ok = await _confirm(
                    context,
                    title: 'Erase everything?',
                    body:
                        'This wipes the bridge back to how it shipped: its '
                        'pairing with the base, its network settings, every '
                        'stored cook, and its Bluetooth bonds. This phone '
                        'will forget the bridge too, and you’ll have to pair '
                        'with it again. It cannot be undone.$cookWarning',
                    confirmLabel: 'Erase everything',
                    destructive: true,
                  );
                  if (ok) {
                    await onFactoryReset!();
                  }
                },
        ),
      ],
    );
  }
}

/// A29 — the phone's own copy of every cook it has seen, and the only way
/// to get rid of it.
///
/// **The cache is unbounded on purpose.** It keeps cooks the bridge has
/// long since deleted under its 64-session retention (04 §4.7), which is
/// the entire reason it exists — a cook you did last spring outlives the
/// device's own memory of it. A policy like that is only honest if the
/// person it stores data for can end it, and that is this page.
///
/// Nothing here touches the bridge. Clearing the cache is a local erase;
/// the next sync refills whatever the device still holds, which is what
/// separates "clear a cache" from "delete my cooking history".
class StorageSettingsView extends StatelessWidget {
  const StorageSettingsView({
    required this.sessions,
    required this.samples,
    required this.approxBytes,
    this.onClear,
    this.busy = false,
    super.key,
  });

  final int sessions;
  final int samples;

  /// Rounded to whole megabytes on screen — a byte count implies a
  /// precision SQLite's page allocation does not actually give us.
  final int approxBytes;

  /// Null while there is nothing to clear, which is why the tile reads as
  /// disabled rather than offering an erase that would do nothing.
  final Future<void> Function()? onClear;
  final bool busy;

  static String _size(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Hours of cooking, at the nominal 30 s cadence. The number people
  /// actually recognise: "62 hours" means something, "7,440 samples" does
  /// not.
  static String _hours(int samples) {
    final h = samples * 30 / 3600;
    if (h < 1) {
      return '${(h * 60).round()} min';
    }
    return '${h.toStringAsFixed(h < 10 ? 1 : 0)} h';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = sessions == 0 && samples == 0;
    return ListView(
      key: const Key('settings-storage'),
      children: [
        const _SectionLabel('On this phone'),
        ListTile(
          key: const Key('storage-sessions'),
          title: const Text('Cooks kept'),
          subtitle: const Text(
            'Including any the bridge has since deleted to make room',
          ),
          trailing: Text('$sessions'),
        ),
        ListTile(
          key: const Key('storage-samples'),
          title: const Text('Recorded time'),
          subtitle: Text('$samples readings'),
          trailing: Text(_hours(samples)),
        ),
        ListTile(
          key: const Key('storage-size'),
          title: const Text('Approximate size'),
          trailing: Text(_size(approxBytes)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Cooks are copied off the bridge as soon as this phone can reach '
            'it — over Bluetooth or Wi-Fi — and then kept here until you '
            'clear them. Nothing expires on its own.',
            key: const Key('storage-explainer'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const _SectionLabel('Danger zone'),
        ListTile(
          key: const Key('storage-clear'),
          leading: Icon(
            Icons.delete_sweep_outlined,
            color: empty ? theme.disabledColor : theme.colorScheme.error,
          ),
          title: Text(
            'Clear stored cooks',
            style: TextStyle(
              color: empty ? theme.disabledColor : theme.colorScheme.error,
            ),
          ),
          subtitle: Text(
            empty
                ? 'Nothing is stored on this phone yet'
                : 'Removes every cook from this phone. The bridge keeps its '
                      'own copy of whatever it still holds.',
          ),
          enabled: !empty && !busy && onClear != null,
          onTap: (empty || busy || onClear == null)
              ? null
              : () async {
                  final ok = await _confirmClear(context);
                  if (ok) {
                    await onClear!();
                  }
                },
        ),
      ],
    );
  }

  Future<bool> _confirmClear(BuildContext context) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear stored cooks?'),
        content: Text(
          'This removes $sessions ${sessions == 1 ? 'cook' : 'cooks'} and '
          '${_hours(samples)} of readings from this phone. It cannot be '
          'undone.\n\nThe bridge is not touched. Anything it still holds '
          'will be copied back the next time this phone connects — but '
          'cooks the bridge has already deleted will be gone for good.',
        ),
        actions: [
          TextButton(
            key: const Key('storage-clear-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('storage-clear-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return ok ?? false;
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
