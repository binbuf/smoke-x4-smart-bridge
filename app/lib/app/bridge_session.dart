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
  });

  final AppDatabase db;
  final BridgeTransport transport;
  final LinkKind link;
  final String address;

  final _snapshots = StreamController<DashboardSnapshot>.broadcast();
  StreamSubscription<BridgeEvent>? _events;

  String _bridgeId = '';
  BridgeStatus? _status;
  LiveState? _live;
  List<Sample> _history = const [];
  List<Mark> _marks = const [];
  CookSession? _session;
  DashboardSnapshot? _last;

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
      onError: (Object _) {},
      cancelOnError: false,
    );
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
      case BridgeNetEvent():
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
    await _events?.cancel();
    await _snapshots.close();
    await transport.close();
  }
}
