/// §F Diagnostics — "replace today's stub with real read-outs".
///
/// This is the page someone opens when they already suspect something is
/// wrong, which makes it the one page where a **wrong fact is worse than no
/// fact**. The stub it replaces had two rows, and one of them was mislabelled:
/// `packets_seen` was actually `numProbes`, the count of probes the base
/// station reports. Somebody debugging a silent cook would have read it as
/// evidence the radio was alive.
///
/// So every row below is measured or absent, and the sections answer the four
/// questions a stuck cook actually raises, in the order they get asked:
///
///  1. *is the phone talking to the bridge?* — the link;
///  2. *is the bridge alive and does it have room?* — the bridge;
///  3. *is the base station still feeding it?* — the radio hop the phone
///     cannot see and the bridge can;
///  4. *does the phone have everything the bridge has?* — the sync high-water
///     marks and the rollover gaps, which are the two numbers that explain a
///     chart with a hole in it.
///
/// This is also the only page in the app where jargon is allowed (16 §16.4
/// rule 3 scopes it here), and even here every number carries a plain-language
/// subtitle saying what it means.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import 'settings_kit.dart';

class DiagnosticsSettingsView extends StatelessWidget {
  const DiagnosticsSettingsView({
    this.lane = SettingsLane.none,
    this.address,
    this.linkDbm,
    this.wifiDbm,
    this.apClients,
    this.ssid = '',
    this.lastProblem = '',
    this.canFullHistory,
    this.canConfigure,
    this.firmware,
    this.model,
    this.deviceId,
    this.uptimeS,
    this.storageFreePct,
    this.socPct,
    this.paired,
    this.probesReported,
    this.lastPacketSAgo,
    this.baseLost,
    this.syncRows = const [],
    this.rolloverLoss = '',
    this.clockUnixMs,
    this.onSetClock,
    this.onFieldReport,
    super.key,
  });

  final SettingsLane lane;
  final String? address;

  /// Phone ↔ bridge, measurable only over Bluetooth.
  final int? linkDbm;

  /// Bridge ↔ router, meaningful only while the bridge is a Wi-Fi client.
  final int? wifiDbm;

  /// Devices joined to the bridge's own network. In hosted mode this is the
  /// only thing the bridge can say about the link, because the signal it would
  /// need to report is the *phone's*, which it cannot see.
  final int? apClients;
  final String ssid;

  /// The last failure, already in the user's words. Never a status code.
  final String lastProblem;

  final bool? canFullHistory;
  final bool? canConfigure;

  final String? firmware;
  final String? model;
  final String? deviceId;
  final int? uptimeS;
  final int? storageFreePct;
  final int? socPct;

  final bool? paired;
  final int? probesReported;
  final int? lastPacketSAgo;
  final bool? baseLost;

  /// `(label, value)` per cook — how far this phone has synced and what extent
  /// the bridge reports holding.
  final List<(String, String)> syncRows;

  /// Time the bridge's buffer rolled past before the phone could copy it.
  /// Permanent, and never papered over.
  final String rolloverLoss;

  /// The bridge's wall clock. Null or implausible means it never learned the
  /// time, and cooks cannot be dated.
  final int? clockUnixMs;
  final VoidCallback? onSetClock;

  /// Opens the one-shot on-device harness. Null hides the row entirely — never
  /// a dead button.
  ///
  /// An "Export the app log" row sat beside this one, permanently disabled
  /// behind "There is nothing logged this session to export." — and it always
  /// would be: there is no log buffer anywhere in the app, and the route never
  /// passed one. A disabled row states a reason somebody could act on; that
  /// one stated a fact about a feature that does not exist. It is gone until
  /// there is a buffer behind it.
  final VoidCallback? onFieldReport;

  /// A clock the device has plainly never set. The epoch, or anything before
  /// this firmware existed, is not a date — it is an unset RTC. Public so the
  /// route can apply the same test to its own read-back.
  static const int plausibleFrom = 1600000000000; // 2020-09-13

  bool get _clockKnown => clockUnixMs != null && clockUnixMs! >= plausibleFrom;

  String? get _signalValue {
    if (linkDbm != null) {
      return '$linkDbm dBm';
    }
    if (wifiDbm != null) {
      return '$wifiDbm dBm';
    }
    if (apClients != null) {
      return '$apClients';
    }
    return null;
  }

