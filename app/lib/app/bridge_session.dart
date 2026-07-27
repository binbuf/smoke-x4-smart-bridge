/// A9.6 — the live session controller: the one object the dashboard,
/// the sessions screens and settings all read from.
///
/// It owns the reconciliation loop and nothing else. Everything it calls
/// already exists and is tested: [SyncEngine] pulls the delta,
/// [SessionRepository] serves the cache, the transport's `events` stream
/// pushes live samples, and [buildDashboard] turns all of it into one
/// immutable snapshot. **No widget subscribes to more than one thing** —
/// which is the entire reason this class is here rather than in a
/// `build()` method.
library;

import 'dart:async';

import '../data/local/database.dart';
import '../data/repos/repositories.dart';
import '../data/repos/sync_engine.dart';
import '../data/transport/bridge_transport.dart';
import '../domain/entities/entities.dart';
import '../features/dashboard/dashboard_snapshot.dart';

class BridgeSession {
  BridgeSession({
    required this.db,
    required this.transport,
    required this.link,
    this.address = '',
    this.onLinkLost,
    this.ownsTransport = true,
  });

  final AppDatabase db;

  /// The active transport, link kind, and address. Mutable because a
  /// [ConnectionSupervisor] swaps them live (Wi-Fi drops → BLE standby;
  /// Wi-Fi returns → back) through [switchTransport] — callers and the
  /// backstop poll read them and follow the swap transparently. Assign only
  /// via [switchTransport], which also rebinds the push stream.
  BridgeTransport transport;
  LinkKind link;
  String address;

  /// Called when the active transport's push stream fails *and a follow-up
  /// status read confirms the bridge is unreachable* — the signal the
  /// [ConnectionSupervisor] needs to swap to a warm BLE standby (05 §5.7,
  /// the A6.7 fix). Null in the legacy routes and tests, where a failed push
  /// just falls back to the 10 s poll exactly as before.
  final void Function()? onLinkLost;

  /// Whether [dispose] closes the active transport. The legacy routes own
  /// their transport (true); under the supervisor the transports outlive the
  /// session and the supervisor closes them (false), so a swapped-out link
  /// is never yanked from under the standby.
  final bool ownsTransport;

  /// Backstop poll cadence. The Smoke X base transmits every ~30 s, so this is
  /// deliberately NOT an attempt to read temperatures faster than they change —
  /// it catches a **missed** live push (a dropped BLE notify or a WS hiccup) so
  /// the screen never lags the bridge's latest reading by more than this, and it
  /// makes a reconnect show the current value promptly instead of waiting out a
  /// full base cycle.
  static const Duration _pollEvery = Duration(seconds: 10);

  final _snapshots = StreamController<DashboardSnapshot>.broadcast();
  StreamSubscription<BridgeEvent>? _events;
  Timer? _poll;

  String _bridgeId = '';
  BridgeStatus? _status;
  LiveState? _live;
  List<Sample> _history = const [];
  List<Mark> _marks = const [];
  CookSession? _session;
  DashboardSnapshot? _last;

  /// 'ap'/'sta' from the last `net` push, so the header chip can name the
  /// Wi-Fi mode. Null until the first net frame; the snapshot then infers it
  /// from the address.
  String? _netMode;

  /// Guards against a storm of push-stream errors each firing its own status
  /// probe (or its own failover): one link check runs at a time.
  bool _checkingLink = false;

  Stream<DashboardSnapshot> get snapshots => _snapshots.stream;
  DashboardSnapshot? get snapshot => _last;
  String get bridgeId => _bridgeId;

  SessionRepository? get sessions =>
      _bridgeId.isEmpty ? null : SessionRepository(db, bridgeId: _bridgeId);

  /// Connect → status → delta sync → cache read → subscribe. The order is
  /// §8.5's, and each step is allowed to fail without taking the screen
  /// with it: a failed refresh still leaves a dashboard rendered from the
  /// cache, which is the whole promise of cache-first.
  Future<void> start() async {
    try {
      _status = await transport.status();
      _bridgeId = _status!.deviceId;
    } on Object {
      // Offline, or a transport that cannot answer. The cache below still
      // has everything it had last time.
    }
    if (_bridgeId.isEmpty) {
      final known = await db.sessionDao.knownBridgeId();
      _bridgeId = known ?? '';
    }

    if (transport.capabilities.fullHistory) {
      try {
        await SyncEngine(db, transport).sync();
      } on Object {
        // A partial sync is still progress: everything already written
        // stays, and the next run's cursor starts after it (A4.3).
      }
    }

    try {
      _live = await transport.live(window: const Duration(hours: 2));
    } on Object {
      _live = null;
    }

    await _reloadCache();
    _emit();

    _events = transport.events.listen(
      _onEvent,
      onError: _onEventsError,
      cancelOnError: false,
    );

    // The backstop poll (see [_pollEvery]). Push is still the primary path;
    // this only fills gaps and keeps the reading current.
    _poll = Timer.periodic(_pollEvery, (_) => unawaited(_pollLive()));
  }

  /// The push stream failed. This is deliberately NOT an immediate failover:
  /// a hit WebSocket cap (`BridgeStreamBusy`) leaves REST working, and even an
  /// unexpected close is often a transient hiccup the 10 s poll rides out. So
  /// we verify with a single status read — if the bridge still answers, the
  /// push just stumbled and we re-subscribe; if it does not, that is the A6.7
  /// case and the supervisor swaps to the warm BLE standby. Verifying by
  /// behaviour, not by exception type, keeps this transport-agnostic.
  void _onEventsError(Object error) {
    unawaited(_verifyLinkOrFailover());
  }

