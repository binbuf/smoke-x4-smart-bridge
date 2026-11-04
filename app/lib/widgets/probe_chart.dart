import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/formatters.dart';
import '../domain/models.dart';

Rect historyChartPlotRect(Size size) {
  // Temperature labels sit inside the plot, so the chart can run nearly edge
  // to edge on a phone instead of reserving a left-hand gutter.
  return Rect.fromLTRB(
    8,
    16,
    math.max(16, size.width - 8),
    math.max(20, size.height - 34),
  );
}

/// Placement of one gap band inside the current viewport.
///
/// The band's own `start`/`end` describe the missing period. A stored gap that
/// is narrower than [minimumWidth] still gets a visible sliver so the user can
/// see the loss; the label policy stays separate.
Rect? historyGapBandRect({
  required HistoryGapBand gap,
  required Rect chart,
  required DateTime viewStart,
  required DateTime viewEnd,
  double minimumWidth = 2,
}) {
  final totalMs = viewEnd.difference(viewStart).inMilliseconds;
  if (totalMs <= 0 || chart.width <= 0) return null;
  if (!gap.end.isAfter(viewStart) || !gap.start.isBefore(viewEnd)) return null;
  double xFor(DateTime time) {
    final clamped = time.isBefore(viewStart)
        ? viewStart
        : (time.isAfter(viewEnd) ? viewEnd : time);
    return chart.left +
        clamped.difference(viewStart).inMilliseconds / totalMs * chart.width;
  }

  var left = xFor(gap.start);
  var right = xFor(gap.end);
  if (right <= left) right = left + minimumWidth;
  if (right - left < minimumWidth) {
    final center = (left + right) / 2;
    left = (center - minimumWidth / 2).clamp(
      chart.left,
      math.max(chart.left, chart.right - minimumWidth),
    );
    right = left + minimumWidth;
  }
  if (right <= chart.left || left >= chart.right) return null;
  return Rect.fromLTRB(
    left.clamp(chart.left, chart.right),
    chart.top,
    right.clamp(chart.left, chart.right),
    chart.bottom,
  );
}

/// Whether the reason label fits in [band].
///
/// A wide band always labels. A permanent loss (`Not synced`) is labelled even
/// when the missing period is only a few pixels wide at the current zoom, so
/// the approved label is present beside the permanent-loss explanation instead
/// of disappearing with the band.
bool historyGapBandShowsLabel(Rect band, HistoryGapReason reason) {
  if (band.width <= 0) return false;
  if (reason == HistoryGapReason.bridgeRotated) return true;
  return band.width >= 58;
}

/// A stable y-axis domain in display units.
///
/// The chart scales to the whole painted fixture, not just the pixels currently
/// on screen. Panning inside one loaded window therefore never changes the
/// vertical scale; only a new window (a zoom commit, a preset, or a probe
/// change) recomputes it. [HistoryChartPanel] freezes this domain during a
/// gesture for the same reason.
class HistoryYDomain {
  const HistoryYDomain(this.min, this.max);

  final double min;
  final double max;

