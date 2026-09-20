/// The settings tree: its sections, and the four pages that describe *what the
/// bridge is* rather than what it does (newapp §F, 16 §16.5–§16.6).
///
/// **The rule that governs every page in this folder**, restated where it is
/// easiest to break: a control that cannot work is worse than no control, and
/// a value nobody read is worse than a blank. So a row is one of exactly three
/// things — live, absent (`—`), or **present, dimmed, and carrying the sentence
/// that says why**. There is no fourth state, and in particular there is no
/// "looks live, writes nothing", which is the state §F was opened to delete.
///
/// The sections below are §F's frozen v1 tree. Two of them are here rather than
/// on the Bridge tab for reasons worth stating:
///
///  * **Data and export** is not about the bridge at all. It governs what THIS
///    PHONE keeps, which survives the bridge being unplugged, reset or
///    replaced — filing it under the device would misdescribe what clearing it
///    does.
///  * **Diagnostics** is a console reached by a deliberate gesture, not a peer
///    of "Probes". It is the page someone opens when they already suspect
///    something is wrong, and every row on it is measured or absent.
library;

import 'package:flutter/material.dart';

import '../../app/app.dart' show ThemeProfile;
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import 'settings_kit.dart';

/// §F's tree, **in the order a cook needs it**.
///
/// The order used to be the order somebody happened to type the sections in,
/// which put Identity first: four read-only rows and a permanently disabled
/// rename, at the top of the one screen a person opens mid-cook. Nobody has
/// ever opened settings to re-read the id printed on the case.
///
/// So the list now runs: what is plugged in, what will wake you, whether it
/// can be reached at all, then what it shows, what it costs in battery, what
/// it keeps, and only at the end the things that are true of the box rather
/// than of the cook.
enum SettingsSection {
  probes(
    'Probes',
    'What each of the four jacks is called, and what it is for',
    Icons.thermostat,
  ),

  /// Named for what the page is actually about. It carries **delivery** —
  /// quiet hours, background monitoring, the battery exemption — while the
  /// rules themselves live in the editor at `/device/alarms`. Two entry points
  /// called "Alarm rules" and "Alarms and notifications", three rows apart and
  /// going to different screens, was a guess the user had to make.
  alarms(
    'Notifications on this phone',
    'Whether an alarm actually reaches you, and when it stays quiet',
    Icons.notifications_outlined,
  ),
  network(
    'Network',
    'Whether it hosts its own or joins yours, and how to reach it',
    Icons.wifi,
  ),
  display(
    'Display and units',
    '°F or °C, how this app looks, and the bridge’s own screen',
    Icons.contrast,
  ),
  power(
    'Power and sleep',
    'Battery saver, restarting, and switching it off',
    Icons.power_settings_new,
  ),
  data(
    'Data and export',
    'What this phone keeps, getting it out, and clearing it',
    Icons.save_outlined,
  ),
  firmware(
    'Firmware',
    'Which version it runs, and how to update it',
    Icons.system_update_alt,
  ),
  led(
    'Status light',
    'Off, or lit while it’s hearing the base station',
    Icons.light_mode,
  ),
  homeAssistant(
    'Home Assistant',
    'Publish your cook to MQTT over Wi-Fi',
    Icons.home_outlined,
  ),
  identity(
    'Name and identity',
    'Which bridge this is, and what it is paired to',
    Icons.badge_outlined,
  ),

  /// Named `advanced` because `/device/settings/advanced` is a live deep link
  /// and the Bridge tab pushes it by name. It is titled Diagnostics
  /// everywhere a person can see.
  advanced(
    'Diagnostics',
    'Link, buffer, sync and clock — the numbers behind a problem',
    Icons.tune,
  ),
  about('About', 'Versions and licences', Icons.info_outline);

