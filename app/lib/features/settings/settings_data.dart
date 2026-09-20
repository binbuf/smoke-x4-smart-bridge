/// §F Data & export — what this phone keeps, how to get it out, and how to end
/// it.
///
/// **This page is not about the bridge**, and that is the reason it is its own
/// section rather than a card under the device. The cache is unbounded on
/// purpose: it holds cooks the bridge deleted long ago under its own retention
/// (04 §4.7), which is the entire reason it exists — a cook you did last spring
/// outlives the device's memory of it. A policy like that is only honest if the
/// person whose data it is can end it, and that is the last card here.
///
/// The two erases on this page are therefore **not** the same act and are not
/// grouped together: clearing this phone loses cooks the bridge no longer has,
/// while the bridge's own buffer rolls over on its own and takes nothing from
/// the phone with it. The cost sheet says exactly that.
library;

import 'package:flutter/material.dart';

import '../../ui/ui.dart';
import 'settings_kit.dart';

class DataSettingsView extends StatelessWidget {
  const DataSettingsView({
    required this.sessions,
    required this.samples,
    required this.approxBytes,
    this.storageFreePct,
    this.maxSessionsOnBridge,
    this.minFreePct,
    this.onMaxSessions,
    this.hardwareReason = '',
    this.onClear,
    this.onOpenCooks,
    this.shareAvailable = false,
    this.busy = false,
    super.key,
  });

  /// Counted from drift, so these three are facts even with no bridge in the
  /// world. Zero here genuinely means zero.
  final int sessions;
  final int samples;

  /// Rounded to whole megabytes on screen — a byte count implies a precision
  /// SQLite's page allocation does not give us.
  final int approxBytes;

  /// From `/status`. Null until it answers.
  final int? storageFreePct;

  /// The bridge's retention limit, from `GET /config/device`. Null until it
  /// answers, or for good on a lane that cannot read it.
  final int? maxSessionsOnBridge;

  /// The share of storage the bridge refuses to fill, so a running cook always
  /// has somewhere to go.
  final int? minFreePct;

  final ValueChanged<int>? onMaxSessions;

  /// Why the bridge's own retention cannot be set on this lane, or `''`.
  final String hardwareReason;

  final Future<void> Function()? onClear;

  /// Opens the cook list, where a single cook can be exported with its marks
  /// and notes. Export lives there because a CSV of "everything" is not a
  /// thing anybody wants.
  final VoidCallback? onOpenCooks;

  /// Whether this platform has a share sheet. False names the file path
  /// instead of offering a button that cannot work.
  final bool shareAvailable;
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

  /// Hours of cooking, at the nominal 30 s cadence. The number people actually
  /// recognise: "62 hours" means something, "7,440 samples" does not.
  static String _hours(int samples) {
    final h = samples * 30 / 3600;
    if (h < 1) {
      return '${(h * 60).round()} min';
    }
    return '${h.toStringAsFixed(h < 10 ? 1 : 0)} h';
  }

  bool get _empty => sessions == 0 && samples == 0;

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-data'),
    children: [
      const SettingsSectionLabel('Kept on this phone'),
      SettingsGroup(
        footer: const Text(
          'Cooks are copied off the bridge as soon as this phone can reach it, '
          'over Bluetooth or Wi-Fi, and then kept here until you clear them. '
          'Nothing expires on its own.',
          key: Key('storage-explainer'),
        ),
        children: [
          SettingsRow(
            key: const Key('storage-sessions'),
            label: 'Cooks kept',
            subtitle:
                'Including ones the bridge has since deleted to make room',
            value: '$sessions',
          ),
          SettingsRow(
            key: const Key('storage-samples'),
            label: 'Recorded time',
            subtitle: '$samples readings',
            value: _hours(samples),
          ),
          SettingsRow(
            key: const Key('storage-size'),
            label: 'Space used',
            value: _size(approxBytes),
          ),
        ],
      ),
      const SettingsSectionLabel('Getting it out'),
      SettingsGroup(
        footer: Text(
          shareAvailable
              ? 'A cook exports as a CSV — one row per reading, with your marks '
                    'and the wall-clock time — and goes straight to the share '
                    'sheet.'
              : 'A cook exports as a CSV. This phone has no share sheet, so the '
                    'app names the file it wrote instead.',
        ),
        children: [
          SettingsActionRow(
            key: const Key('data-export'),
            label: 'Export a cook',
            subtitle:
                'Open the cook you want and use Export. Works with the bridge '
                'unplugged — it reads this phone’s copy.',
            buttonLabel: 'Open cooks',
            onPressed: onOpenCooks,
          ),
        ],
      ),
      const SettingsSectionLabel('Kept on the bridge'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const Key('data-bridge-free'),
            label: 'Space left on the bridge',
            subtitle: 'When it runs out, the oldest readings are dropped first',
            value: storageFreePct == null ? null : '$storageFreePct%',
          ),
          SettingsChoiceRow<int>(
            key: const Key('data-bridge-retention'),
            label: 'Cooks kept on the bridge',
            subtitle: minFreePct == null
                ? 'Once it reaches this many, the oldest cook is deleted to '
                      'make room for a new one'
                : 'Once it reaches this many, the oldest cook is deleted. It '
                      'also keeps $minFreePct% of its storage free so a running '
                      'cook always has somewhere to go.',
            options: const [
              ChipOption(16, '16'),
              ChipOption(32, '32'),
              ChipOption(64, '64'),
              ChipOption(128, '128'),
            ],
            value: maxSessionsOnBridge,
            reportsValue: true,
            valueLabel: maxSessionsOnBridge == null
                ? null
                : '$maxSessionsOnBridge',
            reason: hardwareReason,
            onChanged: onMaxSessions,
          ),
          const SettingsRow(
            key: Key('data-bridge-wipe'),
            label: 'Clear the bridge’s recordings',
            subtitle: 'Erase what it holds without touching this phone’s copy',
            reason:
                'The bridge has no “erase recordings only” command. A factory '
                'reset under Power and sleep erases them along with everything '
                'else.',
          ),
        ],
      ),
      const SettingsSectionLabel('Erase'),
      SettingsGroup(
        children: [
          SettingsActionRow(
            key: const Key('storage-clear'),
            label: 'Clear the cooks on this phone',
            subtitle: _empty
                ? 'Nothing is stored on this phone yet'
                : 'Removes every cook from this phone. The bridge keeps '
                      'whatever it still holds.',
            buttonLabel: busy ? 'Clearing…' : 'Clear',
            danger: true,
            reason: _empty
                ? 'There is nothing stored on this phone to clear.'
                : '',
            onPressed: (busy || onClear == null)
                ? null
                : () async {
                    final ok = await showCostSheet(
                      context,
                      title: 'Clear the cooks on this phone?',
                      body:
                          'This removes $sessions '
                          '${sessions == 1 ? 'cook' : 'cooks'} and '
                          '${_hours(samples)} of readings from this phone. It '
                          'cannot be undone.',
                      keeps:
                          'whatever the bridge still holds — it is copied back '
                          'the next time this phone reaches it.',
                      loses:
                          'every cook the bridge has already deleted to make '
                          'room. Those exist nowhere else.',
                      confirmLabel: 'Clear this phone',
                      cancelLabel: 'Keep them',
                    );
                    if (ok) {
                      await onClear!();
                    }
                  },
          ),
        ],
      ),
    ],
  );
}
