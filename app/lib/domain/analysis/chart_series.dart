/// A10.1 — the chart series builder (design 08 §8.7).
///
/// Pure Dart, in `domain/` — zero Flutter imports, the hard rule CI greps
/// for. **All the work happens before `fl_chart` ever sees the data**, and
/// all of it is here: window slice, per-probe extraction, run splitting at
/// gaps, LTTB decimation, and the min/max envelope for very wide ranges.
///
/// Three invariants this file exists to hold:
///
///  * **Detached probes produce no points at all — never a zero.** A
///    `null` reading is a hole in the series, not a value of 0 °F.
///  * **Gaps are gaps.** Runs separated by a `t` delta > 45 s become
///    separate runs. A 30-minute dropout must look like a 30-minute
///    dropout, not like a straight line pretending everything was fine.
///    This is only possible because samples carry time (04 §4.2).
///  * **Decimation preserves the envelope.** LTTB (A2.6), not stride —
///    naive stride decimation steps straight over a lid-open spike.
library;

import '../entities/entities.dart';
import 'lttb.dart';
import 'series.dart';
import 'units.dart';

/// The reading for [probe] (1..4) in a [Sample], or null when the jack was
/// detached. There is deliberately no "or 0" fallback anywhere in this
/// file — a missing reading is a hole, not a temperature.
int? probeValue(Sample s, int probe) =>
    probe >= 1 && probe <= s.tempsF10.length ? s.tempsF10[probe - 1] : null;

/// One unbroken run of a probe's series. Two runs mean a gap between
/// them, and the renderer draws them as separate segments.
class SeriesRun {
  const SeriesRun(this.points);

  /// Ordered by `t`; never empty.
  final List<ValuePoint> points;

  int get fromT => points.first.t;
  int get toT => points.last.t;
}

/// The min/max envelope for one bucket of a wide range: the band that
/// makes an excursion visible as a *widening* even where the mean is
/// smooth (08 §8.7). Only produced when the range is wide enough to need
/// it — at full fidelity the line already is the envelope.
class EnvelopePoint {
  const EnvelopePoint({required this.t, required this.min, required this.max});
  final int t;
  final double min;
  final double max;
}

/// Everything the renderer needs for one probe.
class ProbeSeries {
  const ProbeSeries({
    required this.probe,
    required this.runs,
    this.envelope = const [],
    this.rawCount = 0,
  });

  /// 1..4.
  final int probe;
  final List<SeriesRun> runs;

  /// Empty unless [buildChartSeries] decided the range was wide enough.
  final List<EnvelopePoint> envelope;

  /// How many valid points existed before decimation — the honest
  /// denominator for "showing 400 of 2,880".
  final int rawCount;

  bool get isEmpty => runs.isEmpty;

  /// Every point that survived decimation, flattened. Runs are the render
  /// model; this is for readouts and tests.
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

/// Above this many valid points in a window, the envelope is worth
/// computing: the line alone stops being able to show an excursion.
const int envelopeThreshold = 1200;

/// The §8.7 gap threshold — 1.5× the nominal 30 s cadence.
const int chartGapThresholdS = 45;

/// The threshold this series should actually be judged against.
///
/// §8.7 fixes 45 s because the nominal cadence is 30 s — but the app also
/// asks the device for `bucket=90&agg=minmax` on very wide ranges
/// (06 §6.2), and a cook retained at a 5-minute cadence is a normal thing
/// to scroll back to. Judging bucketed data against 45 s would call every
/// single interval a dropout and render 15,000 disconnected dots.
///
/// So the rule is: **1.5× the series' own median cadence, never below the
/// §8.7 floor.** At 30 s it is exactly the documented 45 s; at 300 s it is
/// 450 s, and a real dropout still shows.
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
  // Fewer than three intervals is not a cadence, it is two readings. Fall
  // back to the documented floor rather than letting one long silence
  // redefine what "normal" means.
  if (deltas.length < 3) {
    return floorS;
  }
  deltas.sort();
  final median = deltas[deltas.length ~/ 2];
  final scaled = (median * 3) ~/ 2;
  return scaled > floorS ? scaled : floorS;
}

/// Builds the render model.
///
/// [samples] must be ordered by `t`. [targetPoints] is the decimation
/// budget — roughly two points per logical pixel of chart width; passing
/// a value below 3 disables decimation rather than throwing, because a
/// zero-width chart is a layout state, not a programming error.
ChartSeriesModel buildChartSeries(
  List<Sample> samples, {
  required int fromT,
  required int toT,
  int targetPoints = 800,
  List<int> probes = const [1, 2, 3, 4],

  /// Null derives it from the data (see [effectiveGapThresholdS]).
  int? gapThresholdS,
}) {
  final window = [
    for (final s in samples)
      if (s.t >= fromT && s.t <= toT) s,
  ];
  if (window.isEmpty) {
    return ChartSeriesModel(
      series: [for (final p in probes) ProbeSeries(probe: p, runs: const [])],
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
        if (probeValue(s, p) != null) (t: s.t, f: probeValue(s, p)! / 10.0),
    ];
    if (valid.isEmpty) {
      out.add(ProbeSeries(probe: p, runs: const []));
      continue;
    }
    for (final v in valid) {
      lo = lo == null || v.f < lo ? v.f : lo;
      hi = hi == null || v.f > hi ? v.f : hi;
    }

    final envelope = valid.length > envelopeThreshold
        ? _envelope(valid, targetPoints)
        : const <EnvelopePoint>[];

    // Split FIRST, decimate per run. Decimating across a gap would let
    // LTTB choose a triangle whose vertices straddle the hole and quietly
    // reintroduce the straight line we split to avoid.
    final runs = <SeriesRun>[];
    for (final raw in _split(valid, threshold)) {
      final budget = _budgetFor(raw.length, valid.length, targetPoints);
      runs.add(SeriesRun(budget >= 3 ? lttb(raw, budget) : raw));
    }
    out.add(
      ProbeSeries(
        probe: p,
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

/// Share the decimation budget proportionally, so a 4-sample run after a
/// long dropout does not get the same allowance as the 2,000-sample run
/// before it. Never below 3 (LTTB's floor) and never above the run.
int _budgetFor(int runLength, int totalValid, int targetPoints) {
  if (targetPoints < 3 || totalValid <= targetPoints) {
    return runLength;
  }
  final share = (targetPoints * runLength / totalValid).floor();
  return share < 3 ? runLength.clamp(0, 3) : share;
}

/// Fixed-count min/max buckets across the run — mean is the line, this is
/// the band behind it.
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

/// The nearest actual reading to [atT] for each probe, for the crosshair
/// (A10.5). It reads a real sample and reports how far away it was rather
/// than interpolating: an invented reading in the middle of a 30-minute
/// dropout is worse than no reading at all.
class CrosshairReading {
  const CrosshairReading({
    required this.probe,
    required this.f,
    required this.t,
    required this.deltaS,
  });

  final int probe;

  /// Null when this probe has no reading anywhere near [atT] — rendered
  /// as `—`, never as 0.
  final double? f;
  final int t;

  /// |sample.t − atT|. The UI states it when it is larger than a cadence.
  final int deltaS;
}

/// Nearest-sample readout. [maxDeltaS] is how far the crosshair may reach
/// before it admits there is nothing there — one and a half cadences by
/// default, the same threshold that defines a gap.
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
        probe: s.probe,
        f: within ? hit.f : null,
        t: within ? hit.t : atT,
        deltaS: within ? bestDelta : 0,
      );
    }(),
];
