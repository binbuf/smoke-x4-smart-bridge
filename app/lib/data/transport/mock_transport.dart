/// A3.3 — the deterministic fixture-backed transport.
///
/// Backed by a `.smk` fixture (cookgen output or a real capture). Replays
/// the cook through the same [BridgeTransport] surface the HTTP and BLE
/// transports implement, so repository and widget tests run full 18-hour
/// cooks in milliseconds with no network anywhere.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../domain/entities/entities.dart';
import 'bridge_transport.dart';
import 'wire_reader.dart';

class MockTransport implements BridgeTransport {
  MockTransport.fromSmkBytes(
    Uint8List smkBytes, {
    Uint8List? mrkBytes,
    this.replayPeriod = Duration.zero,
  })  : _archive = SmkArchive.parse(smkBytes),
        _marks =
            mrkBytes != null ? marksFromBytes(mrkBytes) : const <Mark>[];

  final SmkArchive _archive;
  final List<Mark> _marks;

  /// Delay between replayed samples on [events]. Zero = as fast as the
  /// event loop drains (deterministic, instant in tests).
  final Duration replayPeriod;

  final List<ControlCommand> controlLog = [];
  final List<BridgeConfig> configureLog = [];
  bool _closed = false;

  List<Mark> get marks => List.unmodifiable(_marks);

  @override
  BridgeCapabilities get capabilities => const BridgeCapabilities(
        liveState: true,
        fullHistory: true,
        historyPreview: true,
        config: true,
        ota: false,
      );

  @override
  Stream<BridgeEvent> get events async* {
    for (final rec in _archive.toSamples()) {
      if (_closed) {
        return;
      }
      if (replayPeriod != Duration.zero) {
        await Future<void>.delayed(replayPeriod);
      }
      yield BridgeEvent.sample(rec);
    }
    yield BridgeEvent.session(
      action: SessionAction.ended,
      sessionId: _archive.header.sessionId,
    );
  }

  @override
  Future<BridgeStatus> status() async {
    final h = _archive.header;
    return BridgeStatus(
      deviceId: h.deviceId,
      model: 'mock',
      fw: '0.0.0-mock',
      uptimeS: _archive.records.isEmpty ? 0 : _archive.records.last.t,
      paired: true,
      numProbes: h.numProbes,
      lastPacketSAgo: 0,
      sessionActive: !h.closed,
      activeSessionId: h.closed ? null : h.sessionId,
      storageFreePct: 91,
      socPct: 71,
      charging: false,
    );
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async {
    final samples = _archive.toSamples();
    if (samples.isEmpty) {
      return const LiveState(t: 0, tempsF10: [null, null, null, null]);
    }
    final last = samples.last;
    final fromT = last.t - window.inSeconds;
    return LiveState(
      t: last.t,
      unixMs: _archive.header.clockValid
          ? _archive.header.startedUnixMs + last.t * 1000
          : null,
      tempsF10: last.tempsF10,
      billows: last.billows,
      recent: [
        for (final s in samples)
          if (s.t > fromT) s,
      ],
    );
  }

  @override
  Future<List<CookSession>> sessions() async => [_archive.toSession()];

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  }) async* {
    if (sessionId != _archive.header.sessionId) {
      throw StateError('session_not_found: $sessionId');
    }
    const batch = 500;
    var pending = <Sample>[];
    for (final s in _archive.toSamples()) {
      if (s.t < fromT || (toT != null && s.t > toT)) {
        continue;
      }
      pending.add(s);
      if (pending.length == batch) {
        yield pending;
        pending = <Sample>[];
      }
    }
    if (pending.isNotEmpty) {
      yield pending;
    }
  }

  @override
  Future<void> control(ControlCommand cmd) async {
    controlLog.add(cmd);
  }

  @override
  Future<void> configure(BridgeConfig cfg) async {
    configureLog.add(cfg);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
