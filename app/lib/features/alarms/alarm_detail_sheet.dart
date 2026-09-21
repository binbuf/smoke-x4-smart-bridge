/// N11.7/N11.8 — the alarm detail sheet (`?overlay=alarmDetail&id=…`).
///
/// Severity card, fired time and ago, the Device/Insight tag, the "why this
/// fired" rows (rule, trigger, reading, suggestion), and the three actions:
/// Acknowledge, Snooze 10m and View on graph.
///
/// **Acknowledging silences; it does not resolve** (design 09 §9.2): the alarm
/// stays in the list with `acked: true`. A snooze is app-side delivery only; the
/// alarm stays raised, and the device knows nothing about it (I2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model/alarm.dart' as bridge;
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import 'alarms_format.dart';
import 'alarms_sheet.dart';

class AlarmDetailSheetBody extends ConsumerWidget {
  const AlarmDetailSheetBody({super.key, required this.alarmId, this.onDone});

  /// The alarm id from the overlay props. Null shows the gone state.
  final String? alarmId;

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final snapshot = ref.watch(snapshotProvider).value;
    final now = ref.watch(alarmsNowProvider);

    final alarm = alarmId == null
        ? null
        : snapshot?.alarms.where((a) => a.id == alarmId).firstOrNull;

    if (alarm == null) {
      return Column(
        key: const ValueKey<String>('alarm-detail-missing'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CapabilityNotice(
            icon: SmokeGlyph.check,
            message:
                'This alert is no longer active. Acknowledged alarms leave the '
                'list, but the bridge keeps recording either way.',
          ),
          const SizedBox(height: 12),
          SmokeButton(
            key: const ValueKey<String>('alarm-detail-done'),
            label: 'Done',
            onPressed: onDone,
          ),
        ],
      );
    }

    final designTier = alarm.tier == bridge.AlarmTier.device
        ? AlarmTier.device
        : AlarmTier.app;
    final severity = _bannerSeverity(alarm.severity);
    final hue = switch (severity) {
      BannerSeverity.info => tokens.info,
      BannerSeverity.warn => tokens.warning,
      BannerSeverity.critical => tokens.critical,
    };

    return Column(
      key: const ValueKey<String>('alarm-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          key: const ValueKey<String>('alarm-detail-severity'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.statusFill(hue, alpha: 0.10),
            borderRadius: BorderRadius.circular(tokens.radii.control),
            border: Border.all(color: tokens.statusBorder(hue, alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SmokeIcon(
                    _severityGlyph(alarm.severity),
                    size: 22,
                    color: hue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          alarm.rule,
                          key: const ValueKey<String>('alarm-detail-rule'),
                          style: SmokeText.bodyStrong.copyWith(
                            fontSize: 15,
                            color: tokens.textHi,
                          ),
                        ),
                        Text(
                          firedLine(
                            nowMs: now.millisecondsSinceEpoch,
                            atMs: alarm.atMs,
                          ),
                          key: const ValueKey<String>('alarm-detail-fired'),
                          style: SmokeText.labelSm.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TierTag(
                    key: const ValueKey<String>('alarm-detail-tier'),
                    tier: designTier,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                alarm.detail.isEmpty ? '—' : alarm.detail,
                key: const ValueKey<String>('alarm-detail-copy'),
                style: SmokeText.body.copyWith(color: tokens.textBody),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SmokeCard(
          key: const ValueKey<String>('alarm-detail-why'),
          subtle: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Why this fired',
                style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: 6),
              for (final row in whyFiredRows(alarm))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    key: ValueKey<String>(
                      'alarm-detail-why-${_slug(row.label)}',
                    ),
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          row.label,
                          style: SmokeText.labelSm.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          row.value,
                          textAlign: TextAlign.right,
                          style: SmokeText.bodyStrong.copyWith(
                            fontSize: 12.5,
                            color: tokens.textHi,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: PrimaryAction(
                key: const ValueKey<String>('alarm-detail-ack'),
                label: 'Acknowledge',
                icon: SmokeGlyph.check,
                onPressed: () async {
                  await ref.read(bridgeRepositoryProvider).ackAlarm(alarm.id);
                  onDone?.call();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('alarm-detail-snooze'),
                label: 'Snooze 10m',
                icon: SmokeGlyph.clock,
                variant: SmokeButtonVariant.ghost,
                onPressed: () async {
                  await ref
                      .read(bridgeRepositoryProvider)
                      .snoozeAlarm(alarm.id);
                  onDone?.call();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SmokeButton(
          key: const ValueKey<String>('alarm-detail-graph'),
          label: 'View on graph',
          icon: SmokeGlyph.chart,
          variant: SmokeButtonVariant.ghost,
          onPressed: () {
            final scope = ShellScope.maybeOf(context);
            onDone?.call();
            scope?.openScreen(ShellScreen.graph);
          },
        ),
        const SizedBox(height: 6),
        Text(
          alarm.tier == bridge.AlarmTier.device
              ? 'The bridge raised this. Acknowledging silences it — it does '
                    'not resolve it, and the bridge keeps recording either way.'
              : 'This is an app insight. It is advisory and never overrides '
                    'the bridge.',
          key: const ValueKey<String>('alarm-detail-note'),
          style: SmokeText.labelSm.copyWith(
            fontSize: 11,
            color: tokens.textMuted,
          ),
        ),
      ],
    );
  }
}

BannerSeverity _bannerSeverity(bridge.AlarmSeverity severity) =>
    switch (severity) {
      bridge.AlarmSeverity.critical => BannerSeverity.critical,
      bridge.AlarmSeverity.warning => BannerSeverity.warn,
      bridge.AlarmSeverity.info ||
      bridge.AlarmSeverity.positive => BannerSeverity.info,
    };

SmokeGlyph _severityGlyph(bridge.AlarmSeverity severity) => switch (severity) {
  bridge.AlarmSeverity.critical => SmokeGlyph.alertCircle,
  bridge.AlarmSeverity.warning => SmokeGlyph.alertTriangle,
  bridge.AlarmSeverity.info || bridge.AlarmSeverity.positive => SmokeGlyph.info,
};

String _slug(String label) => label.toLowerCase().replaceAll(' ', '-');
