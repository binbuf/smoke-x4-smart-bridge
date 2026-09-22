/// N15.17 — the background cook monitor.
///
/// The loop that survives the screen: while a cook is running it reconciles the
/// bridge's state into notifications, keeps the foreground service alive and
/// surfaces the advisory findings the device tier cannot. Everything it decides
/// is delegated to the pure [planNotifications]; this class owns only the state
/// that decision needs (`alreadyPosted`, the escalation rung) and the
/// [NotificationSink]/[ForegroundServiceHost] lifecycle.
///
/// **Persistence is not this loop's job any more.** `BridgeSession` +
/// `SampleCache` already write every sample into drift (attempts 1–3); the
/// monitor watches `BridgeRepository.snapshot()` and reacts. That keeps it
/// pure Dart — the plugin plumbing stays behind the two seams — so it is
/// host-testable with fakes, exactly like `notification_policy.dart`.
///
/// **The device owns alarm state** (I2). This loop mirrors and acknowledges: an
/// alarm raised while the phone was dead is discovered on reconnect and posted
/// once, not once per poll.
library;

import 'dart:async';

import '../../data/alarms/notification_policy.dart';
import '../../data/model/bridge_snapshot.dart';
import '../../data/model/connection_state.dart';
import '../../data/model/cook_state.dart';
import '../../data/repository/bridge_repository.dart';
import '../../domain/domain.dart';
import '../../platform/notifications.dart';

/// What the loop is allowed to do. The caller owns this (prefs), so toggling
/// monitoring off brings every notification down and stops the service.
class MonitorSettings {
  const MonitorSettings({
    this.monitoringEnabled = true,
    this.quiet = const QuietHours(),
    this.preferManualAlarm = false,
  });

  final bool monitoringEnabled;
  final QuietHours quiet;
  final bool preferManualAlarm;
}

