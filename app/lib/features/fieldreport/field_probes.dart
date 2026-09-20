/// The checks the field report runs (newapp §I.2's "integration tests", where
/// they actually have to run — on the phone, against the bridge).
///
/// Each probe is an `async` function returning one [CheckResult]. They are
/// small, independent, and **none of them throws**: a probe that dies takes its
/// own result down to FAIL with the reason, and the run continues. A harness
/// that aborts halfway is a harness that produces half a report from a trip to
/// the smoker nobody wants to repeat.
///
/// Three rules, all inherited from the app they are testing:
///
///  1. **Absent ≠ failed.** A check that could not run is `SKIP` with a reason.
///     "We did not learn this" and "this is broken" call for different next
///     steps, and collapsing them wastes the run.
///  2. **Measure, do not summarise.** Every probe puts its raw numbers in
///     `data`. The desk can re-derive a verdict; it cannot re-derive a number
///     somebody rounded off.
///  3. **Nothing destructive without an explicit opt-in.** Exactly one probe
///     deliberately breaks connectivity (the §E.3 rollback), and it is gated,
///     last, and self-healing by design — which is the property being tested.
library;

import 'dart:async';

import '../../app/app_env.dart';
import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart';
import '../../domain/alarms/alarm_rule.dart';
import '../../domain/alarms/notification_policy.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import 'field_report.dart';

/// Everything a probe is allowed to reach. Injected so the whole battery runs
/// in a widget test against fakes — the harness itself must not be the one
/// untested thing in the build.
class ProbeContext {
  const ProbeContext({
    required this.env,
    this.transport,
    this.now,
    this.deviceInfo = const {},
  });

  final AppEnv env;

  /// The **shared** transport from the shell, or null when nothing is
  /// connected. Every bridge-facing probe skips rather than dialling its own.
  final BridgeTransport? transport;

  final DateTime Function()? now;

  /// Whatever the platform layer could tell us about the phone.
  final Map<String, Object?> deviceInfo;

  DateTime get clock => (now ?? DateTime.now)();
  int get nowMs => clock.millisecondsSinceEpoch;
}

typedef Probe = Future<CheckResult> Function(ProbeContext ctx);

/// Wraps a probe so a throw becomes a FAIL with its reason, and times it.
Future<CheckResult> runProbe(String id, String title, ProbeContext ctx,
    Future<CheckResult> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    final r = await body();
    sw.stop();
    return CheckResult(
      id: r.id.isEmpty ? id : r.id,
      title: r.title.isEmpty ? title : r.title,
      status: r.status,
      detail: r.detail,
      data: r.data,
      elapsedMs: r.elapsedMs ?? sw.elapsedMilliseconds,
    );
  } on Object catch (e) {
    sw.stop();
    return CheckResult.fail(
      id,
      title,
      detail: 'threw: $e',
      elapsedMs: sw.elapsedMilliseconds,
    );
  }
}

// ── 1. The phone ──────────────────────────────────────────────────────

/// Who we are running on. J1 names Samsung, Xiaomi and OnePlus as the OEMs
/// whose background killers behave differently; without the model in the
/// report, a foreground-service failure is unattributable.
Future<CheckResult> probeDevice(ProbeContext ctx) async => CheckResult.info(
  'phone.identity',
  'Phone and OS',
  data: {
    ...ctx.deviceInfo,
    'app version': ctx.env.appVersion,
  },
  detail:
      'Recorded so an OEM-specific failure below is attributable. J1 calls out '
      'Samsung, Xiaomi and OnePlus by name.',
);

/// §G.4 — can this phone wake somebody at all?
Future<CheckResult> probeNotificationPermission(ProbeContext ctx) async {
  final sink = ctx.env.notifications;
  if (sink == null) {
    return const CheckResult.skip(
      'notify.permission',
      'Notifications allowed',
      detail: 'This build has no notification plumbing.',
    );
  }
  final granted = await sink.hasPermission();
  return CheckResult(
    id: 'notify.permission',
    title: 'Notifications allowed',
    status: granted ? CheckStatus.pass : CheckStatus.fail,
    detail: granted
        ? 'The OS will deliver.'
        : 'DENIED — nothing this app posts reaches the user. Every check '
              'below about delivery is meaningless until this is granted.',
  );
}

