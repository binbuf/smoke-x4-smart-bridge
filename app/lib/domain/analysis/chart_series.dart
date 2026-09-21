/// N1.14 — the chart series builder.
///
/// All the work happens before a chart library ever sees the data: window
/// slice, per-probe extraction, run splitting at gaps, per-run LTTB and the
/// min/max envelope for very wide ranges.
///
/// Three invariants this file holds:
///
///  * **Detached probes produce no points at all — never a zero (I3).**
///  * **Gaps are gaps.** Runs separated by a `t` delta over the cadence become
///    separate runs; a 30-minute dropout must look like one. Decimation across
///    a gap would let LTTB quietly reintroduce the straight line we split to
///    avoid, so splitting happens **before** decimation.
///  * **Decimation preserves the envelope.** LTTB, not stride.
library;

import '../entities/gap.dart';
import '../entities/probe.dart';
import '../entities/sample.dart';
import 'lttb.dart';
import 'series.dart';

/// The reading for [jack] in [sample], or null when the jack was detached.
/// There is deliberately no "or 0" fallback.
int? probeValue(Sample sample, ProbeJack jack) => sample.tempFor(jack);

/// One unbroken run of a probe's series. The renderer draws separate segments
/// for separate runs.
class SeriesRun {
  const SeriesRun(this.points);

  /// Ordered by `t`; never empty.
  final List<ValuePoint> points;

  int get fromT => points.first.t;
  int get toT => points.last.t;
}

/// The min/max band for one bucket of a wide range, so an excursion shows as a
/// widening even where the mean is smooth.
class EnvelopePoint {
  const EnvelopePoint({required this.t, required this.min, required this.max});
  final int t;
  final double min;
  final double max;
}

/// Everything the renderer needs for one probe.
class ProbeSeries {
  const ProbeSeries({
    required this.jack,
    required this.runs,
    this.envelope = const [],
    this.rawCount = 0,
  });

  final ProbeJack jack;
  final List<SeriesRun> runs;

  /// Empty unless [buildChartSeries] decided the range was wide enough.
  final List<EnvelopePoint> envelope;

  /// Valid points before decimation — the honest denominator.
  final int rawCount;

  bool get isEmpty => runs.isEmpty;

  /// Every point that survived decimation, flattened.
  List<ValuePoint> get points => [for (final r in runs) ...r.points];
}

/// The complete render model for a window.
class ChartSeriesModel {
  const ChartSeriesModel({
    required this.series,
    required this.gaps,
    required this.fromT,
    required this.toT,
    this.minF,
    this.maxF,
  });

  final List<ProbeSeries> series;

  /// Gaps in the *union* of the window's samples — the dotted connectors.
  final List<Gap> gaps;
  final int fromT;
  final int toT;

  /// The y-extent across every probe, or null when nothing is plottable.
  final double? minF;
  final double? maxF;

  bool get isEmpty => series.every((s) => s.isEmpty);
}

/// Above this many valid points, the envelope is worth computing.
const int envelopeThreshold = 1200;

/// The documented gap threshold: 1.5× the nominal 30 s cadence.
const int chartGapThresholdS = 45;

/// The threshold a series should actually be judged against: **1.5× its own
/// median cadence, never below the floor.** Judging 5-minute bucketed data
/// against 45 s would render fifteen thousand disconnected dots.
int effectiveGapThresholdS(
  Iterable<int> ts, {
  int floorS = chartGapThresholdS,
}) {
  final deltas = <int>[];
  int? prev;
  for (final t in ts) {
    if (prev != null) {
      deltas.add(t - prev);
    }
    prev = t;
  }
  // Fewer than three intervals is not a cadence; use the floor.
  if (deltas.length < 3) {
    return floorS;
  }
  deltas.sort();
  final median = deltas[deltas.length ~/ 2];
  final scaled = (median * 3) ~/ 2;
  return scaled > floorS ? scaled : floorS;
}