  const SettingsSection(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;

  /// The URL slug under `/device/settings/`.
  String get slug => name.toLowerCase();

  /// The sections the Bridge tab lists directly.
  ///
  /// [advanced] is absent because it is a diagnostics console reached by a
  /// deliberate gesture. [about] is absent because nobody goes looking for a
  /// licence notice from a device screen; it stays reachable from the section
  /// list and by URL.
  static const List<SettingsSection> deviceSections = [
    probes,
    alarms,
    network,
    display,
    power,
    data,
    firmware,
    led,
    homeAssistant,
    identity,
  ];
}

/// The section list. One card, one row per section — a subject index, not a
/// settings page in its own right.
class SettingsHomeView extends StatelessWidget {
  const SettingsHomeView({required this.onOpen, super.key});

  final ValueChanged<SettingsSection> onOpen;

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-home'),
    lead:
        'Everything the bridge can be told, from the phone. It has one button, '
        'so this is where the rest of it lives.',
    children: [
      SettingsGroup(
        children: [
          for (final s in SettingsSection.values)
            SettingsRow(
              key: Key('settings-section-${s.name}'),
              label: s.title,
              subtitle: s.subtitle,
              trailing: const SizedBox.shrink(),
              onTap: () => onOpen(s),
            ),
        ],
      ),
    ],
  );
}

/// §F Identity — which bridge this is, and what it is bound to.
///
/// Everything on the first card is **read from `/status`**; nothing here has a
/// constructor default, because there is no honest default for "which device
/// am I talking to". The rename row is present and disabled: it is a control
/// people go looking for, and the reason it is not there is worth one sentence.
class IdentitySettingsView extends StatelessWidget {
  const IdentitySettingsView({
    this.deviceId,
    this.model,
    this.firmware,
    this.address,
    this.paired,
    this.onPair,
    this.onUnpair,
    this.controlReason = '',
    super.key,
  });

  /// All four are null until `/status` answers.
  final String? deviceId;
  final String? model;
  final String? firmware;

  /// The address this phone is reaching it on, when it is on Wi-Fi.
  final String? address;

  /// Whether the bridge is bound to a Smoke X base. Null = not yet known,
  /// which is **not** the same as "not paired" and must not read as it.
  final bool? paired;

  final VoidCallback? onPair;
  final VoidCallback? onUnpair;
  final String controlReason;

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-identity'),
    lead:
        'A bridge is identified by the id printed on its case. This phone uses '
        'it to tell one bridge from another, so a reset bridge is never '
        'mistaken for the one your cooks came from.',
    children: [
      const SettingsSectionLabel('This bridge'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const Key('identity-device-id'),
            label: 'Bridge id',
            subtitle: 'Printed on the case, and never changes',
            value: (deviceId ?? '').isEmpty ? null : deviceId,
          ),
          SettingsRow(
            key: const Key('identity-model'),
            label: 'Model',
            value: (model ?? '').isEmpty ? null : model,
          ),
          SettingsRow(
            key: const Key('identity-firmware'),
            label: 'Firmware',
            value: (firmware ?? '').isEmpty ? null : firmware,
          ),
          SettingsRow(
            key: const Key('identity-address'),
            label: 'Reached at',
            subtitle: 'The address this phone is using right now',
            value: (address ?? '').isEmpty ? null : address,
          ),
          const SettingsRow(
            key: Key('identity-rename'),
            label: 'Rename this bridge',
            subtitle: 'Change the name it advertises on your network',
            reason:
                'This version of the app can’t rename a bridge. It answers to '
                'the id on its case, which is what setup uses to find it.',
          ),
          // §F lists an mDNS name beside the device name. It is derived from
          // the id rather than stored, so it is stated rather than offered —
          // and the value is worth having on screen: it is what somebody types
          // into a browser when the app itself cannot find the bridge.
          SettingsRow(
            key: const Key('identity-mdns'),
            label: 'Name on your network',
            subtitle: 'What it answers to when your network resolves names',
            value: (deviceId ?? '').isEmpty
                ? null
                : '${deviceId!.toLowerCase()}.local',
            reason:
                'The bridge builds this from the id on its case and offers no '
                'way to change it.',
          ),
        ],
      ),
      const SettingsSectionLabel('Base station'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const Key('identity-paired'),
            label: 'Paired to a Smoke X',
            subtitle: switch (paired) {
              null => 'The bridge hasn’t reported this yet',
              true => 'Readings arrive from the base station over its radio',
              false => 'Put the base station in sync mode, then re-scan',
            },
            value: switch (paired) {
              null => null,
              true => 'Yes',
              false => 'No',
            },
          ),
          SettingsActionRow(
            key: const Key('identity-pair'),
            label: 'Look for the base station',
            subtitle:
                'Re-runs the pairing scan. Nothing is lost if it finds the '
                'same one.',
            buttonLabel: 'Re-scan',
            reason: controlReason,
            onPressed: onPair,
          ),
          SettingsActionRow(
            key: const Key('identity-unpair'),
            label: 'Forget the base station',
            subtitle:
                'Readings stop until you pair again. Cooks already recorded '
                'are untouched.',
            buttonLabel: 'Unpair',
            danger: true,
            reason: controlReason,
            onPressed: onUnpair,
          ),
        ],
      ),
    ],
  );
}

