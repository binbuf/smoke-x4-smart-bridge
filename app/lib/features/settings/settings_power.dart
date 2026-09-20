/// §F Power & sleep — the battery, and the three verbs that take the bridge
/// down (D15, 16 §16.4 rule 8).
///
/// The bridge's one button can cycle its screen and put it to sleep. Every
/// other disruptive verb has to live here, and each one runs behind a **cost
/// sheet that states what survives and what does not** — never "Are you sure?",
/// which asks the user to supply the consequence from memory.
///
/// The battery-saver row is the interesting one, and it is the shape every
/// unverifiable write in this app should take. The bridge accepts the mode and
/// **never reports it back**: there is no read for it on any lane. So the row
/// separates two different facts that a single control would have blurred into
/// one lie —
///
///  * **what you asked for**, marked as asked-for until something confirms it;
///  * **what the bridge is doing right now**, which its power push does report,
///    and which is therefore a fact.
///
/// "Auto" is why this is three chips and not a switch: it engages below 20 %
/// and releases at 30 %, which a two-state control cannot say.
library;

import 'package:flutter/material.dart';

import '../../ui/ui.dart';
import 'settings_kit.dart';

class PowerSettingsView extends StatelessWidget {
  const PowerSettingsView({
    this.batterySaver,
    this.batterySaverConfirmed = false,
    this.onBatterySaver,
    this.saverEngaged,
    this.socPct,
    this.charging,
    this.sessionActive = false,
    this.onRestart,
    this.onPowerOff,
    this.onFactoryReset,
    this.configReason = '',
    this.controlReason = '',
    super.key,
  });

  /// `off` · `on` · `auto`, or null before anything is known. Pre-selecting
  /// "Auto" would be a guess wearing a fact's clothes.
  final String? batterySaver;

  /// True only when [batterySaver] came from the device rather than from the
  /// user's own tap. Drives whether the row claims a fact or reports a request.
  final bool batterySaverConfirmed;
  final ValueChanged<String>? onBatterySaver;

  /// Whether the bridge is throttling **right now**, from its power push. This
  /// one is measured, so it is allowed to be stated flatly.
  final bool? saverEngaged;

  /// 0–100, or null on a bridge that cannot measure a battery. Absent ≠ 0 %.
  final int? socPct;
  final bool? charging;

  /// Drives the extra "this ends the cook" line, so the warning is specific
  /// when it matters instead of permanently shouting.
  final bool sessionActive;

  final Future<void> Function()? onRestart;
  final Future<void> Function()? onPowerOff;
  final Future<void> Function()? onFactoryReset;

  /// Why the battery saver cannot be written on this lane, or `''`.
  final String configReason;

  /// Why the verbs cannot be sent on this lane, or `''`.
  final String controlReason;

