import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/data/history/history_deletion.dart';

final DateTime _now = DateTime(2026, 10, 27, 12);

DateTime _ago(Duration age) => _now.subtract(age);

StoredSample _sample(
  int seq,
  DateTime time, {
  String bridgeId = 'bridge-a',
  int generation = 1,
}) => StoredSample(
  bridgeId: bridgeId,
  generation: generation,
  seq: seq,
  unixS: time.millisecondsSinceEpoch ~/ 1000,
  recordedMs: time.millisecondsSinceEpoch,
  timeEstimated: 0,
  tempsF10: const <int?>[2250, 1650, null, 1800],
  flags: 0x1F,
);

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SampleDao dao;
  late HistoryDeletionService service;

  setUp(() async {
    database = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    dao = SqfliteSampleDao(database);
    service = HistoryDeletionService(dao: dao, now: () => _now);
  });

  tearDown(() async {
    await database.close();
  });

  test('30/90/all plans honour the exact older-than boundary', () async {
    final samples = <StoredSample>[
      _sample(0, _ago(const Duration(days: 91))),
      _sample(1, _ago(const Duration(days: 90))),
      _sample(
        2,
        _ago(
          Duration(milliseconds: const Duration(days: 90).inMilliseconds - 1),
        ),
      ),
      _sample(3, _ago(const Duration(days: 31))),
      _sample(4, _ago(const Duration(days: 30))),
      _sample(
        5,
        _ago(
          Duration(milliseconds: const Duration(days: 30).inMilliseconds - 1),
        ),
      ),
      _sample(6, _ago(const Duration(hours: 1))),
    ];
    await dao.insertSamples(samples);

    final plan30 = await service.plan(HistoryDeletionScope.olderThan30Days);
    expect(plan30.count, 4);
    expect(plan30.firstReadingMs, samples[0].recordedMs);
    expect(plan30.lastReadingMs, samples[3].recordedMs);
    expect(plan30.isEmpty, isFalse);

    final plan90 = await service.plan(HistoryDeletionScope.olderThan90Days);
    expect(plan90.count, 1);
    expect(plan90.firstReadingMs, samples[0].recordedMs);
    expect(plan90.lastReadingMs, samples[0].recordedMs);

    final planAll = await service.plan(HistoryDeletionScope.all);
    expect(planAll.count, 7);
    expect(planAll.firstReadingMs, samples[0].recordedMs);
    expect(planAll.lastReadingMs, samples[6].recordedMs);

    // Planning is a read. It never deletes automatically.
    expect(await dao.countSamples(), 7);
  });

  test('30 days keeps a reading exactly on the cutoff', () async {
    await dao.insertSamples(<StoredSample>[
      _sample(
        0,
        _ago(
          Duration(milliseconds: const Duration(days: 30).inMilliseconds + 1),
        ),
      ),
      _sample(1, _ago(const Duration(days: 30))),
      _sample(
        2,
        _ago(
          Duration(milliseconds: const Duration(days: 30).inMilliseconds - 1),
        ),
      ),
    ]);

    final plan = await service.plan(HistoryDeletionScope.olderThan30Days);
    expect(plan.count, 1);

    final outcome = await service.delete(plan);
    expect(outcome.samplesDeleted, 1);
    final remaining = await dao.samplesInRange(
      fromMs: 0,
      toMs: _now.millisecondsSinceEpoch + 1,
    );
    expect(remaining.map((row) => row.seq), <int>[1, 2]);
  });

  test('90 days keeps a reading exactly on the cutoff', () async {
    await dao.insertSamples(<StoredSample>[
      _sample(
        0,
        _ago(
          Duration(
            milliseconds: const Duration(days: 90).inMilliseconds + 1,
          ),
        ),
      ),
      _sample(1, _ago(const Duration(days: 90))),
      _sample(2, _ago(const Duration(days: 89))),
    ]);

    final plan = await service.plan(HistoryDeletionScope.olderThan90Days);
    expect(plan.count, 1);
    final outcome = await service.delete(plan);
    expect(outcome.samplesDeleted, 1);
    expect(await dao.countSamples(), 2);
  });

  test('all history removes every local reading', () async {
    await dao.insertSamples(<StoredSample>[
      _sample(0, _ago(const Duration(days: 100))),
      _sample(1, _ago(const Duration(days: 10))),
      _sample(2, _ago(const Duration(hours: 1))),
    ]);

    final plan = await service.plan(HistoryDeletionScope.all);
    final outcome = await service.delete(plan);
    expect(outcome.samplesDeleted, 3);
    expect(await dao.countSamples(), 0);
    expect(await dao.extent(), isNull);
  });

  test('deleting a range removes and trims the gap rows it described', () async {
    final start = _ago(const Duration(days: 60));
    await dao.insertSamples(<StoredSample>[
      for (var seq = 0; seq < 6; seq++)
        _sample(seq, start.add(Duration(minutes: seq))),
      _sample(6, _ago(const Duration(hours: 1))),
    ]);
    await dao.insertGaps(<StoredGap>[
      // Fully inside the deleted sequence extent.
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 1,
        toSeq: 2,
        reason: 'No signal',
        detectedMs: start.millisecondsSinceEpoch,
      ),
      // Extends past the deleted extent; keep the tail for the surviving rows.
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 4,
        toSeq: 10,
        reason: 'Bridge off',
        detectedMs: start.millisecondsSinceEpoch + 1000,
      ),
      // No samples of its own but detected inside the deleted date range.
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 20,
        toSeq: 30,
        reason: 'Not synced',
        detectedMs: start.millisecondsSinceEpoch + 2000,
      ),
    ]);

    final plan = await service.plan(HistoryDeletionScope.olderThan30Days);
    expect(plan.count, 6);
    final outcome = await service.delete(plan);

    expect(outcome.samplesDeleted, 6);
    expect(outcome.deletion.gapsTrimmed, 1);
    expect(outcome.deletion.gapsDeleted, 2);
    final gaps = await dao.gaps(bridgeId: 'bridge-a');
    expect(gaps, hasLength(1));
    expect(gaps.single.fromSeq, 6);
    expect(gaps.single.toSeq, 10);
    expect(await dao.countSamples(), 1);
  });

  test('an empty plan says so and never issues a delete', () async {
    final plan = await service.plan(HistoryDeletionScope.olderThan30Days);
    expect(plan.isEmpty, isTrue);
    expect(plan.firstReadingMs, isNull);

    final outcome = await service.delete(plan);
    expect(outcome.samplesDeleted, 0);
    expect(outcome.gapsAffected, 0);
  });

  test(
    'deletion reconciles cursors to the remaining current generation',
    () async {
      await dao.saveBridge(
        const SavedBridge(
          id: 'bridge-a',
          name: 'Backyard Bridge',
          lastSeenMs: 1,
          generation: 7,
          cursorAfter: 9,
          cursorBefore: 0,
          deviceMinSeq: 0,
          deviceMaxSeq: 9,
        ),
      );
      await dao.insertSamples(<StoredSample>[
        for (var seq = 0; seq < 10; seq++)
          _sample(
            seq,
            seq < 5
                ? _ago(const Duration(days: 40))
                : _ago(const Duration(days: 2)),
            generation: 7,
          ),
      ]);

      final plan = await service.plan(HistoryDeletionScope.olderThan30Days);
      final outcome = await service.delete(plan);
      expect(outcome.samplesDeleted, 5);

      final saved = await dao.savedBridge();
      expect(saved!.cursorBefore, 5);
      expect(saved.cursorAfter, 9);
      expect(saved.deviceMaxSeq, 9);
    },
  );

  test('losing the current generation clears its cursors and keeps old segments', () async {
    await dao.saveBridge(
      const SavedBridge(
        id: 'bridge-a',
        name: 'Backyard Bridge',
        lastSeenMs: 1,
        generation: 8,
        cursorAfter: 3,
        cursorBefore: 0,
        deviceMinSeq: 0,
        deviceMaxSeq: 3,
      ),
    );
    await dao.insertSamples(<StoredSample>[
      // An older generation segment that is still readable after the deletion.
      _sample(0, _ago(const Duration(days: 2)), generation: 7),
      // The current generation's only row is old enough to delete.
      _sample(0, _ago(const Duration(days: 40)), generation: 8),
    ]);

    final plan = await service.plan(HistoryDeletionScope.olderThan30Days);
    expect(plan.count, 1);
    await service.delete(plan);

    final saved = await dao.savedBridge();
    expect(saved!.cursorBefore, isNull);
    expect(saved.cursorAfter, isNull);
    expect(saved.generation, 8);
    expect(await dao.countSamples(generation: 8), 0);
    expect(await dao.countSamples(generation: 7), 1);
  });
}
