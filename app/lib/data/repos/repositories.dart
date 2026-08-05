/// Cache-first repositories (A4.4 — design 08 §8.3, §8.5).
///
/// Reads come from drift; the transport is only a refresh source. Every
/// screen renders offline — scrolling an 18-hour cook on the couch with
/// the bridge unplugged is the acceptance test, literally.
library;

import '../../domain/entities/entities.dart';
import '../local/database.dart' show AppDatabase, CacheStats, SampleSummary;
import '../transport/bridge_transport.dart';
import 'sync_engine.dart';

class SessionRepository {
  SessionRepository(this.db, {required this.bridgeId});

  final AppDatabase db;
  final String bridgeId;

  Future<List<CookSession>> sessions() => db.sessionDao.allSessions(bridgeId);

  Stream<List<CookSession>> watchSessions() =>
      db.sessionDao.watchSessions(bridgeId);

  /// Chart reads: drift only, never the network.
  Future<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int toT = 0x7fffffff,
  }) => db.sampleDao.range(bridgeId, sessionId, fromT: fromT, toT: toT);

  Future<List<Mark>> marks(int sessionId) =>
      db.markDao.forSession(bridgeId, sessionId);

  /// A11.2 — the sessions list's row data, aggregated in SQL. Deliberately
  /// **not** built from [samples]: see the DAO's comment.
  Future<Map<int, SampleSummary>> summaries() =>
      db.sampleDao.summaries(bridgeId);

  Future<List<({int t, double f})>> sparkline(int sessionId) =>
      db.sampleDao.sparkline(bridgeId, sessionId);

  /// A29 — the cache's size, and the two ways out of it.
  Future<CacheStats> cacheStats() => db.cacheStats();

  /// Wipes every cached cook. The bridge's own copy is untouched — a later
  /// sync refills whatever it still holds, which is the difference between
  /// clearing a cache and deleting data.
  Future<void> clearCache() => db.clearCachedCooks();

  Future<void> deleteSession(int sessionId) =>
      db.deleteCachedSession(bridgeId, sessionId);
}

class BridgeRepository {
  BridgeRepository(this.db, this.transport);

  final AppDatabase db;
  final BridgeTransport transport;

  /// Live status is inherently online; callers degrade gracefully when it
  /// throws (the cache still serves everything historical).
  Future<BridgeStatus> status() => transport.status();

  /// Pulls the delta into the cache and reports what moved.
  Future<SyncReport> refresh() => SyncEngine(db, transport).sync();
}
