/// A24.1 — the shell's live session (design 13 §13.3.2-§13.3.3).
///
/// The four tabs share **one** connection and **one** [BridgeSession]: the race
/// runs once at boot, not once per tab, so switching Cook → History → Bridge
/// never re-dials the bridge and every tab reads the same immutable
/// [DashboardSnapshot]. This is the object `dashboard_route.dart` and
/// `cook_preview_route.dart` each stood up privately; the shell hoists it to a
/// single [ChangeNotifier] the whole tree listens to.
///
/// It boots exactly like those routes did (`AppEnv.newConnection().start()` →
/// `BridgeSession`), exposes the latest snapshot, the [LaunchState], a computed
/// [ProbeFreshness] (the freshness ladder lifted verbatim from
/// `cook_preview_route.dart:106`), and a [control] passthrough — including
/// [ackAlarm], so the shared [AlarmBar] can silence the ringing alarm from any
/// tab without a tab change (§13.3.3).
///
/// The `AppEnv`-null path is a first-class outcome, not an error: a bare widget
/// test mounts the shell with no environment, and [start] then no-ops, leaving
/// the shell in its `LaunchConnecting` (or seeded) state rather than throwing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/app_env.dart';
import '../../app/bridge_session.dart';
import '../../app/connection.dart';
import '../../app/connection_supervisor.dart';
import '../../data/transport/bridge_transport.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../../ui/probe/probe_freshness.dart';

class ShellSession extends ChangeNotifier {
  /// The production session: reads the ambient [AppEnv] and boots on [start].
  ShellSession({AppEnv? env}) : _env = env ?? AppEnv.instance;

  /// Test seam: a session that never boots, pre-loaded with a snapshot and a
  /// launch state. `start()` is a no-op, so no radio, socket or database is
  /// touched and the shell renders the seeded truth immediately.
  ShellSession.seeded({
    DashboardSnapshot? snapshot,
    LaunchState launch = const LaunchConnecting(),
  }) : _env = null,
       _booted = true {
    _snapshot = snapshot;
    _launch = launch;
  }

  final AppEnv? _env;

  AppConnection? _connection;
  ConnectionSupervisor? _supervisor;
  BridgeSession? _session;
  StreamSubscription<DashboardSnapshot>? _sub;
  StreamSubscription<LiveLink>? _linkSub;

  LaunchState _launch = const LaunchConnecting();
  DashboardSnapshot? _snapshot;
  LiveLink? _liveLink;
  bool _booted = false;
  bool _disposed = false;

  /// True when nothing was ever remembered — so an all-lanes-fail boot means
  /// "needs onboarding", not "a known bridge is off" (A9.5).
  bool _neverMet = false;

  /// The newest link from the supervisor, applied one-at-a-time so
  /// [BridgeSession.start] finishes before a [BridgeSession.switchTransport]
  /// (a BLE→Wi-Fi upgrade that lands during boot) touches the same streams.
  LiveLink? _pendingLink;
  bool _applyingLink = false;

  LaunchState get launch => _launch;
  DashboardSnapshot? get snapshot => _snapshot;

  /// The supervisor's latest link, for the header chip's live health: which
  /// transport, whether it is degraded (on BLE), and the background-upgrade
  /// retry count. Null before the first link (or with no environment).
  LiveLink? get liveLink => _liveLink;

  /// The active bridge session, or null before it connects. Exposed so a tab
  /// that needs the cache repositories (History's export) can reach them.
  BridgeSession? get bridge => _session;

  /// Freshness from the live packet age (13 §13.6.1), so a stale reading is
  /// visibly stale rather than a frozen number under a green chip. Copied from
  /// `cook_preview_route.dart:106` — the shell now owns the one instance.
  ProbeFreshness get freshness {
    final s = _snapshot;
    if (s == null) {
      return ProbeFreshness.unknown;
    }
    if (s.baseLost) {
      return ProbeFreshness.frozen;
    }
    final age = s.lastPacketSAgo;
    if (age == null) {
      return s.anyAttached ? ProbeFreshness.live : ProbeFreshness.unknown;
    }
    if (age <= 45) return ProbeFreshness.live;
    if (age <= 90) return ProbeFreshness.aging;
    if (age <= 600) return ProbeFreshness.stale;
    return ProbeFreshness.frozen;
  }

