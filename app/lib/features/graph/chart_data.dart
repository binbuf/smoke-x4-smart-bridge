/// Pure geometry for the temperature chart: the visible x-window, the
/// run-splitting that turns a reception hole into a gap, and the decimation
/// that lets a fifteen-hour cook draw in one frame.
///
/// Nothing here touches a widget or a gesture, so every rule below is
/// table-testable: a pan is a method call, a zoom is a method call, and a
/// segment count is a function of the sample list.
library;

import 'package:fl_chart/fl_chart.dart';

import '../../domain/domain.dart';

/// ── viewport ────────────────────────────────────────────────────────
///
/// The visible slice of the x-axis, in minutes since session start. Only the
/// x-axis pans and zooms; y stays fixed to the whole session, so a pan cannot
/// make the line appear to change value.
class ChartViewport {
  const ChartViewport({
    required this.fullMin,
    required this.fullMax,
    required this.min,
    required this.max,
  });

  /// A window over the whole session. A degenerate span (a one-sample cook) is
  /// widened to [minSpan] so zoom can never divide by zero.
  factory ChartViewport.full(double fullMin, double fullMax) {
    if (fullMax - fullMin < minSpan) {
      return ChartViewport(
        fullMin: fullMin,
        fullMax: fullMin + minSpan,
        min: fullMin,
        max: fullMin + minSpan,
      );
    }
    return ChartViewport(
      fullMin: fullMin,
      fullMax: fullMax,
      min: fullMin,
      max: fullMax,
    );
  }

  final double fullMin;
  final double fullMax;
  final double min;
  final double max;

  /// The tightest useful window: below a minute the axis labels collapse.
  static const double minSpan = 1;

  double get span => max - min;
  double get fullSpan => fullMax - fullMin;
  bool get isFull => min <= fullMin + 1e-6 && max >= fullMax - 1e-6;

  ChartViewport _clamp(double lo, double span) {
    final s = span.clamp(minSpan, fullSpan);
    var start = lo;
    if (start < fullMin) {
      start = fullMin;
    }
    if (start + s > fullMax) {
      start = fullMax - s;
    }
    if (start < fullMin) {
      start = fullMin;
    }
    return ChartViewport(
      fullMin: fullMin,
      fullMax: fullMax,
      min: start,
      max: start + s,
    );
  }

  /// Slides the window by [deltaMinutes]. A positive delta reveals later data.
  ChartViewport pan(double deltaMinutes) =>
      _clamp(min + deltaMinutes, span);

  /// Zooms by [scale] (>1 is closer in) keeping [focus] pinned on screen.
  ChartViewport zoom(double scale, double focus) {
    final factor = scale.clamp(1e-3, 1e6);
    final newSpan = span / factor;
    final fraction = span == 0 ? 0.5 : (focus - min) / span;
    final newMin = focus - fraction * newSpan;
    return _clamp(newMin, newSpan);
  }

  /// A window of [minutes] anchored to the right edge — the newest reading.
  ChartViewport window(double minutes) => _clamp(fullMax - minutes, minutes);

  /// Slides to the newest data, keeping the current width.
  ChartViewport jumpToEnd() => _clamp(fullMax - span, span);

  /// Charge the window to cover [start]..[end] (used when the session changes).
  ChartViewport moveTo(double start, double end) =>
      _clamp(start, end - start);
}

/// ── segmentation ────────────────────────────────────────────────────

/// The four per-jack runs of [samples], split at every null reading and every
/// gap wider than 2.5× the session's own cadence.
///
/// A reception hole is a **break**, never a straight line across it: a detached
/// probe simply has no line, which is why a dropped probe cannot be read as
/// `0 °F`. The split is load-bearing and kept intact.
List<List<List<FlSpot>>> buildSegments(List<Sample> samples) {
  final period = _cadence(samples);
  final threshold = (period * 2.5).round();

  final segs = List.generate(4, (_) => <List<FlSpot>>[]);
  final current = List<List<FlSpot>?>.filled(4, null);

  void flush(int jack) {
    final c = current[jack];
    if (c != null && c.isNotEmpty) {
      segs[jack].add(c);
    }
    current[jack] = null;
  }

  int? prevT;
  for (final s in samples) {
    if (prevT != null && s.t - prevT > threshold) {
      for (var j = 0; j < 4; j++) {
        flush(j);
      }
    }
    for (var j = 0; j < 4; j++) {
      final v = j < s.tempsF10.length ? s.tempsF10[j] : null;
      if (v == null) {
        flush(j);
      } else {
        (current[j] ??= <FlSpot>[]).add(FlSpot(s.t / 60, v / 10));
      }
    }
    prevT = s.t;
  }
  for (var j = 0; j < 4; j++) {
    flush(j);
  }
  return segs;
}

