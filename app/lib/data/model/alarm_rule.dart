/// N2.23 — the alarm-rule catalogue record.
///
/// The rules themselves are data (`fixtures_data.dart`); the two tiers are the
/// contract: **device** rules are authoritative mirrors of the Smoke X4, **app**
/// rules are labelled "Insight" and never override the device (I2).
library;

import 'alarm.dart';

/// One alarm rule: tier, severity, scope and any debounce window.
class AlarmRule {
  const AlarmRule({
    required this.id,
    required this.tier,
    required this.name,
    required this.desc,
    required this.severity,
    this.enabled = true,
    required this.scope,
    this.windowS,
  });

  final String id;
  final AlarmTier tier;
  final String name;
  final String desc;
  final AlarmSeverity severity;
  final bool enabled;
  final AlarmScope scope;

  /// The debounce/hold window in seconds, or null when not applicable.
  final int? windowS;
}
