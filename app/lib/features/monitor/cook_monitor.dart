/// A13.3–A13.5 — the service isolate's half of design 09 §9.6, as a plain
/// Dart class with everything injected.
///
/// ```
/// ┌────── UI isolate ──────┐        ┌───── service isolate ─────┐
/// │ Riverpod providers     │◄──────►│ BridgeTransport (WS/BLE)  │
/// │ drift (reads)          │  port  │ drift (writes)            │
/// │ charts, screens        │        │ alarm reconciliation      │
/// └────────────────────────┘        │ notification updates      │
///                                   └───────────────────────────┘
/// ```
///
/// Everything this class calls already exists and is tested: `SyncEngine`,
/// the DAOs, the A2 analysis, [buildDashboard], [planNotifications]. It
/// wires them into a loop that survives the UI being gone; it invents no
/// analysis and it decides no alarms.
///
/// **The device owns alarm state.** This loop mirrors and acknowledges
/// (§9.1). An alarm raised while the phone was dead is discovered on
/// reconnect and posted once — not once per poll, and not re-decided.
///
/// The plugin lives behind [ForegroundServiceHost] and [NotificationSink]
/// because `flutter_local_notifications` and `flutter_foreground_task`
/// need platform channels and a second isolate, which `flutter test` has
/// neither of. The host suite proves the decisions; the bench proves the
/// plumbing.
library;

import 'dart:async';

import '../../data/local/database.dart';
import '../../data/repos/repositories.dart';
import '../../data/transport/bridge_transport.dart';
import '../../domain/alarms/notification_policy.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../platform/notifications.dart';
import '../dashboard/dashboard_snapshot.dart';

/// §9.6: "`bridge_unreachable` warning after 3 min".
const Duration kUnreachableAfter = Duration(minutes: 3);

/// §9.5: "The ongoing notification is a live readout, updated every 30 s".
const Duration kOngoingUpdateEvery = Duration(seconds: 30);

/// §9.6: "stops ... 10 min after the last successful connection when no
/// session is active".
const Duration kIdleStopAfter = Duration(minutes: 10);

class MonitorSettings {
  const MonitorSettings({
    this.monitoringEnabled = true,
    this.quiet = const QuietHours(),
  });

  final bool monitoringEnabled;
  final QuietHours quiet;
}

