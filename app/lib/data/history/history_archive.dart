import '../../domain/content.dart';
import '../../domain/cook_detection.dart';
import '../../domain/history_decimate.dart';
import '../../domain/models.dart';
import '../db/sample_dao.dart';

/// The data the durable archive can answer for one History window.
class HistoryArchiveData {
  const HistoryArchiveData({
    required this.fixture,
    required this.stats,
    required this.cooks,
    required this.hasAnyHistory,
    required this.entireHistory,
  });

  final HistoryFixture fixture;

  /// Four entries in P1–P4 order, computed by SQL over raw rows.
  final List<ProbeRangeStats> stats;
  final List<CookSession> cooks;
  final bool hasAnyHistory;
  final HistoryWindow entireHistory;
}

/// Read-only History queries over [SampleDao].
///
/// T42's contract: the chart is decimated and SQL-bucketed, Summary is exact,
/// and Cooks come from recorded timestamps and gap rows. Nothing here invents a
/// reading: a probe with no valid value stays `null` and SQL averages ignore
/// nulls instead of turning them into 0 °F.
class HistoryArchive {
  HistoryArchive({required this.dao, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SampleDao dao;
  final DateTime Function() _now;

  /// Raw rows above this count are bucketed in SQL before the chart decimates
  /// them. The cap keeps a 30-day archive to roughly one bucket per 36 minutes
  /// instead of 86,400 rows.
  static const int maxRawRows = 4000;

  /// LTTB target per series. A phone chart is ~400 dp wide, so 2 points per
  /// pixel is the contract; 800 leaves room for a wide tablet without ever
  /// handing the painter tens of thousands of points.
  static const int chartPointTarget = 800;

  /// Cook activity scan bucket. Long enough to stay cheap over a month of
  /// readings, short enough that a normal cook is a contiguous run.
  static const Duration cookActivityBucket = Duration(minutes: 5);

  Future<HistoryArchiveData> load({
    required HistoryRange range,
    DateTime? customStart,
    DateTime? customEnd,
    bool empty = false,
    bool includeCooks = true,
  }) async {
    final now = _now();
    final extent = await dao.extent();
    final hasAnyHistory = !empty && extent != null && extent.count > 0;
    if (extent == null) {
      final window = _window(range, now, customStart, customEnd, null);
      return HistoryArchiveData(
        fixture: _emptyFixture(window.$1, window.$2),
        stats: _emptyStats(),
        cooks: const <CookSession>[],
        hasAnyHistory: false,
        entireHistory: HistoryWindow(start: window.$1, end: window.$2),
      );
    }

    final entire = (
      DateTime.fromMillisecondsSinceEpoch(extent.minRecordedMs),
      DateTime.fromMillisecondsSinceEpoch(extent.maxRecordedMs),
    );
    final window = _window(range, now, customStart, customEnd, entire);
    final startMs = window.$1.millisecondsSinceEpoch;
    // Ranges are inclusive at the chosen end minute, while the DAO contract is
    // half-open. One millisecond keeps an exact end reading visible.
    final endMs = window.$2.millisecondsSinceEpoch + 1;

    if (!hasAnyHistory) {
      return HistoryArchiveData(
        fixture: _emptyFixture(window.$1, window.$2),
        stats: _emptyStats(),
        cooks: const <CookSession>[],
        hasAnyHistory: false,
        entireHistory: HistoryWindow(start: entire.$1, end: entire.$2),
      );
    }

    final count = await dao.countSamples(fromMs: startMs, toMs: endMs);
    final loaded = await _loadSeriesRows(
      fromMs: startMs,
      toMs: endMs,
      count: count,
    );
    final rows = loaded.rows;
    final stats = await _loadStats(fromMs: startMs, toMs: endMs);
    final gapRows = await dao.gapsInRange(fromMs: startMs, toMs: endMs);
    final bands = _gapBands(
      gapRows,
      rows,
      startMs,
      endMs,
      maxDelta: loaded.maxDelta,
    );
    final estimated = rows.any((row) => row.estimated);

    final series = <ChartSeries>[
      for (var probe = 0; probe < 4; probe++)
        ChartSeries(
          probe,
          decimateHistorySeries(
            <ChartPoint>[
              for (final row in rows)
                ChartPoint(
                  DateTime.fromMillisecondsSinceEpoch(row.recordedMs),
                  row.tempsF[probe],
                ),
            ],
            threshold: chartPointTarget,
            maxDelta: loaded.maxDelta,
          ),
        ),
    ];

    final cooks = includeCooks
        ? await _loadCooks(extent: extent)
        : const <CookSession>[];

    final missing = bands.any(
      (band) => band.reason == HistoryGapReason.bridgeRotated,
    );

    return HistoryArchiveData(
      fixture: HistoryFixture(
        start: window.$1,
        end: window.$2,
        series: series,
        gapStart: bands.isEmpty ? window.$1 : bands.first.start,
        gapEnd: bands.isEmpty ? window.$1 : bands.first.end,
        gapReason: bands.isEmpty
            ? HistoryGapReason.noSignal
            : bands.first.reason,
        bands: bands,
        estimated: estimated,
        missingFromBridge: missing,
        decimated: true,
      ),
      stats: stats,
      cooks: cooks,
      hasAnyHistory: true,
      entireHistory: HistoryWindow(start: entire.$1, end: entire.$2),
    );
  }

  Future<_SeriesRows> _loadSeriesRows({
    required int fromMs,
    required int toMs,
    required int count,
  }) async {
    if (count == 0) {
      return const _SeriesRows(rows: <_SeriesRow>[], maxDelta: historyGapThreshold);
    }
    if (count <= maxRawRows) {
      final samples = await dao.samplesInRange(fromMs: fromMs, toMs: toMs);
      return _SeriesRows(
        rows: <_SeriesRow>[
          for (final sample in samples)
            _SeriesRow(
              recordedMs: sample.recordedMs,
              tempsF: <double?>[
                for (final tenths in sample.tempsF10)
                  tenths == null ? null : tenths / 10.0,
              ],
              estimated: sample.timeEstimated != 0,
            ),
        ],
        maxDelta: historyGapThreshold,
      );
    }
    // One bucket per ~1,200 points; LTTB then thins to the pixel budget.
    final span = toMs - fromMs;
    final bucketMs = (span / 1200).ceil().clamp(1000, span);
    final buckets = await dao.bucketedSamplesInRange(
      fromMs: fromMs,
      toMs: toMs,
      bucketMs: bucketMs,
    );
    return _SeriesRows(
      rows: <_SeriesRow>[
        for (final bucket in buckets)
          _SeriesRow(
            recordedMs: bucket.recordedMs,
            tempsF: bucket.tempsF,
            estimated: bucket.estimated,
          ),
      ],
      // Bucket spacing is deliberately wider than 90 s; a real hole remains a
      // hole only when it spans more than two buckets.
      maxDelta: Duration(milliseconds: bucketMs * 2),
    );
  }

  Future<List<ProbeRangeStats>> _loadStats({
    required int fromMs,
    required int toMs,
  }) async {
    final rows = await dao.probeStatsInRange(fromMs: fromMs, toMs: toMs);
    return <ProbeRangeStats>[
      for (final row in rows)
        ProbeRangeStats(
          probe: row.probe,
          first: row.minF,
          last: row.latestF,
          min: row.minF,
          max: row.maxF,
          average: null,
          readingCount: row.readingCount,
          lastSampleAt: row.latestMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.latestMs!),
        ),
    ];
  }

  Future<List<CookSession>> _loadCooks({required SampleExtent extent}) async {
    final activityRows = await dao.bucketedSamplesInRange(
      fromMs: extent.minRecordedMs,
      toMs: extent.maxRecordedMs + 1,
      bucketMs: cookActivityBucket.inMilliseconds,
    );
    final activity = <CookActivity>[
      for (final row in activityRows)
        CookActivity(
          start: DateTime.fromMillisecondsSinceEpoch(row.startMs),
          end: DateTime.fromMillisecondsSinceEpoch(row.recordedMs),
          probes: row.tempsF.where((value) => value != null).length,
        ),
    ];
    final gapRows = await dao.gapsInRange(
      fromMs: extent.minRecordedMs,
      toMs: extent.maxRecordedMs + 1,
    );
    final gapSpans = <({DateTime start, DateTime end})>[
      for (final gap in gapRows)
        (
          start: DateTime.fromMillisecondsSinceEpoch(gap.detectedMs),
          end: DateTime.fromMillisecondsSinceEpoch(
            gap.detectedMs + const Duration(minutes: 2).inMilliseconds,
          ),
        ),
    ];
    return const CookDetection().detect(activity, gapSpans: gapSpans);
  }

  List<HistoryGapBand> _gapBands(
    List<StoredGap> gaps,
    List<_SeriesRow> rows,
    int startMs,
    int endMs, {
    required Duration maxDelta,
  }) {
    final bands = <HistoryGapBand>[];
    for (final gap in gaps) {
      if (gap.detectedMs < startMs || gap.detectedMs >= endMs) continue;
      final detected = gap.detectedMs;
      int? before;
      int? after;
      for (final row in rows) {
        if (row.recordedMs <= detected) {
          before = row.recordedMs;
        } else {
          after = row.recordedMs;
          break;
        }
      }
      final bandStart = before ?? detected;
      var bandEnd = after ?? detected + const Duration(minutes: 2).inMilliseconds;
      if (bandEnd - bandStart < const Duration(minutes: 2).inMilliseconds) {
        bandEnd = bandStart + const Duration(minutes: 2).inMilliseconds;
      }
      if (bandEnd > endMs) bandEnd = endMs;
      if (bandEnd <= bandStart) continue;
      bands.add(
        HistoryGapBand(
          start: DateTime.fromMillisecondsSinceEpoch(bandStart),
          end: DateTime.fromMillisecondsSinceEpoch(bandEnd),
          reason: _reason(gap.reason),
        ),
      );
    }

    // The painter always breaks the line at a real hole. Label those holes too;
    // the tolerance comes from the row source (90 s raw, wider for SQL
    // buckets) so bucket spacing is never mistaken for lost readings.
    for (var i = 1; i < rows.length; i++) {
      final previous = rows[i - 1].recordedMs;
      final current = rows[i].recordedMs;
      if (current - previous <= maxDelta.inMilliseconds) continue;
      final overlaps = bands.any(
        (band) =>
            band.start.millisecondsSinceEpoch <= current &&
            band.end.millisecondsSinceEpoch >= previous,
      );
      if (overlaps) continue;
      bands.add(
        HistoryGapBand(
          start: DateTime.fromMillisecondsSinceEpoch(previous),
          end: DateTime.fromMillisecondsSinceEpoch(current),
          reason: HistoryGapReason.noSignal,
        ),
      );
    }

    bands.sort((a, b) => a.start.compareTo(b.start));
    // Keep the painter cheap even after a month of holes.
    return bands.take(24).toList(growable: false);
  }

  HistoryGapReason _reason(String reason) {
    final normalized = reason.toLowerCase();
    if (normalized.contains('not synced') ||
        normalized.contains('overwrit') ||
        normalized.contains('rotat')) {
      return HistoryGapReason.bridgeRotated;
    }
    if (normalized.contains('off')) return HistoryGapReason.bridgeOff;
    return HistoryGapReason.noSignal;
  }

  (DateTime, DateTime) _window(
    HistoryRange range,
    DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
    (DateTime, DateTime)? entire,
  ) {
    if (range == HistoryRange.custom) {
      var start =
          customStart ?? entire?.$1 ?? now.subtract(const Duration(hours: 24));
      var end = customEnd ?? entire?.$2 ?? now;
      if (end.isBefore(start)) {
        final swap = start;
        start = end;
        end = swap;
      }
      if (!end.isAfter(start)) {
        end = start.add(const Duration(minutes: 1));
      }
      return (start, end);
    }
    final span = switch (range) {
      HistoryRange.oneHour => const Duration(hours: 1),
      HistoryRange.sixHours => const Duration(hours: 6),
      HistoryRange.twentyFourHours => const Duration(hours: 24),
      HistoryRange.twoDays => const Duration(days: 2),
      HistoryRange.custom => const Duration(hours: 24),
    };
    return (now.subtract(span), now);
  }

  HistoryFixture _emptyFixture(DateTime start, DateTime end) {
    return HistoryFixture(
      start: start,
      end: end,
      series: const <ChartSeries>[
        ChartSeries(0, <ChartPoint>[]),
        ChartSeries(1, <ChartPoint>[]),
        ChartSeries(2, <ChartPoint>[]),
        ChartSeries(3, <ChartPoint>[]),
      ],
      gapStart: start,
      gapEnd: start,
      gapReason: HistoryGapReason.noSignal,
      estimated: false,
      missingFromBridge: false,
    );
  }

  List<ProbeRangeStats> _emptyStats() => <ProbeRangeStats>[
    for (var probe = 1; probe <= 4; probe++)
      ProbeRangeStats(
        probe: probe,
        first: null,
        last: null,
        min: null,
        max: null,
        average: null,
        readingCount: 0,
        lastSampleAt: null,
      ),
  ];
}

class _SeriesRow {
  const _SeriesRow({
    required this.recordedMs,
    required this.tempsF,
    required this.estimated,
  });

  final int recordedMs;
  final List<double?> tempsF;
  final bool estimated;
}

class _SeriesRows {
  const _SeriesRows({required this.rows, required this.maxDelta});

  final List<_SeriesRow> rows;

  /// Adjacent rows further apart than this are a real hole. Raw rows use the
  /// shared 90 s rule; SQL buckets use twice the bucket width.
  final Duration maxDelta;
}
