/// The one chart used by both Graph and History.
///
/// A reception hole is drawn as a **break**, never a straight line across it:
/// the series is split into contiguous segments at every null reading and at
/// every gap wider than 2.5× the session's own cadence. A detached probe simply
/// has no line, which is why a dropped probe cannot be read as `0 °F`.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';

class TempChart extends StatelessWidget {
  const TempChart({
    super.key,
    required this.samples,
    this.unit = TempUnit.fahrenheit,
    this.height = 280,
  });

  final List<Sample> samples;
  final TempUnit unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final segments = _segments(samples);
    final hasData = segments.any((perJack) => perJack.isNotEmpty);
    if (!hasData) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'No readings in this range.',
            style: TextStyle(color: SmokePalette.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    final bounds = _bounds(samples);
    final bars = <LineChartBarData>[];
    final legend = <int>[];
    for (var jack = 0; jack < segments.length; jack++) {
      final segs = segments[jack];
      if (segs.isEmpty) {
        continue;
      }
      legend.add(jack + 1);
      for (final seg in segs) {
        bars.add(
          LineChartBarData(
            spots: seg,
            color: SmokePalette.forJack(jack + 1),
            dotData: FlDotData(show: seg.length == 1),
          ),
        );
      }
    }

    final spanX = bounds.maxX - bounds.minX;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: bounds.minX,
              maxX: bounds.maxX,
              minY: bounds.minY,
              maxY: bounds.maxY,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    const FlLine(color: SmokePalette.hairline, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(right: SmokeSpace.sm),
                      child: Text(
                        _axisTemp(v, unit),
                        style: const TextStyle(
                          color: SmokePalette.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: spanX <= 0 ? 1 : spanX / 3,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: SmokeSpace.sm),
                      child: Text(
                        _axisTime(v),
                        style: const TextStyle(
                          color: SmokePalette.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              lineBarsData: bars,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => SmokePalette.cardRaised,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        _valueLabel(s.y, unit),
                        TextStyle(
                          color: s.bar.color ?? SmokePalette.textHi,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: SmokeSpace.md),
        Wrap(
          spacing: SmokeSpace.lg,
          runSpacing: SmokeSpace.sm,
          children: [
            for (final jack in legend)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SeriesDot(jack: jack),
                  const SizedBox(width: SmokeSpace.xs + 2),
                  Text(
                    'Probe $jack',
                    style: const TextStyle(
                      color: SmokePalette.textBody,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ── series splitting ─────────────────────────────────────────────────

List<List<List<FlSpot>>> _segments(List<Sample> samples) {
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

({double minX, double maxX, double minY, double maxY}) _bounds(
  List<Sample> samples,
) {
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final s in samples) {
    if (s.t / 60 < minX) minX = s.t / 60;
    if (s.t / 60 > maxX) maxX = s.t / 60;
    for (final v in s.tempsF10) {
      if (v == null) continue;
      final f = v / 10;
      if (f < minY) minY = f;
      if (f > maxY) maxY = f;
    }
  }
  if (minX == double.infinity) {
    minX = 0;
    maxX = 1;
  }
  if (minY == double.infinity) {
    minY = 0;
    maxY = 1;
  }
  final pad = ((maxY - minY) * 0.1).clamp(2, 20);
  return (minX: minX, maxX: maxX, minY: minY - pad, maxY: maxY + pad);
}

// ── labels ───────────────────────────────────────────────────────────

String _axisTemp(double f, TempUnit unit) {
  final v = unit == TempUnit.fahrenheit ? f : (f - 32) * 5 / 9;
  return '${v.round()}°';
}

String _axisTime(double minutes) {
  if (minutes >= 60) {
    final h = minutes / 60;
    return h == h.roundToDouble()
        ? '${h.round()}h'
        : '${h.toStringAsFixed(1)}h';
  }
  return '${minutes.round()}m';
}

String _valueLabel(double f, TempUnit unit) {
  final v = unit == TempUnit.fahrenheit ? f : (f - 32) * 5 / 9;
  return '${v.toStringAsFixed(1)}${unit.suffix}';
}