/// §G.4 — the rung that lights the screen.
Future<CheckResult> probeFullScreenIntent(ProbeContext ctx) async {
  final sink = ctx.env.notifications;
  if (sink == null) {
    return const CheckResult.skip(
      'notify.fullscreen',
      'Full-screen intent',
      detail: 'No notification plumbing in this build.',
    );
  }
  final can = await sink.canUseFullScreenIntent();
  return CheckResult.info(
    'notify.fullscreen',
    'Full-screen intent',
    data: {'reported': can},
    detail:
        'NOTE: flutter_local_notifications 22 exposes no read-only check, so '
        'the app returns the optimistic unknown rather than spending a '
        'permission prompt to render a banner. The AUTHORITATIVE answer is '
        'whether notify.critical below actually lit the screen — please say '
        'in the notes whether it did, with the phone locked and face down.',
  );
}

/// §G.4 — post on the real critical channel. The one thing that cannot be
/// simulated.
Future<CheckResult> probeCriticalNotification(ProbeContext ctx) async {
  final sink = ctx.env.notifications;
  if (sink == null) {
    return const CheckResult.skip(
      'notify.critical',
      'Critical alarm posts',
      detail: 'No notification plumbing in this build.',
    );
  }
  await sink.ensureChannels();
  await sink.post(
    const PendingNotification(
      key: 'field-report-critical',
      channel: NotificationChannel.critical,
      title: 'Field report — critical channel',
      body: 'If this made a noise, the 3 a.m. path works.',
      silent: false,
      // Deliberately rung 2, so this ALSO tests the mechanism that lights the
      // screen rather than only the one that makes a sound.
      fullScreen: true,
      escalation: 2,
    ),
  );
  return const CheckResult.pass(
    'notify.critical',
    'Critical alarm posts',
    detail:
        'Posted with fullScreenIntent. Please record in the notes: did it '
        'make a sound? Did it light a locked screen? Did it appear as a '
        'heads-up banner?',
  );
}

/// §G.5 — the ladder, evaluated against this phone's real clock.
Future<CheckResult> probeEscalationLadder(ProbeContext ctx) async {
  final now = ctx.clock;
  final rungs = <String, Object?>{
    'fresh': escalationRung(now, now.millisecondsSinceEpoch),
    'after ${kEscalateToRepeat.inMinutes}m': escalationRung(
      now,
      now.subtract(kEscalateToRepeat).millisecondsSinceEpoch,
    ),
    'after ${kEscalateToFullScreen.inMinutes}m': escalationRung(
      now,
      now.subtract(kEscalateToFullScreen).millisecondsSinceEpoch,
    ),
  };
  final ok = rungs['fresh'] == 0 &&
      rungs['after ${kEscalateToRepeat.inMinutes}m'] == 1 &&
      rungs['after ${kEscalateToFullScreen.inMinutes}m'] == 2;
  return CheckResult(
    id: 'notify.escalation',
    title: 'Escalation ladder',
    status: ok ? CheckStatus.pass : CheckStatus.fail,
    data: rungs,
    detail: ok
        ? 'Climbs 0 → 1 → 2 against the device clock.'
        : 'The ladder did not climb — check the device clock and time zone.',
  );
}

/// §G.4/J1 — the service that has to survive fourteen hours.
Future<CheckResult> probeForegroundService(ProbeContext ctx) async {
  final host = ctx.env.foregroundService;
  if (host == null) {
    return const CheckResult.skip(
      'fgs.start',
      'Foreground service starts',
      detail: 'No foreground-service plumbing in this build.',
    );
  }
  final wasRunning = host.running;
  try {
    if (!wasRunning) {
      await host.start();
    }
    final running = host.running;
    return CheckResult(
      id: 'fgs.start',
      title: 'Foreground service starts',
      status: running ? CheckStatus.pass : CheckStatus.fail,
      data: {'was already running': wasRunning, 'running now': running},
      detail: running
          ? 'Started as connectedDevice. Android 15 caps dataSync at 6 h per '
                '24 and then calls onTimeout(); connectedDevice has no such '
                'cap. If this build had the wrong type the start would have '
                'thrown on Android 14+, not merely warned.'
          : 'It did not start. On Android 14+ a missing or wrong '
                'foregroundServiceType is a crash, so a silent false here '
                'points at the OEM rather than the manifest.',
    );
  } finally {
    if (!wasRunning) {
      await host.stop();
    }
  }
}

