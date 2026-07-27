/// A19.6 — AlarmBar (design 14 §14.7).
///
/// The full-width strip below the status bar, present on **every** tab, that
/// carries the highest-severity unacked alarm — **including device-scope alarms**
/// (`probe == 0`), which the old dashboard filtered out and rendered nowhere.
/// Its `[Acknowledge]` is inline: a 3 a.m. silence must never require a tab
/// change (13 §13.3.3).
///
/// It slides down when raised and fires one `heavyImpact` per alarm id — the
/// alarm demands attention once, not on every rebuild.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/design.dart';
import '../../domain/alarms/notification_policy.dart' show alarmTitle;
import '../../domain/entities/entities.dart';

class AlarmBar extends StatefulWidget {
  const AlarmBar({
    super.key,
    required this.alarm,
    this.onAck,
    this.celsius = false,
  });

  /// The highest-severity unacked alarm, or null when nothing is ringing.
  final Alarm? alarm;
  final VoidCallback? onAck;
  final bool celsius;

  @override
  State<AlarmBar> createState() => _AlarmBarState();
}

class _AlarmBarState extends State<AlarmBar> {
  int? _buzzedFor;

  @override
  void didUpdateWidget(AlarmBar old) {
    super.didUpdateWidget(old);
    final id = widget.alarm?.id;
    if (id != null && id != _buzzedFor) {
      _buzzedFor = id;
      HapticFeedback.heavyImpact();
    }
    if (widget.alarm == null) {
      _buzzedFor = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    final alarm = widget.alarm;
    return AnimatedSize(
      duration: motion.standard,
      curve: motion.curve,
      alignment: Alignment.topCenter,
      child: alarm == null
          ? const SizedBox(width: double.infinity)
          : _bar(context, alarm),
    );
  }

  Widget _bar(BuildContext context, Alarm alarm) {
    final t = context.tokens;
    final role = StatusPalette.roleOf(alarm.severity);
    final hue = StatusPalette.hue(role);
    final where = alarm.probe == 0 ? '' : ' · Probe ${alarm.probe}';
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${alarmTitle(alarm.rule)}$where',
      child: Container(
        width: double.infinity,
        color: StatusPalette.fill(role),
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeTokens.s4,
          vertical: SmokeTokens.s3,
        ),
        child: Row(
          children: [
            Icon(StatusPalette.iconOf(alarm.severity), color: hue, size: 22),
            const SizedBox(width: SmokeTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarmTitle(alarm.rule),
                    style: SmokeType.title.copyWith(color: t.textHi),
                  ),
                  if (where.isNotEmpty)
                    Text(
                      where.trim().replaceFirst('· ', ''),
                      style: SmokeType.bodySm.copyWith(color: t.textBody),
                    ),
                ],
              ),
            ),
            if (widget.onAck != null)
              TextButton(
                onPressed: widget.onAck,
                style: TextButton.styleFrom(
                  foregroundColor: t.textHi,
                  backgroundColor: hue.withValues(alpha: 0.2),
                ),
                child: const Text('Acknowledge'),
              ),
          ],
        ),
      ),
    );
  }
}