/// Builds the render model. [samples] must be ordered by `t`.
///
/// [targetPoints] below 3 disables decimation rather than throwing — a
/// zero-width chart is a layout state, not a programming error.
ChartSeriesModel buildChartSeries(
  List<Sample> samples, {
  required int fromT,
  required int toT,
  int targetPoints = 800,
  List<ProbeJack> probes = ProbeJack.values,
  int? gapThresholdS,
}) {
  final window = [
    for (final s in samples)
      if (s.t >= fromT && s.t <= toT) s,
  ];
  if (window.isEmpty) {
    return ChartSeriesModel(
      series: [for (final p in probes) ProbeSeries(jack: p, runs: const [])],
      gaps: const [],
      fromT: fromT,
      toT: toT,
    );
  }

  final threshold =
      gapThresholdS ?? effectiveGapThresholdS(window.map((s) => s.t));
  final gaps = findGaps(window.map((s) => s.t), thresholdS: threshold);

  double? lo;
  double? hi;
  final out = <ProbeSeries>[];
  for (final p in probes) {
    final valid = <ValuePoint>[
      for (final s in window)
        if (probeValue(s, p) != null) (t: s.t, f: probeValue(s, p)! / 10),
    ];
    if (valid.isEmpty) {
      out.add(ProbeSeries(jack: p, runs: const []));
      continue;
    }
    for (final v in valid) {
      lo = lo == null || v.f < lo ? v.f : lo;
      hi = hi == null || v.f > hi ? v.f : hi;
    }

    final envelope = valid.length > envelopeThreshold
        ? _envelope(valid, targetPoints)
        : const <EnvelopePoint>[];

    final runs = <SeriesRun>[];
    for (final raw in _split(valid, threshold)) {
      final budget = _budgetFor(raw.length, valid.length, targetPoints);
      runs.add(SeriesRun(budget >= 3 ? lttb(raw, budget) : raw));
    }
    out.add(
      ProbeSeries(
        jack: p,
        runs: runs,
        envelope: envelope,
        rawCount: valid.length,
      ),
    );
  }

  return ChartSeriesModel(
    series: out,
    gaps: gaps,
    fromT: fromT,
    toT: toT,
    minF: lo,
    maxF: hi,
  );
}

/// Runs of consecutive points with no gap between them.
List<List<ValuePoint>> _split(List<ValuePoint> pts, int thresholdS) {
  final runs = <List<ValuePoint>>[];
  var current = <ValuePoint>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    if (pts[i].t - pts[i - 1].t > thresholdS) {
      runs.add(current);
      current = <ValuePoint>[];
    }
    current.add(pts[i]);
  }
  runs.add(current);
  return runs;
}

/// Share the decimation budget proportionally. Never below 3 (LTTB's floor)
/// and never above the run length.
int _budgetFor(int runLength, int totalValid, int targetPoints) {
  if (targetPoints < 3 || totalValid <= targetPoints) {
    return runLength;
  }
  final share = (targetPoints * runLength / totalValid).floor();
  return share < 3 ? runLength.clamp(0, 3) : share;
}

/// Fixed-count min/max buckets across the run.
List<EnvelopePoint> _envelope(List<ValuePoint> pts, int targetPoints) {
  final buckets = targetPoints < 3 ? 3 : targetPoints;
  if (pts.length <= buckets) {
    return [for (final p in pts) EnvelopePoint(t: p.t, min: p.f, max: p.f)];
  }
  final span = pts.length / buckets;
  final out = <EnvelopePoint>[];
  for (var i = 0; i < buckets; i++) {
    final start = (i * span).floor();
    final end = (((i + 1) * span).floor()).clamp(start + 1, pts.length);
    var lo = pts[start].f;
    var hi = pts[start].f;
    var tSum = 0;
    for (var j = start; j < end; j++) {
      lo = pts[j].f < lo ? pts[j].f : lo;
      hi = pts[j].f > hi ? pts[j].f : hi;
      tSum += pts[j].t;
    }
    out.add(EnvelopePoint(t: (tSum / (end - start)).round(), min: lo, max: hi));
  }
  return out;
}

/// The nearest actual reading to [atT] for each probe, for the crosshair. It
/// reads a real sample and reports how far away it was rather than inventing a
/// reading in the middle of a dropout.
class CrosshairReading {
  const CrosshairReading({
    required this.jack,
    required this.f,
    required this.t,
    required this.deltaS,
  });

  final ProbeJack jack;

  /// Null when this probe has no reading near [atT] — rendered `—`, never 0.
  final double? f;
  final int t;
  final int deltaS;
}

List<CrosshairReading> crosshairAt(
  ChartSeriesModel model,
  int atT, {
  int maxDeltaS = chartGapThresholdS,
}) => [
  for (final s in model.series)
    () {
      ValuePoint? best;
      var bestDelta = 1 << 30;
      for (final p in s.points) {
        final d = (p.t - atT).abs();
        if (d < bestDelta) {
          bestDelta = d;
          best = p;
        }
      }
      final hit = best;
      final within = hit != null && bestDelta <= maxDeltaS;
      return CrosshairReading(
        jack: s.jack,
        f: within ? hit.f : null,
        t: within ? hit.t : atT,
        deltaS: within ? bestDelta : 0,
      );
    }(),
];