/// §G.4 — battery exemption, the difference between 3 a.m. and breakfast.
Future<CheckResult> probeBatteryExemption(ProbeContext ctx) async {
  final host = ctx.env.foregroundService;
  if (host == null) {
    return const CheckResult.skip(
      'fgs.battery',
      'Battery optimisation exemption',
      detail: 'No foreground-service plumbing in this build.',
    );
  }
  final exempt = await host.isIgnoringBatteryOptimizations();
  return CheckResult.info(
    'fgs.battery',
    'Battery optimisation exemption',
    data: {'exempt': exempt},
    detail: exempt
        ? 'Exempt — the monitor should survive Doze.'
        : 'NOT exempt. This is a caveat rather than a failure: the app still '
              'catches up when reopened, because the DEVICE never stopped '
              'recording. It is the difference between woken at 3 a.m. and '
              'told at 7.',
  );
}

// ── 2. The link ───────────────────────────────────────────────────────

/// Which lane won, and what it can do.
Future<CheckResult> probeTransport(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t == null) {
    return const CheckResult.skip(
      'link.transport',
      'Active transport',
      detail:
          'Nothing connected. Every bridge-facing check below will skip — run '
          'this again next to the bridge.',
    );
  }
  final caps = t.capabilities;
  return CheckResult.info(
    'link.transport',
    'Active transport',
    data: {
      'lane': t is BleTransport ? 'Bluetooth' : 'Wi-Fi',
      'live state': caps.liveState,
      'history preview': caps.historyPreview,
      'full history': caps.fullHistory,
      'config': caps.config,
      'ota': caps.ota,
      'mqtt': caps.mqtt,
    },
    detail: t is BleTransport
        ? 'On Bluetooth. `full history` above is read from the device caps '
              'bit, not declared — if it is false against a v1.1 bridge, '
              '§E.6 has a problem.'
        : 'On Wi-Fi.',
  );
}

/// The status read, and everything the device says about itself.
Future<CheckResult> probeStatus(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t == null) {
    return const CheckResult.skip('link.status', 'GET /status');
  }
  final sw = Stopwatch()..start();
  final s = await t.status();
  sw.stop();
  return CheckResult.pass(
    'link.status',
    'GET /status',
    elapsedMs: sw.elapsedMilliseconds,
    data: {
      'device id': s.deviceId,
      'firmware': s.fw,
      'model': s.model,
      'uptime s': s.uptimeS,
      'paired': s.paired,
      'probes': s.numProbes,
      'last packet s ago': s.lastPacketSAgo,
      'base lost': s.baseLost,
      'session active': s.sessionActive,
      'active session': s.activeSessionId,
      'storage free %': s.storageFreePct,
      // Absent ≠ zero: a bridge that cannot measure a battery says nothing.
      'battery %': s.socPct,
      'charging': s.charging,
      'alarms raised': s.alarms.length,
    },
  );
}

/// §E.6 / J2 — what BLE actually achieves. The profiling the spec asks for
/// before trusting full history over Bluetooth.
Future<CheckResult> probeBleHistoryThroughput(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t is! BleTransport) {
    return const CheckResult.skip(
      'ble.history',
      'BLE full-history throughput',
      detail:
          'Not on Bluetooth. Re-run this report on the BLE lane — §E.6 and J2 '
          'both hang on this number, and Wi-Fi cannot answer it.',
    );
  }
  if (!t.capabilities.fullHistory) {
    return const CheckResult.skip(
      'ble.history',
      'BLE full-history throughput',
      detail:
          'This bridge does not advertise the §5.10 history characteristic '
          '(caps b6). Nothing to measure.',
    );
  }
  final sessions = await t.sessions();
  if (sessions.isEmpty) {
    return const CheckResult.skip(
      'ble.history',
      'BLE full-history throughput',
      detail: 'No cooks on the bridge to fetch.',
    );
  }
  // The longest one: a short cook proves nothing about a 15-hour transfer.
  final target = sessions.reduce(
    (a, b) => b.sampleCount > a.sampleCount ? b : a,
  );
  final sw = Stopwatch()..start();
  var samples = 0;
  var batches = 0;
  await for (final batch in t.samples(target.id)) {
    samples += batch.length;
    batches++;
  }
  sw.stop();
  final seconds = sw.elapsedMilliseconds / 1000;
  // ~6 bytes a sample packed, per §E.6's own arithmetic.
  final approxBytes = samples * 6;
  return CheckResult.info(
    'ble.history',
    'BLE full-history throughput',
    elapsedMs: sw.elapsedMilliseconds,
    data: {
      'session': target.id,
      'samples fetched': samples,
      'header claimed': target.sampleCount,
      'batches': batches,
      'seconds': seconds.toStringAsFixed(1),
      'approx bytes': approxBytes,
      'bytes/sec': seconds > 0 ? (approxBytes / seconds).round() : null,
      'samples/sec': seconds > 0 ? (samples / seconds).round() : null,
    },
    detail:
        '§E.6 estimates a 15 h × 4-probe cook at ~7,200 samples ≈ 43 KB, and '
        'predicts "seconds to a couple of minutes". Compare. A shortfall '
        'against `header claimed` means the transfer did not complete, which '
        'is J2 rather than a slow link.',
  );
}

