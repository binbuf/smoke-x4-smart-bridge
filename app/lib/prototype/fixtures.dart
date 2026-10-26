import 'dart:math' as math;

import 'prototype_controller.dart';

class ChartPoint {
  const ChartPoint(this.time, this.valueF);

  final DateTime time;

  /// Null means "no reading". The prototype encodes graph gaps as nulls; the
  /// production chart will split at >90 s using the real sample cadence.
  final double? valueF;
}

class ChartSeries {
  const ChartSeries(this.index, this.points);

  final int index;
  final List<ChartPoint> points;
}

enum HistoryGapReason { noSignal, bridgeOff, bridgeRotated }

class HistoryFixture {
  const HistoryFixture({
    required this.start,
    required this.end,
    required this.series,
    required this.gapStart,
    required this.gapEnd,
    required this.gapReason,
    required this.estimated,
    required this.missingFromBridge,
  });

  final DateTime start;
  final DateTime end;
  final List<ChartSeries> series;
  final DateTime gapStart;
  final DateTime gapEnd;
  final HistoryGapReason gapReason;
  final bool estimated;
  final bool missingFromBridge;

  bool get hasValues =>
      series.any((item) => item.points.any((point) => point.valueF != null));

  bool seriesHasValues(int probe) =>
      series[probe].points.any((point) => point.valueF != null);
}

class ProbeRangeStats {
  const ProbeRangeStats({
    required this.probe,
    required this.first,
    required this.last,
    required this.min,
    required this.max,
    required this.average,
    required this.readingCount,
    required this.lastSampleAt,
  });

  final int probe;
  final double? first;
  final double? last;
  final double? min;
  final double? max;
  final double? average;
  final int readingCount;
  final DateTime? lastSampleAt;

  bool get hasData => last != null;

  double? get change {
    if (first == null || last == null) return null;
    return last! - first!;
  }

  static ProbeRangeStats fromSeries(ChartSeries series) {
    final values = <double>[];
    DateTime? lastAt;
    for (final point in series.points) {
      if (point.valueF == null) continue;
      values.add(point.valueF!);
      lastAt = point.time;
    }
    if (values.isEmpty) {
      return ProbeRangeStats(
        probe: series.index + 1,
        first: null,
        last: null,
        min: null,
        max: null,
        average: null,
        readingCount: 0,
        lastSampleAt: null,
      );
    }
    final total = values.fold<double>(0, (sum, value) => sum + value);
    return ProbeRangeStats(
      probe: series.index + 1,
      first: values.first,
      last: values.last,
      min: values.reduce(math.min),
      max: values.reduce(math.max),
      average: total / values.length,
      readingCount: values.length,
      lastSampleAt: lastAt,
    );
  }
}

HistoryFixture buildHistoryFixture(
  HistoryRange range, {
  bool empty = false,
  bool oneProbe = false,
  bool estimated = false,
  bool missingFromBridge = false,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final now = DateTime(2026, 10, 25, 18, 30);
  final Duration span;
  final int count;
  final double gapPosition;
  final double gapWidth;
  switch (range) {
    case HistoryRange.oneHour:
      span = const Duration(hours: 1);
      count = 60;
      gapPosition = 0.38;
      gapWidth = 0.08;
      break;
    case HistoryRange.sixHours:
      span = const Duration(hours: 6);
      count = 72;
      gapPosition = 0.46;
      gapWidth = 0.05;
      break;
    case HistoryRange.twentyFourHours:
      span = const Duration(hours: 24);
      count = 96;
      gapPosition = 0.52;
      gapWidth = 0.04;
      break;
    case HistoryRange.sevenDays:
      span = const Duration(days: 7);
      count = 84;
      gapPosition = 0.61;
      gapWidth = 0.04;
      break;
    case HistoryRange.all:
      span = const Duration(days: 44, hours: 6);
      count = 120;
      gapPosition = 0.24;
      gapWidth = 0.03;
      break;
    case HistoryRange.custom:
      final start = customStart ?? now.subtract(const Duration(hours: 24));
      final end = customEnd ?? now;
      span = end.difference(start).isNegative
          ? const Duration(hours: 24)
          : end.difference(start);
      count = (span.inMinutes ~/ 30).clamp(24, 240);
      gapPosition = 0.42;
      gapWidth = 0.04;
      break;
  }

  final start = range == HistoryRange.custom
      ? (customStart ?? now.subtract(span))
      : now.subtract(span);
  final end = range == HistoryRange.custom ? (customEnd ?? now) : now;
  final effectiveSpan = end.difference(start);
  final gapStart = start.add(
    Duration(
      milliseconds: (effectiveSpan.inMilliseconds * gapPosition).round(),
    ),
  );
  final gapEnd = start.add(
    Duration(
      milliseconds: (effectiveSpan.inMilliseconds * (gapPosition + gapWidth))
          .round(),
    ),
  );

  const bases = [165.0, 164.0, 151.0, 224.0];
  const amplitudes = [12.0, 10.0, 15.0, 18.0];

  final series = <ChartSeries>[];
  for (var probe = 0; probe < 4; probe++) {
    if (empty || (oneProbe && probe < 3)) {
      series.add(ChartSeries(probe, const []));
      continue;
    }
    final points = <ChartPoint>[];
    for (var i = 0; i <= count; i++) {
      final ratio = i / count;
      final time = start.add(
        Duration(milliseconds: (effectiveSpan.inMilliseconds * ratio).round()),
      );
      final inGap = time.isAfter(gapStart) && time.isBefore(gapEnd);
      final drift =
          (range == HistoryRange.all ||
              range == HistoryRange.sevenDays ||
              range == HistoryRange.custom)
          ? math.sin(ratio * math.pi * 2) * 4
          : 0.0;
      final value =
          bases[probe] +
          amplitudes[probe] * math.sin(ratio * math.pi * 4 + probe * 1.2) +
          math.sin(ratio * math.pi * 17 + probe) * 1.7 +
          drift;
      points.add(ChartPoint(time, inGap ? null : value));
    }
    series.add(ChartSeries(probe, points));
  }

  return HistoryFixture(
    start: start,
    end: end,
    series: series,
    gapStart: gapStart,
    gapEnd: gapEnd,
    gapReason: missingFromBridge
        ? HistoryGapReason.bridgeRotated
        : HistoryGapReason.noSignal,
    estimated: estimated,
    missingFromBridge: missingFromBridge,
  );
}

/// Sparklines use their own relative scale. They deliberately contain no axes
/// or labels; the tile supplies the range and the trend.
List<ChartPoint> buildSparklinePoints(
  int probe, {
  bool hasData = true,
  int count = 44,
}) {
  if (!hasData) return const [];
  final now = DateTime(2026, 10, 25, 18, 30);
  const span = Duration(hours: 1);
  const bases = [165.0, 164.0, 151.0, 224.0];
  const amplitudes = [4.0, 3.0, 5.0, 6.0];
  final start = now.subtract(span);
  return List<ChartPoint>.generate(count + 1, (index) {
    final ratio = index / count;
    final time = start.add(
      Duration(milliseconds: (span.inMilliseconds * ratio).round()),
    );
    final value =
        bases[probe] +
        amplitudes[probe] * math.sin(ratio * math.pi * 2.4 + probe * 0.8) +
        math.sin(ratio * math.pi * 11 + probe) * 1.1;
    return ChartPoint(time, value);
  });
}