/// §F Display & units — one page, three subjects, and they are genuinely
/// different subjects: what the numbers mean, how *this app* looks, and what
/// the *bridge's own screen* does.
///
/// Keeping them apart matters because only the first travels to the device and
/// only the second works with the bridge unplugged. A user who changes the
/// theme and then wonders why the bridge's screen is still dark has been
/// misled by grouping, not by copy.
class DisplaySettingsView extends StatelessWidget {
  const DisplaySettingsView({
    required this.units,
    required this.onUnits,
    this.deviceUnits,
    this.themeProfile = ThemeProfile.dark,
    this.onThemeProfile,
    this.displayTimeoutS,
    this.onDisplayTimeout,
    this.deviceReason = '',
    this.hardwareReason = '',
    super.key,
  });

  /// `F` or `C`. A **phone** setting that also travels to the bridge, because
  /// the bridge renders temperatures on its own screen and two screens
  /// disagreeing about the same probe is worse than either being wrong.
  final String units;
  final ValueChanged<String> onUnits;

  /// What the **bridge** says its own screen is using, read from
  /// `GET /config/device`. Null until it answers.
  ///
  /// Worth its own field rather than being assumed equal to [units]: the two
  /// can genuinely disagree — a bridge provisioned by another phone, or a
  /// write that never landed — and the one place that difference is
  /// discoverable is this row.
  final String? deviceUnits;

  final ThemeProfile themeProfile;
  final ValueChanged<ThemeProfile>? onThemeProfile;

  /// Seconds the bridge's own screen stays lit; 0 = never sleeps. Null until
  /// the bridge reports it.
  final int? displayTimeoutS;
  final ValueChanged<int>? onDisplayTimeout;

  /// Why the **mirror to the bridge's own screen** cannot be sent on this
  /// lane, or `''`.
  ///
  /// It is deliberately *not* on the units row any more. °F/°C is a phone
  /// setting: the route writes it to prefs and every reading in the app
  /// changes on the next frame, bridge or no bridge. Disabling the row when
  /// the bridge was unreachable made the app's own units unchangeable at
  /// precisely the moment somebody was sitting there with nothing else to do
  /// — and the card one section below states the opposite principle out loud.
  /// The caveat belongs in the sentence, not on the control.
  final String deviceReason;

  /// Why the bridge's **own hardware** (its screen) cannot be set on this lane.
  /// Bluetooth carries units and the battery saver and nothing else, so this is
  /// non-empty there even though the units row above stays live.
  final String hardwareReason;