// ── 3. The write-then-verify contracts ────────────────────────────────

/// §G.3 — the mapping onto the firmware's twelve global tunables was
/// **inferred from reading C**. This is the probe that proves it.
Future<CheckResult> probeAlarmRuleReadBack(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t == null) {
    return const CheckResult.skip('rules.readback', 'Alarm rule read-back');
  }
  if (!t.capabilities.config) {
    return const CheckResult.skip(
      'rules.readback',
      'Alarm rule read-back',
      detail: 'This lane cannot write config — expected on Bluetooth.',
    );
  }
  final before = await t.alarmConfig();
  // Toggle a rule that cannot hurt anything if it sticks, and put it back.
  final rule = AlarmRuleSpec(
    id: 0,
    bridgeId: '',
    tier: AlarmTier.device,
    type: AlarmRuleType.storageFull,
    enabled: false,
  );
  final patch = rule.toDeviceJson()!;
  await t.setAlarmConfig(patch);
  final after = await t.alarmConfig();
  final matched = rule.matchesReadBack(after);
  // Restore whatever it was, whatever happened.
  await t.setAlarmConfig(
    rule.copyWith(enabled: _enabledIn(before, 'storage_low') ?? true)
        .toDeviceJson()!,
  );
  final restored = await t.alarmConfig();

  return CheckResult(
    id: 'rules.readback',
    title: 'Alarm rule read-back',
    status: matched ? CheckStatus.pass : CheckStatus.fail,
    data: {
      'sent': patch,
      'rules echoed': (after['rules'] as List?)?.length,
      'storage_low before': _enabledIn(before, 'storage_low'),
      'storage_low after write': _enabledIn(after, 'storage_low'),
      'storage_low restored': _enabledIn(restored, 'storage_low'),
      'tunable keys the device reports': after.keys
          .where((k) => k != 'rules')
          .toList(),
    },
    detail: matched
        ? 'The device took the write and echoed it. The rule→tunable mapping '
              'is correct.'
        : 'MISMATCH. The app writes a rules array plus global tunables '
              '(pit_band_f10, pit_crash_sustain_s, battery_warn_pct, '
              'storage_free_pct, base_lost_s) inferred from app_api_core.c. '
              'The `tunable keys` list above is what the device ACTUALLY '
              'reports — send it back and the mapping can be corrected.',
  );
}

bool? _enabledIn(Map<String, Object?> config, String rule) {
  final rules = config['rules'];
  if (rules is! List) {
    return null;
  }
  for (final r in rules) {
    if (r is Map && r['rule'] == rule) {
      return r['enabled'] == true;
    }
  }
  return null;
}

/// §F — the settings write that used to silently no-op.
Future<CheckResult> probeProbeConfigReadBack(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t == null) {
    return const CheckResult.skip('config.readback', 'Probe config read-back');
  }
  if (!t.capabilities.config || t is BleTransport) {
    return const CheckResult.skip(
      'config.readback',
      'Probe config read-back',
      detail:
          'Probe names/roles are HTTP-only in v1. On Bluetooth the settings '
          'row is disabled with that reason, which is the correct behaviour '
          'and not a failure.',
    );
  }
  final live = await t.live();
  final existing = live.probes.where((p) => p.n == 1).firstOrNull;
  if (existing == null) {
    return const CheckResult.skip(
      'config.readback',
      'Probe config read-back',
      detail: 'The device reported no probe 1 to write to.',
    );
  }
  const marker = 'FieldReport';
  await t.configure(
    BridgeConfig(probes: [existing.copyWith(name: marker)]),
  );
  final after = await t.live();
  final echoed = after.probes.where((p) => p.n == 1).firstOrNull;
  final took = echoed?.name == marker;
  // Put the name back whatever happened.
  await t.configure(BridgeConfig(probes: [existing]));
  final restored = (await t.live()).probes.where((p) => p.n == 1).firstOrNull;

  return CheckResult(
    id: 'config.readback',
    title: 'Probe config read-back',
    status: took ? CheckStatus.pass : CheckStatus.fail,
    data: {
      'original name': existing.name,
      'wrote': marker,
      'device echoed': echoed?.name,
      'restored to': restored?.name,
    },
    detail: took
        ? 'Write reached the device and came back. The §F silent-no-op is gone.'
        : 'The device did NOT echo the write. Either it refused silently or '
              'the shared transport is not reaching it.',
  );
}