/// N15.17 — watches the repository and drives notifications + the service.
class CookMonitor {
  CookMonitor({
    required this.repository,
    required this.sink,
    required this.service,
    this.settings = const MonitorSettings(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BridgeRepository repository;
  final NotificationSink sink;
  final ForegroundServiceHost service;
  MonitorSettings settings;
  final DateTime Function() _clock;

  StreamSubscription<BridgeSnapshot>? _sub;

  /// Snapshot reconciliation is serialised so two rapid stream events cannot
  /// interleave two `planNotifications` passes over the same state.
  Future<void> _pending = Future<void>.value();

  BridgeSnapshot? _latest;
  final Set<String> _posted = {};

  /// The rung each live notification was last posted at (newapp §G.5), so an
  /// unacknowledged critical alarm climbs the ladder exactly once per rung.
  final Map<String, int> _escalatedTo = {};

  DateTime? _lastConnected;
  DateTime? _lastOngoing;
  bool _ongoingShown = false;
  bool _offeredBatteryOptIn = false;
  bool _stalled = false;
  bool _disposed = false;

  /// Whether the monitor is attached to the repository stream.
  bool get running => _sub != null;

  /// The last snapshot the loop reconciled, for tests and diagnostics.
  BridgeSnapshot? get lastSnapshot => _latest;

  /// Attach to the repository and ask for notification permission. Asked on
  /// the first cook, not at launch: a prompt before the user has seen anything
  /// work is the classic way to get it denied permanently.
  Future<void> start() async {
    await sink.ensureChannels();
    await sink.requestPermission();
    _sub = repository.snapshot().listen(
      handleSnapshot,
      onError: (Object _) {},
      cancelOnError: false,
    );
    handleSnapshot(repository.current);
    await settle();
  }

  /// Feed one snapshot into the loop. Public so a test can drive it with no
  /// stream and no timing assumptions.
  void handleSnapshot(BridgeSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _latest = snapshot;
    _pending = _pending.then((_) => _reconcile(snapshot));
  }

  /// Reconcile the current repository value, then wait for it to land.
  Future<void> refresh() async {
    handleSnapshot(repository.current);
    await settle();
  }

  /// The clock-driven pass: findings whose verdict is time-based (unreachable,
  /// idle service stop) and the 30 s ongoing refresh. The caller owns the
  /// timer; this class owns what happens at each instant.
  Future<void> tick() async {
    _pending = _pending.then((_) async {
      final snapshot = _latest ?? repository.current;
      await _reconcile(snapshot);
      await _applyLifecycle(snapshot);
    });
    await _pending;
  }

  /// Await every queued reconciliation.
  Future<void> settle() => _pending;

  Future<void> setSettings(MonitorSettings next) async {
    settings = next;
    await refresh();
    await tick();
  }

  Future<void> _reconcile(BridgeSnapshot s) async {
    if (_disposed) {
      return;
    }
    if (!settings.monitoringEnabled) {
      // Everything comes down: leaving stale notifications behind would imply
      // monitoring is still running.
      for (final key in _posted.toList()) {
        await sink.cancel(key);
      }
      _posted.clear();
      _escalatedTo.clear();
      await _hideOngoing();
      return;
    }

    final plan = planNotifications(
      alarms: s.alarms,
      alreadyPosted: Set<String>.of(_posted),
      escalatedTo: Map<String, int>.of(_escalatedTo),
      now: _clock(),
      findings: _findings(s),
      quiet: settings.quiet,
      preferManualAlarm: settings.preferManualAlarm,
    );

    for (final n in plan.post) {
      await sink.post(n);
      _posted.add(n.key);
      _escalatedTo[n.key] = n.escalation;
    }
    for (final key in plan.withdraw) {
      await sink.cancel(key);
      _posted.remove(key);
      // Acknowledged or resolved: the ladder resets. The next alarm of the
      // same kind starts at rung 0 rather than lighting the screen.
      _escalatedTo.remove(key);
    }

    await _updateOngoing(s);
  }

  /// The advisory findings `planNotifications` should post in addition to the
  /// alarms the repository already raised. A finding whose rule the snapshot
  /// already carries as an active alarm is skipped — the alarm IS the signal,
  /// and posting both would double-notify the same event.
  List<AppFinding> _findings(BridgeSnapshot s) {
    final out = <AppFinding>[];
    final now = _clock();
    final connected = s.connection.phase == ConnectionPhase.connected;

    if (connected) {
      _lastConnected = now;
    }

    bool hasAlarm(String ruleId) =>
        s.alarms.any((a) => a.ruleId == ruleId && !a.acked);

    if (!connected &&
        s.cook.active &&
        !hasAlarm('bridge_unreachable') &&
        _lastConnected != null &&
        now.difference(_lastConnected!) >= kUnreachableAfter) {
      out.add(AppFinding.bridgeUnreachable);
    }

    final stalled = s.probes.any((p) => p.role == ProbeRole.food && p.stalled);
    if (stalled && !hasAlarm('stall')) {
      out.add(AppFinding.stallStarted);
    } else if (!stalled && _stalled && !hasAlarm('stall')) {
      out.add(AppFinding.stallEnded);
    }
    _stalled = stalled;

    final etaSoon = s.probes.any(
      (p) =>
          p.role == ProbeRole.food &&
          !p.stalled &&
          p.etaMin != null &&
          p.etaMin! <= 30,
    );
    if (etaSoon && !hasAlarm('eta_soon')) {
      out.add(AppFinding.etaSoon);
    }

    return out;
  }

  Future<void> _applyLifecycle(BridgeSnapshot s) async {
    if (_disposed) {
      return;
    }
    final active = s.cook.active;
    if (settings.monitoringEnabled && active) {
      if (!service.running) {
        await service.start();
      }
      if (!_offeredBatteryOptIn) {
        // §9.6: offered after the FIRST cook starts, opt-in; a decline is
        // accepted gracefully.
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

  /// §9.5's live readout, built from the SAME snapshot the dashboard renders —
  /// two sources of truth is how a notification disagrees with the screen
  /// behind it.
  Future<void> _updateOngoing(BridgeSnapshot s) async {
    if (!s.cook.active) {
      await _hideOngoing();
      return;
    }
    final now = _clock();
    if (_ongoingShown &&
        _lastOngoing != null &&
        now.difference(_lastOngoing!) < kOngoingUpdateEvery) {
      return; // 30 s, not per sample
    }
    _lastOngoing = now;
    _ongoingShown = true;
    await sink.showOngoing(ongoingTitle(s, now), ongoingBody(s));
  }

  Future<void> _hideOngoing() async {
    if (!_ongoingShown) {
      return;
    }
    _ongoingShown = false;
    _lastOngoing = null;
    await sink.hideOngoing();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await _hideOngoing();
    await service.stop();
  }
}

/// ```
/// 🔥 Smoke Bridge · Sunday Brisket & Ribs · 04:12
/// Pit 248.6°F ▼   Brisket 164.2°F
/// ```
String ongoingTitle(BridgeSnapshot s, DateTime now) {
  final name = s.cook.name.isEmpty ? 'Cook' : s.cook.name;
  return 'Smoke Bridge · $name · ${_hhmm(_elapsedS(s, now))}';
}

String ongoingBody(BridgeSnapshot s) {
  final parts = <String>[];
  for (final p in [pitProbe(s), foodProbe(s)]) {
    if (p == null || p.tempF10 == null) {
      continue;
    }
    parts.add('${probeLabel(p)} ${_temp(p.tempF10)}${_trend(p.trendFPerHr)}');
  }
  final line1 = parts.isEmpty ? 'No probes attached' : parts.join('   ');

  final food = foodProbe(s);
  final extras = <String>[];
  if (food?.stalled ?? false) {
    // The ETA is SUPPRESSED during a stall: the reason, not a number the
    // physics does not support.
    extras.add('stalled — ETA unavailable');
  } else if (food?.etaMin != null) {
    extras.add('ETA ${food!.etaMin}m');
  }
  final battery = s.connection.batteryPct;
  if (battery != null) {
    extras.add('$battery%');
  }
  return extras.isEmpty ? line1 : '$line1\n${extras.join(' · ')}';
}

/// The pit probe: the one the user roled `pit`, else none. Absent is null (I3).
ProbeState? pitProbe(BridgeSnapshot s) {
  for (final p in s.probes) {
    if (p.role == ProbeRole.pit && p.tempF10 != null) {
      return p;
    }
  }
  return null;
}

/// The headline food: the first food probe with a reading, else the first
/// attached food probe, else none.
ProbeState? foodProbe(BridgeSnapshot s) {
  for (final p in s.probes) {
    if (p.role == ProbeRole.food && p.tempF10 != null) {
      return p;
    }
  }
  for (final p in s.probes) {
    if (p.role == ProbeRole.food && p.attached) {
      return p;
    }
  }
  return null;
}

String probeLabel(ProbeState p) => p.role.label;

int _elapsedS(BridgeSnapshot s, DateTime now) {
  final start = s.cook.startedAtMs;
  if (start == null) {
    return 0;
  }
  final elapsed = now.millisecondsSinceEpoch - start;
  return elapsed < 0 ? 0 : elapsed ~/ 1000;
}

String _temp(int? f10) =>
    f10 == null ? '—' : '${(f10 / 10).toStringAsFixed(1)}°F';

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
