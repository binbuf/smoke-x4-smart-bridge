/// Runs the field-report battery in order and assembles the report.
///
/// The order is deliberate and is part of the design:
///
///  1. **The phone first.** If notifications are denied, every delivery result
///     below is meaningless, and the reader needs to know that before reading
///     them.
///  2. **The link, then reads, then writes.** A write-verify failure means
///     something different depending on whether the read worked.
///  3. **The destructive check last, and opt-in.** It costs the link for about
///     a minute; nothing after it would be trustworthy anyway.
///
/// Pure over [ProbeContext] and the probe list, so the whole battery runs in a
/// widget test against fakes. The harness must not be the one untested thing
/// in the build — a diagnostic that lies is worse than no diagnostic, because
/// it is believed.
library;

import 'dart:async';

import 'field_probes.dart';
import 'field_report.dart';

/// A named group, so the report reads in the order the checks ran.
class ProbeGroup {
  const ProbeGroup(this.title, this.probes);
  final String title;
  final List<({String id, String title, Probe run})> probes;
}

/// Everything that runs by default. The destructive check is **not** here.
List<ProbeGroup> defaultProbeGroups() => [
  ProbeGroup('The phone', [
    (id: 'phone.identity', title: 'Phone and OS', run: probeDevice),
    (
      id: 'notify.permission',
      title: 'Notifications allowed',
      run: probeNotificationPermission,
    ),
    (
      id: 'notify.fullscreen',
      title: 'Full-screen intent',
      run: probeFullScreenIntent,
    ),
    (
      id: 'notify.critical',
      title: 'Critical alarm posts',
      run: probeCriticalNotification,
    ),
    (
      id: 'notify.escalation',
      title: 'Escalation ladder',
      run: probeEscalationLadder,
    ),
    (
      id: 'fgs.start',
      title: 'Foreground service starts',
      run: probeForegroundService,
    ),
    (
      id: 'fgs.battery',
      title: 'Battery optimisation exemption',
      run: probeBatteryExemption,
    ),
  ]),
  ProbeGroup('The link', [
    (id: 'link.transport', title: 'Active transport', run: probeTransport),
    (id: 'link.status', title: 'GET /status', run: probeStatus),
    (
      id: 'ble.history',
      title: 'BLE full-history throughput',
      run: probeBleHistoryThroughput,
    ),
  ]),
  ProbeGroup('Write, then verify', [
    (
      id: 'config.readback',
      title: 'Probe config read-back',
      run: probeProbeConfigReadBack,
    ),
    (
      id: 'rules.readback',
      title: 'Alarm rule read-back',
      run: probeAlarmRuleReadBack,
    ),
    (id: 'mark.write', title: 'Mark reaches the device', run: probeMarkWrite),
  ]),
  ProbeGroup('The cache', [
    (id: 'db.schema', title: 'Drift schema v2', run: probeSchema),
    (id: 'sync.state', title: 'Sync high-water marks', run: probeSyncState),
    (
      id: 'chart.decimate',
      title: 'Chart build on real data',
      run: probeChartDecimation,
    ),
  ]),
];

/// The opt-in group. Separate because it breaks the link on purpose.
ProbeGroup destructiveProbeGroup() => ProbeGroup(
  'Destructive — §E.3 rollback (opt-in)',
  [
    (id: 'net.rollback', title: '§E.3 rollback', run: probeNetModeRollback),
  ],
);

/// Runs everything, reporting progress as it goes.
///
/// [onProgress] fires after each check with the result, so the screen can show
/// the run happening rather than a spinner over a minute of BLE transfer. A
/// harness that looks hung is a harness somebody force-quits halfway.
Future<FieldReport> runFieldReport(
  ProbeContext ctx, {
  bool includeDestructive = false,
  void Function(CheckResult result, int done, int total)? onProgress,
  List<ProbeGroup>? groups,
}) async {
  final all = [
    ...(groups ?? defaultProbeGroups()),
    if (includeDestructive) destructiveProbeGroup(),
  ];
  final total = all.fold<int>(0, (a, g) => a + g.probes.length);
  final started = ctx.nowMs;
  final sections = <ReportSection>[];
  var done = 0;

  for (final group in all) {
    final results = <CheckResult>[];
    for (final probe in group.probes) {
      final result = await runProbe(
        probe.id,
        probe.title,
        ctx,
        () => probe.run(ctx),
      );
      results.add(result);
      done++;
      onProgress?.call(result, done, total);
    }
    sections.add(ReportSection(group.title, results));
  }

  return FieldReport(
    startedUnixMs: started,
    finishedUnixMs: ctx.nowMs,
    appVersion: ctx.env.appVersion,
    sections: sections,
  );
}
