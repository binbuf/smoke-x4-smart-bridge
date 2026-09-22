/// N15.9/N15.10/N15.11 — the drift cache.
///
/// Pure Dart (`package:test`) over `NativeDatabase.memory()`, so it runs in
/// both `flutter test` and `dart test test/data`. It pins the contract the
/// sync engine relies on: `(bridge, session, t)` is identity, the first value
/// wins, permanent gaps are never cleared, and a closed+cached session is a
/// no-op to re-sync.
library;

import 'package:drift/native.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

Sample _s(int t, {List<int?> temps = const [1000, null, null, null]}) =>
    Sample(t: t, tempsF10: temps);

void main() {
  late AppDatabase db;
  late DriftSampleCache cache;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
  });

  tearDown(() => db.close());

  test('schema builds from empty and upserts samples', () async {
    await cache.upsertSamples('bridge', 7, [_s(0), _s(30), _s(60)]);
    expect(await cache.sampleCount('bridge', 7), 3);
    expect(await cache.minT('bridge', 7), 0);
    expect(await cache.maxT('bridge', 7), 60);
  });

  test('I10 — the first recorded value wins on re-sync', () async {
    await cache.upsertSamples('bridge', 7, [
      const Sample(t: 30, tempsF10: [1500, null, null, null]),
    ]);
    // A later sync offers a different value for the same key. It must not
    // rewrite the row.
    await cache.upsertSamples('bridge', 7, [
      const Sample(t: 30, tempsF10: [1234, null, null, null]),
    ]);
    expect(await cache.sampleCount('bridge', 7), 1);
    final rows = await cache.samples('bridge', 7);
    expect(rows.single.tempsF10[0], 1500);
  });

  test('a detached jack stays null, never 0 (I3)', () async {
    await cache.upsertSamples('bridge', 7, [
      const Sample(t: 0, tempsF10: [null, 1650, null, null]),
    ]);
    final row = (await cache.samples('bridge', 7)).single;
    expect(row.tempsF10[0], isNull);
    expect(row.tempsF10[1], 1650);
  });

  test('I11 — a clockless sample stores a null wall clock', () async {
    await cache.upsertSamples('bridge', 7, [
      const Sample(t: 0, tempsF10: [1000, null, null, null]),
    ]);
    final row = (await cache.samples('bridge', 7)).single;
    expect(row.unixMs, isNull);
  });

  test('samples are range-read in t order', () async {
    await cache.upsertSamples('bridge', 7, [_s(90), _s(0), _s(30), _s(60)]);
    final window = await cache.samples('bridge', 7, fromT: 30, toT: 60);
    expect(window.map((s) => s.t), [30, 60]);
  });

  test('connectivity gaps are cleared when their range is filled; '
      'rollover gaps never are', () async {
    await cache.recordGap(
      'bridge',
      7,
      const RecordedGap(fromT: 30, toT: 60, reason: GapReason.connectivity),
    );
    await cache.recordGap(
      'bridge',
      7,
      const RecordedGap(fromT: 90, toT: 120, reason: GapReason.bufferRollover),
    );
    expect(await cache.gaps('bridge', 7), hasLength(2));

    // The filled range covers both holes, but only the recoverable one clears.
    await cache.clearConnectivityGapsBetween('bridge', 7, fromT: 0, toT: 200);
    final gaps = await cache.gaps('bridge', 7);
    expect(gaps, hasLength(1));
    expect(gaps.single.reason, GapReason.bufferRollover);
  });

  test('recording the same gap twice is idempotent', () async {
    const gap = RecordedGap(fromT: 30, toT: 60, reason: GapReason.connectivity);
    await cache.recordGap('bridge', 7, gap);
    await cache.recordGap('bridge', 7, gap);
    expect(await cache.gaps('bridge', 7), hasLength(1));
  });

  test('sync state round-trips and advances', () async {
    expect(await cache.syncState('bridge', 7), isNull);
    await cache.writeSyncState(
      'bridge',
      7,
      const SyncState(
        highWaterT: 120,
        deviceMinT: 0,
        deviceMaxT: 300,
        lastSyncMs: 1750000000000,
      ),
    );
    final state = await cache.syncState('bridge', 7);
    expect(state!.highWaterT, 120);
    expect(state.deviceMaxT, 300);
    expect(state.lastSyncMs, 1750000000000);

    await cache.writeSyncState(
      'bridge',
      7,
      const SyncState(
        highWaterT: 240,
        deviceMinT: 0,
        deviceMaxT: 300,
        lastSyncMs: 1750000001000,
      ),
    );
    expect((await cache.syncState('bridge', 7))!.highWaterT, 240);
  });

  test('sessions and marks persist; a re-sync does not duplicate', () async {
    await cache.upsertSessions('bridge', [
      const SessionInfo(
        id: 7,
        name: 'Brisket',
        startedUnixMs: 1750000000000,
        endedUnixMs: null,
        samplePeriodS: 30,
        sampleCount: 3,
        numProbes: 4,
        probes: [],
        closed: false,
        pinned: false,
        markCount: 0,
      ),
    ]);
    await cache.replaceMarks('bridge', 7, [
      const Mark(t: 30, kind: MarkKind.wrapped, probe: 1, text: 'wrap'),
    ]);
    await cache.replaceMarks('bridge', 7, [
      const Mark(t: 30, kind: MarkKind.wrapped, probe: 1, text: 'wrap'),
    ]);

    final rows = await db.select(db.marks).get();
    expect(rows, hasLength(1));
    expect(rows.single.text_, 'wrap');
  });

  test(
    'clear empties samples, gaps and sync states but keeps sessions',
    () async {
      await cache.upsertSamples('bridge', 7, [_s(0)]);
      await cache.recordGap(
        'bridge',
        7,
        const RecordedGap(fromT: 0, toT: 30, reason: GapReason.connectivity),
      );
      await cache.writeSyncState(
        'bridge',
        7,
        const SyncState(
          highWaterT: 0,
          deviceMinT: null,
          deviceMaxT: null,
          lastSyncMs: 0,
        ),
      );
      await cache.upsertSessions('bridge', [
        const SessionInfo(
          id: 7,
          name: 'Brisket',
          startedUnixMs: null,
          endedUnixMs: null,
          samplePeriodS: 30,
          sampleCount: 1,
          numProbes: 4,
          probes: [],
          closed: false,
          pinned: false,
          markCount: 0,
        ),
      ]);

      await cache.clear();

      expect(await cache.sampleCount('bridge', 7), 0);
      expect(await cache.gaps('bridge', 7), isEmpty);
      expect(await cache.syncState('bridge', 7), isNull);
      expect(await db.select(db.sessions).get(), hasLength(1));
    },
  );
}
