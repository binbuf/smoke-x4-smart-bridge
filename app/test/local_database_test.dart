import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int _baseSec = 1700000000;
const int _baseMs = _baseSec * 1000;
const int _cadenceMs = 60000;

int _timeOf(int seq) => _baseMs + seq * _cadenceMs;

DeviceSample _known(
  int seq, {
  int? unixS,
  List<int?> tempsF10 = const <int?>[700, 710, 720, 730],
  int flags = 0x1F,
}) => DeviceSample(
  seq: seq,
  unixS: unixS ?? _baseSec + seq * 60,
  tempsF10: tempsF10,
  flags: flags,
  clockValid: true,
);

StoredSample _stored(
  int seq, {
  int? unixS,
  int? recordedMs,
  int timeEstimated = 0,
  List<int?> tempsF10 = const <int?>[700, null, 720, 730],
  String bridgeId = 'bridge-a',
  int generation = 1,
}) => StoredSample(
  bridgeId: bridgeId,
  generation: generation,
  seq: seq,
  unixS: unixS,
  recordedMs: recordedMs ?? _timeOf(seq),
  timeEstimated: timeEstimated,
  tempsF10: tempsF10,
  flags: 0x1F,
);

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SampleDao dao;

  setUp(() async {
    database = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    dao = SqfliteSampleDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('schema creates bridge, sample, gap and the time index', () async {
    final tables = await database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(<String>['bridge', 'sample', 'gap']),
    );
    final indexes = await database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'sample_time'",
    );
    expect(indexes, hasLength(1));
    expect(await database.database.getVersion(), AppDatabase.schemaVersion);
  });

  test(
    '10,000 records insert, range-query, count and delete in one batch',
    () async {
      final samples = <DeviceSample>[
        for (var seq = 0; seq < 10000; seq++) _known(seq),
      ];

      final inserted = await dao.insertBatch(
        bridgeId: 'bridge-a',
        generation: 1,
        samples: samples,
        syncWallMs: _baseMs,
        deviceMaxSeq: 9999,
      );

      expect(inserted, 10000);
      expect(await dao.countSamples(bridgeId: 'bridge-a'), 10000);

      final extent = await dao.extent(bridgeId: 'bridge-a');
      expect(extent, isNotNull);
      expect(extent!.count, 10000);
      expect(extent.minSeq, 0);
      expect(extent.maxSeq, 9999);
      expect(extent.minRecordedMs, _timeOf(0));
      expect(extent.maxRecordedMs, _timeOf(9999));

      final range = await dao.samplesInRange(
        fromMs: _timeOf(100),
        toMs: _timeOf(200),
        bridgeId: 'bridge-a',
      );
      expect(range, hasLength(100));
      expect(range.first.seq, 100);
      expect(range.last.seq, 199);
      expect(
        await dao.countSamples(
          bridgeId: 'bridge-a',
          fromMs: _timeOf(100),
          toMs: _timeOf(200),
        ),
        100,
      );

      final deletion = await dao.deleteRange(
        fromMs: _timeOf(0),
        toMs: _timeOf(5000),
        bridgeId: 'bridge-a',
      );
      expect(deletion.samplesDeleted, 5000);
      expect(await dao.countSamples(bridgeId: 'bridge-a'), 5000);
      expect((await dao.extent(bridgeId: 'bridge-a'))!.minSeq, 5000);
    },
  );

  test('duplicate seq insertion is idempotent', () async {
    await dao.insertBatch(
      bridgeId: 'bridge-a',
      generation: 1,
      samples: <DeviceSample>[_known(7)],
      syncWallMs: _baseMs,
      deviceMaxSeq: 7,
    );
    await dao.insertBatch(
      bridgeId: 'bridge-a',
      generation: 1,
      samples: <DeviceSample>[_known(7)],
      syncWallMs: _baseMs,
      deviceMaxSeq: 7,
    );

    expect(await dao.countSamples(bridgeId: 'bridge-a'), 1);
  });

  test('re-sync keeps an exact clock and upgrades an estimated one', () async {
    final estimated = _stored(
      4,
      unixS: null,
      recordedMs: _timeOf(4) - 30000,
      timeEstimated: 1,
    );
    await dao.insertSamples(<StoredSample>[estimated]);

    // A worse (estimated) duplicate must not replace an exact row once it has
    // been upgraded, and an exact duplicate must not duplicate.
    final exact = _stored(4, unixS: _baseSec + 240);
    await dao.insertSamples(<StoredSample>[exact]);
    await dao.insertSamples(<StoredSample>[exact]);
    await dao.insertSamples(<StoredSample>[estimated]);

    final rows = await dao.samplesInRange(
      fromMs: 0,
      toMs: _timeOf(10),
      bridgeId: 'bridge-a',
    );
    expect(rows, hasLength(1));
    expect(rows.single.unixS, _baseSec + 240);
    expect(rows.single.recordedMs, _timeOf(4));
    expect(rows.single.timeEstimated, 0);
  });

  test('unknown device clock stores NULL unix_s and the estimate', () async {
    final inserted = await dao.insertBatch(
      bridgeId: 'bridge-a',
      generation: 1,
      samples: <DeviceSample>[
        const DeviceSample(
          seq: 9,
          unixS: 0,
          tempsF10: <int?>[700, deviceTempDetached, deviceTempInvalid, 730],
          flags: 0x0F,
          clockValid: false,
        ),
      ],
      syncWallMs: 1700000000000,
      deviceMaxSeq: 10,
    );

    expect(inserted, 1);
    final row = (await dao.samplesInRange(
      fromMs: 0,
      toMs: 1800000000000,
      bridgeId: 'bridge-a',
    )).single;
    expect(row.unixS, isNull);
    expect(row.timeEstimated, 1);
    expect(row.recordedMs, 1700000000000 - (10 - 9) * 30000);
    expect(row.tempsF10, <int?>[700, null, null, 730]);
  });

  test(
    'bridge identity upserts, orders by last_seen and touches in place',
    () async {
      await dao.saveBridge(
        const SavedBridge(
          id: 'aa:bb',
          name: 'SmokeX4-1A2B',
          lastSeenMs: 100,
          generation: 3,
          cursorAfter: 40,
          cursorBefore: 10,
          deviceMinSeq: 1,
          deviceMaxSeq: 99,
        ),
      );
      await dao.saveBridge(
        const SavedBridge(id: 'cc:dd', name: 'SmokeX4-3C4D', lastSeenMs: 200),
      );

      expect((await dao.savedBridge())!.id, 'cc:dd');

      await dao.touchBridge(id: 'aa:bb', name: 'SmokeX4-1A2B', lastSeenMs: 300);
      final updated = (await dao.savedBridge())!;
      expect(updated.id, 'aa:bb');
      expect(updated.name, 'SmokeX4-1A2B');
      expect(updated.lastSeenMs, 300);
      expect(updated.generation, 3);
      expect(updated.cursorAfter, 40);
      expect(updated.deviceMaxSeq, 99);

      await dao.saveBridge(updated.copyWith(name: 'Renamed'));
      expect((await dao.bridgeById('aa:bb'))!.name, 'Renamed');
    },
  );

  test('forgetting the bridge leaves sample and gap rows readable', () async {
    await dao.saveBridge(
      const SavedBridge(id: 'bridge-a', name: 'SmokeX4-1A2B', lastSeenMs: 100),
    );
    await dao.insertSamples(<StoredSample>[_stored(1)]);
    await dao.insertGaps(<StoredGap>[
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 2,
        toSeq: 3,
        reason: 'Not synced',
        detectedMs: _timeOf(2),
      ),
    ]);

    expect(await dao.removeBridge('bridge-a'), isTrue);
    expect(await dao.savedBridge(), isNull);

    final orphaned = await dao.samplesInRange(fromMs: 0, toMs: _timeOf(5));
    expect(orphaned, hasLength(1));
    expect(orphaned.single.bridgeId, 'bridge-a');
    expect(await dao.gaps(), hasLength(1));
  });

  test('deleteRange trims then removes a gap that loses its samples', () async {
    await dao.insertSamples(<StoredSample>[
      for (var seq = 0; seq < 10; seq++) _stored(seq),
    ]);
    await dao.insertGaps(<StoredGap>[
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 3,
        toSeq: 5,
        reason: 'No signal',
        detectedMs: 1, // outside the deleted date range
      ),
    ]);

    final trimmed = await dao.deleteRange(
      fromMs: _timeOf(4),
      toMs: _timeOf(6),
      bridgeId: 'bridge-a',
    );
    expect(trimmed.samplesDeleted, 2);
    expect(trimmed.gapsDeleted, 0);
    expect(trimmed.gapsTrimmed, 1);
    var rest = await dao.gaps(bridgeId: 'bridge-a');
    expect(rest, hasLength(1));
    expect(rest.single.fromSeq, 3);
    expect(rest.single.toSeq, 3);

    final removed = await dao.deleteRange(
      fromMs: _timeOf(0),
      toMs: _timeOf(4),
      bridgeId: 'bridge-a',
    );
    expect(removed.samplesDeleted, 4);
    expect(removed.gapsDeleted, 1);
    expect(await dao.gaps(bridgeId: 'bridge-a'), isEmpty);
  });

  test('deleteRange removes a gap detected inside the range', () async {
    await dao.insertSamples(<StoredSample>[_stored(0)]);
    await dao.insertGaps(<StoredGap>[
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 20,
        toSeq: 30,
        reason: 'Bridge off',
        detectedMs: _timeOf(5),
      ),
    ]);

    final deletion = await dao.deleteRange(
      fromMs: _timeOf(5),
      toMs: _timeOf(6),
      bridgeId: 'bridge-a',
    );
    expect(deletion.samplesDeleted, 0);
    expect(deletion.gapsDeleted, 1);
    expect(await dao.gaps(), isEmpty);
  });

  test('a relaunch reads the same file and saved Bridge identity', () async {
    final directory = await Directory.systemTemp.createTemp('smoke_db_test');
    final path = '${directory.path}${Platform.pathSeparator}archive.db';
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    var first = await AppDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    var firstDao = SqfliteSampleDao(first);
    await firstDao.saveBridge(
      const SavedBridge(
        id: 'bridge-a',
        name: 'SmokeX4-1A2B',
        lastSeenMs: 123,
        generation: 7,
        cursorAfter: 5,
      ),
    );
    await firstDao.insertSamples(<StoredSample>[_stored(5, generation: 7)]);
    await first.close();

    final reopened = await AppDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final reopenedDao = SqfliteSampleDao(reopened);
    final bridge = await reopenedDao.savedBridge();
    expect(bridge, isNotNull);
    expect(bridge!.id, 'bridge-a');
    expect(bridge.generation, 7);
    expect(bridge.cursorAfter, 5);
    final rows = await reopenedDao.samplesInRange(fromMs: 0, toMs: _timeOf(6));
    expect(rows, hasLength(1));
    expect(rows.single.seq, 5);
    await reopened.close();
  });

  test('a version-1 empty database migrates to the archive schema', () async {
    final directory = await Directory.systemTemp.createTemp('smoke_db_v1');
    final path = '${directory.path}${Platform.pathSeparator}v1.db';
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1),
    );
    expect(await v1.getVersion(), 1);
    await v1.close();

    final migrated = await AppDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    expect(await migrated.database.getVersion(), 2);
    final dao = SqfliteSampleDao(migrated);
    await dao.saveBridge(
      const SavedBridge(id: 'bridge-a', name: 'SmokeX4-1A2B', lastSeenMs: 1),
    );
    expect((await dao.savedBridge())!.id, 'bridge-a');
    await migrated.close();
  });
}