  String get _signalSubtitle {
    if (linkDbm != null) {
      return 'Bluetooth, phone to bridge. Closer to zero is stronger.';
    }
    if (wifiDbm != null) {
      return 'Wi-Fi, bridge to your router. The phone’s own signal is a '
          'different hop and is not shown.';
    }
    if (apClients != null) {
      return 'Devices joined to the bridge’s own network. It cannot measure '
          'your phone’s signal from where it sits.';
    }
    return 'Nothing on this link can measure a signal';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SettingsPage(
      key: const Key('settings-advanced'),
      lead:
          'What the app can actually measure. Everything here is read from the '
          'bridge or from this phone — nothing is assumed.',
      children: [
        const SettingsSectionLabel('The link'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('diag-transport'),
              label: 'Connected over',
              subtitle: switch (lane) {
                SettingsLane.none =>
                  'The app keeps trying, on both radios, on its own',
                SettingsLane.bluetooth =>
                  'Fast and close range. Full history, settings and updates '
                      'need Wi-Fi.',
                SettingsLane.wifi => 'Everything is available on this link',
              },
              value: lane.title,
            ),
            SettingsRow(
              key: const Key('diag-address'),
              label: 'Address',
              subtitle: ssid.isEmpty ? '' : 'On the network $ssid',
              value: (address ?? '').isEmpty ? null : address,
            ),
            SettingsRow(
              key: const Key('diag-signal'),
              label: apClients != null ? 'Devices joined' : 'Signal',
              subtitle: _signalSubtitle,
              value: _signalValue,
            ),
            SettingsRow(
              key: const Key('diag-last-problem'),
              label: 'Last problem',
              subtitle: lastProblem.isEmpty
                  ? 'Nothing has gone wrong since the app started'
                  : '',
              value: lastProblem.isEmpty ? 'None' : lastProblem,
            ),
            SettingsRow(
              key: const Key('diag-capabilities'),
              label: 'What this link can do',
              subtitle:
                  'Full history means the whole cook, not the last two hours',
              value: switch ((canFullHistory, canConfigure)) {
                (null, _) => null,
                (true, true) => 'Full history, settings',
                (true, _) => 'Full history',
                (false, true) => 'Settings',
                (false, _) => 'Live readings only',
              },
            ),
          ],
        ),
        const SettingsSectionLabel('The bridge'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('diag-firmware'),
              label: 'Firmware',
              value: (firmware ?? '').isEmpty ? null : firmware,
            ),
            SettingsRow(
              key: const Key('diag-model'),
              label: 'Model',
              value: (model ?? '').isEmpty ? null : model,
            ),
            SettingsRow(
              key: const Key('diag-device-id'),
              label: 'Bridge id',
              value: (deviceId ?? '').isEmpty ? null : deviceId,
            ),
            SettingsRow(
              key: const Key('diag-uptime'),
              label: 'Up for',
              subtitle: 'Since it last restarted',
              value: uptimeS == null ? null : formatDuration(uptimeS!),
            ),
            SettingsRow(
              key: const Key('diag-storage'),
              label: 'Storage free',
              value: storageFreePct == null ? null : '$storageFreePct%',
            ),
            SettingsRow(
              key: const Key('diag-battery'),
              label: 'Battery',
              subtitle: socPct == null
                  ? 'This bridge cannot measure a battery'
                  : '',
              value: socPct == null ? null : '$socPct%',
            ),
          ],
        ),
        const SettingsSectionLabel('The base station'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('diag-paired'),
              label: 'Paired',
              value: switch (paired) {
                null => null,
                true => 'Yes',
                false => 'No',
              },
            ),
            SettingsRow(
              key: const Key('diag-probes-reported'),
              label: 'Probes it reports',
              subtitle: 'How many jacks the base station says are in use',
              value: probesReported == null ? null : '$probesReported',
            ),
            SettingsRow(
              key: const Key('diag-last-packet'),
              label: 'Last reading from it',
              subtitle: baseLost == true
                  ? 'The bridge has stopped hearing the base station'
                  : '',
              value: lastPacketSAgo == null
                  ? null
                  : '${formatDuration(lastPacketSAgo!)} ago',
            ),
          ],
        ),
        const SettingsSectionLabel('Recording and sync'),
        SettingsGroup(
          footer: rolloverLoss.isEmpty
              ? null
              : Text(
                  'Lost to the bridge’s buffer rolling over before this phone '
                  'could copy it: $rolloverLoss. That time is gone — it is '
                  'drawn as a break in the chart rather than smoothed over.',
                  key: const Key('diag-rollover'),
                ),
          children: [
            if (syncRows.isEmpty)
              const SettingsRow(
                key: Key('diag-sync-empty'),
                label: 'Synced so far',
                subtitle:
                    'Nothing has been copied from this bridge yet, so there '
                    'is no high-water mark to report',
              )
            else
              for (final (label, value) in syncRows)
                SettingsRow(label: label, value: value),
          ],
        ),
        const SettingsSectionLabel('Clock'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('diag-clock'),
              label: 'The bridge’s clock',
              subtitle: _clockKnown
                  ? 'Cooks are dated from this'
                  : 'Until it knows the time, cooks are recorded but cannot be '
                        'dated',
              value: _clockKnown ? formatSessionDate(clockUnixMs) : null,
            ),
            SettingsActionRow(
              key: const Key('diag-set-clock'),
              label: 'Set it from this phone',
              subtitle:
                  'Existing readings keep the times they were recorded '
                  'with',
              buttonLabel: 'Set the clock',
              reason: onSetClock == null
                  ? 'The app isn’t connected to your bridge right now.'
                  : '',
              onPressed: onSetClock,
            ),
          ],
        ),
        if (onFieldReport != null) ...[
          const SettingsSectionLabel('This app'),
          SettingsGroup(
            children: [
              SettingsActionRow(
                key: const Key('settings-field-report'),
                label: 'Run the field checks',
                subtitle:
                    'Tests what only a real phone and a real bridge can '
                    'answer, then hands you one log to send back.',
                buttonLabel: 'Run',
                onPressed: onFieldReport,
              ),
            ],
          ),
        ],
        Text(
          'Nothing on this page leaves your phone unless you export it.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
    );
  }
}
