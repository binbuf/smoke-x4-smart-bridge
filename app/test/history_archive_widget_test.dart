import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/domain/history_decimate.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_chart.dart';

final DateTime _now = DateTime(2026, 10, 27, 12);

class _FixedContent implements BridgeContent {
  const _FixedContent();

  @override
  DateTime get now => _now;

  @override
  List<double?> get probeTemps => const <double?>[null, null, null, null];

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: _now.subtract(const Duration(hours: 2)), end: _now);

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
    throw UnsupportedError('the durable archive owns this test');
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}

/// Small read-only archive seam for the widget test. Every member the History
/// loader uses is real; everything else is intentionally unsupported.
class _FakeHistoryDao implements SampleDao {
  _FakeHistoryDao(this.samples);

  final List<StoredSample> samples;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used here');

  @override
  Future<SampleExtent?> extent({String? bridgeId, int? generation}) async {
    return SampleExtent(
      count: samples.length,
      minSeq: samples.first.seq,
      maxSeq: samples.last.seq,
      minRecordedMs: samples.first.recordedMs,
      maxRecordedMs: samples.last.recordedMs,
    );
  }

  @override
  Future<int> countSamples({
    String? bridgeId,
    int? generation,
    int? fromMs,
    int? toMs,
  }) async {
    return samples
        .where(
          (sample) =>
              (fromMs == null || sample.recordedMs >= fromMs) &&
              (toMs == null || sample.recordedMs < toMs),
        )
        .length;
  }

  @override
  Future<List<StoredSample>> samplesInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
    int? limit,
    bool ascending = true,
  }) async {
    return samples
        .where(
          (sample) =>
              sample.recordedMs >= fromMs && sample.recordedMs < toMs,
        )
        .toList(growable: false);
  }

  @override
  Future<List<HistoryProbeStatsRow>> probeStatsInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  }) async {
    final rows = <HistoryProbeStatsRow>[];
    for (var probe = 0; probe < 4; probe++) {
      final values = <(int, double)>[
        for (final sample in samples)
          if (sample.recordedMs >= fromMs &&
              sample.recordedMs < toMs &&
              sample.tempsF10[probe] != null)
            (sample.recordedMs, sample.tempsF10[probe]! / 10.0),
      ];
      rows.add(
        HistoryProbeStatsRow(
          probe: probe + 1,
          readingCount: values.length,
          latestF: values.isEmpty ? null : values.last.$2,
          latestMs: values.isEmpty ? null : values.last.$1,
          minF: values.isEmpty
              ? null
              : values.map((value) => value.$2).reduce((a, b) => a < b ? a : b),
          maxF: values.isEmpty
              ? null
              : values.map((value) => value.$2).reduce((a, b) => a > b ? a : b),
        ),
      );
    }
    return rows;
  }

  @override
  Future<List<HistoryBucketRow>> bucketedSamplesInRange({
    required int fromMs,
    required int toMs,
    required int bucketMs,
    String? bridgeId,
    int? generation,
  }) async {
    final buckets = <HistoryBucketRow>[];
    var index = 0;
    while (index < samples.length) {
      final first = samples[index];
      final bucket = first.recordedMs ~/ bucketMs;
      var end = index;
      while (end + 1 < samples.length &&
          samples[end + 1].recordedMs ~/ bucketMs == bucket) {
        end++;
      }
      final lasts = samples[end];
      buckets.add(
        HistoryBucketRow(
          startMs: first.recordedMs,
          recordedMs: lasts.recordedMs,
          tempsF: <double?>[
            for (var probe = 0; probe < 4; probe++)
              lasts.tempsF10[probe] == null
                  ? null
                  : lasts.tempsF10[probe]! / 10.0,
          ],
          estimated: lasts.timeEstimated != 0,
        ),
      );
      index = end + 1;
    }
    return buckets;
  }

  @override
  Future<List<StoredGap>> gapsInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  }) async => const <StoredGap>[];
}

StoredSample _sample(DateTime time, int seq, {double? p3}) {
  return StoredSample(
    bridgeId: 'bridge-a',
    generation: 1,
    seq: seq,
    unixS: time.millisecondsSinceEpoch ~/ 1000,
    recordedMs: time.millisecondsSinceEpoch,
    timeEstimated: 0,
    tempsF10: <int?>[2250, 1650, p3 == null ? null : (p3 * 10).round(), 1800],
    flags: 0x1F,
  );
}

void main() {
  testWidgets('the durable archive feeds the approved History screen', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(320 * 3.0, 844.0 * 3.0);

    final start = _now.subtract(const Duration(hours: 1));
    final samples = <StoredSample>[
      for (var i = 0; i <= 120; i++)
        _sample(start.add(Duration(seconds: i * 30)), i, p3: 150),
    ];
    final controller = BridgeController(
      content: const _FixedContent(),
      sampleDao: _FakeHistoryDao(samples),
    )..tab = AppTab.history;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('history.chart')), findsOneWidget);
    expect(find.byType(HistoryChart), findsOneWidget);
    expect(find.byKey(const Key('history.summary')), findsOneWidget);
    expect(find.byKey(const Key('history.cooks')), findsOneWidget);
    expect(find.text('4 probes'), findsOneWidget);
    expect(find.text('No data'), findsNothing);
    expect(find.text('Cooks'), findsOneWidget);
    expect(
      find.text('Grouped automatically from your readings'),
      findsOneWidget,
    );

    // A detected Cook opens its own recorded view without touching the
    // History range or viewport.
    await tester.ensureVisible(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Cook'), findsOneWidget);
    expect(find.text('Recorded history'), findsOneWidget);
    expect(controller.historyRange, HistoryRange.twentyFourHours);
    expect(controller.historyCustomRange, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history.chart')), findsOneWidget);
    expect(controller.historyRange, HistoryRange.twentyFourHours);
  });

  testWidgets('a probe with no readings is disabled with No data', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(320 * 3.0, 844.0 * 3.0);

    final start = _now.subtract(const Duration(hours: 1));
    final samples = <StoredSample>[
      for (var i = 0; i <= 120; i++)
        _sample(start.add(Duration(seconds: i * 30)), i),
    ];
    final controller = BridgeController(
      content: const _FixedContent(),
      sampleDao: _FakeHistoryDao(samples),
    )..tab = AppTab.history;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history.filter.menu')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('history.filter.p3')),
        matching: find.text('No data'),
      ),
      findsOneWidget,
    );
    final p3 = tester.widget<PopupMenuItem<int>>(
      find.byKey(const Key('history.filter.p3')),
    );
    expect(p3.enabled, isFalse);
    final p1 = tester.widget<PopupMenuItem<int>>(
      find.byKey(const Key('history.filter.p1')),
    );
    expect(p1.enabled, isTrue);
  });

  testWidgets('30-day decimation stays inside a frame-sized budget', (
    tester,
  ) async {
    final start = DateTime(2026, 9, 27);
    final points = <ChartPoint>[
      for (var i = 0; i < 86400; i++)
        ChartPoint(
          start.add(Duration(seconds: i * 30)),
          200 + 30 * (i % 600) / 600,
        ),
    ];
    final stopwatch = Stopwatch()..start();
    final result = decimateHistorySeries(points, threshold: 800);
    stopwatch.stop();
    expect(result.length, lessThanOrEqualTo(1602));
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });
}
