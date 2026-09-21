/// N15.7 — one link's data session.
///
/// Owns `status`, `live`, the session list, marks and the sample stream for a
/// single transport. Start order is **status → sync → live → cache →
/// subscribe** (research notes §7): identity first, then the backfill, then
/// the live edge, and only then the push subscription — so a sample arriving
/// during backfill is not lost or double-written.
///
/// A 10 s backstop poll re-reads `status()`. Link loss is *verified* by that
/// read throwing, never inferred from a timer (a socket flag cannot tell you a
/// bridge rebooted).
library;

import 'dart:async';

import '../../domain/domain.dart';
import 'bridge_transport.dart';
import 'sample_cache.dart';
import 'sync_engine.dart';

class BridgeSessionSnapshot {
  const BridgeSessionSnapshot({
    required this.status,
    required this.live,
    required this.sessions,
    required this.marks,
  });

  final BridgeStatus status;
  final LiveStatus live;
  final List<SessionInfo> sessions;
  final List<Mark> marks;
}

class BridgeSession {
  BridgeSession({
    required this.transport,
    required this.bridgeId,
    required this.cache,
    SyncEngine? syncEngine,
    this.statusPollInterval = const Duration(seconds: 10),
    this.nowMs,
  }) : syncEngine = syncEngine ?? SyncEngine(nowMs: nowMs);

  final BridgeTransport transport;
  final String bridgeId;
  final SampleCache cache;
  final SyncEngine syncEngine;
  final Duration statusPollInterval;
  final int Function()? nowMs;

  BridgeStatus? _status;
  LiveStatus? _live;
  List<SessionInfo> _sessions = const [];
  List<Mark> _marks = const [];

  StreamSubscription<TransportEvent>? _events;
  Timer? _poll;
  bool _stopped = false;

  final List<SyncResult> lastSyncResults = [];

  final StreamController<BridgeSessionSnapshot> _snapshotController =
      StreamController<BridgeSessionSnapshot>.broadcast();
  final StreamController<Sample> _sampleController =
      StreamController<Sample>.broadcast();
  final StreamController<TransportEvent> _eventController =
      StreamController<TransportEvent>.broadcast();
  final StreamController<void> _linkLostController =
      StreamController<void>.broadcast();

  BridgeStatus? get status => _status;
  LiveStatus? get live => _live;
  List<SessionInfo> get sessions => List.unmodifiable(_sessions);
  List<Mark> get marks => List.unmodifiable(_marks);

  Stream<BridgeSessionSnapshot> get updates => _snapshotController.stream;
  Stream<Sample> get samples => _sampleController.stream;
  Stream<TransportEvent> get events => _eventController.stream;

  /// Fires when the backstop poll could not read `status()`.
  Stream<void> get linkLost => _linkLostController.stream;

  /// The current active session id, or null when the bridge is idle/clockless.
  int? get activeSessionId =>
      _status?.session.active == true ? _status!.session.id : null;

  Future<void> start() async {
    _status = await transport.status();
    await _syncSessions();
    _live = await transport.live();
    await _loadMarks();
    _subscribe();
    _emit();
    _startPoll();
  }

  Future<void> _syncSessions() async {
    _sessions = await transport.sessions();
    lastSyncResults.clear();
    for (final session in _sessions) {
      final result = await syncEngine.syncSession(
        transport,
        bridgeId: bridgeId,
        session: session,
        cache: cache,
      );
      lastSyncResults.add(result);
    }
  }

  Future<void> _loadMarks() async {
    final id = activeSessionId;
    if (id == null) {
      _marks = const [];
      return;
    }
    _marks = await transport.marks(id);
  }

  void _subscribe() {
    _events = transport.events().listen(
      (event) {
        if (event.type == 'sample') {
          final sample = event.toSample();
          final id = activeSessionId;
          if (id != null) {
            // Fire-and-forget: the live edge must not stall on SQLite.
            unawaited(cache.upsertSamples(bridgeId, id, [sample]));
          }
          if (!_sampleController.isClosed) {
            _sampleController.add(sample);
          }
        }
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(statusPollInterval, (_) => pollStatus());
  }

  /// Re-read `status()`. On failure, surface link loss. Returns false when the
  /// link is gone.
  Future<bool> pollStatus() async {
    if (_stopped) {
      return false;
    }
    try {
      _status = await transport.status();
      _live = await transport.live();
      _emit();
      return true;
    } catch (_) {
      if (!_linkLostController.isClosed) {
        _linkLostController.add(null);
      }
      return false;
    }
  }

  /// Re-run the backfill on demand (pull-to-refresh / reconnect).
  Future<void> resync() async {
    await _syncSessions();
    _live = await transport.live();
    await _loadMarks();
    _emit();
  }

  void _emit() {
    final status = _status;
    final live = _live;
    if (status == null || live == null || _snapshotController.isClosed) {
      return;
    }
    _snapshotController.add(
      BridgeSessionSnapshot(
        status: status,
        live: live,
        sessions: _sessions,
        marks: _marks,
      ),
    );
  }

  Future<void> stop() async {
    _stopped = true;
    _poll?.cancel();
    await _events?.cancel();
    await _snapshotController.close();
    await _sampleController.close();
    await _eventController.close();
    await _linkLostController.close();
  }
}