  @override
  bool operator ==(Object other) =>
      other is HistoryYDomain && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Raw display-unit domain for [fixture], padded so peaks and troughs never
/// touch the plot edge. Empty fixtures get the approved fallback scale.
HistoryYDomain historyYDomainFor(
  HistoryFixture fixture, {
  int? visibleProbe,
  required Units units,
}) {
  final values = <double>[];
  for (final series in fixture.series) {
    if (visibleProbe != null && series.index + 1 != visibleProbe) continue;
    for (final point in series.points) {
      if (point.valueF == null) continue;
      values.add(toDisplayTemperature(point.valueF!, units));
    }
  }
  if (values.isEmpty) {
    return HistoryYDomain(
      units == Units.fahrenheit ? 50 : 10,
      units == Units.fahrenheit ? 300 : 150,
    );
  }
  final min = values.reduce(math.min);
  final max = values.reduce(math.max);
  final padding = math.max(5.0, (max - min) * 0.10);
  return HistoryYDomain(min - padding, max + padding);
}

/// The interactive History chart surface.
///
/// The widget is paint-only. [HistoryChartPanel] owns the viewport, gestures,
/// cursor and range commits, which keeps the painter cheap enough to repaint
/// on every pinch frame.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.fixture,
    required this.units,
    required this.colors,
    required this.viewStart,
    required this.viewEnd,
    this.visibleProbe,
    this.cursorTime,
    this.use24Hour = false,
    this.latestIsNow = true,
    this.yMin,
    this.yMax,
  });

  final HistoryFixture fixture;
  final Units units;
  final List<Color> colors;
  final DateTime viewStart;
  final DateTime viewEnd;
  final int? visibleProbe;
  final DateTime? cursorTime;
  final bool use24Hour;
  final bool latestIsNow;

  /// Frozen display-unit domain during a gesture. When both are null the
  /// painter scales to [fixture].
  final double? yMin;
  final double? yMax;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle =
        Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ) ??
        const TextStyle(fontSize: 11);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          container: true,
          label: _semanticsLabel(),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _HistoryChartPainter(
              fixture: fixture,
              units: units,
              colors: colors,
              labelStyle: labelStyle,
              gridColor: scheme.outlineVariant.withValues(alpha: 0.55),
              labelColor: scheme.onSurfaceVariant,
              labelBackgroundColor: scheme.surface.withValues(alpha: 0.76),
              gapColor: scheme.onSurfaceVariant.withValues(alpha: 0.10),
              plotBackgroundColor: scheme.surfaceContainerHighest.withValues(
                alpha: 0.28,
              ),
              accentColor: scheme.primary,
              visibleProbe: visibleProbe,
              viewStart: viewStart,
              viewEnd: viewEnd,
              cursorTime: cursorTime,
              use24Hour: use24Hour,
              latestIsNow: latestIsNow,
              yMin: yMin,
              yMax: yMax,
            ),
          ),
        );
      },
    );
  }

  String _semanticsLabel() {
    final visible = <ChartSeries>[];
    for (final series in fixture.series) {
      if (visibleProbe != null && series.index + 1 != visibleProbe) continue;
      visible.add(
        ChartSeries(series.index, <ChartPoint>[
          for (final point in series.points)
            if (!point.time.isBefore(viewStart) && !point.time.isAfter(viewEnd))
              point,
        ]),
      );
    }
    final stats = visible
        .map(ProbeRangeStats.fromSeries)
        .where((s) => s.hasData);
    final range =
        '${shortDate(viewStart)} ${clockLabel(viewStart, use24Hour: use24Hour)}'
        ' to ${shortDate(viewEnd)} ${clockLabel(viewEnd, use24Hour: use24Hour)}';
    if (stats.isEmpty) {
      return 'History chart from $range. No readings in this range.';
    }
    final parts = stats
        .map((stat) {
          final last = displayTemp(stat.last, units);
          final min = displayTemp(stat.min, units);
          final max = displayTemp(stat.max, units);
          return 'P${stat.probe}: last $last, minimum $min, maximum $max';
        })
        .join('. ');
    return 'History chart from $range. $parts.';
  }
}

class _HistoryChartPainter extends CustomPainter {
  _HistoryChartPainter({
    required this.fixture,
    required this.units,
    required this.colors,
    required this.labelStyle,
    required this.gridColor,
    required this.labelColor,
    required this.labelBackgroundColor,
    required this.gapColor,
    required this.plotBackgroundColor,
    required this.accentColor,
    required this.visibleProbe,
    required this.viewStart,
    required this.viewEnd,
    required this.cursorTime,
    required this.use24Hour,
    required this.latestIsNow,
    this.yMin,
    this.yMax,
  });

  final HistoryFixture fixture;
  final Units units;
  final List<Color> colors;
  final TextStyle labelStyle;
  final Color gridColor;
  final Color labelColor;
  final Color labelBackgroundColor;
  final Color gapColor;
  final Color plotBackgroundColor;
  final Color accentColor;
  final int? visibleProbe;
  final DateTime viewStart;
  final DateTime viewEnd;
  final DateTime? cursorTime;
  final bool use24Hour;
  final bool latestIsNow;
  final double? yMin;
  final double? yMax;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = historyChartPlotRect(size);

    final visibleSeries = <ChartSeries>[];
    for (final series in fixture.series) {
      if (visibleProbe != null && series.index + 1 != visibleProbe) continue;
      visibleSeries.add(series);
    }