  /// Boots the connection supervisor once (05 §5.7): lead with Bluetooth,
  /// upgrade to Wi-Fi, hold BLE as a warm standby, fail over seamlessly. Safe
  /// to call repeatedly (guarded) and safe with no environment (returns,
  /// leaving the current state).
  Future<void> start() async {
    if (_booted) {
      return;
    }
    _booted = true;
    final env = _env;
    if (env == null) {
      return; // not bootstrapped (a bare widget test) — wait, do not throw
    }
    final connection = env.newConnection();
    _connection = connection;
    // A25: "met a bridge" means ANY lane — a Bluetooth-only setup has no base
    // URL, and keying this on the URL alone bounced those users back into
    // onboarding on every launch (the board-found setup loop).
    _neverMet = !connection.prefs.hasBridge;
    final supervisor = ConnectionSupervisor(connection: connection);
    _supervisor = supervisor;
    // Subscribe before starting so no link update is missed.
    _linkSub = supervisor.links.listen(_onLink);
    await supervisor.start();
  }

  /// The supervisor changed the active transport (first connect, a Wi-Fi
  /// upgrade, a failover, or offline). Coalesce to the newest and apply one at
  /// a time.
  void _onLink(LiveLink link) {
    if (_disposed) {
      return;
    }
    _pendingLink = link;
    unawaited(_applyPendingLink());
  }

  Future<void> _applyPendingLink() async {
    if (_applyingLink) {
      return; // a run is in flight; it will pick up [_pendingLink]
    }
    _applyingLink = true;
    try {
      while (!_disposed) {
        final link = _pendingLink;
        if (link == null) {
          break;
        }
        _pendingLink = null;
        await _handleLink(link);
      }
    } finally {
      _applyingLink = false;
    }
  }

  Future<void> _handleLink(LiveLink link) async {
    _liveLink = link;
    final t = link.transport;
    // The supervisor re-emits on every health change — upgrade retries, the
    // attempt counter, degraded/upgrading flips — usually with the SAME
    // transport. Those are chip updates, not switches: rebinding the session
    // (status read + delta sync + cache reload) on every backoff tick would
    // churn the radio and the battery for nothing.
    if (t != null && identical(t, _session?.transport)) {
      _launch = LaunchConnected(
        transport: t,
        link: link.link,
        address: link.address,
      );
      notifyListeners();
      return;
    }
    if (t == null) {
      // Offline — the cache still renders. Onboarding only when nothing was
      // ever remembered and no session was ever built.
      _launch = _neverMet && _session == null
          ? const LaunchNeedsOnboarding()
          : const LaunchOffline();
      notifyListeners();
      return;
    }
    _launch = LaunchConnected(
      transport: t,
      link: link.link,
      address: link.address,
    );
    final existing = _session;
    if (existing == null) {
      final session = BridgeSession(
        db: _env!.db,
        transport: t,
        link: link.link,
        address: link.address,
        // The supervisor owns every transport's lifecycle and holds the BLE
        // standby, so the session must neither close a swapped-out link nor
        // close its transport on dispose.
        onLinkLost: _supervisor!.reportLinkLost,
        ownsTransport: false,
      );
      _session = session;
      _sub = session.snapshots.listen((s) {
        if (_disposed) {
          return;
        }
        _snapshot = s;
        notifyListeners();
      });
      notifyListeners();
      await session.start();
    } else {
      notifyListeners();
      await existing.switchTransport(
        t,
        link: link.link,
        address: link.address,
        closeOld: link.closePrevious,
      );
    }
  }

  /// Passes a control command to the device and refreshes status. A no-op
  /// before the session connects (an offline tab has nothing to command).
  Future<void> control(ControlCommand cmd) async {
    await _session?.control(cmd);
  }

  /// Acknowledge the ringing alarm — the one call the shared [AlarmBar] needs.
  Future<void> ackAlarm(int alarmId) =>
      control(ControlCommand.ackAlarm(alarmId: alarmId));

  /// The connection-sheet controls (05 §5.7). Reads fall back to the defaults
  /// before boot; writes persist the choice and apply the safe, instant part
  /// live through the supervisor.
  PreferredTransport get preferredTransport =>
      _connection?.prefs.preferredTransport ?? PreferredTransport.auto;

  bool get holdBleWhenOnWifi =>
      _connection?.prefs.holdBleWhenOnWifi ?? true;

  Future<void> setPreferredTransport(PreferredTransport t) async {
    await _connection?.prefs.setPreferredTransport(t);
    _supervisor?.applyPreference(t);
    notifyListeners();
  }

  Future<void> setHoldBleWhenOnWifi(bool value) async {
    await _connection?.prefs.setHoldBleWhenOnWifi(value);
    _supervisor?.applyHoldBle(value);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_linkSub?.cancel());
    unawaited(_sub?.cancel());
    // Session first (cancels its event subscriptions), then the supervisor
    // (closes the active + standby transports), then the connection.
    unawaited(_session?.dispose());
    unawaited(_supervisor?.dispose());
    unawaited(_connection?.dispose());
    super.dispose();
  }
}
