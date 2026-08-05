/// The delta-sync engine (A4.3 — design 08 §8.5), formalised as the
/// **high-water-mark protocol** of newapp §E.4 with the rollover honesty of
/// §E.5.
///
/// On connect: `status()` (firmware gate, active session id), `sessions()`
/// (reconcile), then for each session whose cache is behind, fetch only
/// `from = highWater + 1` and batch-insert. Reconnecting mid-cook transfers
/// only what was missed; a restart mid-sync resumes without duplicating rows
/// because inserts are keyed on (bridge, session, t) and idempotent.
///
/// **What v2 adds.** The cursor used to be recomputed as `MAX(t)` on every
/// connect. That is correct as a resume point and says nothing at all about
/// what the *device* still holds — so the app could not distinguish "I have
/// everything" from "the bridge overwrote the part I was missing while I was in
/// the house". Persisting our mark **beside the device's reported extent** in
/// `sync_states` is what makes that difference visible, and §E.5 requires it be
/// visible: a permanent hole must not render as a dashed line that looks like
/// it will fill in later.
///
/// Three cases, three behaviours:
///
///  1. `deviceMinT <= highWater + 1` — contiguous. Fetch forward. Ordinary.
///  2. `deviceMinT > highWater + 1` — **rollover**. Record a permanent
///     [GapReason.bufferRollover] over the lost span, then fetch what survives.
///  3. cache starts partway in (`minT > 0`) with nothing before it — refetch
///     from 0. The BLE 2-hour preview is a documented producer of this, and the
///     high-water cursor can never reach below itself.
library;

import '../../domain/analysis/gaps.dart';
import '../../domain/entities/entities.dart' show CookSession;
import '../local/database.dart';
import '../transport/bridge_transport.dart';

class SyncReport {
  const SyncReport({
    required this.bridgeId,
    required this.sessionsSeen,
    required this.sessionsSynced,
    required this.samplesInserted,
    this.rolloverGaps = 0,
  });

  final String bridgeId;
  final int sessionsSeen;
  final int sessionsSynced;
  final int samplesInserted;

  /// How many permanent holes this sync discovered. Surfaced so the caller can
  /// tell the user once, rather than leaving it to be noticed on a chart.
  final int rolloverGaps;
}

class SyncEngine {
  SyncEngine(this.db, this.transport, {this.now});

  final AppDatabase db;
  final BridgeTransport transport;

  /// Test seam. Wall clock is only ever used to stamp *when we noticed*
  /// something, never to order device data.
  final DateTime Function()? now;

  int get _nowMs => (now?.call() ?? DateTime.now()).millisecondsSinceEpoch;