  String get _cookLine =>
      sessionActive ? ' A cook is running and will be interrupted.' : '';

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-power'),
    children: [
      const SettingsSectionLabel('Battery'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const Key('power-charge'),
            label: 'Charge',
            subtitle: switch (charging) {
              true => 'On mains power and charging',
              false => 'Running on its own battery',
              null => 'The bridge hasn’t reported this yet',
            },
            value: socPct == null ? null : '$socPct%',
          ),
          SettingsChoiceRow<String>(
            key: const Key('settings-battery-saver'),
            label: 'Battery saver',
            subtitle: switch (batterySaver) {
              'off' => 'Never slow down — right for a bridge on mains power',
              'on' => 'Always saving: slower chip, dimmer screen, less radio',
              'auto' => 'Starts saving below 20%, and stops again at 30%',
              _ => 'The bridge hasn’t reported which of these it is using',
            },
            options: const [
              ChipOption('off', 'Off'),
              ChipOption('on', 'On'),
              ChipOption('auto', 'Auto'),
            ],
            value: batterySaver,
            reason: configReason,
            onChanged: onBatterySaver,
          ),
          SettingsRow(
            key: const Key('power-saver-now'),
            label: 'Saving right now',
            subtitle: batterySaverConfirmed || batterySaver == null
                ? 'Slower chip, dimmer screen — readings keep their '
                      '30-second cadence'
                : 'You asked for “${_modeLabel(batterySaver!)}”. This '
                      'connection can’t read the setting back, so this line is '
                      'the only confirmation there is.',
            value: switch (saverEngaged) {
              true => 'Yes',
              false => 'No',
              null => null,
            },
          ),
          // A "Battery calibration" row lived here, permanently disabled
          // behind "this bridge does not report a battery voltage, so there is
          // nothing to calibrate against" — and per its own comment it always
          // would. A row that can never become available is not a disabled
          // control, it is a permanent line of noise on the page, and 16 §16.5
          // asks for disabled-with-a-reason precisely because the reason is
          // supposed to be temporary.
        ],
      ),
      const SettingsSectionLabel('Sleep'),
      const SettingsGroup(
        children: [
          SettingsRow(
            key: Key('power-auto-sleep'),
            label: 'Sleep when idle',
            subtitle:
                'How long it waits with nothing to record before dozing off',
            reason:
                'The bridge doesn’t report this to the app, so there is '
                'nothing to show and nothing to change.',
          ),
        ],
      ),
      const SettingsSectionLabel('Restart and switch off'),
      SettingsGroup(
        children: [
          SettingsActionRow(
            key: const Key('power-restart'),
            label: 'Restart the bridge',
            subtitle: 'It goes quiet for a few seconds, then comes back alone',
            buttonLabel: 'Restart',
            reason: controlReason,
            onPressed: onRestart == null
                ? null
                : () async {
                    final ok = await showCostSheet(
                      context,
                      title: 'Restart the bridge?',
                      body:
                          'It stops answering for a few seconds while it '
                          'reboots, then reconnects by itself.$_cookLine',
                      keeps:
                          'every cook it has recorded, its pairing with the '
                          'base station, and its network settings.',
                      loses: sessionActive
                          ? 'the readings taken while it is down — a few '
                                'seconds of the running cook.'
                          : 'nothing. This is the safe one.',
                      confirmLabel: 'Restart',
                      cancelLabel: 'Leave it running',
                    );
                    if (ok) {
                      await onRestart!();
                    }
                  },
          ),
          SettingsActionRow(
            key: const Key('power-off'),
            label: 'Power off',
            subtitle: 'Deep sleep. Only the PRG button on the bridge wakes it',
            buttonLabel: 'Power off',
            danger: true,
            reason: controlReason,
            onPressed: onPowerOff == null
                ? null
                : () async {
                    final ok = await showCostSheet(
                      context,
                      title: 'Power off the bridge?',
                      body:
                          'It stops answering on Wi-Fi and Bluetooth, and '
                          'nothing in this app can wake it again. To turn it '
                          'back on you have to physically hold the PRG button '
                          'on the bridge for about five seconds.$_cookLine',
                      keeps:
                          'everything it has already recorded, its pairing, '
                          'and its network settings.',
                      loses:
                          'every reading from now until somebody walks over '
                          'and switches it back on.',
                      confirmLabel: 'Power off',
                      cancelLabel: 'Keep it on',
                    );
                    if (ok) {
                      await onPowerOff!();
                    }
                  },
          ),
        ],
      ),
      const SettingsSectionLabel('Erase'),
      SettingsGroup(
        children: [
          SettingsActionRow(
            key: const Key('power-factory-reset'),
            label: 'Factory reset',
            subtitle: 'Wipes the bridge back to how it shipped',
            buttonLabel: 'Erase',
            danger: true,
            reason: controlReason,
            onPressed: onFactoryReset == null
                ? null
                : () async {
                    final ok = await showCostSheet(
                      context,
                      title: 'Erase everything on the bridge?',
                      body:
                          'This puts the bridge back to how it shipped. It '
                          'cannot be undone.$_cookLine',
                      keeps:
                          'every cook already copied to this phone — those '
                          'stay under Cooks, and clearing the bridge does not '
                          'touch them.',
                      loses:
                          'its pairing with the base station, its network '
                          'settings, any cook it has not yet handed over, and '
                          'its Bluetooth bond with this phone. You will have '
                          'to pair with it again.',
                      confirmLabel: 'Erase everything',
                      cancelLabel: 'Keep it as it is',
                    );
                    if (ok) {
                      await onFactoryReset!();
                    }
                  },
          ),
        ],
      ),
    ],
  );

  static String _modeLabel(String mode) => switch (mode) {
    'off' => 'Off',
    'on' => 'On',
    _ => 'Auto',
  };
}
