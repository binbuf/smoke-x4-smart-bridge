/// The delta-sync engine (A4.3 — design 08 §8.5).
///
/// On connect: `status()` (firmware gate, active session id), `sessions()`
/// (reconcile), then for each session whose cache is behind, fetch only
/// `from = cachedMaxT + 1` and batch-insert. Reconnecting mid-cook
/// transfers only what was missed; a restart mid-sync resumes without
/// duplicating rows because inserts are keyed on (bridge, session, t) and
/// idempotent.
library;

import '../local/database.dart';
import '../transport/bridge_transport.dart';

class SyncReport {
  const SyncReport({
    required this.bridgeId,
    required this.sessionsSeen,
    required this.sessionsSynced,
    required this.samplesInserted,
  });

  final String bridgeId;
  final int sessionsSeen;
  final int sessionsSynced;
  final int samplesInserted;
}

class SyncEngine {
  SyncEngine(this.db, this.transport);

  final AppDatabase db;
  final BridgeTransport transport;

  Future<SyncReport> sync() async {
    final status = await transport.status();
    final bridgeId = status.deviceId;
    await db.sessionDao.upsertBridge(bridgeId);

    final remote = await transport.sessions();
    await db.sessionDao.upsertSessions(bridgeId, remote);

    var synced = 0;
    var inserted = 0;
    for (final session in remote) {
      final cachedMax = await db.sampleDao.maxT(bridgeId, session.id);
      final cachedCount = await db.sampleDao.count(bridgeId, session.id);
      final upToDate =
          session.closed &&
          cachedCount >= session.sampleCount &&
          session.sampleCount > 0;
      if (upToDate) {
        continue; // a finished, fully-cached cook costs zero bytes
      }
      final fromT = cachedMax == null ? 0 : cachedMax + 1;
      var got = 0;
      await for (final batch in transport.samples(session.id, fromT: fromT)) {
        // Each batch lands in its own transaction: a sync interrupted
        // here keeps everything already written, and the next run's
        // cursor starts after it.
        got += await db.sampleDao.insertSamples(bridgeId, session.id, batch);
      }
      if (got > 0) {
        synced++;
        inserted += got;
      }
    }
    return SyncReport(
      bridgeId: bridgeId,
      sessionsSeen: remote.length,
      sessionsSynced: synced,
      samplesInserted: inserted,
    );
  }
}
