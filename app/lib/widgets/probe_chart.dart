import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/formatters.dart';
import '../domain/models.dart';

Rect historyChartPlotRect(Size size) {
  return Rect.fromLTRB(
    44,
    14,
    math.max(45, size.width - 12),
    math.max(15, size.height - 30),
  );
}

class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.fixture,
    required this.units,
    required this.colors,
    this.visibleProbe,
    this.viewStart = 0,
    this.viewEnd = 1,
    this.cursorTime,
    this.use24Hour = false,
    this.latestIsNow = true,
  });

  final HistoryFixture fixture;
  final Units units;
  final List<Color> colors;
  final int? visibleProbe;
  final double viewStart;
  final double viewEnd;
  final DateTime? cursorTime;
  final bool use24Hour;
  final bool latestIsNow;

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
              gapColor: scheme.onSurfaceVariant.withValues(alpha: 0.10),
              visibleProbe: visibleProbe,
              viewStart: viewStart,
              viewEnd: viewEnd,
              cursorTime: cursorTime,
              use24Hour: use24Hour,
              latestIsNow: latestIsNow,
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
      visible.add(series);
    }
    final stats = visible
        .map(ProbeRangeStats.fromSeries)
        .where((s) => s.hasData);
    if (stats.isEmpty) {
      return 'History chart from ${shortDate(fixture.start)} to ${shortDate(fixture.end)}. No readings in this range.';
    }
    final parts = stats
        .map((stat) {
          final last = displayTemp(stat.last, units);
          final min = displayTemp(stat.min, units);
          final max = displayTemp(stat.max, units);
          return 'P${stat.probe}: last $last, minimum $min, maximum $max';
        })
        .join('. ');
    return 'History chart from ${shortDate(fixture.start)} to ${shortDate(fixture.end)}. $parts.';
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
    required this.gapColor,
    required this.visibleProbe,
    required this.viewStart,
    required this.viewEnd,
    required this.cursorTime,
    required this.use24Hour,
    required this.latestIsNow,
  });

  final HistoryFixture fixture;
  final Units units;
  final List<Color> colors;
  final TextStyle labelStyle;
  final Color gridColor;
  final Color labelColor;
  final Color gapColor;
  final int? visibleProbe;
  final double viewStart;
  final double viewEnd;
  final DateTime? cursorTime;
  final bool use24Hour;
  final bool latestIsNow;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = historyChartPlotRect(size);
    final totalMs = fixture.end.difference(fixture.start).inMilliseconds;
    final startFraction = viewStart.clamp(0.0, 0.99);
    final endFraction = viewEnd.clamp(startFraction + 0.01, 1.0);
    final viewStartTime = fixture.start.add(
      Duration(milliseconds: (totalMs * startFraction).round()),
    );
    final viewEndTime = fixture.start.add(
      Duration(milliseconds: (totalMs * endFraction).round()),
    );
    final spanMs = math.max(
      1,
      viewEndTime.difference(viewStartTime).inMilliseconds,
    );

    final visibleSeries = <ChartSeries>[];
    for (final series in fixture.series) {
      if (visibleProbe != null && series.index + 1 != visibleProbe) continue;
      visibleSeries.add(series);
    }

    final values = <double>[];
    for (final series in visibleSeries) {
      for (final point in series.points) {
        if (point.valueF == null) continue;
        if (point.time.isBefore(viewStartTime) ||
            point.time.isAfter(viewEndTime)) {
          continue;
        }
        values.add(_display(point.valueF!));
      }
    }

    double minValue;
    double maxValue;
    if (values.isEmpty) {
      minValue = units == Units.fahrenheit ? 50 : 10;
      maxValue = units == Units.fahrenheit ? 300 : 150;
    } else {
      minValue = values.reduce(math.min);
      maxValue = values.reduce(math.max);
      final padding = math.max(5.0, (maxValue - minValue) * 0.10);
      minValue -= padding;
      maxValue += padding;
    }
    final ticks = _niceTicks(minValue, maxValue);
    minValue = ticks.first;
    maxValue = ticks.last;

    _drawGrid(canvas, chart, minValue, maxValue, ticks);
    _drawYAxisLabels(canvas, chart, ticks);

    _drawGapBand(
      canvas,
      chart,
      viewStartTime,
      viewEndTime,
      spanMs,
      minValue,
      maxValue,
    );

    for (final series in visibleSeries) {
      final color = colors[series.index % colors.length];
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = visibleProbe == null ? 2.2 : 2.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final offsets = <Offset>[];
      var active = false;
      var hasGap = false;
      Offset? lastOffset;
      for (final point in series.points) {
        if (point.valueF == null) {
          active = false;
          hasGap = true;
          continue;
        }
        if (point.time.isBefore(viewStartTime) ||
            point.time.isAfter(viewEndTime)) {
          continue;
        }
        final x =
            chart.left +
            point.time.difference(viewStartTime).inMilliseconds /
                spanMs *
                chart.width;
        final y =
            chart.bottom -
            (_display(point.valueF!) - minValue) /
                (maxValue - minValue) *
                chart.height;
        final offset = Offset(x, y);
        offsets.add(offset);
        if (!active) {
          path.moveTo(offset.dx, offset.dy);
          active = true;
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
        lastOffset = offset;
      }
      canvas.save();
      canvas.clipRect(chart);
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
        canvas.drawPath(fillPath, fill);
      }
      canvas.drawPath(path, paint);
      canvas.restore();
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

    _drawXAxisLabels(
      canvas,
      chart,
      viewStartTime,
      viewEndTime,
      spanMs,
      atLatest: viewEnd > 0.999 && latestIsNow,
    );
    _drawUnit(canvas, size);

    if (cursorTime != null &&
        !cursorTime!.isBefore(viewStartTime) &&
        !cursorTime!.isAfter(viewEndTime)) {
      _drawCursor(
        canvas,
        chart,
        visibleSeries,
        cursorTime!,
        viewStartTime,
        viewEndTime,
        spanMs,
        minValue,
        maxValue,
      );
    }
  }

  double _display(double fahrenheit) =>
      units == Units.fahrenheit ? fahrenheit : (fahrenheit - 32) * 5 / 9;

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

  void _drawGrid(
    Canvas canvas,
    Rect chart,
    double minValue,
    double maxValue,
    List<double> ticks,
  ) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < ticks.length; i++) {
      final y = chart.top + chart.height * i / (ticks.length - 1);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
    }
    final border = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      border,
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
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = chart.top + chart.height * i / (ticks.length - 1);
      painter.paint(canvas, Offset(chart.left - painter.width - 8, y - 7));
    }
  }

  void _drawUnit(Canvas canvas, Size size) {
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
    painter.paint(canvas, const Offset(4, 0));
  }

  void _drawXAxisLabels(
    Canvas canvas,
    Rect chart,
    DateTime viewStartTime,
    DateTime viewEndTime,
    int spanMs, {
    bool atLatest = false,
  }) {
    final span = viewEndTime.difference(viewStartTime);
    final divisions = span.inHours > 24 ? 2 : 3;
    for (var i = 0; i <= divisions; i++) {
      final time = viewStartTime.add(
        Duration(milliseconds: (spanMs * i / divisions).round()),
      );
      final label = i == divisions && atLatest
          ? 'Now'
          : chartTime(time, span, use24Hour: use24Hour);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x =
          chart.left +
          chart.width * i / divisions -
          (i == 0 ? 0 : (i == divisions ? painter.width : painter.width / 2));
      painter.paint(canvas, Offset(x, chart.bottom + 8));
    }
  }

  void _drawGapBand(
    Canvas canvas,
    Rect chart,
    DateTime viewStartTime,
    DateTime viewEndTime,
    int spanMs,
    double minValue,
    double maxValue,
  ) {
    if (!fixture.gapStart.isAfter(viewStartTime) ||
        !fixture.gapEnd.isBefore(viewEndTime)) {
      return;
    }
    final x1 =
        chart.left +
        fixture.gapStart.difference(viewStartTime).inMilliseconds /
            spanMs *
            chart.width;
    final x2 =
        chart.left +
        fixture.gapEnd.difference(viewStartTime).inMilliseconds /
            spanMs *
            chart.width;
    final band = Paint()..color = gapColor;
    canvas.drawRect(Rect.fromLTRB(x1, chart.top, x2, chart.bottom), band);
    final dash = Paint()
      ..color = labelColor.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    _dashedLine(canvas, Offset(x1, chart.top), Offset(x1, chart.bottom), dash);
    _dashedLine(canvas, Offset(x2, chart.top), Offset(x2, chart.bottom), dash);
    if (x2 - x1 > 58) {
      final label = switch (fixture.gapReason) {
        HistoryGapReason.noSignal => 'No signal',
        HistoryGapReason.bridgeOff => 'Bridge off',
        HistoryGapReason.bridgeRotated => 'Not synced',
      };
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset((x1 + x2) / 2 - painter.width / 2, chart.top + 5),
      );
    }
  }

  void _drawCursor(
    Canvas canvas,
    Rect chart,
    List<ChartSeries> visibleSeries,
    DateTime cursor,
    DateTime viewStartTime,
    DateTime viewEndTime,
    int spanMs,
    double minValue,
    double maxValue,
  ) {
    final x =
        chart.left +
        cursor.difference(viewStartTime).inMilliseconds / spanMs * chart.width;
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
      final y =
          chart.bottom -
          (_display(nearest.valueF!) - minValue) /
              (maxValue - minValue) *
              chart.height;
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
        oldDelegate.colors != colors ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelStyle != labelStyle;
  }
}
