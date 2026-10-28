import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/data/history/history_archive.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/domain/cook_detection.dart';
import 'package:smoke_bridge/domain/history_decimate.dart';

final DateTime _now = DateTime(2026, 10, 27, 12);

class _FixedContent implements BridgeContent {
  const _FixedContent();

  @override
  DateTime get now => _now;

  @override
  List<double?> get probeTemps => const <double?>[null, null, null, null];

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: _now.subtract(const Duration(days: 30)), end: _now);

  @override
  int get bridgeRecords => 0;

  @override
  int get bridgeCapacity => 0;

  @override
  int get phoneRecords => 0;

  @override
  String get savedDataRange => '—';

  @override
  String get savedDataSize => '0 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) => const [];

  @override
  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    throw UnsupportedError('archive tests never use the fixture path');
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}

StoredSample _sample(
  DateTime time, {
  int seq = 0,
  double? p1 = 225,
  double? p2 = 165,
  double? p3,
  double? p4 = 180,
  int estimated = 0,
}) {
  int? tenths(double? value) => value == null ? null : (value * 10).round();
  return StoredSample(
    bridgeId: 'bridge-a',
    generation: 1,
    seq: seq,
    unixS: time.millisecondsSinceEpoch ~/ 1000,
    recordedMs: time.millisecondsSinceEpoch,
    timeEstimated: estimated,
    tempsF10: <int?>[tenths(p1), tenths(p2), tenths(p3), tenths(p4)],
    flags: 0x1F,
  );
}

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

  test(
    '30-day four-series archive renders a bounded chart with exact summary',
    () async {
      final samples = <StoredSample>[];
      const spanMinutes = 30 * 24 * 60;
      for (var minute = 0; minute < spanMinutes; minute++) {
        final time = _now.subtract(Duration(minutes: spanMinutes - minute));
        final wave = 20 + 4 * ((minute % 120) / 120);
        samples.add(
          _sample(
            time,
            seq: minute,
            p1: 225 + wave,
            p2: 165 + wave / 2,
            p4: null,
          ),
        );
      }
      await dao.insertSamples(samples);

      final archive = HistoryArchive(dao: dao, now: () => _now);
      final stopwatch = Stopwatch()..start();
      final data = await archive.load(range: HistoryRange.twoDays);
      stopwatch.stop();

      expect(data.hasAnyHistory, isTrue);
      expect(data.fixture.series, hasLength(4));
      for (final series in data.fixture.series) {
        expect(
          series.points.length,
          lessThanOrEqualTo(HistoryArchive.chartPointTarget * 2 + 2),
          reason: 'P${series.index + 1} handed the painter too many points',
        );
      }
      // A probe that never reported stays empty; no fabricated zero line.
      expect(historySeriesSegments(data.fixture.series[2]), isEmpty);
      expect(data.stats[2].last, isNull);
      expect(data.stats[2].min, isNull);
      expect(data.stats[2].max, isNull);
      // P4 was always detached too.
      expect(data.stats[3].last, isNull);

      // Summary uses exact raw SQL values, not the decimated chart shape.
      expect(data.stats[0].last, closeTo(225 + 20 + 4 * (119 / 120), 0.15));
      expect(data.stats[0].min, 245.0);
      expect(data.stats[0].max, 249.0);
      expect(data.stats[1].last, isNotNull);
      expect(data.fixture.estimated, isFalse);
      for (final point in data.fixture.series[0].points) {
        if (point.valueF == null) continue;
        expect(point.valueF, inInclusiveRange(240, 255));
      }
      // SQL bucketing keeps this query off the full raw row set.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    },
  );

  test(
    'custom range across all saved history still bounds chart points',
    () async {
      final samples = <StoredSample>[];
      for (var i = 0; i < 7200; i++) {
        samples.add(
          _sample(_now.subtract(Duration(seconds: (7200 - i) * 30)), seq: i),
        );
      }
      await dao.insertSamples(samples);
      final archive = HistoryArchive(dao: dao, now: () => _now);
      final extent = await dao.extent();
      final data = await archive.load(
        range: HistoryRange.custom,
        customStart: DateTime.fromMillisecondsSinceEpoch(extent!.minRecordedMs),
        customEnd: DateTime.fromMillisecondsSinceEpoch(
          extent.maxRecordedMs + 1000,
        ),
      );
      expect(data.hasAnyHistory, isTrue);
      expect(data.fixture.series[0].points.length, lessThanOrEqualTo(1602));
      expect(data.stats[0].readingCount, 7200);
    },
  );

  test(
    'gaps keep their reason, split the line and report estimated times',
    () async {
      final start = _now.subtract(const Duration(minutes: 40));
      final samples = <StoredSample>[];
      for (var second = 0; second <= 40 * 60; second += 30) {
        // A ten-minute hole in the middle of the hour.
        if (second > 12 * 60 && second < 22 * 60) continue;
        samples.add(
          _sample(
            start.add(Duration(seconds: second)),
            seq: second,
            estimated: second > 30 * 60 ? 1 : 0,
          ),
        );
      }
      await dao.insertSamples(samples);
      final holeAt = start.add(const Duration(minutes: 16));
      await dao.insertGaps(<StoredGap>[
        StoredGap(
          bridgeId: 'bridge-a',
          generation: 1,
          fromSeq: 24 * 2,
          toSeq: 44 * 2,
          reason: 'Not synced',
          detectedMs: holeAt.millisecondsSinceEpoch,
        ),
      ]);

      final archive = HistoryArchive(dao: dao, now: () => _now);
      final data = await archive.load(range: HistoryRange.oneHour);
      expect(data.fixture.allGaps, isNotEmpty);
      expect(
        data.fixture.allGaps.any(
          (gap) => gap.reason == HistoryGapReason.bridgeRotated,
        ),
        isTrue,
      );
      expect(data.fixture.missingFromBridge, isTrue);
      expect(data.fixture.estimated, isTrue);
      // The painter must have more than one run because of the hole.
      expect(
        historySeriesSegments(
          data.fixture.series[0],
          maxDelta: const Duration(days: 3650),
        ).length,
        greaterThan(1),
      );
    },
  );

  test('a stored gap is drawn over the missing sequences, not at detection '
      'time', () async {
    final start = _now.subtract(const Duration(hours: 2));
    final samples = <StoredSample>[];
    var seq = 0;
    // 59.5 min of readings, a 20 min hole, then 40 min of readings.
    for (var second = 0; second < 60 * 60; second += 30) {
      samples.add(_sample(start.add(Duration(seconds: second)), seq: seq++));
    }
    final before = samples.last;
    final missingFrom = seq;
    seq += 40; // the 20-minute hole at 30 s cadence
    final resumeAt = start.add(const Duration(minutes: 80));
    for (var second = 0; second < 40 * 60; second += 30) {
      samples.add(_sample(resumeAt.add(Duration(seconds: second)), seq: seq++));
    }
    final after = samples.firstWhere(
      (row) => row.recordedMs >= resumeAt.millisecondsSinceEpoch,
    );
    await dao.insertSamples(samples);
    await dao.insertGaps(<StoredGap>[
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: missingFrom,
        toSeq: missingFrom + 39,
        reason: 'Not synced',
        // Deliberately the end of the run: the app learned about the loss much
        // later than the missing period itself.
        detectedMs: _now.millisecondsSinceEpoch,
      ),
    ]);

    final archive = HistoryArchive(dao: dao, now: () => _now);
    final data = await archive.load(
      range: HistoryRange.custom,
      customStart: start,
      customEnd: _now,
    );
    final loss = data.fixture.allGaps.firstWhere(
      (band) => band.reason == HistoryGapReason.bridgeRotated,
    );
    expect(loss.start, DateTime.fromMillisecondsSinceEpoch(before.recordedMs));
    expect(loss.end, DateTime.fromMillisecondsSinceEpoch(after.recordedMs));
    expect(
      loss.end,
      isNot(DateTime.fromMillisecondsSinceEpoch(_now.millisecondsSinceEpoch)),
    );
    expect(data.fixture.missingFromBridge, isTrue);
  });

  test(
    'an inferred hole becomes a No signal band and is not permanent loss',
    () async {
      final start = _now.subtract(const Duration(hours: 1));
      final samples = <StoredSample>[];
      var seq = 0;
      for (var second = 0; second < 20 * 60; second += 30) {
        samples.add(_sample(start.add(Duration(seconds: second)), seq: seq++));
      }
      final before = samples.last;
      final resumeAt = start.add(const Duration(minutes: 30));
      for (var second = 0; second < 20 * 60; second += 30) {
        samples.add(
          _sample(resumeAt.add(Duration(seconds: second)), seq: seq++),
        );
      }
      final after = samples.firstWhere(
        (row) => row.recordedMs >= resumeAt.millisecondsSinceEpoch,
      );
      await dao.insertSamples(samples);

      final archive = HistoryArchive(dao: dao, now: () => _now);
      final data = await archive.load(range: HistoryRange.oneHour);
      final hole = data.fixture.allGaps.firstWhere(
        (band) => band.reason == HistoryGapReason.noSignal,
      );
      expect(
        hole.start,
        DateTime.fromMillisecondsSinceEpoch(before.recordedMs),
      );
      expect(hole.end, DateTime.fromMillisecondsSinceEpoch(after.recordedMs));
      expect(data.fixture.missingFromBridge, isFalse);
    },
  );

  test('the permanent-loss banner follows the visible range', () async {
    final start = _now.subtract(const Duration(days: 2, hours: 2));
    final samples = <StoredSample>[];
    var seq = 0;
    for (var second = 0; second < 60 * 60; second += 30) {
      samples.add(_sample(start.add(Duration(seconds: second)), seq: seq++));
    }
    final before = samples.last;
    seq += 40;
    final resumeAt = start.add(const Duration(minutes: 80));
    for (var second = 0; second < 20 * 60; second += 30) {
      samples.add(_sample(resumeAt.add(Duration(seconds: second)), seq: seq++));
    }
    await dao.insertSamples(samples);
    await dao.insertGaps(<StoredGap>[
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 120,
        toSeq: 159,
        reason: 'Not synced',
        detectedMs: _now.millisecondsSinceEpoch,
      ),
    ]);
    final archive = HistoryArchive(dao: dao, now: () => _now);

    // Last hour has no readings and no loss; the old archive-wide flag must not
    // raise the permanent-loss banner here.
    final recent = await archive.load(range: HistoryRange.oneHour);
    expect(recent.fixture.missingFromBridge, isFalse);
    expect(recent.fixture.allGaps, isEmpty);

    final whole = await archive.load(
      range: HistoryRange.custom,
      customStart: start,
      customEnd: start.add(const Duration(hours: 2)),
    );
    expect(whole.fixture.missingFromBridge, isTrue);
    final loss = whole.fixture.allGaps.firstWhere(
      (band) => band.reason == HistoryGapReason.bridgeRotated,
    );
    expect(loss.start, DateTime.fromMillisecondsSinceEpoch(before.recordedMs));
    expect(
      loss.end,
      DateTime.fromMillisecondsSinceEpoch(resumeAt.millisecondsSinceEpoch),
    );
  });

  test(
    'cooks are scoped to the visible range and never span a full ring',
    () async {
      final start = _now.subtract(const Duration(days: 3));
      final samples = <StoredSample>[];
      var seq = 0;
      for (var second = 0; second < 3 * 24 * 60 * 60; second += 300) {
        samples.add(_sample(start.add(Duration(seconds: second)), seq: seq++));
      }
      await dao.insertSamples(samples);
      final archive = HistoryArchive(dao: dao, now: () => _now);

      final day = await archive.load(range: HistoryRange.twentyFourHours);
      expect(day.cooks, isNotEmpty);
      for (final cook in day.cooks) {
        expect(cook.duration, lessThanOrEqualTo(const Duration(hours: 24)));
      }

      final entire = await archive.load(
        range: HistoryRange.custom,
        customStart: start,
        customEnd: _now,
      );
      expect(entire.cooks, hasLength(1));
      expect(
        entire.cooks.single.duration,
        greaterThan(const Duration(days: 2)),
      );
    },
  );

  test(
    'Since cook start is unavailable when the visible range has no cook',
    () async {
      final start = _now.subtract(const Duration(hours: 5));
      await dao.insertSamples(<StoredSample>[
        for (var second = 0; second < 2 * 60 * 60; second += 300)
          _sample(start.add(Duration(seconds: second)), seq: second ~/ 300),
      ]);
      final controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      )..historyRange = HistoryRange.oneHour;
      addTearDown(controller.dispose);

      final view = await controller.loadHistoryView();
      expect(view.cooks, isEmpty);
      expect(view.cookReference, isNull);
    },
  );

  test('cooks are detected from recorded timestamps with exact ends', () async {
    final samples = <StoredSample>[];
    // Two cooks separated by a long idle period.
    final firstStart = _now.subtract(const Duration(hours: 30));
    for (var second = 0; second <= 3 * 3600; second += 30) {
      samples.add(
        _sample(firstStart.add(Duration(seconds: second)), seq: second),
      );
    }
    final secondStart = _now.subtract(const Duration(hours: 5));
    for (var second = 0; second <= 2 * 3600; second += 30) {
      samples.add(
        _sample(
          secondStart.add(Duration(seconds: second)),
          seq: 100000 + second,
          p3: 150,
        ),
      );
    }
    await dao.insertSamples(samples);
    // A device gap inside the live cook marks it as missing readings.
    await dao.insertGaps(<StoredGap>[
      StoredGap(
        bridgeId: 'bridge-a',
        generation: 1,
        fromSeq: 100000 + 1800,
        toSeq: 100000 + 2400,
        reason: 'Not synced',
        detectedMs: secondStart
            .add(const Duration(minutes: 40))
            .millisecondsSinceEpoch,
      ),
    ]);

    final archive = HistoryArchive(dao: dao, now: () => _now);
    // Cooks are scoped to the visible range; both runs live inside two days but
    // the older one starts outside the last 24 hours.
    final data = await archive.load(range: HistoryRange.twoDays);
    expect(data.cooks, hasLength(2));
    final live = data.cooks.first;
    final older = data.cooks.last;
    expect(live.start, secondStart);
    expect(live.end, secondStart.add(const Duration(hours: 2)));
    expect(live.probes, 4);
    expect(live.hasGap, isTrue);
    expect(older.probes, 3);
    expect(older.hasGap, isFalse);
    expect(older.end, firstStart.add(const Duration(hours: 3)));
  });

  test(
    'controller loads the durable History view and respects the probe filter',
    () async {
      final start = _now.subtract(const Duration(minutes: 30));
      await dao.insertSamples(<StoredSample>[
        for (var i = 0; i <= 60; i++)
          _sample(start.add(Duration(seconds: i * 30)), seq: i, p3: 150),
      ]);
      final controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      );
      addTearDown(controller.dispose);

      final all = await controller.loadHistoryView();
      expect(all.noData, isFalse);
      expect(all.stats, hasLength(4));
      expect(all.probeMeta, '4 probes');

      controller.setHistoryProbe(3);
      final filtered = await controller.loadHistoryView();
      expect(filtered.stats, hasLength(1));
      expect(filtered.stats.single.probe, 3);
      expect(filtered.probeMeta, '1 probe');
      expect(filtered.fixture.seriesHasValues(2), isTrue);
    },
  );

  test('offline with no cache shows no archive values', () async {
    await dao.insertSamples(<StoredSample>[
      _sample(_now.subtract(const Duration(minutes: 5))),
    ]);
    final controller = BridgeController(
      content: const _FixedContent(),
      sampleDao: dao,
    )..phase = ConnectionPhase.offline;
    addTearDown(controller.dispose);
    controller.offlineCache = false;

    final view = await controller.loadHistoryView();
    expect(view.noData, isTrue);
    expect(view.fixture.hasValues, isFalse);
    expect(view.cooks, isEmpty);
  });

  test(
    'summary sorting uses exact recorded values and the live cook',
    () async {
      final start = _now.subtract(const Duration(hours: 2));
      await dao.insertSamples(<StoredSample>[
        for (var i = 0; i <= 240; i++)
          _sample(
            start.add(Duration(seconds: i * 30)),
            seq: i,
            p1: 300,
            p2: 200,
            p3: 100,
            p4: 250,
          ),
      ]);
      final controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      );
      addTearDown(controller.dispose);

      controller.setHistorySort(HistorySort.hottest);
      final hottest = await controller.loadHistoryView();
      expect(hottest.stats.first.probe, 1);
      expect(hottest.stats.map((stat) => stat.probe), <int>[1, 4, 2, 3]);

      controller.setHistorySort(HistorySort.highestMax);
      final highest = await controller.loadHistoryView();
      expect(highest.stats.first.probe, 1);

      controller.setHistorySort(HistorySort.sinceCookStart);
      final cookSort = await controller.loadHistoryView();
      expect(cookSort.cookReference, isNotNull);
      expect(cookSort.stats, hasLength(4));
      expect(cookSort.cookSortDetail, contains('Cooking for'));
    },
  );

  test('decimation keeps runs, endpoints and the min/max envelope', () {
    final start = DateTime(2026, 10, 1);
    final points = <ChartPoint>[];
    for (var i = 0; i < 12000; i++) {
      final value = i == 6000 ? 999.0 : 200 + (i % 100) / 10;
      points.add(ChartPoint(start.add(Duration(seconds: i * 30)), value));
    }
    points[3000] = ChartPoint(points[3000].time, null);
    final decimated = decimateHistorySeries(points, threshold: 200);
    expect(decimated.length, lessThan(800));
    expect(decimated.first.valueF, points.first.valueF);
    expect(decimated.last.valueF, points.last.valueF);
    expect(decimated.any((point) => point.valueF == null), isTrue);
    expect(decimated.any((point) => point.valueF == 999.0), isTrue);
    expect(
      historySeriesSegments(
        ChartSeries(0, decimated),
        maxDelta: const Duration(days: 3650),
      ),
      hasLength(2),
    );
    // Monotonic time is what the painter relies on.
    for (var i = 1; i < decimated.length; i++) {
      expect(decimated[i].time.isBefore(decimated[i - 1].time), isFalse);
    }
  });

  test('cook detection groups idle periods and ignores short runs', () {
    final base = DateTime(2026, 10, 1, 8);
    final cooks = const CookDetection().detect(<CookActivity>[
      CookActivity(
        start: base,
        end: base.add(const Duration(minutes: 30)),
        probes: 4,
      ),
      CookActivity(
        start: base.add(const Duration(hours: 2)),
        end: base.add(const Duration(hours: 2, minutes: 5)),
        probes: 3,
      ),
    ]);
    expect(cooks, hasLength(1));
    expect(cooks.single.start, base);
    expect(cooks.single.end, base.add(const Duration(minutes: 30)));
    expect(cooks.single.probes, 4);
  });
}
