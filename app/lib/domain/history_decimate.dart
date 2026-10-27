import 'dart:math' as math;

import 'models.dart';

/// Largest-Triangle-Three-Buckets decimation with a min/max envelope.
///
/// The archive can hold tens of thousands of readings per probe. A chart never
/// needs more than roughly two points per horizontal pixel, but dropping points
/// by stride loses spikes. This helper keeps the LTTB shape and then adds the
/// lowest and highest real point of each decimation bucket, so a hot spike is
/// never hidden between two sampled points.
///
/// `null` values are preserved verbatim: they are the app's honest "no
/// reading" marker and must keep breaking the line. The output is therefore
/// safe to pass straight to [historySeriesSegments].
List<ChartPoint> decimateHistorySeries(
  List<ChartPoint> points, {
  int threshold = 800,
  Duration maxDelta = historyGapThreshold,
}) {
  if (points.isEmpty) return const <ChartPoint>[];
  if (threshold < 4) threshold = 4;

  final output = <ChartPoint>[];
  var run = <ChartPoint>[];
  DateTime? previousTime;
  var nullPending = false;

  void flushRun() {
    if (run.isEmpty) return;
    output.addAll(_decimateRun(run, threshold));
    run = <ChartPoint>[];
  }

  void markGap() {
    if (run.isNotEmpty) {
      flushRun();
    }
    if (!nullPending && output.isNotEmpty) {
      output.add(ChartPoint(previousTime ?? DateTime.now(), null));
      nullPending = true;
    }
  }

  for (final point in points) {
    if (point.valueF == null) {
      markGap();
      continue;
    }
    if (previousTime != null &&
        point.time.difference(previousTime) > maxDelta) {
      markGap();
    }
    nullPending = false;
    run.add(point);
    previousTime = point.time;
  }
  flushRun();
  return output;
}

List<ChartPoint> _decimateRun(List<ChartPoint> run, int threshold) {
  if (run.length <= threshold) return run;

  final sampled = _lttb(run, threshold);
  final envelope = _minMaxEnvelope(run, threshold);
  final merged = <int, ChartPoint>{};
  for (final point in sampled) {
    merged[point.time.microsecondsSinceEpoch] = point;
  }
  for (final point in envelope) {
    merged.putIfAbsent(point.time.microsecondsSinceEpoch, () => point);
  }
  final result = merged.values.toList(growable: false);
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

/// Standard LTTB. `data` is non-empty and contains only real values.
List<ChartPoint> _lttb(List<ChartPoint> data, int threshold) {
  final n = data.length;
  if (threshold >= n || threshold < 3) return data;

  final sampled = <ChartPoint>[data.first];
  final bucketSize = (n - 2) / (threshold - 2);
  var a = 0;

  for (var i = 0; i < threshold - 2; i++) {
    final rangeStart = ((i + 1) * bucketSize).floor() + 1;
    final rangeEnd = math.min(
      ((i + 2) * bucketSize).floor() + 1,
      n,
    );
    final nextStart = rangeStart;
    final nextEnd = math.min(rangeEnd, n);
    var avgX = 0.0;
    var avgY = 0.0;
    final nextCount = nextEnd - nextStart;
    if (nextCount > 0) {
      for (var j = nextStart; j < nextEnd; j++) {
        avgX += data[j].time.microsecondsSinceEpoch / 1000.0;
        avgY += data[j].valueF!;
      }
      avgX /= nextCount;
      avgY /= nextCount;
    } else {
      avgX = data[n - 1].time.microsecondsSinceEpoch / 1000.0;
      avgY = data[n - 1].valueF!;
    }

    final from = (i * bucketSize).floor() + 1;
    final to = math.min(((i + 1) * bucketSize).floor() + 1, n - 1);
    final aX = data[a].time.microsecondsSinceEpoch / 1000.0;
    final aY = data[a].valueF!;
    var maxArea = -1.0;
    var nextA = from;
    for (var j = from; j < to; j++) {
      final area =
          ((aX - avgX) * (data[j].valueF! - aY) -
                  (aX - data[j].time.microsecondsSinceEpoch / 1000.0) *
                      (avgY - aY))
              .abs();
      if (area > maxArea) {
        maxArea = area;
        nextA = j;
      }
    }
    sampled.add(data[nextA]);
    a = nextA;
  }

  sampled.add(data.last);
  return sampled;
}

/// The lowest and highest real point in every bucket. At most two extra
/// points per bucket, which keeps the envelope honest without doubling the
/// whole series.
List<ChartPoint> _minMaxEnvelope(List<ChartPoint> data, int threshold) {
  final buckets = math.max(1, threshold ~/ 3);
  final size = data.length / buckets;
  final envelope = <ChartPoint>[];
  for (var bucket = 0; bucket < buckets; bucket++) {
    final from = (bucket * size).floor();
    final to = math.min(data.length, ((bucket + 1) * size).ceil());
    if (to <= from) continue;
    ChartPoint lowest = data[from];
    ChartPoint highest = data[from];
    for (var i = from + 1; i < to; i++) {
      final value = data[i].valueF!;
      if (value < lowest.valueF!) lowest = data[i];
      if (value > highest.valueF!) highest = data[i];
    }
    envelope.add(lowest);
    if (!identical(lowest, highest)) envelope.add(highest);
  }
  return envelope;
}