  /// The firmware clamps to `{0} ∪ [15, 600]`, so every shortcut here is a
  /// value the bridge will actually keep. A chip that silently became
  /// something else on arrival would be the same lie in a new place.
  static const List<ChipOption<int>> _timeouts = [
    ChipOption(0, 'Never'),
    ChipOption(30, '30s'),
    ChipOption(60, '1m'),
    ChipOption(300, '5m'),
    ChipOption(600, '10m'),
  ];

  String get _unitsNote {
    if (deviceReason.isNotEmpty) {
      return 'Changes every reading in the app straight away. The bridge’s own '
          'screen will catch up when it’s back.';
    }
    if (deviceUnits == null) {
      return 'Changes every reading in the app, and travels to the bridge so '
          'its own screen agrees';
    }
    final same = deviceUnits == (units == 'C' ? 'C' : 'F');
    return same
        ? 'The bridge’s own screen is showing ${_unitName(deviceUnits!)} too'
        : 'This phone shows ${_unitName(units)}; the bridge’s own screen is '
              'still on ${_unitName(deviceUnits!)}. Choosing again sends it.';
  }

  static String _unitName(String u) => u == 'C' ? 'Celsius' : 'Fahrenheit';

  /// Seconds, said the way a person would. `formatDuration` is built for cook
  /// lengths and rounds anything under a minute to `<1m`, which turns the
  /// firmware's 15-second floor into a value nobody can read back.
  static String _timeoutLabel(int s) {
    if (s <= 0) {
      return 'Never sleeps';
    }
    if (s < 60) {
      return '${s}s';
    }
    final m = s ~/ 60;
    final rem = s % 60;
    return rem == 0 ? '${m}m' : '${m}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-display'),
    children: [
      const SettingsSectionLabel('Temperature'),
      SettingsGroup(
        children: [
          SettingsChoiceRow<String>(
            key: const Key('settings-units'),
            label: 'Units',
            subtitle: _unitsNote,
            options: const [ChipOption('F', '°F'), ChipOption('C', '°C')],
            value: units == 'C' ? 'C' : 'F',
            onChanged: onUnits,
          ),
        ],
      ),
      const SettingsSectionLabel('This app'),
      SettingsGroup(
        footer: const Text(
          'This one is only about your phone. It applies straight away, with '
          'the bridge unplugged or out of range.',
        ),
        children: [
          SettingsChoiceRow<ThemeProfile>(
            key: const Key('settings-theme-profile'),
            label: 'Look',
            subtitle: themeProfile.blurb,
            options: [
              for (final p in ThemeProfile.values) ChipOption(p, p.label),
            ],
            value: themeProfile,
            onChanged: onThemeProfile,
          ),
        ],
      ),
      const SettingsSectionLabel('The bridge’s own screen'),
      SettingsGroup(
        children: [
          SettingsChoiceRow<int>(
            key: const Key('settings-display-timeout'),
            label: 'Screen timeout',
            subtitle: displayTimeoutS == 0
                ? 'It never sleeps. Costs battery, and burns the panel in over '
                      'a long cook.'
                : 'How long it stays lit after the last button press',
            options: _timeouts,
            value: displayTimeoutS,
            reportsValue: true,
            valueLabel: displayTimeoutS == null
                ? null
                : _timeoutLabel(displayTimeoutS!),
            reason: hardwareReason,
            onChanged: onDisplayTimeout,
          ),
          const SettingsRow(
            key: Key('settings-oled'),
            label: 'Brightness, contrast, rotation and what it shows',
            subtitle: 'Set on the bridge itself — its button cycles the pages',
            reason:
                'The bridge doesn’t offer these over the network, so the app '
                'has no way to ask for them. Rotation is fixed in its '
                'firmware.',
          ),
        ],
      ),
    ],
  );
}

