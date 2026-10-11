/// The on-device cache's load-bearing rules: idempotent upsert, order and range
/// reads, gap permanence, session upsert-only history and sync bookkeeping.
///
/// The in-memory cache mirrors this exactly, so these are the behaviours the
/// sync engine and the offline screens depend on when the real SQLite file is
/// underneath them.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/cache/sample_cache.dart';
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';
import 'package:smoke_bridge/domain/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSampleCache cache;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert is idempotent: the first recorded value wins', () async {
    await cache.upsertSamples('A4F2', 1, const [
      Sample(t: 0, tempsF10: [2000, 1600, null, 900]),
    ]);
    // A re-sync carrying a different value for the same second changes nothing.
    await cache.upsertSamples('A4F2', 1, const [
      Sample(t: 0, tempsF10: [9999, 9999, 9999, 9999]),
      Sample(t: 30, tempsF10: [2010, 1601, null, 901]),
    ]);

    final rows = await cache.samples('A4F2', 1);
    expect(rows, hasLength(2));
    expect(rows.first.tempsF10.first, 2000, reason: 'first value is truth');
    expect(await cache.sampleCount('A4F2', 1), 2);
    expect(await cache.minT('A4F2', 1), 0);
    expect(await cache.maxT('A4F2', 1), 30);
  });

  test('samples read in t order and honour fromT/toT', () async {
    await cache.upsertSamples('A4F2', 1, const [
      Sample(t: 90, tempsF10: [2000]),
      Sample(t: 0, tempsF10: [2000]),
      Sample(t: 30, tempsF10: [2000]),
      Sample(t: 60, tempsF10: [2000]),
    ]);

    final all = await cache.samples('A4F2', 1);
    expect(all.map((s) => s.t), [0, 30, 60, 90]);

    final ranged = await cache.samples('A4F2', 1, fromT: 30, toT: 60);
    expect(ranged.map((s) => s.t), [30, 60]);
  });

  test(
    'a filled range clears connectivity gaps but never permanent ones',
    () async {
      await cache.recordGap(
        'A4F2',
        1,
        const RecordedGap(fromT: 60, toT: 120, reason: GapReason.connectivity),
      );
      await cache.recordGap(
        'A4F2',
        1,
        const RecordedGap(fromT: 300, toT: 360, reason: GapReason.baseLost),
      );

      await cache.clearConnectivityGapsBetween('A4F2', 1, fromT: 0, toT: 600);

      final gaps = await cache.gaps('A4F2', 1);
      expect(gaps.map((g) => g.reason), [GapReason.baseLost]);
    },
  );

  test('sessions upsert, read newest-first, and remember the bridge', () async {
    await cache.upsertSessions('A4F2', const [
      SessionInfo(
        id: 1,
        name: 'Older',
        startedUnixMs: 1000,
        endedUnixMs: 2000,
        samplePeriodS: 30,
        sampleCount: 10,
        numProbes: 4,
        closed: true,
        pinned: false,
      ),
      SessionInfo(
        id: 2,
        name: 'Newer',
        startedUnixMs: 3000,
        endedUnixMs: null,
        samplePeriodS: 30,
        sampleCount: 5,
        numProbes: 4,
        closed: false,
        pinned: false,
      ),
    ]);

    var sessions = await cache.readSessions('A4F2');
    expect(sessions.map((s) => s.id), [2, 1]);
    expect(await cache.latestBridgeId(), 'A4F2');

    // Missing sessions are replaced, not lost — a phone that saw a session
    // keeps it even after the bridge purges it.
    await cache.upsertSessions('A4F2', const [
      SessionInfo(
        id: 2,
        name: 'Renamed',
        startedUnixMs: 3000,
        endedUnixMs: 4000,
        samplePeriodS: 30,
        sampleCount: 5,
        numProbes: 4,
        closed: true,
        pinned: false,
      ),
    ]);
    sessions = await cache.readSessions('A4F2');
    expect(sessions.map((s) => s.id), [2, 1], reason: 'upsert-only');
    expect(sessions.first.name, 'Renamed');
    expect(sessions.first.closed, isTrue);
  });

  test('sync state round-trips and overwrites in place', () async {
    await cache.writeSyncState(
      'A4F2',
      1,
      const SyncState(
        highWaterT: 90,
        deviceMinT: 0,
        deviceMaxT: 120,
        lastSyncMs: 1234,
      ),
    );
    var state = await cache.syncState('A4F2', 1);
    expect(state!.highWaterT, 90);
    expect(state.deviceMinT, 0);
    expect(state.deviceMaxT, 120);
    expect(state.lastSyncMs, 1234);

    await cache.writeSyncState(
      'A4F2',
      1,
      const SyncState(
        highWaterT: 120,
        deviceMinT: 0,
        deviceMaxT: 150,
        lastSyncMs: 5678,
      ),
    );
    state = await cache.syncState('A4F2', 1);
    expect(state!.highWaterT, 120);
    expect(state.deviceMaxT, 150);
  });
}
