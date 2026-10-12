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
    final period = session.samplePeriodS < 1 ? 30 : session.samplePeriodS;

    // 3. A closed session we have already drained is done — no round trip.
    // This is deliberately independent of `sample_count`: a header's wall-clock
    // extent can sit past its last row, and a ring can report a count it no
    // longer retains, so `before >= sample_count` alone re-fetches such a
    // session forever. The fact is persisted (see [SyncState.complete]).
    if (session.closed &&
        await _closedComplete(cache, bridgeId, session, cachedMax, period)) {
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
    final holes = <RecordedGap>[];

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
        // The device streams what it actually holds, so a sparse stretch means
        // the bridge has no records there — the Smoke X4 was lost, not the
        // phone. It is permanent, unlike a `connectivity` hole the next sync
        // would fill.
        if (previousT != null && sample.t - previousT > period * 2.5) {
          holes.add(
            RecordedGap(
              fromT: previousT,
              toT: sample.t,
              reason: GapReason.baseLost,
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
    final lastSyncMs = (nowMs ?? _wallClock)();
    if (lastFetchedT != null) {
      // Filled range: drop the recoverable holes we just covered and record
      // the ones this run reveals.
      await cache.clearConnectivityGapsBetween(
        bridgeId,
        session.id,
        fromT: fromT,
        toT: lastFetchedT,
      );
      for (final gap in holes) {
        await cache.recordGap(bridgeId, session.id, gap);
      }
      await cache.writeSyncState(
        bridgeId,
        session.id,
        SyncState(
          highWaterT: _max(cachedMax ?? -1, lastFetchedT),
          deviceMinT: firstFetchedT,
          deviceMaxT: deviceMaxT ?? lastFetchedT,
          lastSyncMs: lastSyncMs,
          // A closed session that streamed to its terminator is fully drained;
          // an open one is not, and will be re-read on the next tick.
          complete: session.closed,
        ),
      );
    } else if (session.closed) {
      // The device answered with no rows past our high-water: for a closed
      // session that is the end of it, even when the header claimed a wider
      // extent. Persist the fact so we never ask again.
      await cache.writeSyncState(
        bridgeId,
        session.id,
        SyncState(
          highWaterT: cachedMax ?? -1,
          deviceMinT: null,
          deviceMaxT: deviceMaxT ?? cachedMax,
          lastSyncMs: lastSyncMs,
          complete: true,
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

  /// Whether a closed session has nothing left to pull: either we recorded the
  /// fact after draining it, or the header's extent is already covered by the
  /// cache (within one sample period, since a session's last row sits a period
  /// inside its wall-clock end).
  Future<bool> isComplete(
    SampleCache cache, {
    required String bridgeId,
    required SessionInfo session,
  }) async {
    if (!session.closed) {
      return false;
    }
    final cachedMax = await cache.maxT(bridgeId, session.id);
    final period = session.samplePeriodS < 1 ? 30 : session.samplePeriodS;
    return _closedComplete(cache, bridgeId, session, cachedMax, period);
  }

  Future<bool> _closedComplete(
    SampleCache cache,
    String bridgeId,
    SessionInfo session,
    int? cachedMax,
    int period,
  ) async {
    final state = await cache.syncState(bridgeId, session.id);
    if (state?.complete == true) {
      return true;
    }
    final dm = session.deviceMaxT;
    return cachedMax != null && dm != null && dm <= cachedMax + period;
  }
}

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

int _max(int a, int b) => a > b ? a : b;
