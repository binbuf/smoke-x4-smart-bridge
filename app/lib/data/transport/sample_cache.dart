/// N15.9/N15.10 — the drift-shaped sample cache seam.
///
/// This is the interface the drift schema will implement. A deliberately
/// small in-memory implementation ships now so the sync engine is host-testable
/// and so `BridgeRepository` can run end-to-end before SQLite lands.
///
/// **I10 is the whole point:** `upsertSamples` keys on `(bridgeId, sessionId,
/// t)` and never rewrites an existing row. Re-syncing the same range is a
/// no-op; the first recorded value wins.
library;

import 'dart:collection';
import 'dart:math' as math;

import '../../domain/domain.dart';

/// N15.11 — per-session sync bookkeeping (the drift `SyncStates` row).
class SyncState {
  const SyncState({
    required this.highWaterT,
    required this.deviceMinT,
    required this.deviceMaxT,
    required this.lastSyncMs,
  });

  /// The greatest `t` this phone has cached, or `-1` when it has none.
  final int highWaterT;
  final int? deviceMinT;
  final int? deviceMaxT;
  final int lastSyncMs;
}

/// The cache contract. A drift implementation replaces
/// [InMemorySampleCache] behind this interface; nothing above it changes.
abstract interface class SampleCache {
  /// Idempotent `(bridgeId, sessionId, t)` upsert. Existing rows are kept.
  Future<void> upsertSamples(
    String bridgeId,
    int sessionId,
    Iterable<Sample> samples,
  );

  Future<int> sampleCount(String bridgeId, int sessionId);
  Future<int?> minT(String bridgeId, int sessionId);
  Future<int?> maxT(String bridgeId, int sessionId);

  /// Samples in `t` order, inclusive of [fromT]/[toT] when given.
  Future<List<Sample>> samples(
    String bridgeId,
    int sessionId, {
    int? fromT,
    int? toT,
  });

  /// Record a hole. Permanent (`bufferRollover`) gaps are never cleared;
  /// connectivity gaps are cleared when their range is later filled (N15.11).
  Future<void> recordGap(String bridgeId, int sessionId, RecordedGap gap);
  Future<List<RecordedGap>> gaps(String bridgeId, int sessionId);
  Future<void> clearConnectivityGapsBetween(
    String bridgeId,
    int sessionId, {
    required int fromT,
    required int toT,
  });

  Future<SyncState?> syncState(String bridgeId, int sessionId);
  Future<void> writeSyncState(String bridgeId, int sessionId, SyncState state);

  Future<void> clear();
}

/// The in-memory cache used by tests and the pre-drift build.
class InMemorySampleCache implements SampleCache {
  final Map<String, SplayTreeMap<int, Sample>> _samples = {};
  final Map<String, List<RecordedGap>> _gaps = {};
  final Map<String, SyncState> _states = {};

  String _sampleKey(String bridgeId, int sessionId) => '$bridgeId/$sessionId';

  SplayTreeMap<int, Sample> _rows(String bridgeId, int sessionId) =>
      _samples.putIfAbsent(
        _sampleKey(bridgeId, sessionId),
        () => SplayTreeMap<int, Sample>(),
      );

  @override
  Future<void> upsertSamples(
    String bridgeId,
    int sessionId,
    Iterable<Sample> samples,
  ) async {
    final rows = _rows(bridgeId, sessionId);
    for (final sample in samples) {
      // Never rewrite: the first recorded value is the truth (I10).
      rows.putIfAbsent(sample.t, () => sample);
    }
  }

  @override
  Future<int> sampleCount(String bridgeId, int sessionId) async =>
      _rows(bridgeId, sessionId).length;

  @override
  Future<int?> minT(String bridgeId, int sessionId) async {
    final rows = _rows(bridgeId, sessionId);
    return rows.isEmpty ? null : rows.firstKey();
  }

  @override
  Future<int?> maxT(String bridgeId, int sessionId) async {
    final rows = _rows(bridgeId, sessionId);
    return rows.isEmpty ? null : rows.lastKey();
  }

  @override
  Future<List<Sample>> samples(
    String bridgeId,
    int sessionId, {
    int? fromT,
    int? toT,
  }) async {
    final rows = _rows(bridgeId, sessionId);
    return [
      for (final entry in rows.entries)
        if ((fromT == null || entry.key >= fromT) &&
            (toT == null || entry.key <= toT))
          entry.value,
    ];
  }

  @override
  Future<void> recordGap(
    String bridgeId,
    int sessionId,
    RecordedGap gap,
  ) async {
    final list = _gaps.putIfAbsent(_sampleKey(bridgeId, sessionId), () => []);
    final exists = list.any(
      (g) => g.fromT == gap.fromT && g.toT == gap.toT && g.reason == gap.reason,
    );
    if (!exists) {
      list.add(gap);
      list.sort((a, b) => a.fromT.compareTo(b.fromT));
    }
  }

  @override
  Future<List<RecordedGap>> gaps(String bridgeId, int sessionId) async =>
      List<RecordedGap>.unmodifiable(
        _gaps[_sampleKey(bridgeId, sessionId)] ?? const <RecordedGap>[],
      );

  @override
  Future<void> clearConnectivityGapsBetween(
    String bridgeId,
    int sessionId, {
    required int fromT,
    required int toT,
  }) async {
    final list = _gaps[_sampleKey(bridgeId, sessionId)];
    if (list == null) {
      return;
    }
    // A filled range clears only *recoverable* holes inside it (N15.11, I10):
    // permanence is not negotiable.
    list.removeWhere(
      (g) =>
          g.reason == GapReason.connectivity &&
          g.fromT >= math.min(fromT, g.fromT) &&
          g.toT <= math.max(toT, g.toT) &&
          g.fromT >= fromT &&
          g.toT <= toT,
    );
  }

  @override
  Future<SyncState?> syncState(String bridgeId, int sessionId) async =>
      _states[_sampleKey(bridgeId, sessionId)];

  @override
  Future<void> writeSyncState(
    String bridgeId,
    int sessionId,
    SyncState state,
  ) async {
    _states[_sampleKey(bridgeId, sessionId)] = state;
  }

  @override
  Future<void> clear() async {
    _samples.clear();
    _gaps.clear();
    _states.clear();
  }
}
