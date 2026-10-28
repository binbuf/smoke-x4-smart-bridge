import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/formatters.dart';
import '../domain/models.dart';

/// A tiny, axis-free trend line for a single probe. The sparkline is scaled to
/// its own min/max, so it communicates shape and direction rather than a
/// cross-probe comparison. History is where probes share one scale.
class ProbeSparkline extends StatelessWidget {
  const ProbeSparkline({
    super.key,
    required this.points,
    required this.color,
    required this.units,
    this.muted = false,
    this.height = 48,
  });

  final List<ChartPoint> points;
  final Color color;
  final Units units;
  final bool muted;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasData = points.any((point) => point.valueF != null);
    if (!hasData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No history yet',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: points,
          units: units,
          color: muted ? color.withValues(alpha: 0.45) : color,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.units,
    required this.color,
  });

  final List<ChartPoint> points;
  final Units units;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points
        .where((point) => point.valueF != null)
        .map((point) => _display(point.valueF!))
        .toList();
    if (values.isEmpty) return;

    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    final padding = math.max(0.8, (maxValue - minValue) * 0.12);
    minValue -= padding;
    maxValue += padding;
    if ((maxValue - minValue).abs() < 0.5) maxValue = minValue + 0.5;

    final start = points.first.time;
    final end = points.last.time;
    final spanMs = math.max(1, end.difference(start).inMilliseconds);
    const left = 2.0;
    const right = 2.0;
    const top = 4.0;
    const bottom = 4.0;
    final width = math.max(1.0, size.width - left - right);
    final height = math.max(1.0, size.height - top - bottom);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final offsets = <Offset>[];
    var active = false;
    var hasGap = false;
    for (final point in points) {
      if (point.valueF == null) {
        active = false;
        hasGap = true;
        continue;
      }
      final x =
          left + point.time.difference(start).inMilliseconds / spanMs * width;
      final y =
          top +
          (1 - (_display(point.valueF!) - minValue) / (maxValue - minValue)) *
              height;
      final offset = Offset(x, y);
      offsets.add(offset);
      if (!active) {
        path.moveTo(offset.dx, offset.dy);
        active = true;
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    if (offsets.length > 1 && !hasGap) {
      final fillPath = Path()
        ..moveTo(offsets.first.dx, top + height)
        ..lineTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        fillPath.lineTo(offset.dx, offset.dy);
      }
      fillPath
        ..lineTo(offsets.last.dx, top + height)
        ..close();
      final fill = Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + height), [
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.0),
        ]);
      canvas.drawPath(fillPath, fill);
    }
    canvas.drawPath(path, line);
    final lastOffset = offsets.isEmpty ? null : offsets.last;

    if (lastOffset != null) {
      final dot = Paint()..color = color;
      canvas.drawCircle(lastOffset, 2.6, dot);
      final halo = Paint()..color = color.withValues(alpha: 0.18);
      canvas.drawCircle(lastOffset, 5.5, halo);
    }
  }

  double _display(double fahrenheit) =>
      toDisplayTemperature(fahrenheit, units);

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.units != units ||
        oldDelegate.color != color;
  }
}