/// §C.1 — the Mark button, end to end.
Future<CheckResult> probeMarkWrite(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t == null) {
    return const CheckResult.skip('mark.write', 'Mark reaches the device');
  }
  await t.control(
    const ControlCommand.mark(kind: MarkKind.note, text: 'Field report'),
  );
  return const CheckResult.pass(
    'mark.write',
    'Mark reaches the device',
    detail:
        'Accepted. It should now be on the chart and in the cook’s mark '
        'timeline — please confirm in the notes, since acceptance is not '
        'the same as storage.',
  );
}

// ── 4. The cache and the data model ───────────────────────────────────

/// Schema v2 on the real on-device database, including whether the migration
/// left anything unprojected.
Future<CheckResult> probeSchema(ProbeContext ctx) async {
  final db = ctx.env.db;
  final version = await db
      .customSelect('PRAGMA user_version')
      .getSingle()
      .then((r) => r.data.values.first);
  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  final samples = await count('SELECT COUNT(*) AS n FROM samples');
  final nullClock = await count(
    'SELECT COUNT(*) AS n FROM samples WHERE unix_ms IS NULL',
  );
  return CheckResult(
    id: 'db.schema',
    title: 'Drift schema v2',
    status: version == 2 ? CheckStatus.pass : CheckStatus.fail,
    data: {
      'user_version': version,
      'bridges': await count('SELECT COUNT(*) AS n FROM bridges'),
      'sessions': await count('SELECT COUNT(*) AS n FROM sessions'),
      'samples': samples,
      'samples with no wall clock': nullClock,
      'cooks': await count('SELECT COUNT(*) AS n FROM cooks'),
      'cook probe roles': await count(
        'SELECT COUNT(*) AS n FROM cook_probe_roles',
      ),
      'alarm rules': await count('SELECT COUNT(*) AS n FROM alarm_rules'),
      'gaps': await count('SELECT COUNT(*) AS n FROM gaps'),
      'sync states': await count('SELECT COUNT(*) AS n FROM sync_states'),
      'marks': await count('SELECT COUNT(*) AS n FROM marks'),
    },
    detail: version == 2
        ? 'Migrated. `samples with no wall clock` is expected to be non-zero '
              'ONLY if the bridge has ever run without its RTC set — those '
              'rows are reachable through their cook’s anchor session, never '
              'through a time range.'
        : 'Schema is not v2. The v1→v2 migration did not run.',
  );
}

/// §E.5 — what the sync actually knows, and what it has recorded as lost.
Future<CheckResult> probeSyncState(ProbeContext ctx) async {
  final db = ctx.env.db;
  final bridgeId = await db.sessionDao.knownBridgeId();
  if (bridgeId == null) {
    return const CheckResult.skip(
      'sync.state',
      'Sync high-water marks',
      detail: 'No bridge in the cache yet.',
    );
  }
  final sessions = await db.sessionDao.allSessions(bridgeId);
  final marks = <String, Object?>{};
  final permanent = <String>[];
  for (final s in sessions.take(6)) {
    final sync = await db.syncStateDao.forSession(bridgeId, s.id);
    if (sync != null) {
      marks['cook ${s.id}'] =
          'synced to ${sync.highWaterT}s; device holds '
          '${sync.deviceMinT ?? '?'}–${sync.deviceMaxT ?? '?'}s';
    }
    for (final g in await db.syncStateDao.forBridgeSession(bridgeId, s.id)) {
      if (g.reason.isPermanent) {
        permanent.add('cook ${s.id}: ${g.durationS}s');
      }
    }
  }
  return CheckResult.info(
    'sync.state',
    'Sync high-water marks',
    data: {
      ...marks,
      'permanent (rollover) gaps': permanent.isEmpty ? null : permanent,
    },
    detail:
        'A rollover gap is data nobody has any more. If one appears here on a '
        'bridge that has never been left unattended, the detection is too '
        'eager and §E.5 needs revisiting.',
  );
}

