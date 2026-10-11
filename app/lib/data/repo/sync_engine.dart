/// The sync engine: one session's high-water-mark delta sync.
///
///  1. `sessions()` (done by the caller).
///  2. Derive the device extent, detect rollover **before** fetching, record a
///     permanent gap if the device's buffer wrapped past the phone.
///  3. Skip a closed, fully-cached session.
///  4. Choose `fromT`: no cache → 0, else `cachedMax + 1`.
///  5. Stream, upsert idempotently, advance the high-water per batch, clear
///     filled connectivity gaps.
///
/// This is what makes a multi-hour resync instant: only the seconds the phone
/// has not yet stored are transferred.
library;

import '../../domain/domain.dart';
import '../ble/bridge_transport.dart';
import '../cache/sample_cache.dart';

class SyncResult {
  const SyncResult({
    required this.fetched,
    required this.inserted,
    required this.skipped,
    this.rollover,
  });

  final int fetched;
  final int inserted;
  final bool skipped;

  /// A permanent `bufferRollover` hole discovered this run, if any.
  final RecordedGap? rollover;
}

class SyncEngine {
  SyncEngine({this.nowMs});

  /// Injectable clock so tests are deterministic.
  final int Function()? nowMs;

  Future<SyncResult> syncSession(
    BridgeTransport transport, {
    required String bridgeId,
    required SessionInfo session,
    required SampleCache cache,
  }) async {
    final cachedMax = await cache.maxT(bridgeId, session.id);
    final deviceMaxT = session.deviceMaxT;
    final before = await cache.sampleCount(bridgeId, session.id);

    // 3. A closed session whose authoritative `sample_count` we already hold
    // is done — no round trip. (The header's wall-clock extent can exceed the
    // last sample's `t`, so the sample count is the honest completeness test.)
    if (session.closed &&
        session.sampleCount > 0 &&
        before >= session.sampleCount) {
      return const SyncResult(fetched: 0, inserted: 0, skipped: true);
    }

    // 4. With no rows we take the whole session; otherwise the next unsynced
    // second.
    final fromT = cachedMax == null ? 0 : cachedMax + 1;

    var fetched = 0;
    int? firstFetchedT;
    int? lastFetchedT;
    int? previousT;
    RecordedGap? rollover;
    final connectivity = <RecordedGap>[];
    final period = session.samplePeriodS < 1 ? 30 : session.samplePeriodS;

    await for (final batch in transport.samples(session.id, fromT: fromT)) {
      if (batch.isEmpty) {
        continue;
      }
      if (firstFetchedT == null) {
        firstFetchedT = batch.first.t;
        // 2. Rollover: the device's earliest row is past our high-water, so the
        // buffer wrapped. Record it BEFORE any upsert.
        rollover = detectRollover(
          highWaterT: cachedMax ?? -1,
          deviceMinT: firstFetchedT,
          deviceMaxT: deviceMaxT,
        );
        if (rollover != null) {
          await cache.recordGap(bridgeId, session.id, rollover);
        }
      }
      for (final sample in batch) {
        if (previousT != null && sample.t - previousT > period * 2.5) {
          connectivity.add(
            RecordedGap(
              fromT: previousT,
              toT: sample.t,
              reason: GapReason.connectivity,
            ),
          );
        }
        previousT = sample.t;
      }
      fetched += batch.length;
      lastFetchedT = batch.last.t;
      await cache.upsertSamples(bridgeId, session.id, batch);
    }

    final after = await cache.sampleCount(bridgeId, session.id);
    if (lastFetchedT != null) {
      // Filled range: drop the recoverable holes we just covered and record
      // the ones this run reveals.
      await cache.clearConnectivityGapsBetween(
        bridgeId,
        session.id,
        fromT: fromT,
        toT: lastFetchedT,
      );
      for (final gap in connectivity) {
        await cache.recordGap(bridgeId, session.id, gap);
      }
      await cache.writeSyncState(
        bridgeId,
        session.id,
        SyncState(
          highWaterT: _max(cachedMax ?? -1, lastFetchedT),
          deviceMinT: firstFetchedT,
          deviceMaxT: deviceMaxT ?? lastFetchedT,
          lastSyncMs: (nowMs ?? _wallClock)(),
        ),
      );
    }

    return SyncResult(
      fetched: fetched,
      inserted: after - before,
      skipped: false,
      rollover: rollover,
    );
  }
}

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

int _max(int a, int b) => a > b ? a : b;