  Future<void> _verifyLinkOrFailover() async {
    if (onLinkLost == null || _checkingLink) {
      // Legacy/tests: no supervisor to fail over to — the poll recovers, as
      // it always did when this error was simply swallowed.
      return;
    }
    _checkingLink = true;
    try {
      await transport.status();
      // Still reachable — resume live notifications rather than lean on the
      // poll forever.
      await _resubscribeEvents();
    } on Object {
      onLinkLost!.call();
    } finally {
      _checkingLink = false;
    }
  }

  Future<void> _resubscribeEvents() async {
    await _events?.cancel();
    _events = transport.events.listen(
      _onEvent,
      onError: _onEventsError,
      cancelOnError: false,
    );
  }

  /// Swap the active transport live without dropping the screen (05 §5.7).
  /// The old transport is **never closed here** — the supervisor owns every
  /// transport's lifecycle and keeps a swapped-out BLE link warm as the
  /// standby. Refresh mirrors [start]'s order; a status read that throws
  /// means the *new* link is already dead, so it routes to [onLinkLost] for
  /// the supervisor to try the next option instead of the screen erroring.
  Future<void> switchTransport(
    BridgeTransport t, {
    required LinkKind link,
    String address = '',
    bool closeOld = false,
  }) async {
    final old = transport;
    // Cancel the old subscription FIRST, so closing `old` below cannot deliver
    // a spurious error to a live listener (the failover-loop trap).
    await _events?.cancel();
    _events = null;
    transport = t;
    this.link = link;
    this.address = address;
    // The supervisor owns lifecycle and normally keeps the swapped-out link as
    // a warm standby, so the default is to NOT close it. It closes only when
    // the supervisor says the old link is being discarded (a failover to a
    // dead Wi-Fi link, or a user-chosen switch away from it) via [closeOld].
    if (closeOld && !identical(old, t)) {
      unawaited(old.close().catchError((Object _) {}));
    }

    try {
      _status = await t.status();
    } on Object {
      onLinkLost?.call();
      return; // do not bind a dead transport
    }
    if ((_status?.deviceId ?? '').isNotEmpty) {
      _bridgeId = _status!.deviceId;
    }

    if (t.capabilities.fullHistory) {
      try {
        await SyncEngine(db, t).sync();
      } on Object {
        // A partial sync is progress (A4.3); the next run resumes.
      }
    }
    try {
      _live = await t.live(window: const Duration(hours: 2));
    } on Object {
      _live = null;
    }
    await _reloadCache();

    _events = t.events.listen(
      _onEvent,
      onError: _onEventsError,
      cancelOnError: false,
    );
    _emit();
  }

  /// Reads the bridge's current live state and emits only when it carries a
  /// newer sample than the one already on screen — so a poll that finds nothing
  /// new costs a read and no rebuild. A failed poll is not fatal: the next push
  /// or poll recovers.
  Future<void> _pollLive() async {
    try {
      final live = await transport.live(window: const Duration(hours: 2));
      if (_live == null || live.t > _live!.t) {
        _live = live;
        _emit();
      }
    } on Object {
      // Transient: the bridge is momentarily unreachable, or a read timed out.
    }
  }

  Future<void> _reloadCache() async {
    if (_bridgeId.isEmpty) {
      return;
    }
    final repo = SessionRepository(db, bridgeId: _bridgeId);
    final all = await repo.sessions();
    _session = _status?.activeSessionId != null
        ? all.where((s) => s.id == _status!.activeSessionId).firstOrNull
        : all.firstOrNull;
    final id = _session?.id;
    if (id != null) {
      _history = await repo.samples(id);
      _marks = await repo.marks(id);
    }
  }

  void _onEvent(BridgeEvent e) {
    switch (e) {
      case BridgeSampleEvent(:final sample):
        // Straight into the cache: history must survive the app being
        // swiped away (09 §9.6), and the chart reads drift, not this
        // list. The in-memory copy is only so the next frame is instant.
        final id = _session?.id ?? _status?.activeSessionId;
        if (id != null && _bridgeId.isNotEmpty) {
          unawaited(db.sampleDao.insertSamples(_bridgeId, id, [sample]));
        }
        if (_history.isEmpty || sample.t > _history.last.t) {
          _history = [..._history, sample];
        }
        _live = (_live ?? const LiveState(t: 0, tempsF10: [])).copyWith(
          t: sample.t,
          tempsF10: sample.tempsF10,
        );
        _emit();
      case BridgeAlarmEvent():
      case BridgeSessionEvent():
      case BridgePairingEvent():
        // The device owns alarm and session state (09 §9.1), so the app
        // re-asks rather than deciding for itself.
        unawaited(refreshStatus());
      case BridgeNetEvent(:final mode):
        // The bridge changed Wi-Fi mode (AP↔STA, or fell back to hosting).
        // Stash it so the header chip names the mode rather than inferring
        // it from the address.
        if (mode != _netMode) {
          _netMode = mode;
          _emit();
        }
      case BridgePowerEvent():
      case BridgeOtaEvent():
        break;
    }
  }

  Future<void> refreshStatus() async {
    try {
      _status = await transport.status();
    } on Object {
      return;
    }
    await _reloadCache();
    _emit();
  }

  void _emit() {
    final snap = buildDashboard(
      status: _status,
      live: _live,
      history: _history,
      link: link,
      marks: _marks,
      address: address,
      netMode: _netMode,
      session: _session,
      fullHistory: transport.capabilities.fullHistory,
    );
    _last = snap;
    if (!_snapshots.isClosed) {
      _snapshots.add(snap);
    }
  }

  Future<void> control(ControlCommand cmd) async {
    await transport.control(cmd);
    await refreshStatus();
  }

  Future<void> dispose() async {
    _poll?.cancel();
    await _events?.cancel();
    await _snapshots.close();
    if (ownsTransport) {
      await transport.close();
    }
  }
}
