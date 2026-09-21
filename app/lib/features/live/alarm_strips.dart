/// N5.1 — the sticky alarm strips on Live.
///
/// Unacknowledged alarms only, **highest severity first, at most three**, each
/// carrying its Device/Insight tier tag and an inline acknowledge. More than one
/// shows the "Acknowledge all" affordance. The strip is dumb: the page supplies
/// the alarms and the callbacks.
library;

import 'package:flutter/material.dart';

import '../../data/model/alarm.dart' as bridge;
import '../../design/design.dart';
import '../../domain/domain.dart';
import 'live_format.dart';

/// The highest-severity unacknowledged alarms, ordered.
List<bridge.Alarm> orderedUnackedAlarms(List<bridge.Alarm> alarms) {
  final unacked = [
    for (final alarm in alarms)
      if (!alarm.acked) alarm,
  ];
  unacked.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return unacked;
}

BannerSeverity _severity(bridge.AlarmSeverity severity) => switch (severity) {
  bridge.AlarmSeverity.critical => BannerSeverity.critical,
  bridge.AlarmSeverity.warning => BannerSeverity.warn,
  bridge.AlarmSeverity.info ||
  bridge.AlarmSeverity.positive => BannerSeverity.info,
};

AlarmTier _tier(bridge.AlarmTier tier) =>
    tier == bridge.AlarmTier.device ? AlarmTier.device : AlarmTier.app;

/// The alarm strip list.
class LiveAlarmStrips extends StatelessWidget {
  const LiveAlarmStrips({
    super.key,
    required this.alarms,
    required this.unit,
    this.onAcknowledge,
    this.onAcknowledgeAll,
    this.onOpen,
  });

  final List<bridge.Alarm> alarms;
  final TempUnit unit;
  final ValueChanged<bridge.Alarm>? onAcknowledge;
  final VoidCallback? onAcknowledgeAll;
  final ValueChanged<bridge.Alarm>? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final ordered = orderedUnackedAlarms(alarms);
    if (ordered.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = ordered.take(3).toList();

    return Column(
      key: const ValueKey<String>('live-alarms'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (ordered.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${ordered.length} active alerts',
                    key: const ValueKey<String>('live-alarm-count'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('live-alarm-ack-all'),
                  onPressed: onAcknowledgeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textHi,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Acknowledge all',
                    style: SmokeText.label.copyWith(color: tokens.textHi),
                  ),
                ),
              ],
            ),
          ),
        for (final alarm in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AlarmBar(
              key: ValueKey<String>('live-alarm-${alarm.id}'),
              title: alarm.rule,
              severity: _severity(alarm.severity),
              tier: _tier(alarm.tier),
              detail: _detail(alarm),
              onTap: onOpen == null ? null : () => onOpen!(alarm),
              onAcknowledge: onAcknowledge == null
                  ? null
                  : () => onAcknowledge!(alarm),
            ),
          ),
      ],
    );
  }

  String? _detail(bridge.Alarm alarm) {
    final parts = <String>[
      if (alarm.detail.isNotEmpty) alarm.detail,
      if (alarm.valueF10 != null)
        '${fmtTemp0(alarm.valueF10, unit)}${unit.suffix}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
