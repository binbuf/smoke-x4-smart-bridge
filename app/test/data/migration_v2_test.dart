/// The v1 → v2 migration (newapp §D.2, §I.1).
///
/// This runs against a **hand-built v1 database** — the exact five tables and
/// column set schema v1 shipped — rather than against drift's own `createAll`,
/// because the thing under test is what happens to a phone that already has
/// eighteen hours of brisket in it. A migration tested against a fresh database
/// is a migration tested against the one case that cannot go wrong.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:sqlite3/sqlite3.dart';

const int _epoch = 1700000000000;

/// The v1 schema, verbatim, plus one bridge, two sessions and their samples.
Database _seedV1() {
  final raw = sqlite3.openInMemory();
  raw.execute('''
    CREATE TABLE bridges (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      last_seen_unix_ms INTEGER NULL);
    CREATE TABLE sessions (
      bridge_id TEXT NOT NULL,
      session_id INTEGER NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      started_unix_ms INTEGER NULL,
      ended_unix_ms INTEGER NULL,
      sample_period_s INTEGER NOT NULL DEFAULT 30,
      sample_count INTEGER NOT NULL DEFAULT 0,
      num_probes INTEGER NOT NULL DEFAULT 4,
      closed INTEGER NOT NULL DEFAULT 0,
      pinned INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (bridge_id, session_id));
    CREATE TABLE samples (
      bridge_id TEXT NOT NULL,
      session_id INTEGER NOT NULL,
      t INTEGER NOT NULL,
      p1 INTEGER NULL, p2 INTEGER NULL, p3 INTEGER NULL, p4 INTEGER NULL,
      flags INTEGER NOT NULL DEFAULT 0,
      rssi INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (bridge_id, session_id, t));
    CREATE TABLE marks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      bridge_id TEXT NOT NULL,
      session_id INTEGER NOT NULL,
      t INTEGER NOT NULL,
      kind INTEGER NOT NULL,
      probe INTEGER NOT NULL DEFAULT 0,
      text TEXT NOT NULL DEFAULT '');
    CREATE TABLE alarm_log (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      bridge_id TEXT NOT NULL,
      unix_ms INTEGER NULL,
      rule TEXT NOT NULL,
      probe INTEGER NOT NULL DEFAULT 0,
      value_f10 INTEGER NULL,
      action TEXT NOT NULL);
    PRAGMA user_version = 1;
  ''');

  raw.execute("INSERT INTO bridges (id, name) VALUES ('bridge-a', 'Smoker')");
  // A clocked, closed cook.
  raw.execute(
    'INSERT INTO sessions (bridge_id, session_id, name, started_unix_ms, '
    'ended_unix_ms, sample_period_s, sample_count, closed) '
    "VALUES ('bridge-a', 27, 'Brisket', $_epoch, "
    '${_epoch + 8 * 3600 * 1000}, 30, 960, 1)',
  );
  // A clockless, open one — the bridge whose RTC was never set.
  raw.execute(
    'INSERT INTO sessions (bridge_id, session_id, name, sample_period_s, '
    "sample_count, closed) VALUES ('bridge-a', 28, '', 30, 10, 0)",
  );
  for (var t = 0; t <= 8 * 3600; t += 30) {
    raw.execute(
      'INSERT INTO samples (bridge_id, session_id, t, p1, p2) '
      "VALUES ('bridge-a', 27, $t, 2400, ${1000 + t ~/ 60})",
    );
  }
  for (var t = 0; t < 300; t += 30) {
    raw.execute(
      'INSERT INTO samples (bridge_id, session_id, t, p1) '
      "VALUES ('bridge-a', 28, $t, 2400)",
    );
  }
  raw.execute(
    'INSERT INTO marks (bridge_id, session_id, t, kind, probe, text) '
    "VALUES ('bridge-a', 27, 3600, 1, 2, 'Wrapped')",
  );
  return raw;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.opened(_seedV1()));
    // Opening runs the migration.
    await db.customSelect('SELECT 1').getSingle();
  });

  tearDown(() => db.close());

  Future<int> _count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  test('the schema lands on v2 with the new tables present', () async {
    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.first, 2);
    for (final table in [
      'cooks',
      'cook_probe_roles',
      'alarm_rules',
      'gaps',
      'sync_states',
    ]) {
      expect(
        await _count(
          "SELECT COUNT(*) AS n FROM sqlite_master WHERE name = '$table'",
        ),
        1,
        reason: '$table must exist after the upgrade',
      );
    }
  });

  test('not one sample is lost', () async {
    expect(await _count('SELECT COUNT(*) AS n FROM samples'), 961 + 10);
    expect(await _count('SELECT COUNT(*) AS n FROM marks'), 1);
  });

  test('a clocked session gets its wall clock projected onto every sample',
      () async {
    expect(
      await _count(
        'SELECT COUNT(*) AS n FROM samples '
        'WHERE session_id = 27 AND unix_ms IS NULL',
      ),
      0,
    );
    final first = await db
        .customSelect(
          'SELECT unix_ms AS v FROM samples WHERE session_id = 27 AND t = 0',
        )
        .getSingle();
    expect(first.read<int>('v'), _epoch);
    final later = await db
        .customSelect(
          'SELECT unix_ms AS v FROM samples WHERE session_id = 27 AND t = 3600',
        )
        .getSingle();
    expect(later.read<int>('v'), _epoch + 3600 * 1000);
  });

  test('a clockless session is left NULL rather than given an invented time',
      () async {
    expect(
      await _count(
        'SELECT COUNT(*) AS n FROM samples '
        'WHERE session_id = 28 AND unix_ms IS NOT NULL',
      ),
      0,
      reason:
          '§E.7 forbids fabricating wall times for a bridge whose RTC was '
          'never set — epoch-zero readings would sort into 1970',
    );
  });

  test('every session becomes a cook annotation', () async {
    final cooks = await db.cookDao.forBridge('bridge-a');
    expect(cooks, hasLength(2));

    final brisket = cooks.firstWhere((c) => c.name == 'Brisket');
    expect(brisket.startUnixMs, _epoch);
    expect(brisket.endUnixMs, _epoch + 8 * 3600 * 1000);
    expect(brisket.anchorSessionId, isNull, reason: 'it has a clock');

    final clockless = cooks.firstWhere((c) => c.name.isEmpty);
    expect(
      clockless.anchorSessionId,
      28,
      reason: 'with no clock it must pin to its session or become unreachable',
    );
    expect(clockless.endUnixMs, isNull, reason: 'it was still open');
  });

  test('the migrated cook resolves the samples it always covered', () async {
    final cooks = await db.cookDao.forBridge('bridge-a');
    final brisket = cooks.firstWhere((c) => c.name == 'Brisket');
    final samples = await db.cookDao.samplesFor(brisket);
    expect(
      samples,
      hasLength(960),
      reason:
          'end is exclusive, so the sample exactly at the close belongs to '
          'nothing — 961 rows minus the boundary one',
    );

    final clockless = cooks.firstWhere((c) => c.name.isEmpty);
    expect(await db.cookDao.samplesFor(clockless), hasLength(10));
  });

  test('sync high-water marks are seeded from what is already cached',
      () async {
    expect((await db.syncStateDao.forSession('bridge-a', 27))?.highWaterT,
        8 * 3600);
    expect((await db.syncStateDao.forSession('bridge-a', 28))?.highWaterT, 270);
  });

  test('marks gain the anchor flag, defaulted off', () async {
    final rows = await db.markDao.forSession('bridge-a', 27);
    expect(rows, hasLength(1));
    expect(
      await _count('SELECT COUNT(*) AS n FROM marks WHERE auto_anchor = 0'),
      1,
    );
  });
}