/// §F LED — the light, now that there is something behind it.
///
/// This page exists rather than being folded away because the light is a thing
/// people come looking for: it is the only output the bridge has that is
/// visible from across a yard.
///
/// It is also the page that best shows what the read half bought. Until the
/// transport could read `GET /config/device`, both rows were `—` with a reason.
/// The switch is now live and reports the bridge's own answer; the two rows
/// underneath still say `—`, because §F asks for three-way behaviour and a
/// brightness and the firmware stores neither — and a row that says so is
/// worth more than a row that quietly isn't there.
class LedSettingsView extends StatelessWidget {
  const LedSettingsView({
    this.enabled,
    this.onEnabled,
    this.brightness,
    this.reason = '',
    super.key,
  });

  /// What the bridge reports, from `GET /config/device`. Null until it answers
  /// — and on a lane that cannot read it, null for good, which is why the
  /// switch is inert rather than sitting at a confident "off".
  final bool? enabled;
  final ValueChanged<bool>? onEnabled;

  /// Null always, today: the firmware stores no brightness.
  final int? brightness;

  /// Why the light cannot be set on this lane, or `''`.
  final String reason;

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-led'),
    lead: 'It is the only signal you can see from across the yard.',
    children: [
      // Not "Status light": that was the section label, the row label and half
      // the section's own subtitle on the index — the same two words three
      // times before anything had been said.
      const SettingsSectionLabel('The light on the bridge'),
      SettingsGroup(
        children: [
          SettingsSwitchRow(
            key: const Key('led-enabled'),
            label: 'Status light',
            subtitle: switch (enabled) {
              true => 'Lit while the bridge is awake and hearing the base',
              false => 'Dark. The bridge keeps recording either way.',
              null => '',
            },
            value: enabled,
            reason: reason,
            unknownNote: 'The bridge hasn’t reported this yet.',
            onChanged: onEnabled,
          ),
          const SettingsRow(
            key: Key('led-behaviour'),
            label: 'Only light up for alarms',
            subtitle: 'Dark during a normal cook, lit when something is wrong',
            reason:
                'The bridge stores the light as on or off, with no alarms-only '
                'setting in between.',
          ),
          SettingsRow(
            key: const Key('led-brightness'),
            label: 'Brightness',
            subtitle: 'How bright it is at night',
            value: brightness == null ? null : '$brightness%',
            reason:
                'The bridge doesn’t store a brightness — its light is on or '
                'off.',
          ),
        ],
      ),
    ],
  );
}

/// §F About. The MIT attribution for the reference parser is **D9's legal
/// obligation**, not a nicety, which is why it is a committed string and not a
/// link somebody can forget to add.
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
    final t = context.tokens;
    return SettingsPage(
      key: const Key('settings-about'),
      children: [
        const SettingsSectionLabel('Versions'),
        SettingsGroup(
          children: [
            SettingsRow(
              label: 'App',
              value: appVersion.isEmpty ? null : appVersion,
            ),
            SettingsRow(
              label: 'Bridge firmware',
              value: firmwareVersion.isEmpty ? null : firmwareVersion,
            ),
            SettingsRow(
              label: 'Bridge id',
              value: deviceId.isEmpty ? null : deviceId,
            ),
          ],
        ),
        const SettingsSectionLabel('Licences'),
        SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SmokeTokens.s4,
                SmokeTokens.s3,
                SmokeTokens.s4,
                SmokeTokens.s3,
              ),
              child: Text(
                'The Smoke X packet parser is derived from the ThermoWorks '
                'Smoke gateway reference implementation, used under the MIT '
                'licence with attribution retained (D9).',
                key: const Key('settings-attribution'),
                style: SmokeType.bodySm.copyWith(color: t.textBody),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared by the probe editor, the alarm log and the diagnostics page.
String probeRoleLabel(ProbeRole r) => switch (r) {
  ProbeRole.unused => 'Not used',
  ProbeRole.pit => 'Pit',
  ProbeRole.food => 'Food',
  ProbeRole.ambient => 'Ambient',
};
