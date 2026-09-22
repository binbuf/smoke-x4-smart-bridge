/// N15.9/N15.10 — the drift-backed [SampleCache].
///
/// This is the production cache the N15.11 sync engine and the N15.8
/// repository run on; [InMemorySampleCache] stays for tests and the UX lab.
/// Everything above the seam is unchanged, which is the point of the seam.
///
/// The two rules that matter:
///
///  * **I10** — `upsertSamples` is `insertOrIgnore` keyed `(bridge, session, t)`.
///    Re-syncing a range is a no-op and the first recorded value wins.
///  * **I11** — `unixMs` is stored exactly as the sample carried it. A bridge
///    with no clock stores NULL, never a fabricated epoch.
library;

import 'package:drift/drift.dart';

import '../../domain/domain.dart';
import '../transport/bridge_transport.dart';
import '../transport/sample_cache.dart';
import 'app_database.dart';

/// A [SampleCache] over an [AppDatabase]. Mirrors [InMemorySampleCache]
/// exactly — including clearing only connectivity gaps fully inside a filled
/// range (permanent rollover holes are never cleared).
class DriftSampleCache implements SampleCache {
  DriftSampleCache(this.db);

  final AppDatabase db;

  @override
  Future<void> upsertSamples(
    String bridgeId,
    int sessionId,
    Iterable<Sample> samples,
  ) async {
    final list = samples.toList(growable: false);
    if (list.isEmpty) {
      return;
    }
    await db.batch((b) {
      for (final s in list) {
        b.insert(
          db.samples,
          SamplesCompanion.insert(
            bridgeId: bridgeId,
            sessionId: sessionId,
            t: s.t,
            p1: Value(s.tempsF10.isNotEmpty ? s.tempsF10[0] : null),
            p2: Value(s.tempsF10.length > 1 ? s.tempsF10[1] : null),
            p3: Value(s.tempsF10.length > 2 ? s.tempsF10[2] : null),
            p4: Value(s.tempsF10.length > 3 ? s.tempsF10[3] : null),
            flags: Value(_flagsOf(s)),
            rssi: Value(s.rssi),
            unixMs: Value(s.unixMs),
          ),
          // Never rewrite (I10): the first recorded value is the truth.
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  @override
  Future<int> sampleCount(String bridgeId, int sessionId) async {
    final count = db.samples.t.count();
    final q = db.selectOnly(db.samples)
      ..addColumns([count])
      ..where(_sessionWhere(bridgeId, sessionId));
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<int?> minT(String bridgeId, int sessionId) async {
    final min = db.samples.t.min();
    return _readAggregate(min, bridgeId, sessionId);
  }

  @override
  Future<int?> maxT(String bridgeId, int sessionId) async {
    final max = db.samples.t.max();
    return _readAggregate(max, bridgeId, sessionId);
  }

  Future<int?> _readAggregate(
    Expression<int> expr,
    String bridgeId,
    int sessionId,
  ) async {
    final q = db.selectOnly(db.samples)
      ..addColumns([expr])
      ..where(_sessionWhere(bridgeId, sessionId));
    final row = await q.getSingleOrNull();
    return row?.read(expr);
  }

  @override
  Future<List<Sample>> samples(
    String bridgeId,
    int sessionId, {
    int? fromT,
    int? toT,
  }) async {
    final q = db.select(db.samples)
      ..where((s) => _sessionWhere(bridgeId, sessionId, s));
    if (fromT != null) {
      q.where((s) => s.t.isBiggerOrEqualValue(fromT));
    }
    if (toT != null) {
      q.where((s) => s.t.isSmallerOrEqualValue(toT));
    }
    q.orderBy([(s) => OrderingTerm.asc(s.t)]);
    final rows = await q.get();
    return rows.map(sampleFromRow).toList();
  }

  @override
  Future<void> recordGap(
    String bridgeId,
    int sessionId,
    RecordedGap gap,
  ) async {
    await db
        .into(db.gaps)
        .insert(
          GapsCompanion.insert(
            bridgeId: bridgeId,
            sessionId: sessionId,
            fromT: gap.fromT,
            toT: gap.toT,
            reason: gap.reason.index,
            detectedUnixMs: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<List<RecordedGap>> gaps(String bridgeId, int sessionId) async {
    final q = db.select(db.gaps)
      ..where((g) => _gapWhere(bridgeId, sessionId, g))
      ..orderBy([(g) => OrderingTerm.asc(g.fromT)]);
    final rows = await q.get();
    return [
      for (final g in rows)
        RecordedGap(
          fromT: g.fromT,
          toT: g.toT,
          reason: g.reason >= 0 && g.reason < GapReason.values.length
              ? GapReason.values[g.reason]
              : GapReason.connectivity,
        ),
    ];
  }

  @override
  Future<void> clearConnectivityGapsBetween(
    String bridgeId,
    int sessionId, {
    required int fromT,
    required int toT,
  }) async {
    // A filled range clears only *recoverable* holes fully inside it (N15.11):
    // a `bufferRollover` gap is data nobody will ever have again.
    await (db.delete(db.gaps)..where(
          (g) =>
              _gapWhere(bridgeId, sessionId, g) &
              g.reason.equals(GapReason.connectivity.index) &
              g.fromT.isBiggerOrEqualValue(fromT) &
              g.toT.isSmallerOrEqualValue(toT),
        ))
        .go();
  }

  @override
  Future<SyncState?> syncState(String bridgeId, int sessionId) async {
    final row =
        await (db.select(db.syncStates)..where(
              (s) =>
                  s.bridgeId.equals(bridgeId) & s.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return SyncState(
      highWaterT: row.highWaterT,
      deviceMinT: row.deviceMinT,
      deviceMaxT: row.deviceMaxT,
      lastSyncMs: row.lastSyncUnixMs ?? 0,
    );
  }

  @override
  Future<void> writeSyncState(
    String bridgeId,
    int sessionId,
    SyncState state,
  ) async {
    await db
        .into(db.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            bridgeId: bridgeId,
            sessionId: sessionId,
            highWaterT: Value(state.highWaterT),
            deviceMinT: Value(state.deviceMinT),
            deviceMaxT: Value(state.deviceMaxT),
            lastSyncUnixMs: Value(state.lastSyncMs),
          ),
        );
  }

  @override
  Future<void> clear() async {
    await db.transaction(() async {
      await db.delete(db.samples).go();
      await db.delete(db.gaps).go();
      await db.delete(db.syncStates).go();
    });
  }

  // ── session / mark persistence (the cache's other half) ────────────────

  /// Upsert-only: a session the device has purged stays in the cache, because
  /// the app owns a full copy of every cook it has *seen*.
  Future<void> upsertSessions(
    String bridgeId,
    Iterable<SessionInfo> remote,
  ) async {
    await db.batch((b) {
      for (final s in remote) {
        b.insert(
          db.sessions,
          SessionsCompanion.insert(
            bridgeId: bridgeId,
            sessionId: s.id,
            name: Value(s.name),
            startedUnixMs: Value(s.startedUnixMs),
            endedUnixMs: Value(s.endedUnixMs),
            samplePeriodS: Value(s.samplePeriodS),
            sampleCount: Value(s.sampleCount),
            numProbes: Value(s.numProbes),
            closed: Value(s.closed),
            pinned: Value(s.pinned),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Replace the marks of one session. Marks are app-visible metadata, not
  /// samples: rewriting them touches no recording (N15.12).
  Future<void> replaceMarks(
    String bridgeId,
    int sessionId,
    Iterable<Mark> marks,
  ) async {
    await db.transaction(() async {
      await (db.delete(db.marks)..where(
            (m) => m.bridgeId.equals(bridgeId) & m.sessionId.equals(sessionId),
          ))
          .go();
      await db.batch((b) {
        for (final m in marks) {
          b.insert(
            db.marks,
            MarksCompanion.insert(
              bridgeId: bridgeId,
              sessionId: sessionId,
              t: m.t,
              kind: m.kind.index,
              probe: Value(m.probe),
              text_: Value(m.text),
            ),
          );
        }
      });
    });
  }

  // ── where-clause helpers ───────────────────────────────────────────────

  Expression<bool> _sessionWhere(
    String bridgeId,
    int sessionId, [
    Samples? table,
  ]) {
    final s = table ?? db.samples;
    return s.bridgeId.equals(bridgeId) & s.sessionId.equals(sessionId);
  }

  Expression<bool> _gapWhere(String bridgeId, int sessionId, Gaps g) =>
      g.bridgeId.equals(bridgeId) & g.sessionId.equals(sessionId);
}

int _flagsOf(Sample s) =>
    (s.billows ? 0x10 : 0) |
    (s.newAlarm ? 0x20 : 0) |
    (s.sourceCelsius ? 0x40 : 0);