  Future<SyncReport> sync() async {
    final status = await transport.status();
    final bridgeId = status.deviceId;
    await db.sessionDao.upsertBridge(bridgeId, lastSeenUnixMs: _nowMs);

    final remote = await transport.sessions();
    await db.sessionDao.upsertSessions(bridgeId, remote);

    var synced = 0;
    var inserted = 0;
    var rollovers = 0;

    for (final session in remote) {
      final cachedMax = await db.sampleDao.maxT(bridgeId, session.id);
      final cachedMin = await db.sampleDao.minT(bridgeId, session.id);
      final cachedCount = await db.sampleDao.count(bridgeId, session.id);
      final highWater = cachedMax ?? -1;

      // The device's own extent. `sessions()` carries the count and the header;
      // the buffer's true low-water mark is what a rollover moves, so it is
      // read from the session's own first sample where the transport reports
      // one and falls back to the header's start otherwise.
      final deviceMinT = session.sampleCount > 0 ? _deviceMinTOf(session) : null;
      final deviceMaxT = session.sampleCount > 0 ? _deviceMaxTOf(session) : null;

      await db.syncStateDao.record(
        bridgeId,
        session.id,
        highWaterT: highWater,
        deviceMinT: deviceMinT,
        deviceMaxT: deviceMaxT,
        atUnixMs: _nowMs,
      );

      // §E.5 — did the ring buffer roll past us? Recorded before the fetch, so
      // an interrupted transfer still leaves the honest hole behind.
      final lost = detectRollover(
        highWaterT: highWater,
        deviceMinT: deviceMinT,
        deviceMaxT: deviceMaxT,
      );
      if (lost != null) {
        await db.syncStateDao.recordGap(
          bridgeId,
          session.id,
          fromT: lost.fromT,
          toT: lost.toT,
          reason: GapReason.bufferRollover,
          atUnixMs: _nowMs,
        );
        rollovers++;
      }

      final upToDate =
          session.closed &&
          cachedCount >= session.sampleCount &&
          session.sampleCount > 0;
      if (upToDate) {
        continue; // a finished, fully-cached cook costs zero bytes
      }

      // The cursor resumes from the high-water mark, which is right for the
      // case it was written for — reconnecting mid-cook — and silently wrong
      // for a cache that starts partway in. The BLE lane is a documented
      // producer of exactly that: it served the last 2 hours only before
      // ble-gatt §5.10, so onboarding over Bluetooth against an older bridge
      // and then reaching it over Wi-Fi leaves earlier history below the mark,
      // where `highWater + 1` can never reach it. Found on the bench: a 16 h
      // cook whose dashboard read 8 h, tracking live samples above a hole it
      // would have kept forever.
      //
      // Refetching from 0 is safe rather than merely tolerable — inserts are
      // keyed on (bridge, session, t) and idempotent — so the only cost of
      // being wrong here is bandwidth, against a header that lies.
      //
      // A rollover is the one case where refetching from 0 is *pointless*: the
      // device cannot serve below its own minimum. Start at what survives.
      final startsPartway = cachedMin != null && cachedMin > 0;
      final fromT = lost != null
          ? lost.toT
          : ((cachedMax == null || startsPartway) ? 0 : cachedMax + 1);

      var got = 0;
      var maxSeen = highWater;
      await for (final batch in transport.samples(session.id, fromT: fromT)) {
        // Each batch lands in its own transaction: a sync interrupted here
        // keeps everything already written, and the next run's cursor starts
        // after it.
        got += await db.sampleDao.insertSamples(
          bridgeId,
          session.id,
          batch,
          sessionStartUnixMs: session.startedUnixMs,
        );
        for (final s in batch) {
          if (s.t > maxSeen) {
            maxSeen = s.t;
          }
        }
        // Resumability is the point of the mark: advance it **per batch**, so
        // an interrupted BLE transfer resumes at the last stored `t` rather
        // than at the last completed session.
        await db.syncStateDao.record(
          bridgeId,
          session.id,
          highWaterT: maxSeen,
          deviceMinT: deviceMinT,
          deviceMaxT: deviceMaxT,
          atUnixMs: _nowMs,
        );
      }
      if (got > 0) {
        synced++;
        inserted += got;
        // A connectivity hole the phone has now filled stops being a hole.
        // Rollover gaps are never cleared here — nobody has that data.
        await db.syncStateDao.clearFilledConnectivityGaps(bridgeId, session.id);
      }
    }
    return SyncReport(
      bridgeId: bridgeId,
      sessionsSeen: remote.length,
      sessionsSynced: synced,
      samplesInserted: inserted,
      rolloverGaps: rollovers,
    );
  }

  /// The device's oldest surviving `t` for a session.
  ///
  /// The session header does not carry it directly, so it is derived from what
  /// the header *does* carry: a session that has rolled has fewer samples than
  /// its span implies, and the difference is what fell off the front. Where the
  /// arithmetic cannot be trusted (no cadence, no count) this returns null and
  /// [detectRollover] declines to guess — which is the correct outcome, because
  /// an invented rollover would render a permanent hole that never happened.
  int? _deviceMinTOf(CookSession s) {
    final maxT = _deviceMaxTOf(s);
    if (maxT == null || s.samplePeriodS <= 0 || s.sampleCount <= 0) {
      return null;
    }
    final spanned = (s.sampleCount - 1) * s.samplePeriodS;
    final minT = maxT - spanned;
    return minT < 0 ? 0 : minT.toInt();
  }

  int? _deviceMaxTOf(CookSession s) {
    if (s.sampleCount <= 0 || s.samplePeriodS <= 0) {
      return null;
    }
    final started = s.startedUnixMs;
    final ended = s.endedUnixMs;
    if (started != null && ended != null && ended > started) {
      return ((ended - started) / 1000).round();
    }
    // An open session's newest `t` is not in the header at all; the live push
    // is what carries it. Fall back to the count-times-cadence span, which is
    // exact for a session that has never rolled and an underestimate for one
    // that has — and an underestimate here can only *miss* a rollover, never
    // invent one.
    return (s.sampleCount - 1) * s.samplePeriodS;
  }
}