/// The session's own cadence (median of the first few deltas), so a cook kept
/// at 5-minute buckets is not read as one continuous dropout.
int _cadence(List<Sample> samples) {
  final deltas = <int>[];
  for (var i = 1; i < samples.length && deltas.length < 50; i++) {
    deltas.add(samples[i].t - samples[i - 1].t);
  }
  if (deltas.isEmpty) {
    return 30;
  }
  deltas.sort();
  final median = deltas[deltas.length ~/ 2];
  return median < 1 ? 30 : median;
}

/// The part of [run] visible in `[lo, hi]`, keeping one point just outside each
/// edge so the line is drawn to the boundary rather than stopping short.
List<FlSpot> clipToViewport(List<FlSpot> run, double lo, double hi) {
  var start = 0;
  while (start < run.length && run[start].x < lo) {
    start++;
  }
  var end = start;
  while (end < run.length && run[end].x <= hi) {
    end++;
  }
  final from = start > 0 ? start - 1 : 0;
  final to = end < run.length ? end + 1 : end;
  return run.sublist(from, to);
}

/// ── decimation ──────────────────────────────────────────────────────

/// Largest-Triangle-Three-Buckets: the standard shape-preserving downsample.
///
/// Preserves the first and last point and [threshold] points in between, so a
/// long cook draws its shape rather than every sample.
List<FlSpot> lttb(List<FlSpot> data, int threshold) {
  if (threshold >= data.length || threshold < 3) {
    return List<FlSpot>.of(data);
  }
  final sampled = <FlSpot>[data.first];
  final every = (data.length - 2) / (threshold - 2);
  var a = 0;
  for (var i = 0; i < threshold - 2; i++) {
    final avgStart = ((i + 1) * every).floor() + 1;
    final avgEnd = ((i + 2) * every).floor() + 1;
    final avgStop = avgEnd < data.length ? avgEnd : data.length;
    var avgX = 0.0;
    var avgY = 0.0;
    final avgLen = avgStop - avgStart;
    for (var j = avgStart; j < avgStop; j++) {
      avgX += data[j].x;
      avgY += data[j].y;
    }
    if (avgLen > 0) {
      avgX /= avgLen;
      avgY /= avgLen;
    }
    final rangeStart = (i * every).floor() + 1;
    final rangeEnd = ((i + 1) * every).floor() + 1;
    final pointAX = data[a].x;
    final pointAY = data[a].y;
    var maxArea = -1.0;
    var nextA = rangeStart;
    for (var j = rangeStart; j < rangeEnd; j++) {
      final area =
          ((pointAX - avgX) * (data[j].y - pointAY) -
                  (pointAX - data[j].x) * (avgY - pointAY))
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

/// A min/max envelope over [buckets] buckets. Every bucket contributes its
/// lowest and highest sample, so a one-sample spike survives where LTTB might
/// smooth it away; the cost is vertical density, which is why it is reserved
/// for runs far denser than the pixel budget.
List<FlSpot> minMaxEnvelope(List<FlSpot> data, int buckets) {
  if (buckets < 1 || data.length <= buckets * 2) {
    return List<FlSpot>.of(data);
  }
  final out = <FlSpot>[];
  for (var b = 0; b < buckets; b++) {
    final start = (b * data.length / buckets).floor();
    var end = ((b + 1) * data.length / buckets).floor();
    if (end <= start) {
      end = start + 1;
    }
    var lo = data[start];
    var hi = data[start];
    for (var i = start + 1; i < end; i++) {
      if (data[i].y < lo.y) lo = data[i];
      if (data[i].y > hi.y) hi = data[i];
    }
    if (identical(lo, hi)) {
      out.add(lo);
    } else if (lo.x <= hi.x) {
      out
        ..add(lo)
        ..add(hi);
    } else {
      out
        ..add(hi)
        ..add(lo);
    }
  }
  return out;
}

/// Reduce one contiguous run to at most [budget] points.
///
/// LTTB keeps the shape at ordinary densities; a run at least 8× denser than
/// the budget — a fifteen-hour cook at 30 s — uses the min/max envelope
/// instead, so an extreme never gets averaged off the screen.
List<FlSpot> decimate(List<FlSpot> run, int budget) {
  final b = budget < 3 ? 3 : budget;
  if (run.length <= b) {
    return run;
  }
  if (run.length >= b * 8) {
    return minMaxEnvelope(run, b ~/ 2);
  }
  return lttb(run, b);
}

/// ── vertical bounds ─────────────────────────────────────────────────

/// The y-range over the whole session, padded so the line never touches the
/// frame. Computed from every sample, not the visible window, so a pan does not
/// rescale the axis under the user.
({double minY, double maxY}) boundsY(List<Sample> samples) {
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final s in samples) {
    for (final v in s.tempsF10) {
      if (v == null) continue;
      final f = v / 10;
      if (f < minY) minY = f;
      if (f > maxY) maxY = f;
    }
  }
  if (minY == double.infinity) {
    return (minY: 0, maxY: 1);
  }
  final pad = ((maxY - minY) * 0.1).clamp(2, 20);
  return (minY: minY - pad, maxY: maxY + pad);
}