    final domain = yMin != null && yMax != null
        ? HistoryYDomain(yMin!, yMax!)
        : historyYDomainFor(fixture, visibleProbe: visibleProbe, units: units);
    var minValue = domain.min;
    var maxValue = domain.max;
    final ticks = _niceTicks(minValue, maxValue);
    minValue = ticks.first;
    maxValue = ticks.last;

    _drawPlotBackground(canvas, chart);
    _drawGrid(canvas, chart, ticks);
    _drawYAxisLabels(canvas, chart, ticks);

    final timeTicks = _timeTicks(chart.width);
    _drawTimeGrid(canvas, chart, timeTicks);

    _drawGapBands(canvas, chart);

    for (final series in visibleSeries) {
      _drawSeries(canvas, chart, series, minValue, maxValue);
    }

    _drawXAxisLabels(canvas, chart, timeTicks);
    _drawUnit(canvas, chart);

    if (cursorTime != null &&
        !cursorTime!.isBefore(viewStart) &&
        !cursorTime!.isAfter(viewEnd)) {
      _drawCursor(
        canvas,
        chart,
        visibleSeries,
        cursorTime!,
        minValue,
        maxValue,
      );
    }
  }

  double _display(double fahrenheit) => toDisplayTemperature(fahrenheit, units);

  double _xFor(DateTime time, Rect chart) {
    final spanMs = math.max(1, viewEnd.difference(viewStart).inMilliseconds);
    return chart.left +
        time.difference(viewStart).inMilliseconds / spanMs * chart.width;
  }

  double _yFor(double value, Rect chart, double minValue, double maxValue) {
    final range = math.max(0.0001, maxValue - minValue);
    return chart.bottom - (value - minValue) / range * chart.height;
  }

  List<double> _niceTicks(double minValue, double maxValue) {
    final range = math.max(1.0, maxValue - minValue);
    final rough = range / 5;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
    final normalized = rough / magnitude;
    const choices = [1.0, 2.0, 2.5, 5.0, 10.0];
    var niceNormalized = choices.first;
    for (final choice in choices.skip(1)) {
      if ((choice - normalized).abs() < (niceNormalized - normalized).abs()) {
        niceNormalized = choice;
      }
    }
    final step = niceNormalized * magnitude;
    final niceMin = (minValue / step).floor() * step;
    var niceMax = (maxValue / step).ceil() * step;
    if (niceMax <= niceMin) niceMax = niceMin + step;
    final ticks = <double>[];
    for (var value = niceMin; value <= niceMax + step * 0.01; value += step) {
      ticks.add(value.toDouble());
    }
    return ticks;
  }

  void _drawPlotBackground(Canvas canvas, Rect chart) {
    final rect = RRect.fromRectAndRadius(
      chart.inflate(2),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = plotBackgroundColor);
  }

  void _drawGrid(Canvas canvas, Rect chart, List<double> ticks) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < ticks.length; i++) {
      final y = chart.top + chart.height * i / (ticks.length - 1);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
    }
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      Paint()
        ..color = gridColor.withValues(alpha: 0.9)
        ..strokeWidth = 1,
    );
  }

  void _drawYAxisLabels(Canvas canvas, Rect chart, List<double> ticks) {
    final labelEvery = ticks.length > 6 ? 2 : 1;
    for (var i = 0; i < ticks.length; i++) {
      final isLast = i == ticks.length - 1;
      if (i % labelEvery != 0 && !isLast) continue;
      final label = '${ticks[ticks.length - 1 - i].round()}';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: labelColor.withValues(alpha: 0.82)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = chart.top + chart.height * i / (ticks.length - 1);
      final top = (y - painter.height / 2)
          .clamp(chart.top, chart.bottom - painter.height)
          .toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            chart.left + 2,
            top - 1,
            painter.width + 8,
            painter.height + 2,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = labelBackgroundColor,
      );
      painter.paint(canvas, Offset(chart.left + 6, top));
    }
  }

  void _drawUnit(Canvas canvas, Rect chart) {
    final painter = TextPainter(
      text: TextSpan(
        text: units == Units.fahrenheit ? '°F' : '°C',
        style: labelStyle.copyWith(
          color: labelColor,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(chart.right - painter.width - 6, chart.top + 4),
    );
  }

  List<DateTime> _timeTicks(double width) {
    final span = viewEnd.difference(viewStart);
    if (span.inMilliseconds <= 0) return const <DateTime>[];
    final target = (width / 88).floor().clamp(2, 7);
    final raw = Duration(milliseconds: span.inMilliseconds ~/ target);
    final step = _timeSteps.firstWhere(
      (candidate) => candidate >= raw,
      orElse: () => _timeSteps.last,
    );
    final ticks = <DateTime>[];
    if (step < const Duration(days: 1)) {
      final stepMinutes = step.inMinutes;
      final day = DateTime(viewStart.year, viewStart.month, viewStart.day);
      final minutesIntoDay = viewStart.hour * 60 + viewStart.minute;
      final alignedMinutes = (minutesIntoDay ~/ stepMinutes) * stepMinutes;
      var tick = day.add(Duration(minutes: alignedMinutes));
      if (tick.isBefore(viewStart)) tick = tick.add(step);
      while (!tick.isAfter(viewEnd) && ticks.length < 32) {
        ticks.add(tick);
        tick = tick.add(step);
      }
    } else {
      final stepDays = step.inDays;
      var tick = DateTime(viewStart.year, viewStart.month, viewStart.day);
      while (tick.isBefore(viewStart)) {
        tick = tick.add(Duration(days: stepDays));
      }
      while (!tick.isAfter(viewEnd) && ticks.length < 32) {
        ticks.add(tick);
        tick = tick.add(Duration(days: stepDays));
      }
    }
    if (ticks.isEmpty) {
      ticks
        ..add(viewStart)
        ..add(viewEnd);
    }
    return ticks;
  }

  static const List<Duration> _timeSteps = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 6),
    Duration(hours: 12),
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 7),
    Duration(days: 14),
    Duration(days: 30),
  ];

  void _drawTimeGrid(Canvas canvas, Rect chart, List<DateTime> ticks) {
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final tick in ticks) {
      final x = _xFor(tick, chart);
      if (x <= chart.left + 1 || x >= chart.right - 1) continue;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), paint);
    }
  }

  void _drawXAxisLabels(Canvas canvas, Rect chart, List<DateTime> ticks) {
    final span = viewEnd.difference(viewStart);
    final step = ticks.length > 1 ? ticks[1].difference(ticks[0]) : span;
    double? lastRight;
    for (var i = 0; i < ticks.length; i++) {
      final tick = ticks[i];
      final x = _xFor(tick, chart);
      if (x < chart.left - 1 || x > chart.right + 1) continue;
      final label = _timeTickLabel(tick, span, step);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var left = x - (i == 0 ? 0 : painter.width / 2);
      left = left
          .clamp(chart.left, math.max(chart.left, chart.right - painter.width))
          .toDouble();
      if (lastRight != null && left < lastRight + 6) continue;
      painter.paint(canvas, Offset(left, chart.bottom + 8));
      lastRight = left + painter.width;
    }

    final atLatest =
        latestIsNow && viewEnd.difference(fixture.end).inSeconds.abs() <= 90;
    if (atLatest) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Now',
          style: labelStyle.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = chart.right - painter.width;
      if (lastRight == null || left > lastRight + 8) {
        painter.paint(canvas, Offset(left, chart.bottom + 8));
      }
      canvas.drawCircle(
        Offset(chart.right, chart.bottom),
        3,
        Paint()..color = accentColor,
      );
    }
  }

  String _timeTickLabel(DateTime time, Duration span, Duration step) {
    final midnight = time.hour == 0 && time.minute == 0;
    if (span > const Duration(hours: 36)) {
      if (step >= const Duration(days: 1) || midnight) {
        return shortDate(time);
      }
      return '${shortDate(time)} ${clockLabel(time, use24Hour: use24Hour)}';
    }
    if (midnight) return shortDate(time);
    return clockLabel(time, use24Hour: use24Hour);
  }

  void _drawGapBands(Canvas canvas, Rect chart) {
    for (final gap in fixture.allGaps) {
      final band = historyGapBandRect(
        gap: gap,
        chart: chart,
        viewStart: viewStart,
        viewEnd: viewEnd,
      );
      if (band == null) continue;
      canvas.drawRect(band, Paint()..color = gapColor);
      final dash = Paint()
        ..color = labelColor.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      _dashedLine(
        canvas,
        Offset(band.left, chart.top),
        Offset(band.left, chart.bottom),
        dash,
      );
      _dashedLine(
        canvas,
        Offset(band.right, chart.top),
        Offset(band.right, chart.bottom),
        dash,
      );
      if (!historyGapBandShowsLabel(band, gap.reason)) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: gap.reason.label,
          style: labelStyle.copyWith(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = ((band.left + band.right) / 2 - painter.width / 2)
          .clamp(chart.left, math.max(chart.left, chart.right - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(x, chart.top + 5));
    }
  }

  void _drawSeries(
    Canvas canvas,
    Rect chart,
    ChartSeries series,
    double minValue,
    double maxValue,
  ) {
    final color = colors[series.index % colors.length];
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = visibleProbe == null ? 2.2 : 2.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final runs = historySeriesSegments(
      series,
      maxDelta: fixture.decimated
          ? const Duration(days: 3650)
          : historyGapThreshold,
    );
    final offsets = <Offset>[];
    final hasGap = runs.length > 1;
    Offset? lastOffset;
    for (final run in runs) {
      final visible = <ChartPoint>[];
      ChartPoint? before;
      ChartPoint? after;
      for (final point in run) {
        if (point.time.isBefore(viewStart)) {
          before = point;
          continue;
        }
        if (point.time.isAfter(viewEnd)) {
          after = point;
          break;
        }
        if (visible.isEmpty && before != null) visible.add(before);
        visible.add(point);
      }
      if (visible.isEmpty && before != null && after != null) {
        visible
          ..add(before)
          ..add(after);
      } else if (visible.isNotEmpty && after != null) {
        visible.add(after);
      }
      if (visible.isEmpty) continue;
      final path = Path();
      var started = false;
      for (final point in visible) {
        final x = _xFor(point.time, chart);
        final y = _yFor(_display(point.valueF!), chart, minValue, maxValue);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
        if (!point.time.isBefore(viewStart) && !point.time.isAfter(viewEnd)) {
          offsets.add(Offset(x, y));
          lastOffset = Offset(x, y);
        }
      }
      if (!started) continue;
      canvas.save();
      canvas.clipRect(chart);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
    if (visibleProbe != null && offsets.length > 1 && !hasGap) {
      final fillPath = Path()
        ..moveTo(offsets.first.dx, chart.bottom)
        ..lineTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        fillPath.lineTo(offset.dx, offset.dy);
      }
      fillPath
        ..lineTo(offsets.last.dx, chart.bottom)
        ..close();
      final fill = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, chart.top),
          Offset(0, chart.bottom),
          [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
        );
      canvas.save();
      canvas.clipRect(chart);
      canvas.drawPath(fillPath, fill);
      canvas.restore();
    }
    if (lastOffset != null) {
      final dot = Paint()..color = color;
      canvas.drawCircle(lastOffset, 3.2, dot);
      canvas.drawCircle(
        lastOffset,
        6.0,
        Paint()..color = color.withValues(alpha: 0.16),
      );
    }
  }

  void _drawCursor(
    Canvas canvas,
    Rect chart,
    List<ChartSeries> visibleSeries,
    DateTime cursor,
    double minValue,
    double maxValue,
  ) {
    final x = _xFor(cursor, chart);
    final line = Paint()
      ..color = labelColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), line);
    for (final series in visibleSeries) {
      ChartPoint? nearest;
      for (final point in series.points) {
        if (point.valueF == null) continue;
        if (nearest == null ||
            point.time.difference(cursor).inMilliseconds.abs() <
                nearest.time.difference(cursor).inMilliseconds.abs()) {
          nearest = point;
        }
      }
      if (nearest == null || nearest.valueF == null) continue;
      final y = _yFor(_display(nearest.valueF!), chart, minValue, maxValue);
      final color = colors[series.index % colors.length];
      canvas.drawCircle(Offset(x, y), 5.0, Paint()..color = color);
      canvas.drawCircle(
        Offset(x, y),
        8.0,
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final distance = (to - from).distance;
    if (distance == 0) return;
    final direction = (to - from) / distance;
    var travelled = 0.0;
    while (travelled < distance) {
      final start = from + direction * travelled;
      final end = from + direction * math.min(travelled + dash, distance);
      canvas.drawLine(start, end, paint);
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryChartPainter oldDelegate) {
    return oldDelegate.fixture != fixture ||
        oldDelegate.units != units ||
        oldDelegate.visibleProbe != visibleProbe ||
        oldDelegate.viewStart != viewStart ||
        oldDelegate.viewEnd != viewEnd ||
        oldDelegate.cursorTime != cursorTime ||
        oldDelegate.use24Hour != use24Hour ||
        oldDelegate.latestIsNow != latestIsNow ||
        oldDelegate.yMin != yMin ||
        oldDelegate.yMax != yMax ||
        oldDelegate.colors != colors ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelBackgroundColor != labelBackgroundColor ||
        oldDelegate.plotBackgroundColor != plotBackgroundColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.labelStyle != labelStyle;
  }
}

/// A compact overview of the loaded range with the visible window highlighted.
///
/// This is the range scrubber. Drag the window to pan, drag either edge to
/// zoom, or tap a point to centre the current span there. It is deliberately
/// separate from the main chart so a single-finger drag can never be ambiguous
/// between panning and scrubbing the range.
class HistoryRangeBrush extends StatefulWidget {
  const HistoryRangeBrush({
    super.key,
    required this.fixture,
    required this.viewStart,
    required this.viewEnd,
    required this.colors,
    this.visibleProbe,
    this.onChanged,
    this.onChangeEnd,
    this.height = 54,
    this.use24Hour = false,
  });

  final HistoryFixture fixture;
  final DateTime viewStart;
  final DateTime viewEnd;
  final List<Color> colors;
  final int? visibleProbe;
  final ValueChanged<DateTimeRange>? onChanged;
  final ValueChanged<DateTimeRange>? onChangeEnd;
  final double height;
  final bool use24Hour;

  @override
  State<HistoryRangeBrush> createState() => _HistoryRangeBrushState();
}

enum _BrushDrag { none, move, left, right }

class _HistoryRangeBrushState extends State<HistoryRangeBrush> {
  _BrushDrag _drag = _BrushDrag.none;
  DateTime? _dragStartStart;
  DateTime? _dragStartEnd;
  double _dragStartX = 0;
  DateTimeRange? _lastRange;

  static const double _horizontalPadding = 10;
  static const double _handleHitWidth = 26;
  static const double _minimumSpan = 30 * 1000;
  Rect _plotRect(Size size) => Rect.fromLTRB(
    _horizontalPadding,
    8,
    math.max(_horizontalPadding + 1, size.width - _horizontalPadding),
    math.max(9, size.height - 8),
  );

  double _xFor(DateTime time, Rect plot) {
    final total = widget.fixture.end.difference(widget.fixture.start);
    if (total.inMilliseconds <= 0) return plot.left;
    return plot.left +
        time.difference(widget.fixture.start).inMilliseconds /
            total.inMilliseconds *
            plot.width;
  }

  DateTime _timeFor(double x, Rect plot) {
    final total = widget.fixture.end.difference(widget.fixture.start);
    final fraction = ((x - plot.left) / plot.width).clamp(0.0, 1.0);
    return widget.fixture.start.add(
      Duration(milliseconds: (total.inMilliseconds * fraction).round()),
    );
  }

  DateTimeRange _clamp(DateTime start, DateTime end) {
    final fixtureSpan = widget.fixture.end.difference(widget.fixture.start);
    final minSpan = fixtureSpan.inMilliseconds <= _minimumSpan
        ? fixtureSpan
        : Duration(milliseconds: _minimumSpan.toInt());
    var span = end.difference(start);
    if (span < minSpan) span = minSpan;
    if (span > fixtureSpan) span = fixtureSpan;
    var nextStart = start;
    if (nextStart.isBefore(widget.fixture.start)) {
      nextStart = widget.fixture.start;
    }
    if (nextStart.add(span).isAfter(widget.fixture.end)) {
      nextStart = widget.fixture.end.subtract(span);
    }
    if (nextStart.isBefore(widget.fixture.start)) {
      nextStart = widget.fixture.start;
    }
    return DateTimeRange(start: nextStart, end: nextStart.add(span));
  }

  void _startDrag(Offset local, Rect plot) {
    final left = _xFor(widget.viewStart, plot);
    final right = _xFor(widget.viewEnd, plot);
    _dragStartStart = widget.viewStart;
    _dragStartEnd = widget.viewEnd;
    _dragStartX = local.dx;
    _lastRange = null;
    final windowWidth = right - left;
    if (windowWidth < _handleHitWidth * 2) {
      // A tiny window (a short range inside a long overview) is easier to move
      // than to resize. Resizing stays available from the main chart pinch.
      _drag = _BrushDrag.move;
    } else if ((local.dx - left).abs() <= _handleHitWidth) {
      _drag = _BrushDrag.left;
    } else if ((local.dx - right).abs() <= _handleHitWidth) {
      _drag = _BrushDrag.right;
    } else {
      _drag = _BrushDrag.move;
    }
  }

  void _updateDrag(Offset local, Rect plot) {
    final start = _dragStartStart;
    final end = _dragStartEnd;
    if (start == null || end == null) return;
    final total = widget.fixture.end.difference(widget.fixture.start);
    final delta = (local.dx - _dragStartX) / plot.width * total.inMilliseconds;
    final shift = Duration(milliseconds: delta.round());
    DateTimeRange next;
    switch (_drag) {
      case _BrushDrag.move:
        next = _clamp(start.add(shift), end.add(shift));
        break;
      case _BrushDrag.left:
        next = _clamp(start.add(shift), end);
        break;
      case _BrushDrag.right:
        next = _clamp(start, end.add(shift));
        break;
      case _BrushDrag.none:
        return;
    }
    _lastRange = next;
    widget.onChanged?.call(next);
  }

  void _endDrag() {
    _drag = _BrushDrag.none;
    final range =
        _lastRange ??
        DateTimeRange(start: widget.viewStart, end: widget.viewEnd);
    _lastRange = null;
    widget.onChangeEnd?.call(range);
  }

  void _tap(Offset local, Rect plot) {
    final span = widget.viewEnd.difference(widget.viewStart);
    final center = _timeFor(local.dx, plot);
    final next = _clamp(center.subtract(span ~/ 2), center.add(span ~/ 2));
    _lastRange = next;
    widget.onChanged?.call(next);
    widget.onChangeEnd?.call(next);
  }

  void _nudge(double fraction) {
    final fixtureSpan = widget.fixture.end.difference(widget.fixture.start);
    final shift = Duration(
      milliseconds: (fixtureSpan.inMilliseconds * fraction).round(),
    );
    final next = _clamp(widget.viewStart.add(shift), widget.viewEnd.add(shift));
    _lastRange = next;
    widget.onChanged?.call(next);
    widget.onChangeEnd?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final plot = _plotRect(size);
          return Semantics(
            slider: true,
            label:
                'History overview. Visible range '
                '${shortDate(widget.viewStart)} '
                '${clockLabel(widget.viewStart, use24Hour: widget.use24Hour)} to '
                '${shortDate(widget.viewEnd)} '
                '${clockLabel(widget.viewEnd, use24Hour: widget.use24Hour)}.',
            onIncrease: () => _nudge(0.1),
            onDecrease: () => _nudge(-0.1),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) =>
                  _startDrag(details.localPosition, plot),
              onHorizontalDragUpdate: (details) =>
                  _updateDrag(details.localPosition, plot),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: _endDrag,
              onTapUp: (details) => _tap(details.localPosition, plot),
              child: CustomPaint(
                size: size,
                painter: _RangeBrushPainter(
                  fixture: widget.fixture,
                  viewStart: widget.viewStart,
                  viewEnd: widget.viewEnd,
                  colors: widget.colors,
                  visibleProbe: widget.visibleProbe,
                  plot: plot,
                  background: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.38,
                  ),
                  overlay: scheme.surface.withValues(alpha: 0.68),
                  border: scheme.outlineVariant.withValues(alpha: 0.8),
                  accent: scheme.primary,
                  labelStyle:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ) ??
                      const TextStyle(fontSize: 10),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RangeBrushPainter extends CustomPainter {
  _RangeBrushPainter({
    required this.fixture,
    required this.viewStart,
    required this.viewEnd,
    required this.colors,
    required this.visibleProbe,
    required this.plot,
    required this.background,
    required this.overlay,
    required this.border,
    required this.accent,
    required this.labelStyle,
  });

  final HistoryFixture fixture;
  final DateTime viewStart;
  final DateTime viewEnd;
  final List<Color> colors;
  final int? visibleProbe;
  final Rect plot;
  final Color background;
  final Color overlay;
  final Color border;
  final Color accent;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(plot, const Radius.circular(9));
    canvas.drawRRect(rrect, Paint()..color = background);

    final values = <double>[];
    for (final series in fixture.series) {
      if (visibleProbe != null && series.index + 1 != visibleProbe) continue;
      for (final point in series.points) {
        if (point.valueF == null) continue;
        values.add(point.valueF!);
      }
    }
    if (values.isNotEmpty) {
      final minValue = values.reduce(math.min);
      final maxValue = values.reduce(math.max);
      final padding = math.max(1.0, (maxValue - minValue) * 0.15);
      final low = minValue - padding;
      final high = maxValue + padding;
      for (final series in fixture.series) {
        if (visibleProbe != null && series.index + 1 != visibleProbe) continue;
        final color = colors[series.index % colors.length];
        final paint = Paint()
          ..color = color.withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final runs = historySeriesSegments(
          series,
          maxDelta: fixture.decimated
              ? const Duration(days: 3650)
              : historyGapThreshold,
        );
        for (final run in runs) {
          final path = Path();
          var started = false;
          for (final point in run) {
            if (point.valueF == null) continue;
            final total = fixture.end.difference(fixture.start).inMilliseconds;
            if (total <= 0) continue;
            final x =
                plot.left +
                point.time.difference(fixture.start).inMilliseconds /
                    total *
                    plot.width;
            final y =
                plot.bottom -
                (point.valueF! - low) /
                    math.max(0.0001, high - low) *
                    plot.height;
            if (!started) {
              path.moveTo(x, y);
              started = true;
            } else {
              path.lineTo(x, y);
            }
          }
          if (started) {
            canvas.save();
            canvas.clipRRect(rrect);
            canvas.drawPath(path, paint);
            canvas.restore();
          }
        }
      }
    }

    final total = fixture.end.difference(fixture.start).inMilliseconds;
    if (total <= 0) return;
    double xFor(DateTime time) {
      final clamped = time.isBefore(fixture.start)
          ? fixture.start
          : (time.isAfter(fixture.end) ? fixture.end : time);
      return plot.left +
          clamped.difference(fixture.start).inMilliseconds / total * plot.width;
    }

    final left = xFor(viewStart);
    final right = math.max(left + 2, xFor(viewEnd));
    if (left > plot.left) {
      canvas.drawRect(
        Rect.fromLTRB(plot.left, plot.top, left, plot.bottom),
        Paint()..color = overlay,
      );
    }
    if (right < plot.right) {
      canvas.drawRect(
        Rect.fromLTRB(right, plot.top, plot.right, plot.bottom),
        Paint()..color = overlay,
      );
    }
    final window = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, plot.top, right, plot.bottom),
      const Radius.circular(7),
    );
    canvas.drawRRect(window, Paint()..color = accent.withValues(alpha: 0.10));
    canvas.drawRRect(
      window,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final handlePaint = Paint()..color = accent;
    final handleHeight = math.min(plot.height - 10, 22.0);
    final handleTop = plot.center.dy - handleHeight / 2;
    for (final x in [left, right]) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2.5, handleTop, 5, handleHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, handlePaint);
    }

    if (right - left >= 58) {
      final painter = TextPainter(
        text: TextSpan(
          text: durationShort(viewEnd.difference(viewStart)),
          style: labelStyle.copyWith(color: accent),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width + 12 <= right - left) {
        painter.paint(
          canvas,
          Offset((left + right) / 2 - painter.width / 2, plot.center.dy - 6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RangeBrushPainter oldDelegate) {
    return oldDelegate.fixture != fixture ||
        oldDelegate.viewStart != viewStart ||
        oldDelegate.viewEnd != viewEnd ||
        oldDelegate.visibleProbe != visibleProbe ||
        oldDelegate.colors != colors ||
        oldDelegate.background != background ||
        oldDelegate.accent != accent;
  }
}