/// §H.2's open decision 3 — the profiling spike, on a real dataset.
Future<CheckResult> probeChartDecimation(ProbeContext ctx) async {
  final db = ctx.env.db;
  final bridgeId = await db.sessionDao.knownBridgeId();
  if (bridgeId == null) {
    return const CheckResult.skip('chart.decimate', 'Chart build on real data');
  }
  final summaries = await db.sampleDao.summaries(bridgeId);
  if (summaries.isEmpty) {
    return const CheckResult.skip(
      'chart.decimate',
      'Chart build on real data',
      detail: 'No cached cooks to draw.',
    );
  }
  final biggest = summaries.values.reduce((a, b) => b.count > a.count ? b : a);
  final loadSw = Stopwatch()..start();
  final samples = await db.sampleDao.range(bridgeId, biggest.sessionId);
  loadSw.stop();
  final buildSw = Stopwatch()..start();
  final model = buildChartSeries(
    samples,
    fromT: biggest.minT,
    toT: biggest.maxT,
  );
  buildSw.stop();
  final points = model.series.fold<int>(0, (a, s) => a + s.points.length);
  return CheckResult.info(
    'chart.decimate',
    'Chart build on real data',
    data: {
      'cook': biggest.sessionId,
      'raw samples': samples.length,
      'hours': (biggest.durationS / 3600).toStringAsFixed(1),
      'db load ms': loadSw.elapsedMilliseconds,
      'series build ms': buildSw.elapsedMilliseconds,
      'points after LTTB': points,
      'gaps drawn': model.gaps.length,
    },
    detail:
        '§H.2 decision 3 (keep fl_chart vs move to a CustomPainter) is meant '
        'to be settled by exactly this measurement on a real 15 h dataset. A '
        'series build inside one 16 ms frame says keep it. `hours` says '
        'whether this dataset is big enough to have decided anything.',
  );
}

// ── 5. The destructive one (§E.3), opt-in and last ────────────────────

/// **This deliberately breaks the Wi-Fi link, and that is the test.**
///
/// It asks the bridge to join a network that does not exist, with a short
/// revert window, and then watches for it to come back on its own. The
/// property under test is precisely that nobody has to walk to the smoker.
///
/// Gated behind an explicit opt-in because a user who ran it by accident on a
/// bridge with no Bluetooth bond would be waiting out the window with no link
/// at all — recoverable, but a bad surprise mid-cook.
Future<CheckResult> probeNetModeRollback(ProbeContext ctx) async {
  final t = ctx.transport;
  if (t == null) {
    return const CheckResult.skip('net.rollback', '§E.3 rollback');
  }
  if (t is BleTransport) {
    return const CheckResult.skip(
      'net.rollback',
      '§E.3 rollback',
      detail:
          'Run this on Wi-Fi. Over Bluetooth the switch would not drop the '
          'link this test is about.',
    );
  }
  const revertS = 30;
  final before = await t.applyNetwork(
    mode: NetworkMode.sta,
    ssid: 'SmokeBridgeFieldReportNoSuchNetwork',
    psk: 'not-a-real-password',
    revertAfterS: revertS,
  );
  // The bridge is now leaving. Wait out the window plus slack, then look.
  await Future<void>.delayed(const Duration(seconds: revertS + 20));
  BridgeStatus? back;
  var attempts = 0;
  for (; attempts < 10; attempts++) {
    try {
      back = await t.status();
      break;
    } on Object {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
  return CheckResult(
    id: 'net.rollback',
    title: '§E.3 rollback',
    status: back != null ? CheckStatus.pass : CheckStatus.fail,
    data: {
      'revert window s': revertS,
      'apply returned': before.isEmpty ? '(no psk)' : before,
      'attempts to re-reach': attempts + 1,
      'came back': back != null,
      'firmware after': back?.fw,
    },
    detail: back != null
        ? 'The bridge left, failed to join a network that does not exist, and '
              'PUT ITSELF BACK. This is the behaviour that used to need a USB '
              'cable, and it has now run on hardware.'
        : 'It did not come back within the window plus slack. Check whether '
              'the bridge is on its hosted AP (192.168.4.1) or still trying '
              'the bad SSID — and whether Bluetooth can still reach it, which '
              'is the escape hatch this design depends on.',
  );
}
