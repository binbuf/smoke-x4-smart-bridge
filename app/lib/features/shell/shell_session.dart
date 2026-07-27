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
import '../../data/transport/ble_transport.dart'
    show BridgeControlException, BridgeUnsupportedException;
import '../../data/transport/bridge_transport.dart';
import '../../data/transport/http_transport.dart' show BridgeApiException;
import '../../features/dashboard/dashboard_snapshot.dart';
import '../../ui/probe/probe_freshness.dart';

/// A26 — why the last pull-to-refresh could not produce a new reading.
///
/// A refresh that fails **must say so**. Leaving the previous number on screen
/// is indistinguishable from a successful refresh that found nothing new, and
/// on this app the difference is "your brisket is at 165 °F" versus "your
/// brisket was at 165 °F an hour ago and the bridge has been off since".
///
/// [notConnected] separates the two failures that need different words and a
/// different action: the bridge was never reached (retry, check power/range)
/// versus it answered and then refused or stalled (wait, try again).
@immutable
class RefreshFailure {
  const RefreshFailure({
    required this.title,
    required this.detail,
    this.notConnected = false,
  });

  final String title;
  final String detail;
  final bool notConnected;
}

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
    if (t != null) {
      // A "not connected" banner over a screen that just reconnected is its
      // own lie — the link coming back retires the last failure.
      _refreshFailure = null;
    }
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

  // ── pull-to-refresh (A26, 13 §13.5.2) ────────────────────────────────

  bool _refreshing = false;
  RefreshFailure? _refreshFailure;

  /// True while a pull is in flight. The [RefreshIndicator] owns its own
  /// spinner; this exists so the banner can say "trying again…" instead of
  /// leaving the previous failure on screen while we work.
  bool get refreshing => _refreshing;

  /// The last pull's failure, or null when the last one worked (or none has
  /// run). Cleared automatically the moment a link comes back — a stale
  /// "not connected" over a live screen is its own lie.
  RefreshFailure? get refreshFailure => _refreshFailure;

  void dismissRefreshFailure() {
    if (_refreshFailure != null) {
      _refreshFailure = null;
      notifyListeners();
    }
  }

  /// The gesture: **get a new value from the unit**, or say why not.
  ///
  /// Disconnected, it is a reconnect first ([ConnectionSupervisor.retryNow] —
  /// both radios, no backoff wait) and only then a read. Connected, it goes
  /// straight to [BridgeSession.refreshNow], whose throw becomes the banner.
  ///
  /// Never throws: the caller is a [RefreshIndicator], whose future ending in
  /// an error would leave the spinner spinning forever.
  Future<void> refresh() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    _refreshFailure = null;
    notifyListeners();
    try {
      await _refreshOnce();
    } on Object catch (e) {
      _refreshFailure = _classify(e);
    } finally {
      _refreshing = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _refreshOnce() async {
    if (_session == null || (_liveLink?.offline ?? true)) {
      final supervisor = _supervisor;
      final up = supervisor == null ? false : await supervisor.retryNow();
      if (!up) {
        _refreshFailure = const RefreshFailure(
          title: 'Not connected',
          detail:
              'Couldn’t reach your bridge. Check it is powered on and in '
              'range — the app keeps trying on its own.',
          notConnected: true,
        );
        return;
      }
      // The link is up but [_handleLink] builds/rebinds the session on its
      // own turn. That path already reads status, history and live, so
      // there is nothing left for this pull to ask for.
      if (_session == null) {
        return;
      }
    }
    try {
      await _session!.refreshNow();
    } on Object catch (e) {
      _refreshFailure = _classify(e);
    }
  }

  /// Failures the user can act on get their own words; everything else gets
  /// one honest sentence rather than a stack trace or an error code.
  RefreshFailure _classify(Object e) => switch (e) {
    BridgeApiException(:final message, :final code) => RefreshFailure(
      title: 'The bridge refused',
      detail: message.isEmpty ? code : message,
    ),
    BridgeControlException(:final detail) => RefreshFailure(
      title: 'The bridge refused',
      detail: detail.isEmpty ? 'It could not answer that right now.' : detail,
    ),
    BridgeUnsupportedException(:final what) => RefreshFailure(
      title: 'Not over Bluetooth',
      detail:
          '$what needs Wi-Fi. Connect the bridge to your network for the '
          'full picture.',
    ),
    TimeoutException() => const RefreshFailure(
      title: 'The bridge didn’t answer',
      detail: 'It is there but slow to reply. Try again in a moment.',
    ),
    _ => const RefreshFailure(
      title: 'Couldn’t refresh',
      detail:
          'The bridge stopped answering. The app keeps trying and reconnects '
          'on its own.',
      notConnected: true,
    ),
  };

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

  bool get holdBleWhenOnWifi => _connection?.prefs.holdBleWhenOnWifi ?? true;

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
