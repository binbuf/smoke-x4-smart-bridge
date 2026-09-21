/// N2.23 — an alarm, and the rule catalogue it comes from.
library;

/// Device alarms are authoritative; app alarms are labelled "Insight".
enum AlarmTier { device, app }

/// Severity, matching the prototype's status channel (never colour alone).
enum AlarmSeverity { critical, warning, info, positive }

/// What an alarm rule is scoped to.
enum AlarmScope { perProbe, pit, cook, device }

/// One raised alarm in a scenario.
class Alarm {
  const Alarm({
    required this.id,
    required this.tier,
    required this.severity,
    required this.rule,
    this.detail = '',
    this.valueF10,
    required this.atMs,
    this.acked = false,
    this.sessionScoped = true,
    required this.ruleId,
    this.trigger = '',
    this.suggestion = '',
    this.snoozedUntilMs,
  });

  final String id;
  final AlarmTier tier;
  final AlarmSeverity severity;
  final String rule;
  final String detail;

  /// The temperature that tripped it, tenths °F, or null.
  final int? valueF10;

  final int atMs;
  final bool acked;
  final bool sessionScoped;
  final String ruleId;
  final String trigger;
  final String suggestion;

  /// N11.8 — app-side notification snooze. A snoozed alarm stays raised and
  /// unacknowledged (it is not resolved); the phone simply stops re-notifying
  /// until this instant. The device knows nothing about it (I2).
  final int? snoozedUntilMs;

  /// Whether the app is currently suppressing the notification for this alarm.
  bool snoozedAt(int nowMs) =>
      snoozedUntilMs != null && snoozedUntilMs! > nowMs;

  Alarm copyWith({bool? acked, int? snoozedUntilMs}) => Alarm(
    id: id,
    tier: tier,
    severity: severity,
    rule: rule,
    detail: detail,
    valueF10: valueF10,
    atMs: atMs,
    acked: acked ?? this.acked,
    sessionScoped: sessionScoped,
    ruleId: ruleId,
    trigger: trigger,
    suggestion: suggestion,
    snoozedUntilMs: snoozedUntilMs ?? this.snoozedUntilMs,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'tier': tier.name,
    'severity': severity.name,
    'rule': rule,
    'detail': detail,
    if (valueF10 != null) 'value_f10': valueF10,
    'at_ms': atMs,
    'acked': acked,
    'session_scoped': sessionScoped,
    'rule_id': ruleId,
    'trigger': trigger,
    'suggestion': suggestion,
    if (snoozedUntilMs != null) 'snoozed_until_ms': snoozedUntilMs,
  };

  static Alarm fromJson(Map<String, Object?> j) => Alarm(
    id: j['id'] as String? ?? '',
    tier: AlarmTier.values.firstWhere(
      (t) => t.name == j['tier'],
      orElse: () => AlarmTier.app,
    ),
    severity: AlarmSeverity.values.firstWhere(
      (s) => s.name == j['severity'],
      orElse: () => AlarmSeverity.info,
    ),
    rule: j['rule'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    valueF10: (j['value_f10'] as num?)?.toInt(),
    atMs: (j['at_ms'] as num?)?.toInt() ?? 0,
    acked: j['acked'] as bool? ?? false,
    sessionScoped: j['session_scoped'] as bool? ?? true,
    ruleId: j['rule_id'] as String? ?? '',
    trigger: j['trigger'] as String? ?? '',
    suggestion: j['suggestion'] as String? ?? '',
    snoozedUntilMs: (j['snoozed_until_ms'] as num?)?.toInt(),
  );
}
