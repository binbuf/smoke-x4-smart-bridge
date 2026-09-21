/// N11 — the Alerts sheet's pure projections.
///
/// Formatting, filtering and the delivery verdict only: no Flutter, no
/// repository. Kept out of the widgets so the two-tier filters, the derived
/// findings and the verdict can be unit-tested against the fixture numbers.
library;

import '../../data/alarms/notification_policy.dart';
import '../../data/model/alarm.dart';
import '../../data/model/alarm_rule.dart';
import '../../data/model/bridge_snapshot.dart';
import '../../data/model/connection_state.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';

/// The delivery verdict the Alerts sheet shows (N11.3).
class DeliveryVerdict {
  const DeliveryVerdict({
    required this.title,
    required this.detail,
    required this.wake,
  });

  final String title;
  final String detail;

  /// Whether this phone is currently set up to wake the user.
  final bool wake;
}

/// N11.3 — "will this phone wake you?", read from the three preferences.
DeliveryVerdict deliveryVerdict({
  required bool monitoring,
  required bool quietHours,
  required bool preferManualAlarm,
}) {
  if (!monitoring) {
    return const DeliveryVerdict(
      title: 'Background monitoring is off',
      detail:
          'Alarms still appear in the list, but this phone will not be '
          'notified while the app is closed.',
      wake: false,
    );
  }
  final quiet = quietHours
      ? 'Quiet hours 10pm–6am silence warning & info · critical alarms always '
            'sound.'
      : 'Notifications allowed · critical alarms bypass quiet hours.';
  final manual = preferManualAlarm ? ' Your own insights win the sound.' : '';
  return DeliveryVerdict(
    title: 'This phone will wake you',
    detail: '$quiet$manual',
    wake: true,
  );
}

/// The nine authoritative device rules, catalogue order.
List<AlarmRule> deviceRules(List<AlarmRule> rules) => <AlarmRule>[
  for (final r in rules)
    if (r.tier == AlarmTier.device) r,
];

/// The advisory app rules, catalogue order.
List<AlarmRule> appRules(List<AlarmRule> rules) => <AlarmRule>[
  for (final r in rules)
    if (r.tier == AlarmTier.app) r,
];

/// N11.15 — the app-tier findings derivable from a snapshot. Pure and
/// advisory: it never raises a device alarm (I2).
List<AppFinding> deriveFindings(BridgeSnapshot snapshot) {
  final findings = <AppFinding>[];
  final offline = snapshot.connection.phase == ConnectionPhase.offline;
  if (offline) {
    findings.add(
      snapshot.cook.active
          ? AppFinding.bridgeUnreachable
          : AppFinding.phoneOffline,
    );
  }
  final probes = snapshot.probes;
  for (final probe in probes) {
    if (!probe.attached || probe.role != ProbeRole.food) {
      continue;
    }
    if (!probe.freshness.showsDerived) {
      continue;
    }
    final eta = probe.etaMin;
    if (eta != null && eta <= 30 && !findings.contains(AppFinding.etaSoon)) {
      findings.add(AppFinding.etaSoon);
    }
    if (probe.stalled && !findings.contains(AppFinding.stallStarted)) {
      findings.add(AppFinding.stallStarted);
    }
  }
  return findings;
}

/// `Critical` / `Warning` / `Info` / `Ready` — a status word, never colour
/// alone.
String severityWord(AlarmSeverity severity) => switch (severity) {
  AlarmSeverity.critical => 'Critical',
  AlarmSeverity.warning => 'Warning',
  AlarmSeverity.info => 'Info',
  AlarmSeverity.positive => 'Ready',
};

/// `Device` / `Insight` (I2's tag, in words).
String tierWord(AlarmTier tier) =>
    tier == AlarmTier.device ? 'Device' : 'Insight';

/// A short relative time (`just now`, `12 min ago`, `2 h ago`).
String agoWord({required int nowMs, required int atMs}) {
  final delta = nowMs - atMs;
  if (delta < 0) {
    return 'just now';
  }
  final minutes = delta ~/ 60000;
  if (minutes < 1) {
    return 'just now';
  }
  if (minutes < 60) {
    return '$minutes min ago';
  }
  final hours = minutes ~/ 60;
  return '$hours h ago';
}

/// The full fired line: `9:41 AM · 12 min ago`.
String firedLine({required int nowMs, required int atMs}) {
  final clock = fmtClock(DateTime.fromMillisecondsSinceEpoch(atMs));
  return '$clock · ${agoWord(nowMs: nowMs, atMs: atMs)}';
}

/// Whether a rule can be edited (app tier) or only toggled (device tier).
bool ruleIsEditable(AlarmRule rule) => rule.tier == AlarmTier.app;

/// The `why this fired` rows for an alarm. Always includes the rule id; the
/// others are omitted when absent (the prototype's conditional rows).
List<({String label, String value})> whyFiredRows(
  Alarm alarm,
) => <({String label, String value})>[
  (label: 'Rule', value: alarm.ruleId.isEmpty ? alarm.id : alarm.ruleId),
  if (alarm.trigger.trim().isNotEmpty) (label: 'Trigger', value: alarm.trigger),
  if (alarm.valueF10 != null)
    (label: 'Reading', value: '${(alarm.valueF10! / 10).toStringAsFixed(1)}°F'),
  if (alarm.suggestion.trim().isNotEmpty)
    (label: 'Suggestion', value: alarm.suggestion),
];
