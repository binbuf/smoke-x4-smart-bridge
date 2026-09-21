/// N15.11/N15.12/N15.14 — the sync engine, cook-window membership and cache CSV.
///
/// The high-water-mark protocol (research notes §5.3):
///
///  1. `sessions()` (done by the caller / [BridgeSession]).
///  2. Derive the device extent, detect rollover **before** fetching, record a
///     permanent gap if the device's buffer wrapped past the phone.
///  3. Skip a closed, fully-cached session.
///  4. Choose `fromT`: no cache → 0, rollover → device min, else `cachedMax+1`.
///  5. Stream, upsert idempotently, advance the high-water per batch, clear
///     filled connectivity gaps.
library;

import '../../domain/domain.dart';
import '../export/cook_export.dart';
import 'bridge_transport.dart';
import 'sample_cache.dart';

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

/// N15.11 — one session's high-water-mark sync.
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
    final deviceMaxT = _deviceMaxT(session);

    // 3. A closed session we already hold in full is done.
    if (session.closed &&
        cachedMax != null &&
        deviceMaxT != null &&
        cachedMax >= deviceMaxT) {
      return const SyncResult(fetched: 0, inserted: 0, skipped: true);
    }

    // 4. fromT. With no rows we take the whole session; otherwise the next
    // unsynced second. A detected rollover rewrites fromT to the device min.
    final fromT = cachedMax == null ? 0 : cachedMax + 1;
    final before = await cache.sampleCount(bridgeId, session.id);

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
        // 2. Rollover: the device's earliest row is past our high-water, so
        // the buffer wrapped. Record it BEFORE any upsert.
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
          highWaterT: mathMax(cachedMax ?? -1, lastFetchedT),
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

  /// The last second a closed session holds. Null while the clock or the end
  /// is unknown (I11) — an open session has no known extent.
  static int? _deviceMaxT(SessionInfo session) {
    final start = session.startedUnixMs;
    final end = session.endedUnixMs;
    if (!session.closed || start == null || end == null || end < start) {
      return null;
    }
    return (end - start) ~/ 1000;
  }
}

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

int mathMax(int a, int b) => a > b ? a : b;

/// N15.12 — a cook annotation is a **time window over the continuous
/// recording**, never a sample row (I10, NOTES §5.2). [startUnixMs] and
/// [endUnixMs] are wall-clock milliseconds; a sample's wall clock is its own
/// [Sample.unixMs] when present, else `session.startedUnixMs + t*1000`.
///
/// A null [sessionStartedUnixMs] with no sample timestamps yields **no**
/// members: without a clock there is no honest window (I11).
List<Sample> samplesInWindow(
  List<Sample> samples, {
  required int? sessionStartedUnixMs,
  required int startUnixMs,
  int? endUnixMs,
}) {
  final out = <Sample>[];
  for (final sample in samples) {
    final unix =
        sample.unixMs ??
        (sessionStartedUnixMs == null
            ? null
            : sessionStartedUnixMs + sample.t * 1000);
    if (unix == null || unix < startUnixMs) {
      continue;
    }
    if (endUnixMs != null && unix > endUnixMs) {
      continue;
    }
    out.add(sample);
  }
  return out;
}

/// N15.14 — build the device-compatible CSV for one cook from the cache.
///
/// The rows are the cook's time window; the byte format is
/// [buildCookCsv]'s (header, field order, ISO-8601, detached = empty).
/// Reading the cache means the export works with the bridge offline.
Future<String> exportCookCsvFromCache({
  required SampleCache cache,
  required String bridgeId,
  required int sessionId,
  required int? sessionStartedUnixMs,
  required int startUnixMs,
  int? endUnixMs,
}) async {
  final all = await cache.samples(bridgeId, sessionId);
  final window = samplesInWindow(
    all,
    sessionStartedUnixMs: sessionStartedUnixMs,
    startUnixMs: startUnixMs,
    endUnixMs: endUnixMs,
  );
  return buildCookCsv(
    samples: window,
    sessionStartedUnixMs: sessionStartedUnixMs,
  );
}
