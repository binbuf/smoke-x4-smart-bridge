/// A4.1/A4.2: the drift schema builds from empty, a detached probe stores
/// as NULL, batched inserts land a 24 h cook inside the budget, and range
/// reads come back exact.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schema builds from empty and round-trips a session', () async {
    await db.sessionDao.upsertBridge('LMXC[\\');
    await db.sessionDao.upsertSessions('LMXC[\\', const [
      CookSession(
        id: 7,
        name: 'Test cook',
        startedUnixMs: 1750000000000,
        sampleCount: 3,
        closed: true,
      ),
    ]);
    final back = await db.sessionDao.allSessions('LMXC[\\');
    expect(back, hasLength(1));
    expect(back.first.id, 7);
    expect(back.first.name, 'Test cook');
    expect(back.first.closed, isTrue);

    // Upsert reconciles in place — no duplicate on re-sync.
    await db.sessionDao.upsertSessions('LMXC[\\', const [
      CookSession(id: 7, name: 'Renamed', sampleCount: 5, closed: true),
    ]);
    final again = await db.sessionDao.allSessions('LMXC[\\');
    expect(again, hasLength(1));
    expect(again.first.name, 'Renamed');
  });

  test('a detached probe stores as NULL, never 0', () async {
    await db.sampleDao.insertSamples('b', 1, const [
      Sample(t: 0, tempsF10: [2250, null, 950, null], rssi: -40),
    ]);
    final row = await db.sampleDao.range('b', 1);
    expect(row.single.tempsF10, [2250, null, 950, null]);

    // Straight from the table too: NULL in the column, not a sentinel.
    final raw = await db
        .customSelect('SELECT p2, p4 FROM samples WHERE t = 0')
        .getSingle();
    expect(raw.data['p2'], isNull);
    expect(raw.data['p4'], isNull);
  });

  test('flags survive the round trip', () async {
    await db.sampleDao.insertSamples('b', 1, const [
      Sample(
        t: 30,
        tempsF10: [1000, 1000, 1000, 1000],
        billows: true,
        newAlarm: true,
        sourceCelsius: true,
        rssi: -51,
      ),
    ]);
    final s = (await db.sampleDao.range('b', 1)).single;
    expect(s.billows, isTrue);
    expect(s.newAlarm, isTrue);
    expect(s.sourceCelsius, isTrue);
    expect(s.rssi, -51);
  });

  test('a 24 h cook batch-inserts inside the budget', () async {
    final cook = List<Sample>.generate(
      2880,
      (i) => Sample(
        t: i * 30,
        tempsF10: [2250 + (i % 7), 1400 + i ~/ 4, null, 950],
        rssi: -40,
      ),
    );
    final sw = Stopwatch()..start();
    final n = await db.sampleDao.insertSamples('b', 27, cook);
    sw.stop();
    expect(n, 2880);
    expect(await db.sampleDao.count('b', 27), 2880);
    // Tens of milliseconds locally; the bound is loose only for CI noise.
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('range queries and the delta cursor are exact', () async {
    final cook = List<Sample>.generate(
      100,
      (i) => Sample(t: i * 30, tempsF10: const [1000, null, null, null]),
    );
    await db.sampleDao.insertSamples('b', 2, cook);

    expect(await db.sampleDao.maxT('b', 2), 99 * 30);
    expect(await db.sampleDao.maxT('b', 999), isNull);

    final window = await db.sampleDao.range('b', 2, fromT: 300, toT: 600);
    expect(window, hasLength(11)); // t = 300..600 inclusive at 30 s
    expect(window.first.t, 300);
    expect(window.last.t, 600);

    // Re-inserting the same rows is idempotent (mid-sync restart).
    await db.sampleDao.insertSamples('b', 2, cook);
    expect(await db.sampleDao.count('b', 2), 100);
  });

  test('marks round-trip including UTF-8', () async {
    await db.markDao.replaceMarks('b', 1, const [
      Mark(t: 60, kind: MarkKind.wrapped, text: 'wrapped in foil'),
      Mark(t: 120, kind: MarkKind.note, probe: 2, text: 'crutch — 165°'),
    ]);
    final back = await db.markDao.forSession('b', 1);
    expect(back, hasLength(2));
    expect(back[1].text, 'crutch — 165°');
    expect(back[1].probe, 2);
    expect(back[0].kind, MarkKind.wrapped);
  });
}