class CookMonitor {
  CookMonitor({
    required this.db,
    required this.transport,
    required this.sink,
    required this.service,
    required this.bridgeId,
    this.settings = const MonitorSettings(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final BridgeTransport transport;
  final NotificationSink sink;
  final ForegroundServiceHost service;
  final String bridgeId;
  MonitorSettings settings;
  final DateTime Function() _clock;

  StreamSubscription<BridgeEvent>? _events;
  BridgeStatus? _status;
  CookSession? _session;
  final List<Sample> _history = [];
  final Set<String> _posted = {};

  DateTime? _lastData;
  DateTime? _lastOngoing;
  DateTime? _lastConnected;
  bool _unreachableNotified = false;
  bool _offeredBatteryOptIn = false;
  bool _stalled = false;

  /// Every sample this loop has written to drift, for the test that says
  /// history survives the app being swiped away.
  int samplesPersisted = 0;

  DashboardSnapshot? _snapshot;
  DashboardSnapshot? get snapshot => _snapshot;
  bool get serviceRunning => service.running;

  Future<void> start() async {
    await sink.ensureChannels();
    // Asked at the moment the first cook starts, not at launch: a
    // permission prompt on first open, before the user has seen anything
    // work, is the classic way to get it denied permanently.
    await sink.requestPermission();
    _events = transport.events.listen(
      _onEvent,
      onError: (Object _) {},
      cancelOnError: false,
    );
    await refresh();
  }

  /// One reconciliation pass: ask the device, mirror what it says.
  Future<void> refresh() async {
    try {
      _status = await transport.status();
      _lastConnected = _clock();
      _lastData ??= _lastConnected;
      if (_unreachableNotified) {
        _unreachableNotified = false;
      }
    } on Object {
      // Offline is a first-class outcome, not an error: everything
      // already cached still renders and the device never stopped
      // recording (04).
      await _applyLifecycle();
      return;
    }
    await _reloadCache();
    await _publish();
  }

  Future<void> _reloadCache() async {
    if (bridgeId.isEmpty) {
      return;
    }
    final repo = SessionRepository(db, bridgeId: bridgeId);
    final all = await repo.sessions();
    final id = _status?.activeSessionId;
    _session = id != null
        ? all.where((s) => s.id == id).firstOrNull
        : all.firstOrNull;
    final sid = _session?.id;
    if (sid != null && _history.isEmpty) {
      _history.addAll(await repo.samples(sid));
    }
  }

  void _onEvent(BridgeEvent e) {
    switch (e) {
      case BridgeSampleEvent(:final sample):
        _lastData = _clock();
        // Straight into drift: history must survive the app being swiped
        // away (§9.6), and the chart reads drift rather than this list.
        final id = _session?.id ?? _status?.activeSessionId;
        if (id != null && bridgeId.isNotEmpty) {
          samplesPersisted++;
          unawaited(db.sampleDao.insertSamples(bridgeId, id, [sample]));
        }
        if (_history.isEmpty || sample.t > _history.last.t) {
          _history.add(sample);
        }
      case BridgeAlarmEvent():
      case BridgeSessionEvent():
        // The device owns both. Re-ask rather than deciding for
        // ourselves — the whole point of §9.1's two tiers.
        unawaited(refresh());
      case BridgePairingEvent():
      case BridgeNetEvent():
      case BridgePowerEvent():
      case BridgeOtaEvent():
        break;
    }
  }

  /// Drive the clock forward. The caller owns the timer; this class owns
  /// what happens at each instant, which is what makes it testable.
  Future<void> tick() async {
    await _publish();
    await _applyLifecycle();
  }

  List<AppFinding> _findings() {
    final out = <AppFinding>[];
    final now = _clock();
    final last = _lastData;
    // §9.3: no data for 3 min while a cook is active. Once, not per
    // retry — a warning that repeats every 30 s is a warning that gets
    // muted.
    if (last != null &&
        now.difference(last) >= kUnreachableAfter &&
        (_status?.sessionActive ?? false)) {
      out.add(AppFinding.bridgeUnreachable);
    }
    final snap = _snapshot;
    if (snap != null) {
      final food = snap.headlineFood;
      if (food != null && food.stalled) {
        out.add(AppFinding.stallStarted);
      } else if (_stalled) {
        out.add(AppFinding.stallEnded);
      }
      _stalled = food?.stalled ?? false;
      final eta = food?.eta;
      // §9.3's "start getting ready". The LOW end of the range is what
      // decides it: an ETA of "25 min – 55 min" means you might need to
      // be ready in 25.
      if (eta is EtaRange && eta.low <= const Duration(minutes: 30)) {
        out.add(AppFinding.etaSoon);
      }
    }
    return out;
  }

  Future<void> _publish() async {
    _snapshot = buildDashboard(
      status: _status,
      live: null,
      history: _history,
      link: LinkKind.http,
      session: _session,
      fullHistory: transport.capabilities.fullHistory,
    );

    final findings = _findings();
    if (findings.contains(AppFinding.bridgeUnreachable)) {
      if (_unreachableNotified) {
        findings.remove(AppFinding.bridgeUnreachable);
      } else {
        _unreachableNotified = true;
      }
    }

    final plan = planNotifications(
      alarms: _status?.alarms ?? const [],
      alreadyPosted: Set<String>.from(_posted),
      now: _clock(),
      findings: findings,
      quiet: settings.quiet,
      monitoringEnabled: settings.monitoringEnabled,
      probeName: (n) =>
          _snapshot!.probes
              .where((p) => p.probe == n)
              .map((p) => p.name)
              .firstOrNull ??
          'Probe $n',
    );
    for (final n in plan.post) {
      await sink.post(n);
      _posted.add(n.key);
    }
    for (final key in plan.withdraw) {
      await sink.cancel(key);
      _posted.remove(key);
    }

    await _updateOngoing();
  }

  /// §9.5's live readout. Built from the SAME projection the dashboard
  /// renders — two sources of truth for "what is the pit doing" is how a
  /// notification ends up disagreeing with the screen behind it.
  Future<void> _updateOngoing() async {
    final snap = _snapshot;
    if (snap == null || !snap.sessionActive || !settings.monitoringEnabled) {
      if (_lastOngoing != null) {
        _lastOngoing = null;
        await sink.hideOngoing();
      }
      return;
    }
    final now = _clock();
    if (_lastOngoing != null &&
        now.difference(_lastOngoing!) < kOngoingUpdateEvery) {
      return; // 30 s, not per sample
    }
    _lastOngoing = now;
    await sink.showOngoing(ongoingTitle(snap), ongoingBody(snap));
  }

  Future<void> _applyLifecycle() async {
    final active = _status?.sessionActive ?? false;
    if (settings.monitoringEnabled && active) {
      if (!service.running) {
        await service.start();
      }
      if (!_offeredBatteryOptIn) {
        // §9.6: offered after the FIRST cook starts, opt-in, and a
        // decline is accepted gracefully — the app degrades to
        // "reconnects and catches up when you open it", which works
        // because sync is delta-based and the device never stopped.
        _offeredBatteryOptIn = true;
        await service.requestIgnoreBatteryOptimizations();
      }
      return;
    }
    if (!settings.monitoringEnabled) {
      await service.stop();
      return;
    }
    final last = _lastConnected;
    if (service.running &&
        last != null &&
        _clock().difference(last) >= kIdleStopAfter) {
      await service.stop();
    }
  }

  Future<void> setSettings(MonitorSettings s) async {
    settings = s;
    await _publish();
    await _applyLifecycle();
  }

  Future<void> dispose() async {
    await _events?.cancel();
    await sink.hideOngoing();
    await service.stop();
  }
}

/// ```
/// 🔥 Smoke Bridge · Brisket · 04:12
/// Pit 243°F ▼   Brisket 163°F ▲
/// ETA 5h45m – 7h00m · stalling
/// ```
String ongoingTitle(DashboardSnapshot s) {
  final name = s.sessionName.isEmpty ? 'Cook' : s.sessionName;
  return 'Smoke Bridge · $name · ${_hhmm(s.elapsedS)}';
}

String ongoingBody(DashboardSnapshot s) {
  final parts = <String>[];
  for (final p in [s.headlinePit, s.headlineFood]) {
    if (p == null) {
      continue;
    }
    parts.add('${p.name} ${_temp(p.tempF10)}${_trend(p.rateFPerHr)}');
  }
  final line1 = parts.isEmpty ? 'No probes attached' : parts.join('   ');

  final food = s.headlineFood;
  final extras = <String>[];
  if (food?.stalled ?? false) {
    // The ETA is SUPPRESSED during a stall (§9.4) — the reason, not a
    // number the physics does not support.
    extras.add('stalled — ETA unavailable');
  } else if (food?.eta case final EtaRange r) {
    // A RANGE, never a single number — the physics does not support that
    // precision, and the false confidence is what makes people trust it
    // and then get burned (§9.4).
    extras.add('ETA ${_dur(r.low)} – ${_dur(r.high)}');
  }
  // Battery only when it exists: a `0%` on a bridge that cannot measure
  // one is a bug report against the hardware (P3.2).
  if (s.batteryKnown && s.socPct != null) {
    extras.add('${s.socPct}%');
  }
  return extras.isEmpty ? line1 : '$line1\n${extras.join(' · ')}';
}

String _temp(int? f10) => f10 == null ? '—' : '${(f10 / 10).round()}°F';

String _trend(double? rate) {
  if (rate == null) {
    return '';
  }
  if (rate > 5) {
    return ' ▲';
  }
  if (rate < -5) {
    return ' ▼';
  }
  return '';
}

String _hhmm(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds ~/ 60) % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String _dur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}m' : '${m}m';
}
